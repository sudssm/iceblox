package com.iceblox.app.config

object AppConfig {
    const val SERVER_BASE_URL = "http://10.0.2.2:8080"
    const val PLATES_ENDPOINT = "/api/v1/plates"
    const val DEVICES_ENDPOINT = "/api/v1/devices"

    const val NOTIFICATION_CHANNEL_ID = "plate_alerts"
    const val NOTIFICATION_CHANNEL_NAME = "Plate Alerts"

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

    const val TEST_FRAME_INTERVAL_MS = 500L
    const val TEST_IMAGES_ASSET_DIR = "test_images"
    const val TEST_IMAGES_RUNTIME_DIR = "test_images"
    const val INTENT_EXTRA_TEST_MODE = "test_mode"
}
