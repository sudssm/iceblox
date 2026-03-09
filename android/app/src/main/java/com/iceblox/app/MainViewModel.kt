package com.iceblox.app

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.PowerManager
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.iceblox.app.camera.FrameAnalyzer
import com.iceblox.app.camera.ProcessedPlate
import com.iceblox.app.camera.TestFrameFeeder
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
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
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class SessionSummary(
    val sessionId: String,
    val platesSeen: Long,
    val iceVehicles: Int,
    val durationMs: Long,
    val pendingUploads: Int
)

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

    private val _sessionSummary = MutableStateFlow<SessionSummary?>(null)
    val sessionSummary: StateFlow<SessionSummary?> = _sessionSummary

    private var activeSessionId: String? = null
    private var sessionStartedAt: Long = 0L

    val alertClient = AlertClient(
        context = application,
        locationProvider = locationProvider
    )

    val apiClient = ApiClient(
        context = application,
        queueDao = queueDao,
        retryManager = retryManager,
        onTargetMatched = { sessionId -> onTargetMatched(sessionId) },
        onPlateSent = { hash, matched, sessionId -> onPlateSent(hash, matched, sessionId) }
    )

    private val _testFrameFeeder = MutableStateFlow<TestFrameFeeder?>(null)
    val testFrameFeeder: StateFlow<TestFrameFeeder?> = _testFrameFeeder

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    val testBitmap: StateFlow<Bitmap?> = _testFrameFeeder
        .flatMapLatest { it?.currentBitmap ?: flowOf(null) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    val testStatus: StateFlow<String> = _testFrameFeeder
        .flatMapLatest { it?.status ?: flowOf("") }
        .stateIn(viewModelScope, SharingStarted.Eagerly, "")

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

    private val powerManager = application.getSystemService(Context.POWER_SERVICE) as PowerManager

    init {
        connectivityMonitor.onReconnected = {
            apiClient.flushQueue()
        }
        powerManager.addThermalStatusListener(thermalListener)
    }

    fun onPlatesDetected(plates: List<ProcessedPlate>) {
        val sessionId = activeSessionId ?: return

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

        val summary = _sessionSummary.value
        if (summary?.sessionId == sessionId) {
            _sessionSummary.value = summary.copy(iceVehicles = summary.iceVehicles + 1)
        }
    }

    private fun onPlateSent(hash: String, matched: Boolean, sessionId: String) {
        val prefix = hash.take(8)
        val newState = if (matched) DetectionState.MATCHED else DetectionState.SENT
        if (sessionId == visibleSessionId()) {
            val current = _detectionFeed.value.toMutableList()
            val idx = current.indexOfLast { it.hashPrefix == prefix && it.state == DetectionState.QUEUED }
            if (idx >= 0) {
                current[idx] = current[idx].copy(state = newState)
                _detectionFeed.value = current
            }
        }

        refreshQueueState(sessionId)
    }

    private fun addFeedEntry(entry: DetectionFeedEntry) {
        val current = _detectionFeed.value.toMutableList()
        current.add(0, entry)
        if (current.size > 20) current.subList(20, current.size).clear()
        _detectionFeed.value = current
    }

    fun startPipeline(isTestMode: Boolean = false) {
        if (_sessionSummary.value != null) return
        if (activeSessionId == null) {
            startNewSession()
        }
        locationProvider.startUpdates()
        apiClient.startBatchTimer()
        alertClient.startTimer()
        if (isTestMode) {
            startTestMode()
        } else {
            processTestImage()
        }
    }

    private fun startTestMode() {
        val app = getApplication<Application>()
        val feeder = TestFrameFeeder(app, frameAnalyzer)
        _testFrameFeeder.value = feeder
        if (feeder.loadImages()) {
            DebugLog.d(TAG, "Test mode: ${feeder.imageCount} images loaded, starting feed")
            feeder.start(viewModelScope)
        } else {
            DebugLog.w(TAG, "Test mode: no test images found")
        }
    }

    private fun processTestImage() {
        val testFile = File(getApplication<Application>().filesDir, "test_plate.png")
        if (!testFile.exists()) return
        DebugLog.d(TAG, "Found test image at ${testFile.absolutePath}")
        viewModelScope.launch(Dispatchers.IO) {
            val bitmap = BitmapFactory.decodeFile(testFile.absolutePath)
            if (bitmap != null) {
                DebugLog.d(TAG, "Loaded test image: ${bitmap.width}x${bitmap.height}")
                frameAnalyzer.analyzeBitmap(bitmap)
            } else {
                DebugLog.w(TAG, "Failed to decode test image")
            }
        }
    }

    fun stopPipeline() {
        _testFrameFeeder.value?.stop()
        locationProvider.stopUpdates()
        apiClient.stopBatchTimer()
        apiClient.flushQueue()
        alertClient.subscribeOnce()
        alertClient.stopTimer()
    }

    fun stopRecordingSession() {
        val sessionId = activeSessionId ?: return
        val stoppedAt = System.currentTimeMillis()
        val durationMs = (stoppedAt - sessionStartedAt).coerceAtLeast(0L)

        activeSessionId = null
        stopPipeline()

        viewModelScope.launch(Dispatchers.IO) {
            val pendingUploads = queueDao.countBySessionId(sessionId)
            _sessionSummary.value = SessionSummary(
                sessionId = sessionId,
                platesSeen = _plateCount.value,
                iceVehicles = _targetCount.value,
                durationMs = durationMs,
                pendingUploads = pendingUploads
            )
            _queueDepth.value = queueDao.count()
        }
    }

    fun dismissSessionSummary() {
        _sessionSummary.value = null
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
        _testFrameFeeder.value?.stop()
        powerManager.removeThermalStatusListener(thermalListener)
        frameAnalyzer.close()
        locationProvider.stopUpdates()
        apiClient.stopBatchTimer()
        alertClient.stopTimer()
    }

    private fun startNewSession() {
        activeSessionId = UUID.randomUUID().toString()
        sessionStartedAt = System.currentTimeMillis()
        deduplicationCache.reset()
        _plateCount.value = 0L
        _targetCount.value = 0
        _lastDetectionTime.value = 0L
        _detectionFeed.value = emptyList()
        _sessionSummary.value = null
    }

    private fun visibleSessionId(): String? = _sessionSummary.value?.sessionId ?: activeSessionId

    private fun refreshQueueState(sessionId: String) {
        viewModelScope.launch(Dispatchers.IO) {
            _queueDepth.value = queueDao.count()

            val summary = _sessionSummary.value
            if (summary?.sessionId == sessionId) {
                _sessionSummary.value = summary.copy(
                    pendingUploads = queueDao.countBySessionId(sessionId)
                )
            }
        }
    }
}
