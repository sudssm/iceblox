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

data class DetectedPlate(val boundingBox: RectF, val confidence: Float)

class PlateDetector(context: Context) {
    private var interpreter: Interpreter? = null
    private val inputSize = 640
    private val confidenceThreshold = AppConfig.DETECTION_CONFIDENCE_THRESHOLD
    private val iouThreshold = 0.45f
    private val inputBuffer: ByteBuffer =
        ByteBuffer.allocateDirect(1 * inputSize * inputSize * 3 * 4)
            .order(ByteOrder.nativeOrder())

    private var numChannels = NUM_CHANNELS

    init {
        try {
            DebugLog.d(TAG, "Loading model from assets...")
            val model = loadModelFile(context, "plate_detector.tflite")
            DebugLog.d(TAG, "Model file loaded, creating interpreter...")
            val options = Interpreter.Options().apply {
                numThreads = 4
            }
            val interp = Interpreter(model, options)
            val outputShape = interp.getOutputTensor(0).shape()
            DebugLog.d(TAG, "Model output shape: ${outputShape.contentToString()}")
            // YOLOv8 output is [1, num_channels, 8400]
            if (outputShape.size >= 2) {
                numChannels = outputShape[1]
            }
            DebugLog.d(TAG, "Interpreter ready, numChannels=$numChannels (default was $NUM_CHANNELS)")
            interpreter = interp
        } catch (e: Exception) {
            DebugLog.e(TAG, "Model init failed: ${e.javaClass.simpleName}: ${e.message}", e)
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

    @Synchronized
    fun detect(bitmap: Bitmap): List<DetectedPlate> {
        val interp = this.interpreter
        if (interp == null) {
            DebugLog.w(TAG, "detect called but interpreter is null")
            return emptyList()
        }

        val resized = Bitmap.createScaledBitmap(bitmap, inputSize, inputSize, true)

        inputBuffer.rewind()
        val pixels = IntArray(inputSize * inputSize)
        resized.getPixels(pixels, 0, inputSize, 0, 0, inputSize, inputSize)
        for (pixel in pixels) {
            inputBuffer.putFloat(((pixel shr 16) and 0xFF) / 255.0f)
            inputBuffer.putFloat(((pixel shr 8) and 0xFF) / 255.0f)
            inputBuffer.putFloat((pixel and 0xFF) / 255.0f)
        }

        // YOLOv8 output: [1, numChannels, 8400] where numChannels = 4 bbox + num_classes
        val outputArray = Array(1) { Array(numChannels) { FloatArray(NUM_DETECTIONS) } }
        interp.run(inputBuffer, outputArray)

        val rawDetections = parseDetections(
            outputArray[0],
            bitmap.width.toFloat(),
            bitmap.height.toFloat()
        )

        val result = nms(rawDetections)
        if (result.isNotEmpty()) {
            DebugLog.d(
                TAG,
                "detect: ${rawDetections.size} raw -> ${result.size} after NMS (channels=$numChannels, threshold=$confidenceThreshold)"
            )
        }
        return result
    }

    private fun parseDetections(
        output: Array<FloatArray>,
        originalWidth: Float,
        originalHeight: Float
    ): List<DetectedPlate> {
        val detections = mutableListOf<DetectedPlate>()
        val scaleX = originalWidth / inputSize
        val scaleY = originalHeight / inputSize

        var maxConfSeen = 0f
        // Auto-detect coordinate format: scan cx/cy channels to distinguish normalized [0,1] vs pixel [0,640]
        var maxCoord = 0f
        for (i in 0 until NUM_DETECTIONS) {
            maxCoord = maxOf(maxCoord, output[0][i], output[1][i])
        }
        val coordScale = if (maxCoord > 2.0f) 1.0f else inputSize.toFloat()
        if (coordScale != 1.0f) {
            DebugLog.d(TAG, "coordScale=%.0f (maxCoord=%.2f)".format(coordScale, maxCoord))
        }

        for (i in 0 until NUM_DETECTIONS) {
            // Find max class confidence across all class channels (4..numChannels-1)
            var confidence = 0f
            for (c in 4 until numChannels) {
                if (output[c][i] > confidence) confidence = output[c][i]
            }
            if (confidence > maxConfSeen) maxConfSeen = confidence
            if (confidence < confidenceThreshold) continue

            val cx = output[0][i] * coordScale
            val cy = output[1][i] * coordScale
            val w = output[2][i] * coordScale
            val h = output[3][i] * coordScale

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

        if (detections.isNotEmpty()) {
            DebugLog.d(
                TAG,
                "parseDetections: maxConf=%.4f, passed=${detections.size}/$NUM_DETECTIONS"
                    .format(maxConfSeen)
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
        private const val NUM_CHANNELS = 84 // fallback, overridden by model output shape

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
