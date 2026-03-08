package com.cameras.app

import com.cameras.app.network.DeviceTokenManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment

@RunWith(RobolectricTestRunner::class)
class DeviceTokenManagerTest {
    private lateinit var server: MockWebServer
    private lateinit var manager: DeviceTokenManager

    @Before
    fun setUp() {
        server = MockWebServer()
        server.start()
        manager = DeviceTokenManager(
            context = RuntimeEnvironment.getApplication(),
            scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        )
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    @Test
    fun requestIncludesDeviceIdHeader() {
        val request = manager.buildRegistrationRequest("test-token", "android")

        assertNotNull(request.header("X-Device-ID"))
        assertTrue(request.header("X-Device-ID")!!.isNotEmpty())
    }

    @Test
    fun requestIncludesContentTypeHeader() {
        val request = manager.buildRegistrationRequest("test-token", "android")

        assertEquals("application/json", request.header("Content-Type"))
    }

    @Test
    fun requestTargetsDevicesEndpoint() {
        val request = manager.buildRegistrationRequest("test-token", "android")

        assertTrue(request.url.encodedPath.endsWith("/api/v1/devices"))
    }

    @Test
    fun requestUsesPostMethod() {
        val request = manager.buildRegistrationRequest("test-token", "android")

        assertEquals("POST", request.method)
    }

    @Test
    fun requestBodyContainsTokenAndPlatform() {
        val request = manager.buildRegistrationRequest("fcm-token-123", "android")
        val buffer = okio.Buffer()
        request.body!!.writeTo(buffer)
        val body = buffer.readUtf8()

        assertTrue(body.contains("fcm-token-123"))
        assertTrue(body.contains("android"))
    }
}
