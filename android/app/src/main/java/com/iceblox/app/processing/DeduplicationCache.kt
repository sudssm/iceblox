package com.iceblox.app.processing

import com.iceblox.app.config.AppConfig

class DeduplicationCache {
    private val seen = mutableMapOf<String, Long>()

    @Synchronized
    fun isDuplicate(normalizedPlate: String): Boolean {
        val now = System.currentTimeMillis()
        seen.entries.removeAll { now - it.value > AppConfig.DEDUPLICATION_WINDOW_MS }

        val lastSeen = seen[normalizedPlate]
        if (lastSeen != null && now - lastSeen <= AppConfig.DEDUPLICATION_WINDOW_MS) {
            return true
        }
        seen[normalizedPlate] = now
        return false
    }

    @Synchronized
    fun reset() {
        seen.clear()
    }
}
