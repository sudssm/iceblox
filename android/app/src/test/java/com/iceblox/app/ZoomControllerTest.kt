package com.iceblox.app

import android.graphics.RectF
import com.iceblox.app.camera.ZoomController
import com.iceblox.app.config.AppConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.math.sqrt

@RunWith(RobolectricTestRunner::class)
class ZoomControllerTest {

    // UT-1: Zoom eligibility / safe zoom ratio

    @Test
    fun centerPlateGetsMaxZoomAt3x() {
        val ratio = ZoomController.safeZoomRatio(
            boundingBox = RectF(400f, 400f, 600f, 600f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 3.0f, margin = 1.0f
        )
        assertEquals(3.0f, ratio, 0.01f)
    }

    @Test
    fun topLeftCornerGetsLowZoom() {
        val ratio = ZoomController.safeZoomRatio(
            boundingBox = RectF(0f, 0f, 200f, 200f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 3.0f, margin = 1.0f
        )
        assertEquals(1.0f, ratio, 0.01f)
    }

    @Test
    fun offCenterPlateGetsReducedZoom() {
        val ratio = ZoomController.safeZoomRatio(
            boundingBox = RectF(600f, 400f, 800f, 600f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 3.0f, margin = 1.0f
        )
        assertTrue(ratio > 1.0f)
        assertTrue(ratio < 3.0f)
    }

    @Test
    fun zoomRatioIsCappedAtMax() {
        val ratio = ZoomController.safeZoomRatio(
            boundingBox = RectF(490f, 490f, 510f, 510f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 2.0f, margin = 1.0f
        )
        assertEquals(2.0f, ratio, 0.01f)
    }

    @Test
    fun returnsZeroWhenZoomIs1x() {
        val ratio = ZoomController.safeZoomRatio(
            boundingBox = RectF(400f, 400f, 600f, 600f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 1.0f, margin = 1.0f
        )
        assertEquals(0f, ratio, 0.01f)
    }

    @Test
    fun returnsZeroWithZeroImageDimensions() {
        val ratio = ZoomController.safeZoomRatio(
            boundingBox = RectF(0f, 0f, 10f, 10f),
            imageWidth = 0, imageHeight = 0,
            maxOpticalZoom = 3.0f, margin = 1.0f
        )
        assertEquals(0f, ratio, 0.01f)
    }

    @Test
    fun marginReducesSafeZoom() {
        val withFullMargin = ZoomController.safeZoomRatio(
            boundingBox = RectF(350f, 350f, 650f, 650f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 5.0f, margin = 1.0f
        )
        val withReducedMargin = ZoomController.safeZoomRatio(
            boundingBox = RectF(350f, 350f, 650f, 650f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 5.0f, margin = 0.8f
        )
        assertTrue(withFullMargin > withReducedMargin)
    }

    @Test
    fun higherZoomShrinksSafeArea() {
        val at3x = ZoomController.safeZoomRatio(
            boundingBox = RectF(350f, 350f, 650f, 650f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 3.0f, margin = 1.0f
        )
        val at5x = ZoomController.safeZoomRatio(
            boundingBox = RectF(350f, 350f, 650f, 650f),
            imageWidth = 1000, imageHeight = 1000,
            maxOpticalZoom = 5.0f, margin = 1.0f
        )
        assertTrue(at5x > at3x)
    }

    // UT-4: Best candidate selection

    @Test
    fun bestCandidateSelectsClosestToCenter() {
        val detections = listOf(
            Triple(RectF(450f, 450f, 550f, 550f), 1000, 1000),
            Triple(RectF(350f, 450f, 450f, 550f), 1000, 1000),
            Triple(RectF(420f, 420f, 520f, 520f), 1000, 1000),
        )
        val result = bestCandidate(detections, maxOpticalZoom = 3.0f)
        assertEquals(0, result?.first)
    }

    @Test
    fun bestCandidateReturnsNullWhenNoneEligible() {
        val detections = listOf(
            Triple(RectF(0f, 0f, 100f, 100f), 1000, 1000),
            Triple(RectF(800f, 800f, 900f, 900f), 1000, 1000),
        )
        val result = bestCandidate(detections, maxOpticalZoom = 3.0f)
        assertNull(result)
    }

    @Test
    fun bestCandidateSkipsIneligiblePlates() {
        val detections = listOf(
            Triple(RectF(0f, 0f, 100f, 100f), 1000, 1000),
            Triple(RectF(440f, 440f, 560f, 560f), 1000, 1000),
            Triple(RectF(900f, 900f, 1000f, 1000f), 1000, 1000),
        )
        val result = bestCandidate(detections, maxOpticalZoom = 3.0f)
        assertEquals(1, result?.first)
    }

    @Test
    fun bestCandidateReturnsZoomRatio() {
        val detections = listOf(
            Triple(RectF(450f, 450f, 550f, 550f), 1000, 1000),
        )
        val result = bestCandidate(detections, maxOpticalZoom = 3.0f)
        assertTrue(result!!.second > 1.0f)
        assertTrue(result.second <= 3.0f)
    }

    private fun bestCandidate(
        detections: List<Triple<RectF, Int, Int>>,
        maxOpticalZoom: Float,
        margin: Float = AppConfig.ZOOM_RETRY_MARGIN,
        minRatio: Float = AppConfig.ZOOM_RETRY_MIN_RATIO
    ): Pair<Int, Float>? {
        var bestIdx: Int? = null
        var bestDist = Float.MAX_VALUE
        var bestRatio = 0f

        for ((i, det) in detections.withIndex()) {
            val (box, imgW, imgH) = det
            val ratio = ZoomController.safeZoomRatio(box, imgW, imgH, maxOpticalZoom, margin)
            if (ratio < minRatio) continue
            val cx = (box.centerX() / imgW.toFloat()) - 0.5f
            val cy = (box.centerY() / imgH.toFloat()) - 0.5f
            val dist = sqrt(cx * cx + cy * cy)
            if (dist < bestDist) {
                bestDist = dist
                bestIdx = i
                bestRatio = ratio
            }
        }
        return bestIdx?.let { Pair(it, bestRatio) }
    }
}
