package com.iceblox.app.notification

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.iceblox.app.MainActivity
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject

class PushNotificationService : FirebaseMessagingService() {

    private val client = OkHttpClient()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onNewToken(token: String) {
        DebugLog.d(TAG, "FCM token refreshed")
        sendTokenToServer(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        DebugLog.d(TAG, "Push notification received")
        val title = message.data["title"] ?: "Potential ICE Activity Reported"
        val body = message.data["body"] ?: "Potential ICE Activity reported"
        val sightingId = message.data["sighting_id"]

        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("SHOW_MAP", true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = NotificationCompat.Builder(this, AppConfig.NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        val notificationId = sightingId?.hashCode() ?: System.currentTimeMillis().toInt()
        manager.notify(notificationId, notification)
    }

    override fun onDestroy() {
        super.onDestroy()
        scope.cancel()
    }

    private fun sendTokenToServer(token: String) {
        val deviceId = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
            ?: "unknown"
        scope.launch {
            val url = "${AppConfig.SERVER_BASE_URL}${AppConfig.DEVICES_ENDPOINT}"
            val mediaType = "application/json".toMediaType()
            val json = JSONObject().apply {
                put("token", token)
                put("platform", "android")
            }
            val request = Request.Builder()
                .url(url)
                .addHeader("Content-Type", "application/json")
                .addHeader("X-Device-ID", deviceId)
                .post(json.toString().toRequestBody(mediaType))
                .build()
            try {
                client.newCall(request).execute().use { response ->
                    if (response.isSuccessful) {
                        DebugLog.d(TAG, "Token registered via onNewToken")
                    } else {
                        DebugLog.w(TAG, "Token registration failed: ${response.code}")
                    }
                }
            } catch (e: IOException) {
                DebugLog.w(TAG, "Token registration failed: ${e.message}")
            }
        }
    }

    companion object {
        private const val TAG = "PushNotificationService"
    }
}
