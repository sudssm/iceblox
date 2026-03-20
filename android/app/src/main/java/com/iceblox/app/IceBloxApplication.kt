package com.iceblox.app

import android.app.Application
import com.google.firebase.analytics.FirebaseAnalytics
import com.iceblox.app.capture.CaptureRepository

class IceBloxApplication : Application() {
    val captureRepository: CaptureRepository by lazy { CaptureRepository(this) }
    lateinit var firebaseAnalytics: FirebaseAnalytics
        private set

    override fun onCreate() {
        super.onCreate()
        firebaseAnalytics = FirebaseAnalytics.getInstance(this)
    }
}
