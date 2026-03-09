package com.iceblox.app

import com.iceblox.app.ui.DetectionFeedEntry
import com.iceblox.app.ui.DetectionState
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CyclicBarrier
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DetectionFeedUpdateTest {

    private fun addFeedEntry(
        feed: MutableStateFlow<List<DetectionFeedEntry>>,
        entry: DetectionFeedEntry
    ) {
        feed.update { current ->
            val list = current.toMutableList()
            list.add(0, entry)
            if (list.size > 20) list.subList(20, list.size).clear()
            list
        }
    }

    private fun markSent(
        feed: MutableStateFlow<List<DetectionFeedEntry>>,
        hashPrefix: String
    ): Boolean {
        var found = false
        feed.update { current ->
            val list = current.toMutableList()
            val idx = list.indexOfLast { it.hashPrefix == hashPrefix && it.state == DetectionState.QUEUED }
            if (idx >= 0) {
                list[idx] = list[idx].copy(state = DetectionState.SENT)
                found = true
                list
            } else {
                current
            }
        }
        return found
    }

    @Test
    fun concurrentAddAndMarkSentPreservesBothUpdates() {
        val feed = MutableStateFlow<List<DetectionFeedEntry>>(emptyList())
        val entry1 = DetectionFeedEntry("PLATE1", "aaa11111", DetectionState.QUEUED)
        addFeedEntry(feed, entry1)

        val iterations = 200
        var lostUpdates = 0

        for (i in 0 until iterations) {
            feed.value = listOf(
                DetectionFeedEntry("EXISTING", "existing$i", DetectionState.QUEUED)
            )

            val barrier = CyclicBarrier(2)
            val latch = CountDownLatch(2)
            val newEntry = DetectionFeedEntry("NEW_$i", "new_${i}_00", DetectionState.QUEUED)

            val t1 = Thread {
                barrier.await()
                markSent(feed, "existing$i")
                latch.countDown()
            }
            val t2 = Thread {
                barrier.await()
                addFeedEntry(feed, newEntry)
                latch.countDown()
            }

            t1.start()
            t2.start()
            latch.await()

            val result = feed.value
            val existingEntry = result.find { it.hashPrefix == "existing$i" }
            val addedEntry = result.find { it.hashPrefix == "new_${i}_00" }

            if (existingEntry?.state != DetectionState.SENT || addedEntry == null) {
                lostUpdates++
            }
        }

        assertEquals(0, lostUpdates)
    }

    @Test
    fun markSentTransitionsQueuedToSent() {
        val feed = MutableStateFlow<List<DetectionFeedEntry>>(emptyList())
        val entry = DetectionFeedEntry("TEST", "abc12345", DetectionState.QUEUED)
        addFeedEntry(feed, entry)

        val found = markSent(feed, "abc12345")

        assertTrue(found)
        assertEquals(DetectionState.SENT, feed.value[0].state)
    }

    @Test
    fun markSentIgnoresAlreadySentEntry() {
        val feed = MutableStateFlow<List<DetectionFeedEntry>>(emptyList())
        val entry = DetectionFeedEntry("TEST", "abc12345", DetectionState.SENT)
        addFeedEntry(feed, entry)

        val found = markSent(feed, "abc12345")

        assertTrue(!found)
        assertEquals(DetectionState.SENT, feed.value[0].state)
    }
}
