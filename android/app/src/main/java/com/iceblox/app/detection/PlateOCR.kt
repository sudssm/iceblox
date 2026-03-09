package com.iceblox.app.detection

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import org.tensorflow.lite.Interpreter
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.roundToInt

data class OCRResult(val text: String, val confidence: Float)

class PlateOCR(context: Context) {
    private var interpreter: Interpreter? = null
    private val inputBuffer: ByteBuffer =
        ByteBuffer.allocateDirect(1 * 3 * TARGET_HEIGHT * TARGET_WIDTH * 4)
            .order(ByteOrder.nativeOrder())

    private var seqLen = 0
    private var numClasses = 0

    init {
        try {
            val model = loadModelFile(context, "plate_ocr.tflite")
            val options = Interpreter.Options().apply { numThreads = 4 }
            val interp = Interpreter(model, options)
            val outputShape = interp.getOutputTensor(0).shape()
            DebugLog.d(TAG, "OCR model loaded, output shape: ${outputShape.contentToString()}")

            // Output: [1, seq_len, num_classes] or [seq_len, num_classes]
            if (outputShape.size == 3) {
                seqLen = outputShape[1]
                numClasses = outputShape[2]
            } else if (outputShape.size == 2) {
                seqLen = outputShape[0]
                numClasses = outputShape[1]
            }
            interpreter = interp
        } catch (e: Exception) {
            DebugLog.e(TAG, "OCR model init failed: ${e.javaClass.simpleName}: ${e.message}", e)
        }
    }

    private fun loadModelFile(context: Context, filename: String): MappedByteBuffer {
        val fd = context.assets.openFd(filename)
        return FileInputStream(fd.fileDescriptor).use { inputStream ->
            inputStream.channel.map(
                FileChannel.MapMode.READ_ONLY,
                fd.startOffset,
                fd.declaredLength
            )
        }
    }

    fun recognizeText(bitmap: Bitmap, region: RectF): OCRResult? {
        val interp = interpreter ?: return null

        val left = maxOf(0, region.left.toInt())
        val top = maxOf(0, region.top.toInt())
        val right = minOf(bitmap.width, region.right.toInt())
        val bottom = minOf(bitmap.height, region.bottom.toInt())
        val width = right - left
        val height = bottom - top

        if (width <= 0 || height <= 0) return null

        val cropped = Bitmap.createBitmap(bitmap, left, top, width, height)
        return try {
            runInference(interp, cropped)
        } catch (e: Exception) {
            DebugLog.w(TAG, "OCR failed: ${e.message}")
            null
        }
    }

    private fun runInference(interp: Interpreter, cropped: Bitmap): OCRResult? {
        preprocessImage(cropped)

        val outputArray = Array(1) { Array(seqLen) { FloatArray(numClasses) } }
        interp.run(inputBuffer, outputArray)

        return ctcDecode(outputArray[0])
    }

    private fun preprocessImage(bitmap: Bitmap) {
        val h = bitmap.height
        val w = bitmap.width

        val scale = TARGET_HEIGHT.toFloat() / h
        val scaledWidth = min((w * scale).roundToInt(), TARGET_WIDTH)

        val resized = Bitmap.createScaledBitmap(bitmap, scaledWidth, TARGET_HEIGHT, true)
        val pixels = IntArray(scaledWidth * TARGET_HEIGHT)
        resized.getPixels(pixels, 0, scaledWidth, 0, 0, scaledWidth, TARGET_HEIGHT)

        inputBuffer.rewind()

        // CHW layout: fill R channel, then G, then B
        val hw = TARGET_HEIGHT * TARGET_WIDTH
        // Pre-fill with -1.0f (normalized black)
        for (i in 0 until 3 * hw) {
            inputBuffer.putFloat(-1.0f)
        }

        inputBuffer.rewind()
        val channels = Array(3) { FloatArray(hw) { -1.0f } }

        for (y in 0 until TARGET_HEIGHT) {
            for (x in 0 until scaledWidth) {
                val pixel = pixels[y * scaledWidth + x]
                val r = ((pixel shr 16) and 0xFF).toFloat()
                val g = ((pixel shr 8) and 0xFF).toFloat()
                val b = (pixel and 0xFF).toFloat()

                val idx = y * TARGET_WIDTH + x
                channels[0][idx] = (r / 255.0f - 0.5f) / 0.5f
                channels[1][idx] = (g / 255.0f - 0.5f) / 0.5f
                channels[2][idx] = (b / 255.0f - 0.5f) / 0.5f
            }
        }

        inputBuffer.rewind()
        for (c in 0 until 3) {
            for (v in channels[c]) {
                inputBuffer.putFloat(v)
            }
        }
    }

    private fun ctcDecode(logits: Array<FloatArray>): OCRResult? {
        val decoded = StringBuilder()
        var totalConfidence = 0.0f
        var decodedCount = 0
        var prevIndex = -1

        for (t in logits.indices) {
            val scores = logits[t]

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
                // Softmax probability
                var sumExp = 0.0f
                for (c in scores.indices) {
                    sumExp += exp(scores[c] - maxVal)
                }
                val prob = 1.0f / sumExp

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
        interpreter?.close()
    }

    companion object {
        private const val TAG = "PlateOCR"
        private const val TARGET_HEIGHT = 48
        private const val TARGET_WIDTH = 320

        // PP-OCRv3 en_dict.txt: printable ASCII characters (space through tilde).
        // Index 0 = CTC blank; indices 1..N map to characters in this string.
        private val DICTIONARY: String = buildString {
            for (code in 32..126) {
                append(code.toChar())
            }
        }
    }
}
