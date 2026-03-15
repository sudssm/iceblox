package com.iceblox.app.camera

import android.app.Activity
import android.view.WindowManager
import com.iceblox.app.config.AppConfig
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class BrightnessManager {
    var isDimmed: Boolean = false
        private set
    var savedBrightness: Float? = null
        private set
    private var restoreJob: Job? = null

    fun dim(activity: Activity?) {
        val window = activity?.window ?: return
        if (!AppConfig.DIM_SCREEN_DURING_SCANNING) return

        if (savedBrightness == null) {
            val current = window.attributes.screenBrightness
            savedBrightness = if (current < 0) 0.5f else current
        }
        setBrightness(window, AppConfig.DIM_BRIGHTNESS_LEVEL)
        isDimmed = true
    }

    fun restore(activity: Activity?) {
        val window = activity?.window ?: return
        val saved = savedBrightness ?: return
        if (!isDimmed) return

        restoreJob?.cancel()
        restoreJob = null
        setBrightness(window, saved)
        isDimmed = false
    }

    fun temporarilyRestore(
        activity: Activity?,
        scope: CoroutineScope?,
        seconds: Long = 5L
    ) {
        val window = activity?.window ?: return
        val activeScope = scope ?: return
        val saved = savedBrightness ?: return
        if (!isDimmed) return

        restoreJob?.cancel()
        setBrightness(window, saved)
        isDimmed = false

        restoreJob = activeScope.launch {
            delay(seconds * 1000)
            if (AppConfig.DIM_SCREEN_DURING_SCANNING) {
                setBrightness(window, AppConfig.DIM_BRIGHTNESS_LEVEL)
                isDimmed = true
            }
        }
        // Mark as dimmed so the pending re-dim is expected
        isDimmed = true
    }

    fun teardown(activity: Activity?) {
        restoreJob?.cancel()
        restoreJob = null
        val window = activity?.window
        val saved = savedBrightness
        if (window != null && saved != null) {
            setBrightness(window, saved)
        }
        savedBrightness = null
        isDimmed = false
    }

    private fun setBrightness(window: android.view.Window, level: Float) {
        val params = window.attributes
        params.screenBrightness = level
        window.attributes = params
    }
}
