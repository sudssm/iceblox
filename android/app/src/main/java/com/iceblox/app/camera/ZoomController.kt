package com.iceblox.app.camera

import android.content.Context
import android.graphics.RectF
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import androidx.camera.core.Camera
import com.google.common.util.concurrent.ListenableFuture
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sqrt

class ZoomController(context: Context) {
    val maxOpticalZoom: Float
    val isZoomRetryAvailable: Boolean

    private var lastRetryTime = 0L
    private var camera: Camera? = null

    var zoomRetryAttempts = 0
        private set
    var zoomRetrySuccesses = 0
        private set

    init {
        maxOpticalZoom = detectMaxOpticalZoom(context)
        isZoomRetryAvailable = AppConfig.ZOOM_RETRY_ENABLED && maxOpticalZoom > 1.0f
        DebugLog.d(
            TAG,
            "Init: maxOpticalZoom=$maxOpticalZoom, featureEnabled=${AppConfig.ZOOM_RETRY_ENABLED}, available=$isZoomRetryAvailable, cooldownMs=${AppConfig.ZOOM_RETRY_COOLDOWN_MS}, margin=${AppConfig.ZOOM_RETRY_MARGIN}"
        )
    }

    fun setCamera(camera: Camera) {
        this.camera = camera
        DebugLog.d(TAG, "Camera connected, zoom retry available=$isZoomRetryAvailable")
    }

    fun isOnCooldown(): Boolean {
        val elapsed = System.currentTimeMillis() - lastRetryTime
        val onCooldown = elapsed < AppConfig.ZOOM_RETRY_COOLDOWN_MS
        if (onCooldown) {
            DebugLog.d(TAG, "On cooldown: ${elapsed}ms elapsed, need ${AppConfig.ZOOM_RETRY_COOLDOWN_MS}ms")
        }
        return onCooldown
    }

    fun maxSafeZoomRatio(boundingBox: RectF, imageWidth: Int, imageHeight: Int): Float {
        if (maxOpticalZoom <= 1.0f) {
            DebugLog.d(TAG, "SafeZoom: no optical zoom (maxOpticalZoom=$maxOpticalZoom)")
            return 0f
        }
        val ratio = safeZoomRatio(boundingBox, imageWidth, imageHeight, maxOpticalZoom, AppConfig.ZOOM_RETRY_MARGIN)
        if (ratio < AppConfig.ZOOM_RETRY_MIN_RATIO) {
            DebugLog.d(
                TAG,
                "SafeZoom FAIL: safeRatio=${"%.2f".format(
                    ratio
                )}x < min=${AppConfig.ZOOM_RETRY_MIN_RATIO}x (box=[${String.format(
                    "%.1f",
                    boundingBox.left
                )},${String.format(
                    "%.1f",
                    boundingBox.top
                )},${String.format(
                    "%.1f",
                    boundingBox.right
                )},${String.format("%.1f", boundingBox.bottom)}] in ${imageWidth}x$imageHeight)"
            )
            return 0f
        }
        DebugLog.d(
            TAG,
            "SafeZoom PASS: ${"%.2f".format(
                ratio
            )}x (max=${maxOpticalZoom}x, box=[${String.format(
                "%.1f",
                boundingBox.left
            )},${String.format(
                "%.1f",
                boundingBox.top
            )},${String.format(
                "%.1f",
                boundingBox.right
            )},${String.format("%.1f", boundingBox.bottom)}] in ${imageWidth}x$imageHeight)"
        )
        return ratio
    }

    fun bestCandidate(detections: List<Triple<RectF, Int, Int>>): Pair<Int, Float>? {
        DebugLog.d(TAG, "bestCandidate: evaluating ${detections.size} failed detections")
        var bestIdx: Int? = null
        var bestDist = Float.MAX_VALUE
        var bestRatio = 0f

        for ((i, det) in detections.withIndex()) {
            val (box, imgW, imgH) = det
            val ratio = maxSafeZoomRatio(box, imgW, imgH)
            if (ratio <= 0f) {
                DebugLog.d(TAG, "  candidate[$i] NOT eligible")
                continue
            }
            val cx = (box.centerX() / imgW.toFloat()) - 0.5f
            val cy = (box.centerY() / imgH.toFloat()) - 0.5f
            val dist = sqrt(cx * cx + cy * cy)
            DebugLog.d(
                TAG,
                "  candidate[$i] eligible, safeZoom=${"%.2f".format(ratio)}x, distFromCenter=${"%.4f".format(dist)}"
            )
            if (dist < bestDist) {
                bestDist = dist
                bestIdx = i
                bestRatio = ratio
            }
        }
        return bestIdx?.let { idx ->
            DebugLog.d(TAG, "Best candidate: [$idx] dist=${"%.4f".format(bestDist)}, zoom=${"%.2f".format(bestRatio)}x")
            Pair(idx, bestRatio)
        } ?: run {
            DebugLog.d(TAG, "No eligible candidates for zoom retry")
            null
        }
    }

    fun zoomIn(ratio: Float): Boolean {
        val cam = camera
        if (cam == null) {
            DebugLog.w(TAG, "zoomIn: camera is null, cannot zoom")
            return false
        }
        return try {
            DebugLog.d(
                TAG,
                "zoomIn: setting zoom ratio to ${"%.2f".format(ratio)}x (attempt #${zoomRetryAttempts + 1})"
            )
            cam.cameraControl.setZoomRatio(ratio)
            lastRetryTime = System.currentTimeMillis()
            zoomRetryAttempts++
            DebugLog.d(TAG, "zoomIn: SUCCESS, total attempts=$zoomRetryAttempts, successes=$zoomRetrySuccesses")
            true
        } catch (e: Exception) {
            DebugLog.e(TAG, "zoomIn FAILED: ${e.message}", e)
            false
        }
    }

    fun restoreZoom(): ListenableFuture<Void>? {
        val cam = camera ?: return null
        return try {
            val future = cam.cameraControl.setZoomRatio(1.0f)
            DebugLog.d(TAG, "restoreZoom: reset to 1.0x")
            future
        } catch (e: Exception) {
            DebugLog.e(TAG, "restoreZoom FAILED: ${e.message}", e)
            null
        }
    }

    fun recordSuccess() {
        zoomRetrySuccesses++
        val pct = if (zoomRetryAttempts > 0) {
            "${"%.0f".format(zoomRetrySuccesses.toFloat() / zoomRetryAttempts * 100)}%"
        } else {
            "N/A"
        }
        DebugLog.d(
            TAG,
            "recordSuccess: successes=$zoomRetrySuccesses / attempts=$zoomRetryAttempts ($pct)"
        )
    }

    private fun detectMaxOpticalZoom(context: Context): Float {
        return try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            DebugLog.d(TAG, "detectMaxOpticalZoom: camera IDs=${cameraManager.cameraIdList.toList()}")

            var baseFocal = 0f
            var maxFocal = 0f

            for (id in cameraManager.cameraIdList) {
                val chars = cameraManager.getCameraCharacteristics(id)
                if (chars.get(CameraCharacteristics.LENS_FACING) != CameraCharacteristics.LENS_FACING_BACK) continue
                val focals = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS) ?: continue
                DebugLog.d(TAG, "detectMaxOpticalZoom: back camera=$id, focalLengths=${focals.toList()}")

                // The logical camera's focal length is the CameraX 1.0x baseline
                if (baseFocal == 0f && focals.isNotEmpty()) {
                    baseFocal = focals[0]
                }
                for (f in focals) if (f > maxFocal) maxFocal = f

                // Check physical cameras behind this logical camera (API 28+)
                val physicalIds = chars.physicalCameraIds
                if (physicalIds.isNotEmpty()) {
                    DebugLog.d(TAG, "detectMaxOpticalZoom: logical camera=$id has physical cameras=$physicalIds")
                    for (physId in physicalIds) {
                        try {
                            val physChars = cameraManager.getCameraCharacteristics(physId)
                            val physFocals =
                                physChars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS) ?: continue
                            DebugLog.d(
                                TAG,
                                "detectMaxOpticalZoom: physical camera=$physId, focalLengths=${physFocals.toList()}"
                            )
                            for (f in physFocals) if (f > maxFocal) maxFocal = f
                        } catch (e: Exception) {
                            DebugLog.w(
                                TAG,
                                "detectMaxOpticalZoom: failed to query physical camera $physId: ${e.message}"
                            )
                        }
                    }
                }
            }

            if (baseFocal <= 0f || maxFocal <= 0f) {
                DebugLog.w(TAG, "detectMaxOpticalZoom: no valid focal lengths found")
                return 1.0f
            }

            if (maxFocal <= baseFocal) {
                DebugLog.d(TAG, "detectMaxOpticalZoom: no telephoto (base=$baseFocal, max=$maxFocal)")
                return 1.0f
            }

            // Ratio from the logical camera baseline (CameraX 1.0x) to the longest telephoto
            val ratio = maxFocal / baseFocal
            DebugLog.d(TAG, "detectMaxOpticalZoom: base=$baseFocal (CameraX 1.0x), telephoto=$maxFocal, ratio=$ratio")
            ratio
        } catch (e: Exception) {
            DebugLog.e(TAG, "detectMaxOpticalZoom FAILED: ${e.message}", e)
            1.0f
        }
    }

    companion object {
        private const val TAG = "ZoomController"

        fun safeZoomRatio(
            boundingBox: RectF,
            imageWidth: Int,
            imageHeight: Int,
            maxOpticalZoom: Float,
            margin: Float
        ): Float {
            if (maxOpticalZoom <= 1.0f) return 0f
            val w = imageWidth.toFloat()
            val h = imageHeight.toFloat()
            if (w <= 0f || h <= 0f) return 0f

            val nx0 = boundingBox.left / w
            val ny0 = boundingBox.top / h
            val nx1 = boundingBox.right / w
            val ny1 = boundingBox.bottom / h

            var maxCornerDist = 0f
            val corners = arrayOf(
                nx0 to ny0,
                nx1 to ny0,
                nx0 to ny1,
                nx1 to ny1
            )
            for ((cx, cy) in corners) {
                val d = maxOf(abs(cx - 0.5f), abs(cy - 0.5f))
                if (d > maxCornerDist) maxCornerDist = d
            }

            if (maxCornerDist <= 0f) return maxOpticalZoom
            val safeZoom = (0.5f * margin) / maxCornerDist
            return min(maxOpticalZoom, safeZoom)
        }
    }
}
