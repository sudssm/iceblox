package com.cameras.app

import android.app.Application
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

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

    val apiClient = ApiClient(
        context = application,
        queueDao = queueDao,
        retryManager = retryManager,
        onTargetMatched = { _targetCount.value++ }
    )

    val frameAnalyzer = FrameAnalyzer(application) { plates ->
        onPlatesDetected(plates)
    }

    init {
        connectivityMonitor.onReconnected = {
            apiClient.flushQueue()
        }
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
        }

        apiClient.checkAndFlush()
    }

    fun startPipeline() {
        locationProvider.startUpdates()
        apiClient.startBatchTimer()
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

    override fun onCleared() {
        super.onCleared()
        frameAnalyzer.close()
        locationProvider.stopUpdates()
        apiClient.stopBatchTimer()
    }
}
