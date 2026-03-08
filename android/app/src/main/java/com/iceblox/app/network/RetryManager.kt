package com.iceblox.app.network

import com.iceblox.app.config.AppConfig

class RetryManager {
    private var attempts = 0
    private var rateLimitedUntil = 0L

    val isRateLimited: Boolean
        get() = System.currentTimeMillis() < rateLimitedUntil

    fun handleFailure(): Long? {
        if (attempts >= AppConfig.RETRY_MAX_ATTEMPTS) return null
        val delay = minOf(
            AppConfig.RETRY_INITIAL_DELAY_MS * (1L shl attempts),
            AppConfig.RETRY_MAX_DELAY_MS
        )
        attempts++
        return delay
    }

    fun handleRateLimit(retryAfterSeconds: Long) {
        rateLimitedUntil = System.currentTimeMillis() + retryAfterSeconds * 1000
    }

    fun reset() {
        attempts = 0
    }
}
