package com.iceblox.app.settings

import android.content.Context

object UserSettings {
    private const val PREFS_NAME = "iceblox_settings"
    private const val KEY_PUSH_NOTIFICATIONS = "push_notifications_enabled"

    fun isPushNotificationsEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KEY_PUSH_NOTIFICATIONS, true)
    }

    fun setPushNotificationsEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PUSH_NOTIFICATIONS, enabled)
            .apply()
    }
}
