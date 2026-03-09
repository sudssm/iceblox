package com.iceblox.app

import android.app.Application
import com.iceblox.app.capture.CaptureRepository

class IceBloxApplication : Application() {
    val captureRepository: CaptureRepository by lazy { CaptureRepository(this) }
}
