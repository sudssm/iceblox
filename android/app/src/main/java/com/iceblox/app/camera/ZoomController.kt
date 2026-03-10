package com.iceblox.app.camera

import android.content.Context
import android.graphics.RectF
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import androidx.camera.core.Camera
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import kotlin.math.abs
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
        DebugLog.d(TAG, "maxOpticalZoom=$maxOpticalZoom available=$isZoomRetryAvailable")
    }

    fun setCamera(camera: Camera) {
        this.camera = camera
    }

    fun isOnCooldown(): Boolean {
        return System.currentTimeMillis() - lastRetryTime < AppConfig.ZOOM_RETRY_COOLDOWN_MS
    }

    fun isPlateEligibleForZoom(boundingBox: RectF, imageWidth: Int, imageHeight: Int): Boolean {
        if (maxOpticalZoom <= 1.0f) return false
        val w = imageWidth.toFloat()
        val h = imageHeight.toFloat()
        if (w <= 0f || h <= 0f) return false

        val nx0 = boundingBox.left / w
        val ny0 = boundingBox.top / h
        val nx1 = boundingBox.right / w
        val ny1 = boundingBox.bottom / h

        val limit = 0.5f * (1.0f / maxOpticalZoom) * AppConfig.ZOOM_RETRY_MARGIN

        val corners = arrayOf(
            nx0 to ny0, nx1 to ny0, nx0 to ny1, nx1 to ny1
        )
        for ((cx, cy) in corners) {
            if (abs(cx - 0.5f) > limit || abs(cy - 0.5f) > limit) {
                return false
            }
        }
        return true
    }

    fun bestCandidateIndex(
        detections: List<Triple<RectF, Int, Int>>
    ): Int? {
        var bestIdx: Int? = null
        var bestDist = Float.MAX_VALUE

        for ((i, det) in detections.withIndex()) {
            val (box, imgW, imgH) = det
            if (!isPlateEligibleForZoom(box, imgW, imgH)) continue
            val cx = (box.centerX() / imgW.toFloat()) - 0.5f
            val cy = (box.centerY() / imgH.toFloat()) - 0.5f
            val dist = sqrt(cx * cx + cy * cy)
            if (dist < bestDist) {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }

    fun zoomIn(): Boolean {
        val cam = camera ?: return false
        return try {
            cam.cameraControl.setZoomRatio(maxOpticalZoom)
            lastRetryTime = System.currentTimeMillis()
            zoomRetryAttempts++
            true
        } catch (e: Exception) {
            DebugLog.e(TAG, "Failed to zoom in: ${e.message}", e)
            false
        }
    }

    fun restoreZoom() {
        val cam = camera ?: return
        try {
            cam.cameraControl.setZoomRatio(1.0f)
        } catch (e: Exception) {
            DebugLog.e(TAG, "Failed to restore zoom: ${e.message}", e)
        }
    }

    fun recordSuccess() {
        zoomRetrySuccesses++
    }

    private fun detectMaxOpticalZoom(context: Context): Float {
        return try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val backCameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: return 1.0f

            val chars = cameraManager.getCameraCharacteristics(backCameraId)
            val focalLengths = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?: return 1.0f

            if (focalLengths.size <= 1) return 1.0f
            val minFocal = focalLengths.minOrNull() ?: return 1.0f
            val maxFocal = focalLengths.maxOrNull() ?: return 1.0f
            if (minFocal <= 0f) return 1.0f
            maxFocal / minFocal
        } catch (e: Exception) {
            DebugLog.e(TAG, "Failed to detect optical zoom: ${e.message}", e)
            1.0f
        }
    }

    companion object {
        private const val TAG = "ZoomController"

        fun isPlateEligible(
            boundingBox: RectF,
            imageWidth: Int,
            imageHeight: Int,
            maxOpticalZoom: Float,
            margin: Float
        ): Boolean {
            if (maxOpticalZoom <= 1.0f) return false
            val w = imageWidth.toFloat()
            val h = imageHeight.toFloat()
            if (w <= 0f || h <= 0f) return false

            val nx0 = boundingBox.left / w
            val ny0 = boundingBox.top / h
            val nx1 = boundingBox.right / w
            val ny1 = boundingBox.bottom / h

            val limit = 0.5f * (1.0f / maxOpticalZoom) * margin

            val corners = arrayOf(
                nx0 to ny0, nx1 to ny0, nx0 to ny1, nx1 to ny1
            )
            for ((cx, cy) in corners) {
                if (abs(cx - 0.5f) > limit || abs(cy - 0.5f) > limit) {
                    return false
                }
            }
            return true
        }
    }
}
