package com.iceblox.app.detection

import android.graphics.Bitmap
import android.graphics.RectF
import com.iceblox.app.debug.DebugLog
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

data class OCRResult(val text: String, val confidence: Float)

class PlateOCR {
    private val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    private val confidenceThreshold = 0.6f

    fun recognizeText(bitmap: Bitmap, region: RectF): OCRResult? {
        val left = maxOf(0, region.left.toInt())
        val top = maxOf(0, region.top.toInt())
        val right = minOf(bitmap.width, region.right.toInt())
        val bottom = minOf(bitmap.height, region.bottom.toInt())
        val width = right - left
        val height = bottom - top

        if (width <= 0 || height <= 0) return null

        val cropped = Bitmap.createBitmap(bitmap, left, top, width, height)
        val image = InputImage.fromBitmap(cropped, 0)

        return try {
            val result = Tasks.await(recognizer.process(image))
            val bestLine = result.textBlocks
                .flatMap { it.lines }
                .maxByOrNull { it.text.length }

            if (bestLine != null) {
                val confidence = bestLine.confidence ?: 1.0f
                if (confidence >= confidenceThreshold) {
                    OCRResult(text = bestLine.text, confidence = confidence)
                } else {
                    null
                }
            } else {
                null
            }
        } catch (e: Exception) {
            DebugLog.w(TAG, "OCR failed: ${e.message}")
            null
        }
    }

    companion object {
        private const val TAG = "PlateOCR"
    }
}
