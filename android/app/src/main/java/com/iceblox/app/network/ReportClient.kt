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
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class ReportClient(context: Context) {
    private val client = OkHttpClient()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val deviceId: String = Settings.Secure.getString(
        context.contentResolver,
        Settings.Secure.ANDROID_ID
    ) ?: "unknown"

    fun submitReport(
        photoBytes: ByteArray,
        description: String,
        plateNumber: String?,
        latitude: Double,
        longitude: Double,
        onResult: (Result<Int>) -> Unit
    ) {
        scope.launch {
            val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.REPORTS_ENDPOINT}"

            val bodyBuilder = MultipartBody.Builder()
                .setType(MultipartBody.FORM)
                .addFormDataPart("description", description)
                .addFormDataPart("latitude", latitude.toString())
                .addFormDataPart("longitude", longitude.toString())
                .addFormDataPart(
                    "photo",
                    "report.jpg",
                    photoBytes.toRequestBody("image/jpeg".toMediaType())
                )

            if (!plateNumber.isNullOrBlank()) {
                bodyBuilder.addFormDataPart("plate_number", plateNumber)
            }

            val request = Request.Builder()
                .url(url)
                .addHeader("X-Device-ID", deviceId)
                .post(bodyBuilder.build())
                .build()

            val result = try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        val responseBody = response.body?.string()
                        val reportId = responseBody?.let {
                            try {
                                JSONObject(it).optInt("report_id", -1)
                            } catch (e: Exception) {
                                -1
                            }
                        } ?: -1
                        DebugLog.d(TAG, "Report submitted, id=$reportId")
                        Result.success(reportId)
                    } else {
                        DebugLog.w(TAG, "Report submission failed: ${response.code}")
                        Result.failure(IOException("Server returned ${response.code}"))
                    }
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "Report submission failed: ${e.message}")
                Result.failure(e)
            }
            withContext(Dispatchers.Main) {
                onResult(result)
            }
        }
    }

    companion object {
        private const val TAG = "ReportClient"
    }
}
