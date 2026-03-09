package com.iceblox.app

import android.app.Application
import android.graphics.Bitmap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.iceblox.app.camera.TestFrameFeeder
import com.iceblox.app.capture.CaptureRepository
import com.iceblox.app.debug.DebugLog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

data class SessionSummary(
    val sessionId: String,
    val platesSeen: Long,
    val iceVehicles: Int,
    val durationMs: Long,
    val pendingUploads: Int
)

class MainViewModel(application: Application) : AndroidViewModel(application) {
    private val repository: CaptureRepository =
        (application as IceBloxApplication).captureRepository

    val locationProvider = repository.locationProvider
    val connectivityMonitor = repository.connectivityMonitor
    val plateCount: StateFlow<Long> = repository.plateCount
    val targetCount: StateFlow<Int> = repository.targetCount
    val lastDetectionTime: StateFlow<Long> = repository.lastDetectionTime
    val queueDepth: StateFlow<Int> = repository.queueDepth
    val detectionFeed = repository.detectionFeed
    val alertClient = repository.alertClient
    val apiClient = repository.apiClient

    private val _sessionSummary = MutableStateFlow<SessionSummary?>(null)
    val sessionSummary: StateFlow<SessionSummary?> = _sessionSummary

    private var activeSessionId: String? = null
    private var sessionStartedAt: Long = 0L

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

    val frameAnalyzer = repository.frameAnalyzer

    fun startForegroundPipeline(isTestMode: Boolean = false) {
        if (_sessionSummary.value != null) return
        if (activeSessionId == null) {
            startNewSession()
        }
        repository.setForegroundActive(true)
        if (isTestMode) {
            startTestMode()
        } else {
            repository.processTestImageIfPresent()
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

    fun stopForegroundPipeline() {
        _testFrameFeeder.value?.stop()
        repository.setForegroundActive(false)
    }

    fun stopRecordingSession() {
        val sessionId = activeSessionId ?: return
        val stoppedAt = System.currentTimeMillis()
        val durationMs = (stoppedAt - sessionStartedAt).coerceAtLeast(0L)

        activeSessionId = null
        stopForegroundPipeline()

        viewModelScope.launch(Dispatchers.IO) {
            val pendingUploads = repository.countBySessionId(sessionId)
            _sessionSummary.value = SessionSummary(
                sessionId = sessionId,
                platesSeen = plateCount.value,
                iceVehicles = targetCount.value,
                durationMs = durationMs,
                pendingUploads = pendingUploads
            )
        }
    }

    fun dismissSessionSummary() {
        _sessionSummary.value = null
    }

    companion object {
        private const val TAG = "MainViewModel"
    }

    override fun onCleared() {
        super.onCleared()
        _testFrameFeeder.value?.stop()
    }

    private fun startNewSession() {
        activeSessionId = java.util.UUID.randomUUID().toString()
        sessionStartedAt = System.currentTimeMillis()
        repository.resetSessionState(activeSessionId!!)
        _sessionSummary.value = null
    }
}
