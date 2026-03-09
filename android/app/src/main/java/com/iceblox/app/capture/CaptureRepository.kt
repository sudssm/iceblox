package com.iceblox.app.capture

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.PowerManager
import com.iceblox.app.camera.FrameAnalyzer
import com.iceblox.app.camera.ProcessedPlate
import com.iceblox.app.config.AppConfig
import com.iceblox.app.location.LocationProvider
import com.iceblox.app.network.AlertClient
import com.iceblox.app.network.ApiClient
import com.iceblox.app.network.ConnectivityMonitor
import com.iceblox.app.network.RetryManager
import com.iceblox.app.persistence.OfflineQueueDatabase
import com.iceblox.app.persistence.OfflineQueueEntry
import com.iceblox.app.processing.DeduplicationCache
import com.iceblox.app.processing.PlateHasher
import com.iceblox.app.ui.DetectionFeedEntry
import com.iceblox.app.ui.DetectionState
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class CaptureRepository(private val application: Application) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val deduplicationCache = DeduplicationCache()
    private val database = OfflineQueueDatabase.getInstance(application)
    private val queueDao = database.queueDao()
    private val retryManager = RetryManager()

    @Volatile
    var activeSessionId: String? = null
        private set

    val locationProvider = LocationProvider(application)
    val connectivityMonitor = ConnectivityMonitor(application)
    val alertClient = AlertClient(
        context = application,
        locationProvider = locationProvider
    )

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
        onTargetMatched = { sessionId -> onTargetMatched(sessionId) },
        onPlateSent = { hash, matched, sessionId -> onPlateSent(hash, matched, sessionId) },
        onQueueDepthChanged = { depth -> _queueDepth.value = depth }
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

    private val powerManager =
        application.getSystemService(Context.POWER_SERVICE) as PowerManager

    @Volatile
    private var foregroundActive = false

    @Volatile
    private var backgroundActive = false

    init {
        connectivityMonitor.onReconnected = {
            apiClient.flushQueue()
        }
        powerManager.addThermalStatusListener(thermalListener)
        refreshQueueDepth()
    }

    fun setForegroundActive(active: Boolean) {
        foregroundActive = active
        updateSharedComponents()
    }

    fun setBackgroundActive(active: Boolean) {
        backgroundActive = active
        updateSharedComponents()
    }

    fun resetSessionState(sessionId: String) {
        activeSessionId = sessionId
        deduplicationCache.reset()
        _plateCount.value = 0L
        _targetCount.value = 0
        _lastDetectionTime.value = 0L
        _detectionFeed.value = emptyList()
    }

    suspend fun countBySessionId(sessionId: String): Int =
        queueDao.countBySessionId(sessionId)

    fun processTestImageIfPresent() {
        val testFile = File(application.filesDir, "test_plate.png")
        if (!testFile.exists()) return
        scope.launch(Dispatchers.IO) {
            val bitmap = BitmapFactory.decodeFile(testFile.absolutePath)
            if (bitmap != null) {
                frameAnalyzer.analyzeBitmap(bitmap)
                bitmap.recycle()
            }
        }
    }

    private fun updateSharedComponents() {
        if (foregroundActive || backgroundActive) {
            locationProvider.startUpdates()
            apiClient.startBatchTimer()
            alertClient.startTimer()
        } else {
            locationProvider.stopUpdates()
            apiClient.stopBatchTimer()
            apiClient.flushQueue()
            alertClient.subscribeOnce()
            alertClient.stopTimer()
        }
    }

    private fun onPlatesDetected(plates: List<ProcessedPlate>) {
        val sessionId = activeSessionId ?: return

        for (plate in plates) {
            if (deduplicationCache.isDuplicate(plate.normalizedText)) continue

            val hash = PlateHasher.hash(plate.normalizedText)
            val loc = locationProvider.currentLocation.value

            scope.launch(Dispatchers.IO) {
                queueDao.insert(
                    OfflineQueueEntry(
                        plateHash = hash,
                        timestamp = System.currentTimeMillis(),
                        latitude = loc?.latitude,
                        longitude = loc?.longitude,
                        sessionId = sessionId
                    )
                )
                enforceMaxQueueSize()
                _queueDepth.value = queueDao.count()
                apiClient.checkAndFlush()
            }

            _plateCount.update { it + 1 }
            _lastDetectionTime.value = System.currentTimeMillis()

            addFeedEntry(
                DetectionFeedEntry(
                    plateText = plate.normalizedText,
                    hashPrefix = hash.take(8),
                    state = DetectionState.QUEUED
                )
            )
        }
    }

    private fun onTargetMatched(sessionId: String) {
        if (sessionId == activeSessionId) {
            _targetCount.update { it + 1 }
        }
    }

    private fun onPlateSent(hash: String, matched: Boolean, sessionId: String) {
        val prefix = hash.take(8)
        val newState = if (matched) DetectionState.MATCHED else DetectionState.SENT
        val current = _detectionFeed.value.toMutableList()
        val idx = current.indexOfLast {
            it.hashPrefix == prefix && it.state == DetectionState.QUEUED
        }
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

    private fun refreshQueueDepth() {
        scope.launch(Dispatchers.IO) {
            _queueDepth.value = queueDao.count()
        }
    }

    private suspend fun enforceMaxQueueSize() {
        val count = queueDao.count()
        if (count > AppConfig.MAX_QUEUE_SIZE) {
            queueDao.deleteOldest(count - AppConfig.MAX_QUEUE_SIZE)
        }
    }
}
