package com.cameras.app.config

object AppConfig {
    const val SERVER_BASE_URL = "http://127.0.0.1:8080"
    const val PLATES_ENDPOINT = "/api/v1/plates"

    const val DETECTION_CONFIDENCE_THRESHOLD = 0.7f
    const val OCR_CONFIDENCE_THRESHOLD = 0.6f
    const val DEDUPLICATION_WINDOW_MS = 60_000L
    const val MIN_PLATE_LENGTH = 2
    const val MAX_PLATE_LENGTH = 8

    const val BATCH_SIZE = 10
    const val BATCH_INTERVAL_MS = 30_000L
    const val MAX_QUEUE_SIZE = 1000

    const val RETRY_INITIAL_DELAY_MS = 5_000L
    const val RETRY_MAX_DELAY_MS = 300_000L
    const val RETRY_MAX_ATTEMPTS = 10

    const val FRAME_SKIP_COUNT = 2
    const val THROTTLED_FRAME_SKIP_COUNT = 6
}
