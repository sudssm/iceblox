package com.iceblox.app.detection

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.nio.ByteBuffer
import java.nio.ByteOrder

data class SlotCandidate(val char: Char, val probability: Float)

data class OCRResult(
    val text: String,
    val confidence: Float,
    val charConfidences: FloatArray,
    val slotCandidates: List<List<SlotCandidate>> = emptyList()
)

class PlateOCR(context: Context) {
    private var session: OrtSession? = null
    private val env = OrtEnvironment.getEnvironment()

    private var inputName = "input"

    private val pixelBuffer = IntArray(TARGET_WIDTH * TARGET_HEIGHT)
    private val rgbBuffer = ByteArray(TARGET_HEIGHT * TARGET_WIDTH * 3)
    private val inputByteBuffer: ByteBuffer =
        ByteBuffer.allocateDirect(TARGET_HEIGHT * TARGET_WIDTH * 3).order(ByteOrder.nativeOrder())

    init {
        try {
            val modelBytes = context.assets.open("plate_ocr.onnx").use { it.readBytes() }
            val sess = env.createSession(modelBytes)
            session = sess
            inputName = sess.inputNames.first()
            val outputInfo = sess.outputInfo.values.first()
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
        } finally {
            cropped.recycle()
        }
    }

    private fun runInference(sess: OrtSession, cropped: Bitmap): OCRResult? {
        val inputData = preprocessImage(cropped)
        val shape = longArrayOf(1, TARGET_HEIGHT.toLong(), TARGET_WIDTH.toLong(), 3)

        inputByteBuffer.clear()
        inputByteBuffer.put(inputData)
        inputByteBuffer.rewind()

        OnnxTensor.createTensor(env, inputByteBuffer, shape, ai.onnxruntime.OnnxJavaType.UINT8).use { inputTensor ->
            sess.run(mapOf(inputName to inputTensor)).use { output ->
                val outputTensor = output[0].value

                @Suppress("UNCHECKED_CAST")
                val result = outputTensor as Array<Array<FloatArray>>
                return fixedSlotDecode(result[0])
            }
        }
    }

    private fun preprocessImage(bitmap: Bitmap): ByteArray {
        val resized = Bitmap.createScaledBitmap(bitmap, TARGET_WIDTH, TARGET_HEIGHT, true)
        try {
            resized.getPixels(pixelBuffer, 0, TARGET_WIDTH, 0, 0, TARGET_WIDTH, TARGET_HEIGHT)

            // Pack as HWC uint8 RGB
            for (y in 0 until TARGET_HEIGHT) {
                for (x in 0 until TARGET_WIDTH) {
                    val pixel = pixelBuffer[y * TARGET_WIDTH + x]
                    val r = ((pixel shr 16) and 0xFF).toByte()
                    val g = ((pixel shr 8) and 0xFF).toByte()
                    val b = (pixel and 0xFF).toByte()

                    val baseIdx = (y * TARGET_WIDTH + x) * 3
                    rgbBuffer[baseIdx] = r
                    rgbBuffer[baseIdx + 1] = g
                    rgbBuffer[baseIdx + 2] = b
                }
            }

            return rgbBuffer
        } finally {
            if (resized !== bitmap) resized.recycle()
        }
    }

    private fun fixedSlotDecode(output: Array<FloatArray>): OCRResult? {
        val decoded = StringBuilder()
        val charConfs = mutableListOf<Float>()
        val allSlotCandidates = mutableListOf<List<SlotCandidate>>()
        var totalConfidence = 0.0f
        var decodedCount = 0

        for (slot in output.indices) {
            val scores = output[slot]

            var maxIdx = 0
            var maxVal = scores[0]
            for (c in 1 until scores.size) {
                if (scores[c] > maxVal) {
                    maxVal = scores[c]
                    maxIdx = c
                }
            }

            if (maxIdx < ALPHABET.length) {
                val ch = ALPHABET[maxIdx]
                if (ch != PAD_CHAR) {
                    decoded.append(ch)
                    charConfs.add(maxVal)
                    totalConfidence += maxVal
                    decodedCount++

                    val candidates = mutableListOf<SlotCandidate>()
                    for (c in scores.indices) {
                        if (c < ALPHABET.length &&
                            ALPHABET[c] != PAD_CHAR &&
                            scores[c] >= AppConfig.OCR_CANDIDATE_THRESHOLD
                        ) {
                            candidates.add(SlotCandidate(ALPHABET[c], scores[c]))
                        }
                    }
                    candidates.sortByDescending { it.probability }
                    allSlotCandidates.add(candidates)
                }
            }
        }

        if (decodedCount == 0) return null

        val avgConfidence = totalConfidence / decodedCount
        if (avgConfidence < AppConfig.OCR_CONFIDENCE_THRESHOLD) return null

        return OCRResult(
            text = decoded.toString(),
            confidence = avgConfidence,
            charConfidences = charConfs.toFloatArray(),
            slotCandidates = allSlotCandidates
        )
    }

    fun close() {
        session?.close()
    }

    companion object {
        private const val TAG = "PlateOCR"
        private const val TARGET_HEIGHT = 64
        private const val TARGET_WIDTH = 128
        private const val ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_"
        private const val PAD_CHAR = '_'
    }
}
