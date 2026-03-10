package com.iceblox.app

import android.graphics.RectF
import com.iceblox.app.camera.ZoomController
import com.iceblox.app.config.AppConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.math.sqrt

@RunWith(RobolectricTestRunner::class)
class ZoomControllerTest {

    // UT-1: Zoom eligibility calculation

    @Test
    fun centerPlateEligibleAt3x() {
        assertTrue(
            ZoomController.isPlateEligible(
                boundingBox = RectF(400f, 400f, 600f, 600f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 3.0f,
                margin = 0.8f
            )
        )
    }

    @Test
    fun topLeftCornerNotEligibleAt3x() {
        assertFalse(
            ZoomController.isPlateEligible(
                boundingBox = RectF(0f, 0f, 200f, 200f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 3.0f,
                margin = 0.8f
            )
        )
    }

    @Test
    fun largeCenteredPlateEligibleAt2x() {
        assertTrue(
            ZoomController.isPlateEligible(
                boundingBox = RectF(300f, 300f, 700f, 700f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 2.0f,
                margin = 0.8f
            )
        )
    }

    @Test
    fun rightSidePlateNotEligibleAt3x() {
        assertFalse(
            ZoomController.isPlateEligible(
                boundingBox = RectF(700f, 400f, 900f, 600f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 3.0f,
                margin = 0.8f
            )
        )
    }

    @Test
    fun edgeCaseJustFitsAt2x() {
        assertTrue(
            ZoomController.isPlateEligible(
                boundingBox = RectF(350f, 350f, 650f, 650f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 2.0f,
                margin = 0.8f
            )
        )
    }

    @Test
    fun notEligibleWhenZoomIs1x() {
        assertFalse(
            ZoomController.isPlateEligible(
                boundingBox = RectF(400f, 400f, 600f, 600f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 1.0f,
                margin = 0.8f
            )
        )
    }

    @Test
    fun notEligibleWithZeroImageDimensions() {
        assertFalse(
            ZoomController.isPlateEligible(
                boundingBox = RectF(0f, 0f, 10f, 10f),
                imageWidth = 0,
                imageHeight = 0,
                maxOpticalZoom = 3.0f,
                margin = 0.8f
            )
        )
    }

    @Test
    fun marginOf1MeansFullTheoreticalArea() {
        assertTrue(
            ZoomController.isPlateEligible(
                boundingBox = RectF(340f, 340f, 660f, 660f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 3.0f,
                margin = 1.0f
            )
        )
    }

    @Test
    fun higherZoomShrinksCenterRegion() {
        // limit = 0.5 * (1/5) * 0.8 = 0.08; use 0.075 from center to stay inside
        assertTrue(
            ZoomController.isPlateEligible(
                boundingBox = RectF(425f, 425f, 575f, 575f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 5.0f,
                margin = 0.8f
            )
        )

        // 0.1 from center — clearly outside
        assertFalse(
            ZoomController.isPlateEligible(
                boundingBox = RectF(400f, 400f, 600f, 600f),
                imageWidth = 1000,
                imageHeight = 1000,
                maxOpticalZoom = 5.0f,
                margin = 0.8f
            )
        )
    }

    // UT-4: Best candidate selection

    @Test
    fun bestCandidateSelectsClosestToCenter() {
        val detections = listOf(
            Triple(RectF(450f, 450f, 550f, 550f), 1000, 1000),
            Triple(RectF(350f, 450f, 450f, 550f), 1000, 1000),
            Triple(RectF(420f, 420f, 520f, 520f), 1000, 1000),
        )
        val idx = bestCandidateIndex(detections, maxOpticalZoom = 3.0f)
        assertEquals(0, idx)
    }

    @Test
    fun bestCandidateReturnsNullWhenNoneEligible() {
        val detections = listOf(
            Triple(RectF(0f, 0f, 100f, 100f), 1000, 1000),
            Triple(RectF(800f, 800f, 900f, 900f), 1000, 1000),
        )
        val idx = bestCandidateIndex(detections, maxOpticalZoom = 3.0f)
        assertNull(idx)
    }

    @Test
    fun bestCandidateSkipsIneligiblePlates() {
        val detections = listOf(
            Triple(RectF(0f, 0f, 100f, 100f), 1000, 1000),
            Triple(RectF(440f, 440f, 560f, 560f), 1000, 1000),
            Triple(RectF(900f, 900f, 1000f, 1000f), 1000, 1000),
        )
        val idx = bestCandidateIndex(detections, maxOpticalZoom = 3.0f)
        assertEquals(1, idx)
    }

    /**
     * Replicates ZoomController.bestCandidateIndex logic without needing
     * a real Android Context (which ZoomController's constructor requires).
     */
    private fun bestCandidateIndex(
        detections: List<Triple<RectF, Int, Int>>,
        maxOpticalZoom: Float,
        margin: Float = AppConfig.ZOOM_RETRY_MARGIN
    ): Int? {
        var bestIdx: Int? = null
        var bestDist = Float.MAX_VALUE

        for ((i, det) in detections.withIndex()) {
            val (box, imgW, imgH) = det
            if (!ZoomController.isPlateEligible(box, imgW, imgH, maxOpticalZoom, margin)) continue
            val cx = (box.centerX() / imgW.toFloat()) - 0.5f
            val cy = (box.centerY() / imgH.toFloat()) - 0.5f
            val dist = sqrt(cx * cx + cy * cy)
            if (dist < bestDist) {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }
}
