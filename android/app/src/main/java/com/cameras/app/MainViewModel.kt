package com.cameras.app

import android.app.Application
import android.content.Context
import android.graphics.BitmapFactory
import android.os.PowerManager
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.cameras.app.camera.FrameAnalyzer
import com.cameras.app.camera.ProcessedPlate
import com.cameras.app.config.AppConfig
import com.cameras.app.location.LocationProvider
import com.cameras.app.network.ApiClient
import com.cameras.app.network.ConnectivityMonitor
import com.cameras.app.network.RetryManager
import com.cameras.app.persistence.OfflineQueueDatabase
import com.cameras.app.persistence.OfflineQueueEntry
import com.cameras.app.processing.DeduplicationCache
import com.cameras.app.processing.PlateHasher
import com.cameras.app.ui.DetectionFeedEntry
import com.cameras.app.ui.DetectionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.io.File

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val deduplicationCache = DeduplicationCache()
    private val database = OfflineQueueDatabase.getInstance(application)
    private val queueDao = database.queueDao()
    val locationProvider = LocationProvider(application)
    val connectivityMonitor = ConnectivityMonitor(application)
    private val retryManager = RetryManager()

    private val _plateCount = MutableStateFlow(0L)
    val plateCount: StateFlow<Long> = _plateCount

    private val _targetCount = MutableStateFlow(0)
    val targetCount: StateFlow<Int> = _targetCount

    private val _lastDetectionTime = MutableStateFlow(0L)
    val lastDetectionTime: StateFlow<Long> = _lastDetectionTime

    private val _queueDepth = MutableStateFlow(0)
    val queueDepth: StateFlow<Int> = _queueDepth

    private val _detectionFeed = MutableStateFlow<List<DetectionFeedEntry>>(emptyList())
    val detectionFeed: StateFlow<List<DetectionFeedEntry>> = _detectionFeed

    val apiClient = ApiClient(
        context = application,
        queueDao = queueDao,
        retryManager = retryManager,
        onTargetMatched = { _targetCount.value++ },
        onPlateSent = { hash, matched -> onPlateSent(hash, matched) }
    )

    val frameAnalyzer = FrameAnalyzer(application) { plates ->
        onPlatesDetected(plates)
    }

    private val thermalListener = PowerManager.OnThermalStatusChangedListener { status ->
        val throttled = status >= PowerManager.THERMAL_STATUS_SEVERE
        frameAnalyzer.frameSkipCount = if (throttled) {
            AppConfig.THROTTLED_FRAME_SKIP_COUNT
        } else {
            AppConfig.FRAME_SKIP_COUNT
        }
    }

    init {
        connectivityMonitor.onReconnected = {
            apiClient.flushQueue()
        }
        val powerManager = application.getSystemService(Context.POWER_SERVICE) as PowerManager
        powerManager.addThermalStatusListener(thermalListener)
    }

    fun onPlatesDetected(plates: List<ProcessedPlate>) {
        for (plate in plates) {
            if (deduplicationCache.isDuplicate(plate.normalizedText)) continue

            val hash = PlateHasher.hash(plate.normalizedText)
            val loc = locationProvider.currentLocation.value

            viewModelScope.launch(Dispatchers.IO) {
                queueDao.insert(
                    OfflineQueueEntry(
                        plateHash = hash,
                        timestamp = System.currentTimeMillis(),
                        latitude = loc?.latitude,
                        longitude = loc?.longitude
                    )
                )
                enforceMaxQueueSize()
                _queueDepth.value = queueDao.count()
            }

            _plateCount.value++
            _lastDetectionTime.value = System.currentTimeMillis()

            addFeedEntry(DetectionFeedEntry(
                plateText = plate.normalizedText,
                hashPrefix = hash.take(8),
                state = DetectionState.QUEUED
            ))
        }

        apiClient.checkAndFlush()
    }

    private fun onPlateSent(hash: String, matched: Boolean) {
        val prefix = hash.take(8)
        val newState = if (matched) DetectionState.MATCHED else DetectionState.SENT
        val current = _detectionFeed.value.toMutableList()
        val idx = current.indexOfLast { it.hashPrefix == prefix && it.state == DetectionState.QUEUED }
        if (idx >= 0) {
            current[idx] = current[idx].copy(state = newState)
            _detectionFeed.value = current
        }
    }

    private fun addFeedEntry(entry: DetectionFeedEntry) {
        val current = _detectionFeed.value.toMutableList()
        current.add(0, entry)
        if (current.size > 20) current.subList(20, current.size).clear()
        _detectionFeed.value = current
    }

    fun startPipeline() {
        locationProvider.startUpdates()
        apiClient.startBatchTimer()
        processTestImage()
    }

    private fun processTestImage() {
        val testFile = File(getApplication<Application>().filesDir, "test_plate.png")
        if (!testFile.exists()) return
        Log.d(TAG, "Found test image at ${testFile.absolutePath}")
        viewModelScope.launch(Dispatchers.IO) {
            val bitmap = BitmapFactory.decodeFile(testFile.absolutePath)
            if (bitmap != null) {
                Log.d(TAG, "Loaded test image: ${bitmap.width}x${bitmap.height}")
                frameAnalyzer.analyzeBitmap(bitmap)
            } else {
                Log.w(TAG, "Failed to decode test image")
            }
        }
    }

    fun stopPipeline() {
        locationProvider.stopUpdates()
        apiClient.stopBatchTimer()
        apiClient.flushQueue()
    }

    private suspend fun enforceMaxQueueSize() {
        val count = queueDao.count()
        if (count > AppConfig.MAX_QUEUE_SIZE) {
            queueDao.deleteOldest(count - AppConfig.MAX_QUEUE_SIZE)
        }
    }

    companion object {
        private const val TAG = "MainViewModel"
    }

    override fun onCleared() {
        super.onCleared()
        frameAnalyzer.close()
        locationProvider.stopUpdates()
        apiClient.stopBatchTimer()
    }
}
