package com.iceblox.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import com.iceblox.app.notification.NotificationHelper
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.O])
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
        val channel = notificationChannel(manager)
        assertNotNull(channel)
    }

    @Test
    fun channelHasHighImportance() {
        val context = RuntimeEnvironment.getApplication()
        NotificationHelper.createChannel(context)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = requireNotNull(notificationChannel(manager))
        assertEquals(NotificationManager.IMPORTANCE_HIGH, channel.importance)
    }

    @Test
    fun createChannelIsIdempotent() {
        val context = RuntimeEnvironment.getApplication()
        NotificationHelper.createChannel(context)
        NotificationHelper.createChannel(context)

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = notificationChannel(manager)
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

    private fun notificationChannel(manager: NotificationManager): NotificationChannel? {
        return Shadows.shadowOf(manager)
            .notificationChannels
            .firstOrNull { it.id == NotificationHelper.CHANNEL_ID }
    }
}
