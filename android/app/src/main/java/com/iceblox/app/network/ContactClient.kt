package com.iceblox.app.network

import android.content.Context
import android.provider.Settings
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class ContactClient(context: Context) {
    private val client = OkHttpClient()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val deviceId: String = Settings.Secure.getString(
        context.contentResolver,
        Settings.Secure.ANDROID_ID
    ) ?: "unknown"

    fun submitContact(name: String, email: String, message: String, logs: String?, onResult: (Result<Int>) -> Unit) {
        scope.launch {
            val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.CONTACT_ENDPOINT}"

            val body = JSONObject().apply {
                put("name", name)
                put("email", email)
                put("message", message)
                put("hardware_id", deviceId)
                if (!logs.isNullOrEmpty()) {
                    put("logs", logs)
                }
            }

            val request = Request.Builder()
                .url(url)
                .addHeader("X-Device-ID", deviceId)
                .addHeader("Content-Type", "application/json")
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .build()

            val result = try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val responseBody = response.body?.string()
                        val contactId = responseBody?.let {
                            try {
                                JSONObject(it).optInt("contact_id", -1)
                            } catch (e: Exception) {
                                -1
                            }
                        } ?: -1
                        DebugLog.d(TAG, "Contact submitted, id=$contactId")
                        Result.success(contactId)
                    } else {
                        DebugLog.w(TAG, "Contact submission failed: ${response.code}")
                        Result.failure(IOException("Server returned ${response.code}"))
                    }
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "Contact submission failed: ${e.message}")
                Result.failure(e)
            }
            withContext(Dispatchers.Main) {
                onResult(result)
            }
        }
    }

    companion object {
        private const val TAG = "ContactClient"
    }
}
