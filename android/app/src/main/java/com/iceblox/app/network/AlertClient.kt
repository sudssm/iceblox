package com.iceblox.app.network

import android.content.Context
import android.provider.Settings
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import com.iceblox.app.location.LocationProvider
import java.io.IOException
import kotlin.math.floor
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

class AlertClient(
    context: Context,
    private val locationProvider: LocationProvider,
    private val client: OkHttpClient = OkHttpClient(),
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
) {
    private val deviceId: String = Settings.Secure.getString(
        context.contentResolver,
        Settings.Secure.ANDROID_ID
    ) ?: "unknown"

    private var timerJob: Job? = null

    var nearbySightings: Int = 0
        private set

    fun startTimer() {
        timerJob?.cancel()
        timerJob = scope.launch {
            subscribe()
            while (isActive) {
                delay(AppConfig.SUBSCRIBE_INTERVAL_MS)
                subscribe()
            }
        }
    }

    fun stopTimer() {
        timerJob?.cancel()
        timerJob = null
    }

    fun subscribeOnce() {
        scope.launch { subscribe() }
    }

    internal suspend fun subscribe() {
        val location = locationProvider.currentLocation.value
        if (location == null) {
            DebugLog.w(TAG, "subscribe: no location available")
            return
        }

        val truncatedLat = truncateGps(location.latitude)
        val truncatedLon = truncateGps(location.longitude)

        val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.SUBSCRIBE_ENDPOINT}"
        val mediaType = "application/json".toMediaType()

        val json = JSONObject().apply {
            put("latitude", truncatedLat)
            put("longitude", truncatedLon)
            put("radius_miles", AppConfig.DEFAULT_RADIUS_MILES)
        }

        val request = Request.Builder()
            .url(url)
            .addHeader("Content-Type", "application/json")
            .addHeader("X-Device-ID", deviceId)
            .post(json.toString().toRequestBody(mediaType))
            .build()

        try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    DebugLog.w(TAG, "subscribe failed: ${response.code}")
                    return
                }

                val body = response.body?.string() ?: return
                val responseJson = JSONObject(body)
                val sightings = responseJson.optJSONArray("recent_sightings")

                if (sightings != null && sightings.length() > 0) {
                    for (i in 0 until sightings.length()) {
                        val sighting = sightings.getJSONObject(i)
                        val sightingId = sighting.optString("sighting_id", "unknown")
                        val timestamp = sighting.optString("timestamp", "")
                        DebugLog.d(TAG, "Nearby sighting: id=$sightingId ts=$timestamp")
                    }
                    nearbySightings += sightings.length()
                    DebugLog.d(TAG, "Total nearby sightings: $nearbySightings")
                }
            }
        } catch (e: IOException) {
            DebugLog.w(TAG, "subscribe error: ${e.message}")
        }
    }

    companion object {
        private const val TAG = "AlertClient"

        fun truncateGps(value: Double): Double {
            return floor(value * 100) / 100
        }
    }
}
