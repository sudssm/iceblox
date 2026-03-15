package com.iceblox.app

import com.iceblox.app.processing.DeduplicationCache
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DeduplicationCacheTest {

    private lateinit var cache: DeduplicationCache

    @Before
    fun setUp() {
        cache = DeduplicationCache()
    }

    @Test
    fun firstPlateIsNotDuplicate() {
        assertFalse(cache.isDuplicate("ABC1234"))
    }

    @Test
    fun samePlateIsDeduplicatedWithinSession() {
        assertFalse(cache.isDuplicate("ABC1234"))
        assertTrue(cache.isDuplicate("ABC1234"))
    }

    @Test
    fun differentPlatesAreNotDeduplicated() {
        assertFalse(cache.isDuplicate("ABC1234"))
        assertFalse(cache.isDuplicate("XYZ5678"))
    }

    @Test
    fun plateRemainsDuplicateIndefinitely() {
        assertFalse(cache.isDuplicate("ABC1234"))
        assertTrue(cache.isDuplicate("ABC1234"))
        assertTrue(cache.isDuplicate("ABC1234"))
    }

    @Test
    fun resetClearsTextDedup() {
        assertFalse(cache.isDuplicate("ABC1234"))
        assertTrue(cache.isDuplicate("ABC1234"))
        cache.reset()
        assertFalse(cache.isDuplicate("ABC1234"))
    }

    @Test
    fun allHashesSeenReturnsFalseWhenEmpty() {
        assertFalse(cache.allHashesSeen(listOf("hash1", "hash2")))
    }

    @Test
    fun allHashesSeenReturnsFalseForNewHashes() {
        cache.recordHashes(listOf("hash1"))
        assertFalse(cache.allHashesSeen(listOf("hash1", "hash2")))
    }

    @Test
    fun allHashesSeenReturnsTrueWhenAllPresent() {
        cache.recordHashes(listOf("hash1", "hash2", "hash3"))
        assertTrue(cache.allHashesSeen(listOf("hash1", "hash2")))
    }

    @Test
    fun allHashesSeenReturnsTrueForExactSet() {
        cache.recordHashes(listOf("hash1", "hash2"))
        assertTrue(cache.allHashesSeen(listOf("hash1", "hash2")))
    }

    @Test
    fun allHashesSeenReturnsTrueForEmptyList() {
        assertFalse(cache.allHashesSeen(emptyList()))
    }

    @Test
    fun resetClearsHashDedup() {
        cache.recordHashes(listOf("hash1", "hash2"))
        assertTrue(cache.allHashesSeen(listOf("hash1", "hash2")))
        cache.reset()
        assertFalse(cache.allHashesSeen(listOf("hash1", "hash2")))
    }

    @Test
    fun hashesAccumulateAcrossRecordCalls() {
        cache.recordHashes(listOf("hash1"))
        cache.recordHashes(listOf("hash2"))
        assertTrue(cache.allHashesSeen(listOf("hash1", "hash2")))
    }

    @Test
    fun partialOverlapIsNotAllSeen() {
        cache.recordHashes(listOf("hash1", "hash2"))
        assertFalse(cache.allHashesSeen(listOf("hash2", "hash3")))
    }
}
