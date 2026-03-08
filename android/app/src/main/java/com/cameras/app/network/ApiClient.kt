package com.cameras.app.network

import android.content.Context
import android.provider.Settings
import android.util.Log
import com.cameras.app.config.AppConfig
import com.cameras.app.persistence.OfflineQueueDao
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
import org.json.JSONObject
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

class ApiClient(
    context: Context,
    private val queueDao: OfflineQueueDao,
    private val retryManager: RetryManager,
    private val onTargetMatched: () -> Unit,
    private val onPlateSent: (hash: String, matched: Boolean) -> Unit = { _, _ -> }
) {
    private val client = OkHttpClient()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var batchJob: Job? = null
    private val deviceId: String = Settings.Secure.getString(
        context.contentResolver, Settings.Secure.ANDROID_ID
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

    private suspend fun checkAndFlushInternal() {
        val count = queueDao.count()
        if (count >= AppConfig.BATCH_SIZE) {
            sendBatch()
        }
    }

    private suspend fun sendBatch() {
        if (retryManager.isRateLimited) return

        val entries = queueDao.dequeue(AppConfig.BATCH_SIZE)
        if (entries.isEmpty()) return

        val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.PLATES_ENDPOINT}"
        val mediaType = "application/json".toMediaType()

        for (entry in entries) {
            val json = JSONObject().apply {
                put("plate_hash", entry.plateHash)
                put("latitude", entry.latitude ?: 0.0)
                put("longitude", entry.longitude ?: 0.0)
                val ts = Instant.ofEpochMilli(entry.timestamp)
                    .atOffset(ZoneOffset.UTC)
                    .format(DateTimeFormatter.ISO_INSTANT)
                put("timestamp", ts)
            }

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
                            queueDao.deleteByIds(listOf(entry.id))
                            response.body?.string()?.let { body ->
                                try {
                                    val responseJson = JSONObject(body)
                                    val matched = responseJson.optBoolean("matched", false)
                                    if (matched) {
                                        onTargetMatched()
                                    }
                                    onPlateSent(entry.plateHash, matched)
                                } catch (e: Exception) {
                                    Log.w(TAG, "Failed to parse response: ${e.message}")
                                }
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
                Log.w(TAG, "Upload failed: ${e.message}")
                val delayMs = retryManager.handleFailure() ?: return
                delay(delayMs)
                return
            }
        }
    }

    companion object {
        private const val TAG = "ApiClient"
    }
}
