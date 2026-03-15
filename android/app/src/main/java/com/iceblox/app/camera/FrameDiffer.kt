package com.iceblox.app.camera

import android.graphics.Bitmap
import android.graphics.Color
import com.iceblox.app.config.AppConfig
import kotlin.math.abs

class FrameDiffer {
    companion object {
        private const val THUMBNAIL_SIZE = 64
        private const val PIXEL_COUNT = THUMBNAIL_SIZE * THUMBNAIL_SIZE
    }

    private var previousThumbnail: IntArray? = null

    @Volatile
    var framesSkippedByDiff: Int = 0
        private set

    fun shouldProcess(bitmap: Bitmap): Boolean {
        val current = downsampleToGrayscale(bitmap)

        val previous = previousThumbnail
        if (previous == null) {
            previousThumbnail = current
            return true
        }

        val diff = meanAbsoluteDifference(previous, current)
        previousThumbnail = current

        if (diff >= AppConfig.FRAME_DIFF_THRESHOLD) {
            return true
        }

        framesSkippedByDiff++
        return false
    }

    fun reset() {
        previousThumbnail = null
    }

    fun downsampleToGrayscale(bitmap: Bitmap): IntArray {
        val scaled = Bitmap.createScaledBitmap(bitmap, THUMBNAIL_SIZE, THUMBNAIL_SIZE, true)
        val grayscale = IntArray(PIXEL_COUNT)

        for (y in 0 until THUMBNAIL_SIZE) {
            for (x in 0 until THUMBNAIL_SIZE) {
                val pixel = scaled.getPixel(x, y)
                val r = Color.red(pixel)
                val g = Color.green(pixel)
                val b = Color.blue(pixel)
                val lum = (0.299 * r + 0.587 * g + 0.114 * b).toInt().coerceIn(0, 255)
                grayscale[y * THUMBNAIL_SIZE + x] = lum
            }
        }

        if (scaled !== bitmap) {
            scaled.recycle()
        }

        return grayscale
    }

    fun meanAbsoluteDifference(a: IntArray, b: IntArray): Float {
        if (a.size != b.size || a.isEmpty()) return 0f
        var sum = 0L
        for (i in a.indices) {
            sum += abs(a[i] - b[i])
        }
        return sum.toFloat() / a.size.toFloat()
    }
}
