package com.iceblox.app

import android.graphics.Bitmap
import android.graphics.Color
import com.iceblox.app.camera.FrameDiffer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class FrameDifferTest {

    @Test
    fun firstFrameReturnsTrue() {
        val differ = FrameDiffer()
        val bitmap = makeSolidBitmap(Color.GRAY)
        assertTrue(differ.shouldProcess(bitmap))
    }

    @Test
    fun identicalFramesReturnsFalse() {
        val differ = FrameDiffer()
        val bitmap1 = makeSolidBitmap(Color.GRAY)
        val bitmap2 = makeSolidBitmap(Color.GRAY)

        differ.shouldProcess(bitmap1)
        assertFalse(differ.shouldProcess(bitmap2))
    }

    @Test
    fun differentFramesReturnsTrue() {
        val differ = FrameDiffer()
        val bitmap1 = makeSolidBitmap(Color.BLACK)
        val bitmap2 = makeSolidBitmap(Color.WHITE)

        differ.shouldProcess(bitmap1)
        assertTrue(differ.shouldProcess(bitmap2))
    }

    @Test
    fun resetClearsPreviousThumbnail() {
        val differ = FrameDiffer()
        val bitmap1 = makeSolidBitmap(Color.GRAY)
        val bitmap2 = makeSolidBitmap(Color.GRAY)

        differ.shouldProcess(bitmap1)
        differ.reset()
        assertTrue(differ.shouldProcess(bitmap2))
    }

    @Test
    fun counterIncrementsOnSkip() {
        val differ = FrameDiffer()
        val bitmap1 = makeSolidBitmap(Color.GRAY)
        val bitmap2 = makeSolidBitmap(Color.GRAY)
        val bitmap3 = makeSolidBitmap(Color.GRAY)

        differ.shouldProcess(bitmap1)
        differ.shouldProcess(bitmap2)
        differ.shouldProcess(bitmap3)

        assertEquals(2, differ.framesSkippedByDiff)
    }

    @Test
    fun meanAbsoluteDifferenceWithIdenticalArrays() {
        val differ = FrameDiffer()
        val a = intArrayOf(100, 150, 200)
        val b = intArrayOf(100, 150, 200)
        assertEquals(0f, differ.meanAbsoluteDifference(a, b), 0.001f)
    }

    @Test
    fun meanAbsoluteDifferenceWithDifferentArrays() {
        val differ = FrameDiffer()
        val a = intArrayOf(0, 0, 0)
        val b = intArrayOf(30, 60, 90)
        assertEquals(60f, differ.meanAbsoluteDifference(a, b), 0.001f)
    }

    private fun makeSolidBitmap(color: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(color)
        return bitmap
    }
}
