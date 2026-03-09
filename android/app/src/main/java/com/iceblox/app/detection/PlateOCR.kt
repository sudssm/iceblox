package com.iceblox.app.detection

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.nio.FloatBuffer
import kotlin.math.min
import kotlin.math.roundToInt

data class OCRResult(val text: String, val confidence: Float)

class PlateOCR(context: Context) {
    private var session: OrtSession? = null
    private val env = OrtEnvironment.getEnvironment()

    private var inputName = "x"

    init {
        try {
            val modelBytes = context.assets.open("plate_ocr.onnx").use { it.readBytes() }
            session = env.createSession(modelBytes)
            inputName = session!!.inputNames.first()
            val outputInfo = session!!.outputInfo.values.first()
            DebugLog.d(TAG, "OCR model loaded (ONNX Runtime), input=$inputName, output=${outputInfo.info}")
        } catch (e: Exception) {
            DebugLog.e(TAG, "OCR model init failed: ${e.javaClass.simpleName}: ${e.message}", e)
        }
    }

    fun recognizeText(bitmap: Bitmap, region: RectF): OCRResult? {
        val sess = session ?: return null

        val left = maxOf(0, region.left.toInt())
        val top = maxOf(0, region.top.toInt())
        val right = minOf(bitmap.width, region.right.toInt())
        val bottom = minOf(bitmap.height, region.bottom.toInt())
        val width = right - left
        val height = bottom - top

        if (width <= 0 || height <= 0) return null

        val cropped = Bitmap.createBitmap(bitmap, left, top, width, height)
        return try {
            runInference(sess, cropped)
        } catch (e: Exception) {
            DebugLog.w(TAG, "OCR failed: ${e.message}")
            null
        }
    }

    private fun runInference(sess: OrtSession, cropped: Bitmap): OCRResult? {
        val inputData = preprocessImage(cropped)
        val shape = longArrayOf(1, 3, TARGET_HEIGHT.toLong(), TARGET_WIDTH.toLong())

        OnnxTensor.createTensor(env, FloatBuffer.wrap(inputData), shape).use { inputTensor ->
            sess.run(mapOf(inputName to inputTensor)).use { output ->
                val outputTensor = output[0].value
                @Suppress("UNCHECKED_CAST")
                val result = outputTensor as Array<Array<FloatArray>>
                return ctcDecode(result[0])
            }
        }
    }

    private fun preprocessImage(bitmap: Bitmap): FloatArray {
        val h = bitmap.height
        val w = bitmap.width

        val scale = TARGET_HEIGHT.toFloat() / h
        val scaledWidth = min((w * scale).roundToInt(), TARGET_WIDTH)

        val resized = Bitmap.createScaledBitmap(bitmap, scaledWidth, TARGET_HEIGHT, true)
        val pixels = IntArray(scaledWidth * TARGET_HEIGHT)
        resized.getPixels(pixels, 0, scaledWidth, 0, 0, scaledWidth, TARGET_HEIGHT)

        val hw = TARGET_HEIGHT * TARGET_WIDTH
        val data = FloatArray(3 * hw) { -1.0f }

        for (y in 0 until TARGET_HEIGHT) {
            for (x in 0 until scaledWidth) {
                val pixel = pixels[y * scaledWidth + x]
                val r = ((pixel shr 16) and 0xFF).toFloat()
                val g = ((pixel shr 8) and 0xFF).toFloat()
                val b = (pixel and 0xFF).toFloat()

                val idx = y * TARGET_WIDTH + x
                data[0 * hw + idx] = (r / 255.0f - 0.5f) / 0.5f
                data[1 * hw + idx] = (g / 255.0f - 0.5f) / 0.5f
                data[2 * hw + idx] = (b / 255.0f - 0.5f) / 0.5f
            }
        }

        return data
    }

    private fun ctcDecode(output: Array<FloatArray>): OCRResult? {
        val decoded = StringBuilder()
        var totalConfidence = 0.0f
        var decodedCount = 0
        var prevIndex = -1

        for (t in output.indices) {
            val scores = output[t]

            // Argmax
            var maxIdx = 0
            var maxVal = scores[0]
            for (c in 1 until scores.size) {
                if (scores[c] > maxVal) {
                    maxVal = scores[c]
                    maxIdx = c
                }
            }

            // Skip blank (index 0) and collapse consecutive duplicates
            if (maxIdx != 0 && maxIdx != prevIndex) {
                // Model outputs softmax probabilities — use max value directly
                val prob = maxVal

                val charIdx = maxIdx - 1
                if (charIdx < DICTIONARY.length) {
                    decoded.append(DICTIONARY[charIdx])
                    totalConfidence += prob
                    decodedCount++
                }
            }
            prevIndex = maxIdx
        }

        if (decodedCount == 0) return null

        val avgConfidence = totalConfidence / decodedCount
        if (avgConfidence < AppConfig.OCR_CONFIDENCE_THRESHOLD) return null

        return OCRResult(text = decoded.toString(), confidence = avgConfidence)
    }

    fun close() {
        session?.close()
    }

    companion object {
        private const val TAG = "PlateOCR"
        private const val TARGET_HEIGHT = 48
        private const val TARGET_WIDTH = 320

        // PP-OCRv3 en_dict.txt character order (NOT ASCII order).
        // Index 0 = CTC blank; indices 1..95 map to characters in this string.
        // Index 96 = unknown/padding (ignored).
        // Order: space, 0-9, :-~, !-/
        private const val DICTIONARY =
            " 0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~!\"#\$%&'()*+,-./"
    }
}
