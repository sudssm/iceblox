package com.iceblox.app.processing

class DeduplicationCache {
    private val seenTexts = mutableSetOf<String>()
    private val seenHashes = mutableSetOf<String>()

    @Synchronized
    fun isDuplicate(normalizedPlate: String): Boolean {
        return !seenTexts.add(normalizedPlate)
    }

    @Synchronized
    fun allHashesSeen(hashes: List<String>): Boolean {
        return hashes.isNotEmpty() && seenHashes.containsAll(hashes)
    }

    @Synchronized
    fun recordHashes(hashes: List<String>) {
        seenHashes.addAll(hashes)
    }

    @Synchronized
    fun reset() {
        seenTexts.clear()
        seenHashes.clear()
    }
}
