package com.cameras.app.camera

import android.content.Context
import android.graphics.RectF
import android.util.Log
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import com.cameras.app.detection.PlateDetector
import com.cameras.app.detection.PlateOCR
import com.cameras.app.processing.PlateNormalizer

data class ProcessedPlate(
    val normalizedText: String,
    val boundingBox: RectF,
    val confidence: Float
)

class FrameAnalyzer(
    context: Context,
    private val onPlatesDetected: (List<ProcessedPlate>) -> Unit
) : ImageAnalysis.Analyzer {
    private val detector = PlateDetector(context)
    private val ocr = PlateOCR()

    override fun analyze(imageProxy: ImageProxy) {
        try {
            val bitmap = imageProxy.toBitmap()
            val detections = detector.detect(bitmap)

            val plates = detections.mapNotNull { detection ->
                val ocrResult = ocr.recognizeText(bitmap, detection.boundingBox)
                    ?: return@mapNotNull null
                val normalized = PlateNormalizer.normalize(ocrResult.text)
                    ?: return@mapNotNull null

                ProcessedPlate(
                    normalizedText = normalized,
                    boundingBox = detection.boundingBox,
                    confidence = detection.confidence
                )
            }

            if (plates.isNotEmpty()) {
                onPlatesDetected(plates)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Frame analysis failed: ${e.message}")
        } finally {
            imageProxy.close()
        }
    }

    fun close() {
        detector.close()
    }

    companion object {
        private const val TAG = "FrameAnalyzer"
    }
}
