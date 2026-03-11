package com.iceblox.app.network

import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

data class MapSighting(
    val latitude: Double,
    val longitude: Double,
    val confidence: Double,
    val seenAt: String,
    val type: String,
    val description: String?,
    val photoUrl: String?
)

class MapClient(private val client: OkHttpClient = OkHttpClient()) {
    suspend fun fetchSightings(lat: Double, lng: Double, radius: Double): Result<List<MapSighting>> =
        withContext(Dispatchers.IO) {
            val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.MAP_SIGHTINGS_ENDPOINT}" +
                "?lat=$lat&lng=$lng&radius=$radius"

            val request = Request.Builder()
                .url(url)
                .get()
                .build()

            try {
                client.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) {
                        return@withContext Result.failure(IOException("HTTP ${response.code}"))
                    }

                    val body = response.body?.string()
                        ?: return@withContext Result.failure(IOException("Empty response"))

                    val json = JSONObject(body)
                    val array = json.optJSONArray("sightings")
                        ?: return@withContext Result.success(emptyList())

                    val sightings = mutableListOf<MapSighting>()
                    for (i in 0 until array.length()) {
                        val obj = array.getJSONObject(i)
                        sightings.add(
                            MapSighting(
                                latitude = obj.getDouble("latitude"),
                                longitude = obj.getDouble("longitude"),
                                confidence = obj.getDouble("confidence"),
                                seenAt = obj.getString("seen_at"),
                                type = obj.getString("type"),
                                description = if (obj.has("description")) obj.getString("description") else null,
                                photoUrl = if (obj.has("photo_url")) obj.getString("photo_url") else null
                            )
                        )
                    }
                    Result.success(sightings)
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "fetchSightings error: ${e.message}")
                Result.failure(e)
            }
        }

    companion object {
        private const val TAG = "MapClient"
    }
}
