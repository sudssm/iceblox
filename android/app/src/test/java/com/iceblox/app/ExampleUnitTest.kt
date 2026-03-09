package com.iceblox.app

import android.graphics.RectF
import com.iceblox.app.detection.DetectedPlate
import com.iceblox.app.detection.PlateDetector
import com.iceblox.app.network.RetryManager
import com.iceblox.app.persistence.OfflineQueueEntry
import com.iceblox.app.processing.DeduplicationCache
import com.iceblox.app.processing.PlateHasher
import com.iceblox.app.processing.PlateNormalizer
import com.iceblox.app.ui.formatSessionDuration
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

class PlateNormalizerTest {
    @Test
    fun basicNormalization() {
        assertEquals("ABC1234", PlateNormalizer.normalize("abc 1234"))
    }

    @Test
    fun removesHyphens() {
        assertEquals("AB1234", PlateNormalizer.normalize("AB-1234"))
    }

    @Test
    fun removesWhitespace() {
        assertEquals("AB1234", PlateNormalizer.normalize("AB  12 34"))
    }

    @Test
    fun uppercases() {
        assertEquals("ABC", PlateNormalizer.normalize("abc"))
    }

    @Test
    fun removesNonAlphanumeric() {
        assertEquals("AB1234", PlateNormalizer.normalize("AB@#1234"))
    }

    @Test
    fun truncatesTo8Chars() {
        assertEquals("ABCDEFGH", PlateNormalizer.normalize("ABCDEFGHIJ"))
    }

    @Test
    fun rejectsTooShort() {
        assertNull(PlateNormalizer.normalize("A"))
    }

    @Test
    fun rejectsEmpty() {
        assertNull(PlateNormalizer.normalize(""))
    }

    @Test
    fun rejectsAllSymbols() {
        assertNull(PlateNormalizer.normalize("@#$"))
    }

    @Test
    fun acceptsMinLength() {
        assertEquals("AB", PlateNormalizer.normalize("AB"))
    }

    @Test
    fun acceptsMaxLength() {
        assertEquals("ABCD1234", PlateNormalizer.normalize("ABCD1234"))
    }
}

@RunWith(RobolectricTestRunner::class)
class NmsTest {
    @Test
    fun emptyInput() {
        assertEquals(emptyList<DetectedPlate>(), PlateDetector.nms(emptyList()))
    }

    @Test
    fun singleDetection() {
        val det = DetectedPlate(RectF(0f, 0f, 100f, 100f), 0.9f)
        assertEquals(listOf(det), PlateDetector.nms(listOf(det)))
    }

    @Test
    fun suppressesOverlapping() {
        val high = DetectedPlate(RectF(0f, 0f, 100f, 100f), 0.9f)
        val low = DetectedPlate(RectF(10f, 10f, 110f, 110f), 0.7f)
        val result = PlateDetector.nms(listOf(low, high))
        assertEquals(1, result.size)
        assertEquals(0.9f, result[0].confidence)
    }

    @Test
    fun keepsNonOverlapping() {
        val a = DetectedPlate(RectF(0f, 0f, 50f, 50f), 0.9f)
        val b = DetectedPlate(RectF(200f, 200f, 300f, 300f), 0.8f)
        val result = PlateDetector.nms(listOf(a, b))
        assertEquals(2, result.size)
    }

    @Test
    fun iouCalculation() {
        val a = RectF(0f, 0f, 100f, 100f)
        val b = RectF(50f, 50f, 150f, 150f)
        val iou = PlateDetector.iou(a, b)
        // intersection = 50*50 = 2500, union = 10000+10000-2500 = 17500
        assertEquals(2500f / 17500f, iou, 0.001f)
    }

    @Test
    fun iouNoOverlap() {
        val a = RectF(0f, 0f, 50f, 50f)
        val b = RectF(100f, 100f, 200f, 200f)
        assertEquals(0f, PlateDetector.iou(a, b), 0.001f)
    }
}

class PlateHasherTest {
    @Test
    fun producesHexString() {
        val hash = PlateHasher.hash("ABC1234")
        assertEquals(64, hash.length)
        assertTrue(hash.all { it in '0'..'9' || it in 'a'..'f' })
    }

    @Test
    fun deterministicOutput() {
        val h1 = PlateHasher.hash("ABC1234")
        val h2 = PlateHasher.hash("ABC1234")
        assertEquals(h1, h2)
    }

    @Test
    fun differentInputsDifferentHashes() {
        val h1 = PlateHasher.hash("ABC1234")
        val h2 = PlateHasher.hash("XYZ9876")
        assertNotEquals(h1, h2)
    }
}

class DeduplicationCacheTest {
    @Test
    fun firstOccurrenceNotDuplicate() {
        val cache = DeduplicationCache()
        assertFalse(cache.isDuplicate("ABC1234"))
    }

    @Test
    fun secondOccurrenceIsDuplicate() {
        val cache = DeduplicationCache()
        cache.isDuplicate("ABC1234")
        assertTrue(cache.isDuplicate("ABC1234"))
    }

    @Test
    fun differentPlatesNotDuplicate() {
        val cache = DeduplicationCache()
        cache.isDuplicate("ABC1234")
        assertFalse(cache.isDuplicate("XYZ9876"))
    }
}

class RetryManagerTest {
    @Test
    fun firstFailureReturnsInitialDelay() {
        val manager = RetryManager()
        val delay = manager.handleFailure()
        assertEquals(5000L, delay)
    }

    @Test
    fun exponentialBackoff() {
        val manager = RetryManager()
        manager.handleFailure() // 5s
        val second = manager.handleFailure()
        assertEquals(10000L, second)
    }

    @Test
    fun resetClearsAttempts() {
        val manager = RetryManager()
        manager.handleFailure()
        manager.reset()
        val delay = manager.handleFailure()
        assertEquals(5000L, delay)
    }

    @Test
    fun maxAttemptsReturnsNull() {
        val manager = RetryManager()
        repeat(10) { manager.handleFailure() }
        assertNull(manager.handleFailure())
    }

    @Test
    fun rateLimitSetsDeadline() {
        val manager = RetryManager()
        assertFalse(manager.isRateLimited)
        manager.handleRateLimit(60)
        assertTrue(manager.isRateLimited)
    }
}

class SessionSummaryTest {
    @Test
    fun formatSessionDurationUsesMinutesAndSeconds() {
        assertEquals("7m 05s", formatSessionDuration(425_000))
    }

    @Test
    fun offlineQueueEntryRetainsSessionId() {
        val entry = OfflineQueueEntry(
            plateHash = "abc123",
            timestamp = 1234L,
            latitude = 1.0,
            longitude = 2.0,
            sessionId = "session-1"
        )

        assertEquals("session-1", entry.sessionId)
    }
}
