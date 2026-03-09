package com.iceblox.app.config

object AppConfig {
    const val SERVER_BASE_URL = "http://10.0.2.2:8080"
    const val PLATES_ENDPOINT = "/api/v1/plates"
    const val DEVICES_ENDPOINT = "/api/v1/devices"

    const val NOTIFICATION_CHANNEL_ID = "plate_alerts"
    const val NOTIFICATION_CHANNEL_NAME = "Plate Alerts"
    const val BACKGROUND_CAPTURE_CHANNEL_ID = "background_capture"
    const val BACKGROUND_CAPTURE_CHANNEL_NAME = "Background Capture"
    const val BACKGROUND_CAPTURE_NOTIFICATION_ID = 2001

    const val DETECTION_CONFIDENCE_THRESHOLD = 0.7f
    const val OCR_CONFIDENCE_THRESHOLD = 0.6f
    const val DEDUPLICATION_WINDOW_MS = 60_000L
    const val MIN_PLATE_LENGTH = 2
    const val MAX_PLATE_LENGTH = 8

    const val BATCH_SIZE = 65
    const val BATCH_INTERVAL_MS = 30_000L
    const val MAX_BATCH_WAIT_MS = 1_000L
    const val MAX_QUEUE_SIZE = 1000
    const val UPLOAD_TIMEOUT_MS = 600_000L

    const val RETRY_INITIAL_DELAY_MS = 5_000L
    const val RETRY_MAX_DELAY_MS = 300_000L
    const val RETRY_MAX_ATTEMPTS = 10

    const val MAX_LOOKALIKE_VARIANTS = 64

    const val FRAME_SKIP_COUNT = 2
    const val THROTTLED_FRAME_SKIP_COUNT = 6

    const val SUBSCRIBE_ENDPOINT = "/api/v1/subscribe"
    const val SUBSCRIBE_INTERVAL_MS = 600_000L // 10 minutes
    const val DEFAULT_RADIUS_MILES = 100.0

    const val TEST_FRAME_INTERVAL_MS = 500L
    const val TEST_IMAGES_ASSET_DIR = "test_images"
    const val TEST_IMAGES_RUNTIME_DIR = "test_images"
    const val INTENT_EXTRA_TEST_MODE = "test_mode"

    const val ACTION_START_BACKGROUND_CAPTURE = "com.iceblox.app.action.START_BACKGROUND_CAPTURE"
    const val ACTION_STOP_BACKGROUND_CAPTURE = "com.iceblox.app.action.STOP_BACKGROUND_CAPTURE"
}
