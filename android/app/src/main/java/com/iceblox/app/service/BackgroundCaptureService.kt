package com.iceblox.app.service

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleService
import com.iceblox.app.IceBloxApplication
import com.iceblox.app.R
import com.iceblox.app.camera.CameraCaptureBinder
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class BackgroundCaptureService : LifecycleService() {
    private val repository by lazy {
        (application as IceBloxApplication).captureRepository
    }

    private var analysisExecutor: ExecutorService? = null
    private var captureBound = false

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        when (intent?.action ?: AppConfig.ACTION_START_BACKGROUND_CAPTURE) {
            AppConfig.ACTION_STOP_BACKGROUND_CAPTURE -> stopCapture()
            AppConfig.ACTION_START_BACKGROUND_CAPTURE -> startCapture()
        }
        return START_NOT_STICKY
    }

    private fun startCapture() {
        if (!hasCameraPermission()) {
            DebugLog.w(TAG, "Cannot start background capture without camera permission")
            stopSelf()
            return
        }

        ensureNotificationChannel()
        try {
            startForeground(
                AppConfig.BACKGROUND_CAPTURE_NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            )
        } catch (e: SecurityException) {
            DebugLog.w(TAG, "Cannot start foreground service: ${e.message}")
            stopSelf()
            return
        }
        repository.setBackgroundActive(true)

        if (!captureBound) {
            val executor = analysisExecutor ?: Executors.newSingleThreadExecutor().also {
                analysisExecutor = it
            }
            CameraCaptureBinder.bindAnalysisOnly(
                context = this,
                lifecycleOwner = this,
                analyzer = repository.frameAnalyzer,
                analysisExecutor = executor
            )
            captureBound = true
        }
    }

    private fun stopCapture() {
        if (captureBound) {
            CameraCaptureBinder.unbindAll(this)
            captureBound = false
        }
        repository.setBackgroundActive(false)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (captureBound) {
            CameraCaptureBinder.unbindAll(this)
            captureBound = false
        }
        repository.setBackgroundActive(false)
        analysisExecutor?.shutdown()
        analysisExecutor = null
        super.onDestroy()
    }

    private fun buildNotification() = NotificationCompat.Builder(
        this,
        AppConfig.BACKGROUND_CAPTURE_CHANNEL_ID
    )
        .setSmallIcon(R.mipmap.ic_launcher)
        .setContentTitle("IceBlox capture active")
        .setContentText("Background plate capture is running")
        .setOngoing(true)
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setContentIntent(createLaunchPendingIntent())
        .addAction(
            0,
            "Stop",
            PendingIntent.getService(
                this,
                1,
                Intent(this, BackgroundCaptureService::class.java).setAction(
                    AppConfig.ACTION_STOP_BACKGROUND_CAPTURE
                ),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        )
        .build()

    private fun createLaunchPendingIntent(): PendingIntent? {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        launchIntent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        return PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun ensureNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            AppConfig.BACKGROUND_CAPTURE_CHANNEL_ID,
            AppConfig.BACKGROUND_CAPTURE_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        )
        manager.createNotificationChannel(channel)
    }

    private fun hasCameraPermission(): Boolean = ContextCompat.checkSelfPermission(
        this,
        Manifest.permission.CAMERA
    ) == PackageManager.PERMISSION_GRANTED

    companion object {
        private const val TAG = "BackgroundCaptureService"

        fun start(context: Context) {
            val intent = Intent(context, BackgroundCaptureService::class.java)
                .setAction(AppConfig.ACTION_START_BACKGROUND_CAPTURE)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, BackgroundCaptureService::class.java))
        }
    }
}
