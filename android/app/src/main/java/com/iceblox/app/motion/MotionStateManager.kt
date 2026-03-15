package com.iceblox.app.motion

import android.Manifest
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import com.google.android.gms.location.ActivityRecognition
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionRequest
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

enum class MotionState {
    UNKNOWN,
    MOVING,
    STATIONARY
}

class MotionStateManager(private val context: Context, private val scope: CoroutineScope) {
    private val _motionState = MutableStateFlow(MotionState.UNKNOWN)
    val motionState: StateFlow<MotionState> = _motionState

    private val _isMotionPaused = MutableStateFlow(false)
    val isMotionPaused: StateFlow<Boolean> = _isMotionPaused

    @Volatile
    private var stationaryStartTime: Long? = null

    private var pollingJob: Job? = null
    private var isMonitoring = false

    private val transitionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (ActivityTransitionResult.hasResult(intent)) {
                val result = ActivityTransitionResult.extractResult(intent) ?: return
                for (event in result.transitionEvents) {
                    handleTransition(event.activityType, event.transitionType)
                }
            }
        }
    }

    private val pendingIntent: PendingIntent by lazy {
        val intent = Intent(ACTION_ACTIVITY_TRANSITION)
        PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
    }

    fun hasPermission(): Boolean = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACTIVITY_RECOGNITION
        ) == PackageManager.PERMISSION_GRANTED
    } else {
        true
    }

    fun startMonitoring() {
        if (isMonitoring) return
        if (!hasPermission()) {
            DebugLog.w(TAG, "ACTIVITY_RECOGNITION permission not granted")
            return
        }

        isMonitoring = true

        val filter = IntentFilter(ACTION_ACTIVITY_TRANSITION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(
                transitionReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            context.registerReceiver(transitionReceiver, filter)
        }

        val transitions = listOf(
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.STILL)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.STILL)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_EXIT)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.IN_VEHICLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.WALKING)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build(),
            ActivityTransition.Builder()
                .setActivityType(DetectedActivity.ON_BICYCLE)
                .setActivityTransition(ActivityTransition.ACTIVITY_TRANSITION_ENTER)
                .build()
        )

        val request = ActivityTransitionRequest(transitions)

        try {
            ActivityRecognition.getClient(context)
                .requestActivityTransitionUpdates(request, pendingIntent)
                .addOnSuccessListener {
                    DebugLog.d(TAG, "Activity transition updates registered")
                }
                .addOnFailureListener { e ->
                    DebugLog.w(TAG, "Failed to register activity transitions: ${e.message}")
                }
        } catch (e: SecurityException) {
            DebugLog.w(TAG, "SecurityException requesting transitions: ${e.message}")
        }

        pollingJob = scope.launch {
            while (isActive) {
                delay(30_000)
                checkStationaryTimeout()
            }
        }
    }

    fun stopMonitoring() {
        if (!isMonitoring) return
        isMonitoring = false

        pollingJob?.cancel()
        pollingJob = null

        try {
            context.unregisterReceiver(transitionReceiver)
        } catch (_: IllegalArgumentException) {
            // Receiver was not registered
        }

        try {
            ActivityRecognition.getClient(context)
                .removeActivityTransitionUpdates(pendingIntent)
        } catch (_: SecurityException) {
            // Permission revoked
        }

        stationaryStartTime = null
        _motionState.value = MotionState.UNKNOWN
        _isMotionPaused.value = false
    }

    fun manualResume() {
        _isMotionPaused.value = false
        stationaryStartTime = null
    }

    private fun handleTransition(activityType: Int, transitionType: Int) {
        when {
            activityType == DetectedActivity.STILL &&
                transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER -> {
                _motionState.value = MotionState.STATIONARY
                if (stationaryStartTime == null) {
                    stationaryStartTime = System.currentTimeMillis()
                }
            }

            activityType == DetectedActivity.STILL &&
                transitionType == ActivityTransition.ACTIVITY_TRANSITION_EXIT -> {
                _motionState.value = MotionState.MOVING
                stationaryStartTime = null
                if (_isMotionPaused.value) {
                    _isMotionPaused.value = false
                }
            }

            activityType in listOf(
                DetectedActivity.IN_VEHICLE,
                DetectedActivity.WALKING,
                DetectedActivity.ON_BICYCLE
            ) && transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER -> {
                _motionState.value = MotionState.MOVING
                stationaryStartTime = null
                if (_isMotionPaused.value) {
                    _isMotionPaused.value = false
                }
            }
        }
    }

    private fun checkStationaryTimeout() {
        val startTime = stationaryStartTime ?: return
        val elapsed = System.currentTimeMillis() - startTime
        val timeoutMs = AppConfig.STATIONARY_TIMEOUT_MINUTES * 60 * 1000
        if (elapsed >= timeoutMs && !_isMotionPaused.value) {
            _isMotionPaused.value = true
        }
    }

    companion object {
        private const val TAG = "MotionStateManager"
        private const val ACTION_ACTIVITY_TRANSITION =
            "com.iceblox.app.ACTION_ACTIVITY_TRANSITION"
    }
}
