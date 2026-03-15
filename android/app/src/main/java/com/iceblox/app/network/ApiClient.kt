package com.iceblox.app.network

import android.content.Context
import android.provider.Settings
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import com.iceblox.app.persistence.OfflineQueueDao
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

class ApiClient(
    context: Context,
    private val queueDao: OfflineQueueDao,
    private val retryManager: RetryManager,
    private val onTargetMatched: (sessionId: String) -> Unit,
    private val onPlateSent: (hash: String, matched: Boolean, sessionId: String) -> Unit = { _, _, _ -> },
    private val onQueueDepthChanged: (Int) -> Unit = { }
) {
    private val client = OkHttpClient()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var batchJob: Job? = null
    private var deadlineJob: Job? = null
    private val deviceId: String = Settings.Secure.getString(
        context.contentResolver,
        Settings.Secure.ANDROID_ID
    ) ?: "unknown"

    fun startBatchTimer() {
        batchJob?.cancel()
        batchJob = scope.launch {
            while (isActive) {
                delay(AppConfig.BATCH_INTERVAL_MS)
                sendBatch()
            }
        }
    }

    fun stopBatchTimer() {
        batchJob?.cancel()
        batchJob = null
    }

    fun checkAndFlush() {
        scope.launch { checkAndFlushInternal() }
    }

    fun flushQueue() {
        scope.launch { sendBatch() }
    }

    fun registerDeviceToken(token: String) {
        scope.launch {
            val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.DEVICES_ENDPOINT}"
            val mediaType = "application/json".toMediaType()
            val json = JSONObject().apply {
                put("token", token)
                put("platform", "android")
            }
            val request = Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .addHeader("X-Device-ID", deviceId)
                .post(json.toString().toRequestBody(mediaType))
                .build()
            try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        DebugLog.d(TAG, "Device token registered")
                    } else {
                        DebugLog.w(TAG, "Device token registration failed: ${response.code}")
                    }
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "Device token registration failed: ${e.message}")
            }
        }
    }

    private suspend fun checkAndFlushInternal() {
        val count = queueDao.count()
        if (count >= AppConfig.BATCH_SIZE) {
            deadlineJob?.cancel()
            deadlineJob = null
            sendBatch()
        } else if (count > 0 && deadlineJob == null) {
            deadlineJob = scope.launch {
                delay(AppConfig.MAX_BATCH_WAIT_MS)
                deadlineJob = null
                sendBatch()
            }
        }
    }

    private suspend fun sendBatch() {
        deadlineJob?.cancel()
        deadlineJob = null
        if (retryManager.isRateLimited) {
            DebugLog.w(TAG, "sendBatch: rate limited, skipping")
            return
        }

        val cutoff = System.currentTimeMillis() - AppConfig.UPLOAD_TIMEOUT_MS
        val expired = queueDao.selectOlderThan(cutoff)
        if (expired.isNotEmpty()) {
            queueDao.deleteOlderThan(cutoff)
            for (entry in expired) {
                onPlateSent(entry.plateHash, false, entry.sessionId)
            }
        }
        onQueueDepthChanged(queueDao.count())

        val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.PLATES_ENDPOINT}"
        val mediaType = "application/json".toMediaType()

        while (true) {
            val entries = queueDao.dequeue(AppConfig.BATCH_SIZE)
            if (entries.isEmpty()) return
            DebugLog.d(TAG, "sendBatch: sending ${entries.size} entries")

            val platesArray = JSONArray()
            for (entry in entries) {
                val plate = JSONObject().apply {
                    put("plate_hash", entry.plateHash)
                    put("latitude", entry.latitude ?: 0.0)
                    put("longitude", entry.longitude ?: 0.0)
                    val ts = Instant.ofEpochMilli(entry.timestamp)
                        .atOffset(ZoneOffset.UTC)
                        .format(DateTimeFormatter.ISO_INSTANT)
                    put("timestamp", ts)
                    put("confidence", entry.confidence.toDouble())
                }
                platesArray.put(plate)
            }
            val json = JSONObject().apply { put("plates", platesArray) }

            val request = Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .addHeader("X-Device-ID", deviceId)
                .post(json.toString().toRequestBody(mediaType))
                .build()

            try {
                client.newCall(request).execute().use { response ->
                    when (response.code) {
                        200 -> {
                            retryManager.reset()
                            queueDao.deleteByIds(entries.map { it.id })
                            onQueueDepthChanged(queueDao.count())
                            val matchResults = BooleanArray(entries.size)
                            response.body?.string()?.let { body ->
                                try {
                                    val responseJson = JSONObject(body)
                                    val results = responseJson.optJSONArray("results") ?: return@let
                                    for (i in 0 until results.length().coerceAtMost(entries.size)) {
                                        matchResults[i] = results.getJSONObject(i).optBoolean("matched", false)
                                    }
                                } catch (e: Exception) {
                                    DebugLog.w(TAG, "Failed to parse response: ${e.message}")
                                }
                            }
                            for (i in entries.indices) {
                                val entry = entries[i]
                                if (matchResults[i]) {
                                    onTargetMatched(entry.sessionId)
                                }
                                onPlateSent(entry.plateHash, matchResults[i], entry.sessionId)
                            }
                        }

                        429 -> {
                            val retryAfter = response.header("Retry-After")?.toLongOrNull() ?: 60
                            retryManager.handleRateLimit(retryAfter)
                            return
                        }

                        else -> {
                            val delayMs = retryManager.handleFailure() ?: return
                            delay(delayMs)
                            return
                        }
                    }
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "Upload failed: ${e.message}")
                val delayMs = retryManager.handleFailure() ?: return
                delay(delayMs)
                return
            }
        }
    }

    fun startSession(sessionId: String) {
        scope.launch {
            val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.SESSIONS_START_ENDPOINT}"
            val mediaType = "application/json".toMediaType()
            val json = JSONObject().apply {
                put("session_id", sessionId)
                put("device_id", deviceId)
            }
            val request = Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .post(json.toString().toRequestBody(mediaType))
                .build()
            try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        DebugLog.d(TAG, "Session started: $sessionId")
                    } else {
                        DebugLog.w(TAG, "Session start failed: ${response.code}")
                    }
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "Session start failed: ${e.message}")
            }
        }
    }

    fun endSession(
        sessionId: String,
        maxDetConf: Float,
        totalDetConf: Float,
        maxOCRConf: Float,
        totalOCRConf: Float
    ) {
        scope.launch {
            val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.SESSIONS_END_ENDPOINT}"
            val mediaType = "application/json".toMediaType()
            val json = JSONObject().apply {
                put("session_id", sessionId)
                put("max_detection_confidence", maxDetConf.toDouble())
                put("total_detection_confidence", totalDetConf.toDouble())
                put("max_ocr_confidence", maxOCRConf.toDouble())
                put("total_ocr_confidence", totalOCRConf.toDouble())
            }
            val request = Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .post(json.toString().toRequestBody(mediaType))
                .build()
            try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        DebugLog.d(TAG, "Session ended: $sessionId")
                    } else {
                        DebugLog.w(TAG, "Session end failed: ${response.code}")
                    }
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "Session end failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "ApiClient"
    }
}
