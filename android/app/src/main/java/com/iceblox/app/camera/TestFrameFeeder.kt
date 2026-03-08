package com.iceblox.app.camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class TestFrameFeeder(
    private val context: Context,
    private val frameAnalyzer: FrameAnalyzer,
    private val intervalMs: Long = AppConfig.TEST_FRAME_INTERVAL_MS
) {
    private var feedJob: Job? = null
    private var images: List<Bitmap> = emptyList()
    private var imageNames: List<String> = emptyList()
    private var currentIndex = 0

    private val _currentBitmap = MutableStateFlow<Bitmap?>(null)
    val currentBitmap: StateFlow<Bitmap?> = _currentBitmap

    private val _status = MutableStateFlow("")
    val status: StateFlow<String> = _status

    val imageCount: Int get() = images.size

    fun loadImages(): Boolean {
        val loaded = mutableListOf<Pair<String, Bitmap>>()

        try {
            val assetFiles = context.assets.list(AppConfig.TEST_IMAGES_ASSET_DIR) ?: emptyArray()
            for (filename in assetFiles.sorted()) {
                if (!filename.isImageFile()) continue
                try {
                    val bitmap = context.assets.open("${AppConfig.TEST_IMAGES_ASSET_DIR}/$filename")
                        .use { BitmapFactory.decodeStream(it) }
                    if (bitmap != null) {
                        loaded.add(filename to bitmap)
                        DebugLog.d(TAG, "Loaded asset image: $filename (${bitmap.width}x${bitmap.height})")
                    }
                } catch (e: Exception) {
                    DebugLog.w(TAG, "Failed to load asset image $filename: ${e.message}")
                }
            }
        } catch (e: Exception) {
            DebugLog.d(TAG, "No asset test_images directory: ${e.message}")
        }

        val runtimeDir = File(context.filesDir, AppConfig.TEST_IMAGES_RUNTIME_DIR)
        if (runtimeDir.isDirectory) {
            val files = runtimeDir.listFiles()?.sortedBy { it.name } ?: emptyList()
            for (file in files) {
                if (!file.name.isImageFile()) continue
                if (loaded.any { it.first == file.name }) continue
                try {
                    val bitmap = BitmapFactory.decodeFile(file.absolutePath)
                    if (bitmap != null) {
                        loaded.add(file.name to bitmap)
                        DebugLog.d(TAG, "Loaded runtime image: ${file.name} (${bitmap.width}x${bitmap.height})")
                    }
                } catch (e: Exception) {
                    DebugLog.w(TAG, "Failed to load runtime image ${file.name}: ${e.message}")
                }
            }
        }

        images = loaded.map { it.second }
        imageNames = loaded.map { it.first }
        _status.value = "Loaded ${images.size} test images"
        DebugLog.d(TAG, "Total test images loaded: ${images.size}")
        return images.isNotEmpty()
    }

    fun start(scope: CoroutineScope) {
        if (images.isEmpty()) {
            DebugLog.w(TAG, "No test images loaded, cannot start feeding")
            _status.value = "No test images found"
            return
        }

        feedJob?.cancel()
        currentIndex = 0
        DebugLog.d(TAG, "Starting test frame feed: ${images.size} images, interval=${intervalMs}ms")

        feedJob = scope.launch(Dispatchers.IO) {
            while (isActive) {
                val bitmap = images[currentIndex]
                val name = imageNames[currentIndex]
                _currentBitmap.value = bitmap
                _status.value = "[${currentIndex + 1}/${images.size}] $name"

                frameAnalyzer.analyzeBitmap(bitmap)

                currentIndex = (currentIndex + 1) % images.size
                delay(intervalMs)
            }
        }
    }

    fun stop() {
        feedJob?.cancel()
        feedJob = null
        _status.value = "Stopped"
        DebugLog.d(TAG, "Test frame feed stopped")
    }

    private fun String.isImageFile(): Boolean {
        val lower = this.lowercase()
        return lower.endsWith(".png") || lower.endsWith(".jpg") ||
            lower.endsWith(".jpeg") || lower.endsWith(".bmp")
    }

    companion object {
        private const val TAG = "TestFrameFeeder"
    }
}
