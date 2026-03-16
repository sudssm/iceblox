package com.iceblox.app.camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.RectF
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import com.iceblox.app.detection.PlateDetector
import com.iceblox.app.detection.PlateOCR
import com.iceblox.app.detection.SlotCandidate
import com.iceblox.app.processing.PlateHasher
import com.iceblox.app.processing.PlateNormalizer
import com.iceblox.app.ui.DebugDetection
import com.iceblox.app.ui.RawDetectionBox
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class ProcessedPlate(
    val normalizedText: String,
    val boundingBox: RectF,
    val confidence: Float,
    val charConfidences: FloatArray = FloatArray(0),
    val slotCandidates: List<List<SlotCandidate>> = emptyList()
)

class FrameAnalyzer(context: Context, private val onPlatesDetected: (List<ProcessedPlate>) -> Unit) :
    ImageAnalysis.Analyzer {
    private val detector = PlateDetector(context)
    private val ocr = PlateOCR(context)
    val frameDiffer = FrameDiffer()

    private val rotationMatrix = Matrix()
    private var frameCount = 0

    @Volatile var frameSkipCount = AppConfig.FRAME_SKIP_COUNT

    @Volatile var isThrottled = false

    var zoomController: ZoomController? = null
    var previewFreezer: PreviewFreezer? = null
    var debugMode = false

    private var lastBitmap: Bitmap? = null

    private var lastFpsTime = System.nanoTime()
    private var fpsFrameCount = 0
    private var rawDetectionsTimestamp = 0L
    private var debugDetectionsTimestamp = 0L

    private val _fps = MutableStateFlow(0.0)
    val fps: StateFlow<Double> = _fps

    private val _framesSkippedByDiff = MutableStateFlow(0)
    val framesSkippedByDiff: StateFlow<Int> = _framesSkippedByDiff

    private val _debugDetections = MutableStateFlow<List<DebugDetection>>(emptyList())
    val debugDetections: StateFlow<List<DebugDetection>> = _debugDetections

    private val _rawDetections = MutableStateFlow<List<RawDetectionBox>>(emptyList())
    val rawDetections: StateFlow<List<RawDetectionBox>> = _rawDetections

    private enum class ZoomRetryState { IDLE, AWAITING_FRAME }

    @Volatile private var zoomRetryState = ZoomRetryState.IDLE
    private var framesToSkipAfterZoom = 0
    private var zoomRetryStartTime = 0L
    private var zoomShotRatios = floatArrayOf()
    private var currentShotIdx = 0
    private val zoomedPlatesAccumulator = mutableListOf<ProcessedPlate>()

    override fun analyze(imageProxy: ImageProxy) {
        try {
            if (zoomRetryState == ZoomRetryState.AWAITING_FRAME) {
                if (framesToSkipAfterZoom > 0) {
                    framesToSkipAfterZoom--
                    return
                }

                val elapsedMs = System.currentTimeMillis() - zoomRetryStartTime
                if (elapsedMs > AppConfig.ZOOM_RETRY_MAX_WAIT_MS) {
                    DebugLog.w(
                        TAG,
                        "Zoom retry TIMED OUT after ${elapsedMs}ms (max=${AppConfig.ZOOM_RETRY_MAX_WAIT_MS}ms)"
                    )
                    finishZoomRetry()
                    return
                }

                val bitmap = extractBitmap(imageProxy)
                zoomedPlatesAccumulator.addAll(extractPlatesFromFrame(bitmap))

                currentShotIdx++
                if (currentShotIdx < zoomShotRatios.size) {
                    val nextRatio = zoomShotRatios[currentShotIdx]
                    zoomController?.zoomIn(nextRatio)
                    framesToSkipAfterZoom = 1
                    return
                }

                finishZoomRetry()
                return
            }

            frameCount++
            if (frameCount % (frameSkipCount + 1) != 0) {
                return
            }

            updateFps()

            val bitmap = extractBitmap(imageProxy)
            lastBitmap = bitmap

            if (AppConfig.FRAME_DIFF_ENABLED && !frameDiffer.shouldProcess(bitmap)) {
                _framesSkippedByDiff.value = frameDiffer.framesSkippedByDiff
                return
            }

            val detections = detector.detect(bitmap)

            if (detections.isNotEmpty()) {
                _rawDetections.value = detections.map { det ->
                    RawDetectionBox(
                        boundingBox = det.boundingBox,
                        confidence = det.confidence,
                        imageWidth = bitmap.width,
                        imageHeight = bitmap.height
                    )
                }
                rawDetectionsTimestamp = System.currentTimeMillis()
            } else if (System.currentTimeMillis() - rawDetectionsTimestamp > DETECTIONS_HOLD_MS) {
                _rawDetections.value = emptyList()
            }

            val plates = mutableListOf<ProcessedPlate>()
            val failedDetections = mutableListOf<Triple<RectF, Int, Int>>()

            for (detection in detections) {
                val ocrResult = ocr.recognizeText(bitmap, detection.boundingBox)
                if (ocrResult != null) {
                    val normalized = PlateNormalizer.normalize(ocrResult.text)
                        ?: continue
                    plates.add(
                        ProcessedPlate(
                            normalizedText = normalized,
                            boundingBox = detection.boundingBox,
                            confidence = detection.confidence,
                            charConfidences = ocrResult.charConfidences.copyOf(normalized.length),
                            slotCandidates = ocrResult.slotCandidates.take(normalized.length)
                        )
                    )
                    if (ocrResult.confidence < AppConfig.ZOOM_RETRY_LOW_CONFIDENCE_THRESHOLD) {
                        failedDetections.add(Triple(detection.boundingBox, bitmap.width, bitmap.height))
                    }
                } else {
                    failedDetections.add(Triple(detection.boundingBox, bitmap.width, bitmap.height))
                }
            }

            if (plates.isNotEmpty()) {
                _debugDetections.value = plates.map { plate ->
                    DebugDetection(
                        plateText = plate.normalizedText,
                        hash = PlateHasher.hash(plate.normalizedText),
                        boundingBox = plate.boundingBox,
                        imageWidth = bitmap.width,
                        imageHeight = bitmap.height
                    )
                }
                debugDetectionsTimestamp = System.currentTimeMillis()
                onPlatesDetected(plates)
            } else if (System.currentTimeMillis() - debugDetectionsTimestamp > DETECTIONS_HOLD_MS) {
                _debugDetections.value = emptyList()
            }

            if (failedDetections.isNotEmpty()) {
                attemptZoomRetry(failedDetections, bitmap)
            }
        } catch (e: Exception) {
            DebugLog.e(TAG, "Frame analysis failed: ${e.javaClass.simpleName}: ${e.message}", e)
        } finally {
            imageProxy.close()
        }
    }

    private fun attemptZoomRetry(failedDetections: List<Triple<RectF, Int, Int>>, bitmap: Bitmap) {
        val zc = zoomController ?: return
        if (!zc.isZoomRetryAvailable || zc.isOnCooldown() || isThrottled) return

        val best = zc.bestCandidate(failedDetections) ?: return
        val (_, safeZoom) = best

        val ratios = if (safeZoom < zc.maxOpticalZoom) {
            floatArrayOf(safeZoom, zc.maxOpticalZoom)
        } else {
            floatArrayOf(safeZoom)
        }

        previewFreezer?.freeze(if (!debugMode) bitmap else null, debugMode)

        if (!zc.zoomIn(ratios[0])) {
            DebugLog.w(TAG, "Zoom retry: zoomIn() failed, unfreezing")
            previewFreezer?.unfreeze()
            return
        }

        zoomShotRatios = ratios
        currentShotIdx = 0
        zoomedPlatesAccumulator.clear()
        framesToSkipAfterZoom = 2
        zoomRetryStartTime = System.currentTimeMillis()
        zoomRetryState = ZoomRetryState.AWAITING_FRAME
    }

    private fun extractPlatesFromFrame(bitmap: Bitmap): List<ProcessedPlate> {
        val detections = detector.detect(bitmap)

        val plates = mutableListOf<ProcessedPlate>()
        for (detection in detections) {
            val ocrResult = ocr.recognizeText(bitmap, detection.boundingBox) ?: continue
            val normalized = PlateNormalizer.normalize(ocrResult.text) ?: continue
            plates.add(
                ProcessedPlate(
                    normalizedText = normalized,
                    boundingBox = detection.boundingBox,
                    confidence = detection.confidence,
                    charConfidences = ocrResult.charConfidences.copyOf(normalized.length),
                    slotCandidates = ocrResult.slotCandidates.take(normalized.length)
                )
            )
            zoomController?.recordSuccess()
            DebugLog.d(TAG, "Zoom retry SUCCESS: '$normalized' (raw='${ocrResult.text}', conf=${detection.confidence})")
        }
        return plates
    }

    private fun finishZoomRetry() {
        try {
            if (zoomedPlatesAccumulator.isNotEmpty()) {
                onPlatesDetected(zoomedPlatesAccumulator.toList())
            }
        } finally {
            zoomedPlatesAccumulator.clear()
            zoomRetryState = ZoomRetryState.IDLE
            val future = zoomController?.restoreZoom()
            if (future != null) {
                future.addListener({ previewFreezer?.unfreeze() }, { it.run() })
            } else {
                previewFreezer?.unfreeze()
            }
        }
    }

    private fun extractBitmap(imageProxy: ImageProxy): Bitmap {
        val rawBitmap = imageProxy.toBitmap()
        val rotationDegrees = imageProxy.imageInfo.rotationDegrees
        return if (rotationDegrees != 0) {
            rotationMatrix.reset()
            rotationMatrix.postRotate(rotationDegrees.toFloat())
            val rotated = Bitmap.createBitmap(
                rawBitmap,
                0,
                0,
                rawBitmap.width,
                rawBitmap.height,
                rotationMatrix,
                true
            )
            rawBitmap.recycle()
            rotated
        } else {
            rawBitmap
        }
    }

    fun analyzeBitmap(bitmap: Bitmap, useFallback: Boolean = true) {
        try {
            val detections = detector.detect(bitmap)
            DebugLog.d(TAG, "Test image: ${detections.size} detections")

            val plates = detections.mapNotNull { detection ->
                val ocrResult = ocr.recognizeText(bitmap, detection.boundingBox)
                    ?: return@mapNotNull null
                DebugLog.d(TAG, "OCR result: ${ocrResult.text} (conf=${ocrResult.confidence})")
                val normalized = PlateNormalizer.normalize(ocrResult.text)
                    ?: return@mapNotNull null
                DebugLog.d(TAG, "Normalized: $normalized")

                ProcessedPlate(
                    normalizedText = normalized,
                    boundingBox = detection.boundingBox,
                    confidence = detection.confidence,
                    charConfidences = ocrResult.charConfidences.copyOf(normalized.length),
                    slotCandidates = ocrResult.slotCandidates.take(normalized.length)
                )
            }

            if (plates.isNotEmpty()) {
                DebugLog.d(TAG, "Test image produced ${plates.size} plates")
                onPlatesDetected(plates)
            } else if (useFallback) {
                DebugLog.w(TAG, "Test image: no plates extracted, injecting fallback")
                onPlatesDetected(listOf(ProcessedPlate("AB12345", RectF(), 1.0f, charConfidences = FloatArray(7))))
            } else {
                DebugLog.d(TAG, "Test image: no plates extracted")
            }
        } catch (e: Exception) {
            DebugLog.w(TAG, "Test image analysis failed: ${e.javaClass.simpleName}: ${e.message}", e)
            if (useFallback) {
                onPlatesDetected(listOf(ProcessedPlate("AB12345", RectF(), 1.0f, charConfidences = FloatArray(7))))
            }
        }
    }

    private fun updateFps() {
        fpsFrameCount++
        val now = System.nanoTime()
        val elapsed = (now - lastFpsTime) / 1_000_000_000.0
        if (elapsed >= 1.0) {
            _fps.value = fpsFrameCount / elapsed
            fpsFrameCount = 0
            lastFpsTime = now
        }
    }

    fun close() {
        detector.close()
        ocr.close()
    }

    companion object {
        private const val TAG = "FrameAnalyzer"
        private const val DETECTIONS_HOLD_MS = 1000L
    }
}
