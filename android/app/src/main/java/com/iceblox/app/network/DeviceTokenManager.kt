package com.iceblox.app.network

import android.content.Context
import android.provider.Settings
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class DeviceTokenManager(
    context: Context,
    private val client: OkHttpClient = OkHttpClient(),
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
) {
    private val deviceId: String = Settings.Secure.getString(
        context.contentResolver,
        Settings.Secure.ANDROID_ID
    ) ?: "unknown"

    fun registerToken(token: String, platform: String = "android") {
        scope.launch {
            registerWithRetry(token, platform)
        }
    }

    internal suspend fun registerWithRetry(token: String, platform: String) {
        val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.DEVICES_ENDPOINT}"
        val mediaType = "application/json".toMediaType()

        val json = JSONObject().apply {
            put("token", token)
            put("platform", platform)
        }

        val request = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .addHeader("X-Device-ID", deviceId)
            .post(json.toString().toRequestBody(mediaType))
            .build()

        var attempts = 0
        while (attempts < AppConfig.RETRY_MAX_ATTEMPTS) {
            try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        DebugLog.d(TAG, "Token registered successfully")
                        return
                    }
                    DebugLog.w(TAG, "Token registration failed: ${response.code}")
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "Token registration error: ${e.message}")
            }

            val backoff = minOf(
                AppConfig.RETRY_INITIAL_DELAY_MS * (1L shl attempts),
                AppConfig.RETRY_MAX_DELAY_MS
            )
            attempts++
            DebugLog.d(TAG, "Retrying token registration in ${backoff}ms (attempt $attempts)")
            delay(backoff)
        }
        DebugLog.e(TAG, "Token registration failed after $attempts attempts")
    }

    fun buildRegistrationRequest(token: String, platform: String): Request {
        val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.DEVICES_ENDPOINT}"
        val mediaType = "application/json".toMediaType()

        val json = JSONObject().apply {
            put("token", token)
            put("platform", platform)
        }

        return Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .addHeader("X-Device-ID", deviceId)
            .post(json.toString().toRequestBody(mediaType))
            .build()
    }

    companion object {
        private const val TAG = "DeviceTokenManager"
    }
}
