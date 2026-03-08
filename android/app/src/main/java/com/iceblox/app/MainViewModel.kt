package com.iceblox.app

import android.app.Application
import android.graphics.Bitmap
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.iceblox.app.camera.TestFrameFeeder
import com.iceblox.app.capture.CaptureRepository
import com.iceblox.app.debug.DebugLog
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn

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

    companion object {
        private const val TAG = "MainViewModel"
    }

    override fun onCleared() {
        super.onCleared()
        _testFrameFeeder.value?.stop()
    }
}
