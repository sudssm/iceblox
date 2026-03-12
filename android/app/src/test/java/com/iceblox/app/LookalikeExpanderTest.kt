package com.iceblox.app

import com.iceblox.app.detection.SlotCandidate
import com.iceblox.app.processing.LookalikeExpander
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln

class LookalikeExpanderTest {

    private fun candidates(vararg slots: List<Pair<Char, Float>>): List<List<SlotCandidate>> =
        slots.map { slot -> slot.map { SlotCandidate(it.first, it.second) } }

    @Test
    fun singleCandidatePerSlot() {
        val cands = candidates(
            listOf('A' to 0.9f),
            listOf('B' to 0.8f),
            listOf('C' to 0.7f)
        )
        val result = LookalikeExpander.expand("ABC", floatArrayOf(0.9f, 0.8f, 0.7f), cands)
        assertEquals(1, result.size)
        assertEquals("ABC", result[0].first)
        assertEquals(0, result[0].second)
    }

    @Test
    fun twoCandidateSlot() {
        val cands = candidates(
            listOf('A' to 0.8f, '4' to 0.1f),
            listOf('B' to 0.95f)
        )
        val result = LookalikeExpander.expand("AB", floatArrayOf(0.8f, 0.95f), cands)
        assertEquals(2, result.size)
        val texts = result.map { it.first }.toSet()
        assertEquals(setOf("AB", "4B"), texts)
    }

    @Test
    fun multiSlotCartesian() {
        val cands = candidates(
            listOf('S' to 0.7f, '5' to 0.2f),
            listOf('O' to 0.6f, '0' to 0.3f)
        )
        val result = LookalikeExpander.expand("SO", floatArrayOf(0.7f, 0.6f), cands)
        assertEquals(4, result.size)
        val texts = result.map { it.first }.toSet()
        assertEquals(setOf("SO", "S0", "5O", "50"), texts)
    }

    @Test
    fun primaryAlwaysFirst() {
        val cands = candidates(
            listOf('X' to 0.5f, 'Y' to 0.9f),
            listOf('Z' to 0.5f)
        )
        val result = LookalikeExpander.expand("XZ", floatArrayOf(0.5f, 0.5f), cands)
        assertEquals("XZ", result[0].first)
        assertEquals(0, result[0].second)
    }

    @Test
    fun confidenceOrdering() {
        val cands = candidates(
            listOf('A' to 0.9f, 'B' to 0.05f),
            listOf('C' to 0.9f, 'D' to 0.05f)
        )
        val result = LookalikeExpander.expand("AC", floatArrayOf(0.9f, 0.9f), cands)
        assertEquals("AC", result[0].first)
        for (i in 1 until result.size - 1) {
            assertTrue(result[i].third >= result[i + 1].third)
        }
    }

    @Test
    fun capEnforcement() {
        val cands = candidates(
            listOf('A' to 0.5f, 'B' to 0.1f, 'C' to 0.1f),
            listOf('D' to 0.5f, 'E' to 0.1f, 'F' to 0.1f),
            listOf('G' to 0.5f, 'H' to 0.1f, 'I' to 0.1f)
        )
        val result = LookalikeExpander.expand("ADG", floatArrayOf(0.5f, 0.5f, 0.5f), cands, maxVariants = 10)
        assertEquals(10, result.size)
    }

    @Test
    fun substitutionCount() {
        val cands = candidates(
            listOf('A' to 0.8f, 'B' to 0.1f),
            listOf('C' to 0.9f),
            listOf('D' to 0.7f, 'E' to 0.2f)
        )
        val result = LookalikeExpander.expand("ACD", floatArrayOf(0.8f, 0.9f, 0.7f), cands)
        val lookup = result.associate { it.first to it.second }
        assertEquals(0, lookup["ACD"])
        assertEquals(1, lookup["BCD"])
        assertEquals(1, lookup["ACE"])
        assertEquals(2, lookup["BCE"])
    }

    @Test
    fun geometricMeanCorrectness() {
        val p0 = 0.8f
        val p1 = 0.6f
        val cands = candidates(
            listOf('A' to p0),
            listOf('B' to p1)
        )
        val result = LookalikeExpander.expand("AB", floatArrayOf(p0, p1), cands)
        val expected = exp((ln(p0) + ln(p1)) / 2f)
        assertTrue(abs(result[0].third - expected) < 1e-5f)
    }

    @Test
    fun emptyCandidatesFallback() {
        val result = LookalikeExpander.expand("ABC", floatArrayOf(0.9f, 0.8f, 0.7f))
        assertEquals(1, result.size)
        assertEquals("ABC", result[0].first)
    }

    @Test
    fun noDuplicates() {
        val cands = candidates(
            listOf('O' to 0.5f, '0' to 0.3f),
            listOf('O' to 0.5f, '0' to 0.3f)
        )
        val result = LookalikeExpander.expand("OO", floatArrayOf(0.5f, 0.5f), cands, maxVariants = 200)
        val texts = result.map { it.first }
        assertEquals(texts.size, texts.toSet().size)
    }

    @Test
    fun priorityQueuePath() {
        val manySlots = (0 until 5).map {
            listOf('A' to 0.7f, 'B' to 0.1f, 'C' to 0.1f)
        }
        val cands = manySlots.map { slot -> slot.map { SlotCandidate(it.first, it.second) } }
        val result = LookalikeExpander.expand(
            "AAAAA",
            FloatArray(5) { 0.7f },
            cands,
            maxVariants = 20
        )
        assertEquals(20, result.size)
        assertEquals("AAAAA", result[0].first)
        for (i in 1 until result.size - 1) {
            assertTrue(result[i].third >= result[i + 1].third)
        }
        val texts = result.map { it.first }
        assertEquals(texts.size, texts.toSet().size)
    }
}
