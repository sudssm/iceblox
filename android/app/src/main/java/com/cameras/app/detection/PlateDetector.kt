package com.cameras.app.detection

import android.content.Context
import android.graphics.Bitmap
import android.graphics.RectF
import android.util.Log
import org.tensorflow.lite.Interpreter
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel

data class DetectedPlate(
    val boundingBox: RectF,
    val confidence: Float
)

class PlateDetector(context: Context) {
    private var interpreter: Interpreter? = null
    private val inputSize = 640
    private val confidenceThreshold = 0.7f
    private val iouThreshold = 0.45f
    private val inputBuffer: ByteBuffer =
        ByteBuffer.allocateDirect(1 * inputSize * inputSize * 3 * 4)
            .order(ByteOrder.nativeOrder())

    init {
        try {
            val model = loadModelFile(context, "plate_detector.tflite")
            val options = Interpreter.Options().apply {
                numThreads = 4
            }
            interpreter = Interpreter(model, options)
        } catch (e: Exception) {
            Log.w(TAG, "Model not found in assets — detection disabled: ${e.message}")
        }
    }

    private fun loadModelFile(context: Context, filename: String): MappedByteBuffer {
        val fileDescriptor = context.assets.openFd(filename)
        return FileInputStream(fileDescriptor.fileDescriptor).use { inputStream ->
            val fileChannel = inputStream.channel
            fileChannel.map(
                FileChannel.MapMode.READ_ONLY,
                fileDescriptor.startOffset,
                fileDescriptor.declaredLength
            )
        }
    }

    fun detect(bitmap: Bitmap): List<DetectedPlate> {
        val interpreter = this.interpreter ?: return emptyList()

        val resized = Bitmap.createScaledBitmap(bitmap, inputSize, inputSize, true)

        inputBuffer.rewind()
        val pixels = IntArray(inputSize * inputSize)
        resized.getPixels(pixels, 0, inputSize, 0, 0, inputSize, inputSize)
        for (pixel in pixels) {
            inputBuffer.putFloat(((pixel shr 16) and 0xFF) / 255.0f)
            inputBuffer.putFloat(((pixel shr 8) and 0xFF) / 255.0f)
            inputBuffer.putFloat((pixel and 0xFF) / 255.0f)
        }

        // YOLOv8 output: [1, NUM_CHANNELS, 8400] where NUM_CHANNELS = 4 bbox + num_classes
        val outputArray = Array(1) { Array(NUM_CHANNELS) { FloatArray(NUM_DETECTIONS) } }
        interpreter.run(inputBuffer, outputArray)

        val rawDetections = parseDetections(
            outputArray[0],
            bitmap.width.toFloat(),
            bitmap.height.toFloat()
        )

        return nms(rawDetections)
    }

    private fun parseDetections(
        output: Array<FloatArray>,
        originalWidth: Float,
        originalHeight: Float
    ): List<DetectedPlate> {
        val detections = mutableListOf<DetectedPlate>()
        val scaleX = originalWidth / inputSize
        val scaleY = originalHeight / inputSize

        for (i in 0 until NUM_DETECTIONS) {
            // Find max class confidence across all class channels (4..NUM_CHANNELS-1)
            var confidence = 0f
            for (c in 4 until NUM_CHANNELS) {
                if (output[c][i] > confidence) confidence = output[c][i]
            }
            if (confidence < confidenceThreshold) continue

            val cx = output[0][i]
            val cy = output[1][i]
            val w = output[2][i]
            val h = output[3][i]

            val x1 = (cx - w / 2) * scaleX
            val y1 = (cy - h / 2) * scaleY
            val x2 = (cx + w / 2) * scaleX
            val y2 = (cy + h / 2) * scaleY

            detections.add(
                DetectedPlate(
                    boundingBox = RectF(x1, y1, x2, y2),
                    confidence = confidence
                )
            )
        }

        return detections
    }

    fun close() {
        interpreter?.close()
    }

    companion object {
        private const val TAG = "PlateDetector"
        private const val NUM_DETECTIONS = 8400
        private const val NUM_CHANNELS = 84 // 4 bbox + 80 class scores (YOLOv8)

        fun nms(detections: List<DetectedPlate>, iouThreshold: Float = 0.45f): List<DetectedPlate> {
            if (detections.isEmpty()) return emptyList()

            val sorted = detections.sortedByDescending { it.confidence }
            val selected = mutableListOf<DetectedPlate>()
            val suppressed = BooleanArray(sorted.size)

            for (i in sorted.indices) {
                if (suppressed[i]) continue
                selected.add(sorted[i])
                for (j in i + 1 until sorted.size) {
                    if (suppressed[j]) continue
                    if (iou(sorted[i].boundingBox, sorted[j].boundingBox) > iouThreshold) {
                        suppressed[j] = true
                    }
                }
            }

            return selected
        }

        fun iou(a: RectF, b: RectF): Float {
            val intersectLeft = maxOf(a.left, b.left)
            val intersectTop = maxOf(a.top, b.top)
            val intersectRight = minOf(a.right, b.right)
            val intersectBottom = minOf(a.bottom, b.bottom)

            val intersectArea =
                maxOf(0f, intersectRight - intersectLeft) * maxOf(0f, intersectBottom - intersectTop)
            val aArea = (a.right - a.left) * (a.bottom - a.top)
            val bArea = (b.right - b.left) * (b.bottom - b.top)
            val unionArea = aArea + bArea - intersectArea

            return if (unionArea > 0f) intersectArea / unionArea else 0f
        }
    }
}
