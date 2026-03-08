package com.iceblox.app.processing

object PlateNormalizer {
    fun normalize(text: String): String? {
        val normalized = text
            .uppercase()
            .replace(Regex("\\s"), "")
            .replace("-", "")
            .filter { it.isLetterOrDigit() && it.code < 128 }
            .take(8)

        return if (normalized.length in 2..8) normalized else null
    }
}
