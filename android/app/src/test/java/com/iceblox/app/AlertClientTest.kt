package com.iceblox.app

import android.location.Location
import com.iceblox.app.location.LocationProvider
import com.iceblox.app.network.AlertClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class AlertClientTest {

    private lateinit var server: MockWebServer

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun truncateGpsPositiveValue() {
        assertEquals(36.16, AlertClient.truncateGps(36.1627), 0.0001)
    }

    @Test
    fun truncateGpsNegativeValue() {
        assertEquals(-86.78, AlertClient.truncateGps(-86.7743), 0.0001)
    }

    @Test
    fun truncateGpsExactValue() {
        assertEquals(40.71, AlertClient.truncateGps(40.71), 0.0001)
    }

    @Test
    fun truncateGpsZero() {
        assertEquals(0.0, AlertClient.truncateGps(0.0), 0.0001)
    }

    @Test
    fun truncateGpsSmallPositive() {
        assertEquals(0.12, AlertClient.truncateGps(0.129), 0.0001)
    }

    @Test
    fun truncateGpsNegativeFloors() {
        assertEquals(-1.0, AlertClient.truncateGps(-0.991), 0.0001)
    }

    @Test
    fun nearbySightingsStartsAtZero() {
        val client = AlertClient(
            context = RuntimeEnvironment.getApplication(),
            locationProvider = LocationProvider(RuntimeEnvironment.getApplication()),
            scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        )
        assertEquals(0, client.nearbySightings)
    }

    @Test
    fun timerStartsAndStopsWithoutCrash() {
        val client = AlertClient(
            context = RuntimeEnvironment.getApplication(),
            locationProvider = LocationProvider(RuntimeEnvironment.getApplication()),
            scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        )
        client.startTimer()
        client.stopTimer()
    }

    @Test
    fun stopTimerIsIdempotent() {
        val client = AlertClient(
            context = RuntimeEnvironment.getApplication(),
            locationProvider = LocationProvider(RuntimeEnvironment.getApplication()),
            scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        )
        client.stopTimer()
        client.stopTimer()
    }
}
