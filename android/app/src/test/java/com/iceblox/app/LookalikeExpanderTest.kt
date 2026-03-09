package com.iceblox.app

import com.iceblox.app.processing.LookalikeExpander
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LookalikeExpanderTest {
    @Test
    fun noConfusableCharacters() {
        val result = LookalikeExpander.expand("XYW", maxVariants = 64)
        assertEquals(1, result.size)
        assertEquals("XYW" to 0, result[0])
    }

    @Test
    fun originalAlwaysFirst() {
        val result = LookalikeExpander.expand("ABC1234", maxVariants = 64)
        assertEquals("ABC1234", result[0].first)
        assertEquals(0, result[0].second)
    }

    @Test
    fun singlePositionExpansion() {
        val result = LookalikeExpander.expand("S", maxVariants = 64)
        assertEquals(2, result.size)
        assertEquals("S" to 0, result[0])
        assertEquals("5" to 1, result[1])
    }

    @Test
    fun mergedGroupG1() {
        val result = LookalikeExpander.expand("0", maxVariants = 64)
        val texts = result.map { it.first }.toSet()
        assertEquals(setOf("0", "O", "D", "Q", "8", "B"), texts)
        for (r in result) {
            if (r.first == "0") assertEquals(0, r.second) else assertEquals(1, r.second)
        }
    }

    @Test
    fun multiPositionExpansion() {
        val result = LookalikeExpander.expand("5S", maxVariants = 64)
        val texts = result.map { it.first }.toSet()
        assertEquals(setOf("5S", "SS", "55", "S5"), texts)
        assertEquals(0, result.first { it.first == "5S" }.second)
        assertEquals(1, result.first { it.first == "SS" }.second)
        assertEquals(1, result.first { it.first == "55" }.second)
        assertEquals(2, result.first { it.first == "S5" }.second)
    }

    @Test
    fun capEnforcement() {
        val result = LookalikeExpander.expand("0O8BDQ", maxVariants = 10)
        assertEquals(10, result.size)
    }

    @Test
    fun bfsOrdering() {
        val result = LookalikeExpander.expand("0O", maxVariants = 64)
        var lastSub = 0
        for (r in result) {
            assertTrue(r.second >= lastSub)
            lastSub = r.second
        }
    }

    @Test
    fun noDuplicates() {
        val result = LookalikeExpander.expand("00", maxVariants = 200)
        val texts = result.map { it.first }
        assertEquals(texts.size, texts.toSet().size)
    }

    @Test
    fun allGroupsCovered() {
        val result = LookalikeExpander.expand("0IS2A", maxVariants = 500)
        val texts = result.map { it.first }.toSet()
        assertTrue(texts.contains("0LS2A"))
        assertTrue(texts.contains("0IS24"))
        assertTrue(texts.contains("0ISZA"))
    }
}
