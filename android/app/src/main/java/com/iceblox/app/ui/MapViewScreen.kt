package com.iceblox.app.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState
import com.iceblox.app.network.MapClient
import com.iceblox.app.network.MapSighting
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.debounce
import org.json.JSONArray
import org.json.JSONObject

@OptIn(ExperimentalMaterial3Api::class, FlowPreview::class)
@Composable
fun MapViewScreen(locationLat: Double?, locationLng: Double?, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val mapClient = remember { MapClient() }
    val prefs = remember { context.getSharedPreferences("map_cache", Context.MODE_PRIVATE) }

    var sightings by remember { mutableStateOf<List<MapSighting>>(loadCachedSightings(prefs)) }
    var isLoading by remember { mutableStateOf(true) }
    var isOffline by remember { mutableStateOf(false) }

    val initialLat = locationLat ?: 40.7128
    val initialLng = locationLng ?: -74.0060
    val cameraPositionState = rememberCameraPositionState {
        position = CameraPosition.fromLatLngZoom(LatLng(initialLat, initialLng), 12f)
    }

    LaunchedEffect(cameraPositionState) {
        snapshotFlow { cameraPositionState.position }
            .debounce(500)
            .collect { position ->
                val target = position.target
                val visibleRadius = estimateVisibleRadius(cameraPositionState.position.zoom)
                isLoading = true
                val result = mapClient.fetchSightings(target.latitude, target.longitude, visibleRadius)
                result.onSuccess { data ->
                    sightings = data
                    isOffline = false
                    saveCachedSightings(prefs, data)
                }.onFailure {
                    isOffline = true
                }
                isLoading = false
            }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("View Map", color = Color.White) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = Color.White
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Black)
            )
        },
        containerColor = Color.Black
    ) { padding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            Text(
                text = "Reported ICE vehicles near you",
                color = Color.White,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.Black)
                    .padding(vertical = 8.dp)
            )

            if (isOffline) {
                Text(
                    text = "Offline — showing cached data",
                    color = Color.Yellow,
                    fontSize = 12.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(Color.Black)
                        .padding(vertical = 4.dp)
                )
            }

            Box(modifier = Modifier.fillMaxSize()) {
                GoogleMap(
                    modifier = Modifier.fillMaxSize(),
                    cameraPositionState = cameraPositionState,
                    properties = MapProperties(isMyLocationEnabled = true)
                ) {
                    sightings.forEach { sighting ->
                        val hue = if (sighting.confidence >= 0.5) {
                            BitmapDescriptorFactory.HUE_RED
                        } else {
                            BitmapDescriptorFactory.HUE_YELLOW
                        }
                        val title = if (sighting.confidence >= 0.5) {
                            "Likely ICE activity"
                        } else {
                            "Potential ICE activity"
                        }
                        val snippet = buildString {
                            append(formatTimeAgo(sighting.seenAt))
                            if (sighting.type == "report") {
                                append(" • User submitted report")
                                sighting.description?.let { append("\n$it") }
                            }
                        }
                        Marker(
                            state = MarkerState(
                                position = LatLng(sighting.latitude, sighting.longitude)
                            ),
                            title = title,
                            snippet = snippet,
                            icon = BitmapDescriptorFactory.defaultMarker(hue)
                        )
                    }
                }

                if (isLoading) {
                    CircularProgressIndicator(
                        color = Color.White,
                        modifier = Modifier
                            .align(Alignment.Center)
                            .padding(16.dp)
                    )
                }
            }
        }
    }
}

private fun estimateVisibleRadius(zoom: Float): Double {
    val earthCircumferenceMiles = 24901.0
    val visibleDegrees = 360.0 / Math.pow(2.0, zoom.toDouble())
    return (visibleDegrees / 360.0 * earthCircumferenceMiles / 2).coerceIn(1.0, 500.0)
}

private fun formatTimeAgo(seenAt: String): String = try {
    val formatter = java.time.ZonedDateTime.parse(seenAt)
    val minutes = java.time.Duration.between(formatter, java.time.ZonedDateTime.now()).toMinutes()
    when {
        minutes < 1 -> "Just now"
        minutes < 60 -> "$minutes min ago"
        else -> "${minutes / 60}h ago"
    }
} catch (_: Exception) {
    seenAt
}

private fun saveCachedSightings(prefs: SharedPreferences, sightings: List<MapSighting>) {
    val array = JSONArray()
    for (s in sightings) {
        val obj = JSONObject()
        obj.put("latitude", s.latitude)
        obj.put("longitude", s.longitude)
        obj.put("confidence", s.confidence)
        obj.put("seen_at", s.seenAt)
        obj.put("type", s.type)
        s.description?.let { obj.put("description", it) }
        s.photoUrl?.let { obj.put("photo_url", it) }
        array.put(obj)
    }
    prefs.edit().putString("cached_sightings", array.toString()).apply()
}

private fun loadCachedSightings(prefs: SharedPreferences): List<MapSighting> {
    val raw = prefs.getString("cached_sightings", null) ?: return emptyList()
    return try {
        val array = JSONArray(raw)
        val list = mutableListOf<MapSighting>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            list.add(
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
        list
    } catch (_: Exception) {
        emptyList()
    }
}
