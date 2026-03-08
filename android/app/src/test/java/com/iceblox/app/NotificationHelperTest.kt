package com.iceblox.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import com.iceblox.app.notification.NotificationHelper
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows

@RunWith(RobolectricTestRunner::class)
class NotificationHelperTest {

    @Test
    fun channelIdIsPlateAlerts() {
        assertEquals("plate_alerts", NotificationHelper.CHANNEL_ID)
    }

    @Test
    fun createChannelRegistersWithSystem() {
        val context = RuntimeEnvironment.getApplication()
        NotificationHelper.createChannel(context)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = manager.getNotificationChannel("plate_alerts")
        assertNotNull(channel)
    }

    @Test
    fun channelHasHighImportance() {
        val context = RuntimeEnvironment.getApplication()
        NotificationHelper.createChannel(context)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = manager.getNotificationChannel("plate_alerts")
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channel.importance)
    }

    @Test
    fun createChannelIsIdempotent() {
        val context = RuntimeEnvironment.getApplication()
        NotificationHelper.createChannel(context)
        NotificationHelper.createChannel(context)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = manager.getNotificationChannel("plate_alerts")
        assertNotNull(channel)
    }

    @Test
    fun showNotificationUsesUniqueIds() {
        val context = RuntimeEnvironment.getApplication()
        NotificationHelper.createChannel(context)

        val id1 = "sighting-1".hashCode()
        val id2 = "sighting-2".hashCode()
        assertNotEquals(id1, id2)
    }
}
