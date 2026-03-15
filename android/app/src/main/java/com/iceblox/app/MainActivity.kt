package com.iceblox.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.firebase.messaging.FirebaseMessaging
import com.iceblox.app.config.AppConfig
import com.iceblox.app.debug.DebugLog
import com.iceblox.app.service.BackgroundCaptureService
import com.iceblox.app.settings.UserSettings
import com.iceblox.app.ui.CameraScreen
import com.iceblox.app.ui.MapViewScreen
import com.iceblox.app.ui.ReportICEScreen
import com.iceblox.app.ui.SettingsScreen
import com.iceblox.app.ui.SplashScreen
import com.iceblox.app.ui.theme.IceBloxTheme

class MainActivity : ComponentActivity() {
    private var hasCameraPermission by mutableStateOf(false)
    private var hasLocationPermission by mutableStateOf(false)
    private var showCamera by mutableStateOf(false)
    private var showReport by mutableStateOf(false)
    private var showMap by mutableStateOf(false)
    private var showSettings by mutableStateOf(false)
    private var isTestMode = false
    private var isScreenshotMode = false

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
        if (granted) {
            showCamera = true
            requestLocationPermission()
        }
    }

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        DebugLog.d(TAG, "POST_NOTIFICATIONS permission: $granted")
    }

    private val locationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        hasLocationPermission = permissions.values.any { it }
        if (hasLocationPermission) {
            val vm = androidx.lifecycle.ViewModelProvider(this)[MainViewModel::class.java]
            vm.locationProvider.startUpdates()
        }
        requestNotificationPermission()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        if (intent.getBooleanExtra("SHOW_MAP", false)) {
            showMap = true
        }
        if (intent.getBooleanExtra("SHOW_REPORT", false)) {
            showReport = true
        }

        isTestMode = intent.getBooleanExtra(AppConfig.INTENT_EXTRA_TEST_MODE, false)
        isScreenshotMode = intent.getBooleanExtra("SCREENSHOT_MODE", false)
        if (isTestMode) {
            DebugLog.d("MainActivity", "TEST MODE enabled via intent extra")
        }

        hasCameraPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED

        hasLocationPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        createNotificationChannel()
        if (UserSettings.isPushNotificationsEnabled(this)) {
            requestNotificationPermission()
            registerFcmToken()
        }

        setContent {
            IceBloxTheme {
                if (showCamera) {
                    if (hasCameraPermission || isTestMode) {
                        CameraScreen(
                            isTestMode = isTestMode,
                            isScreenshotMode = isScreenshotMode,
                            onSessionFinished = { showCamera = false }
                        )
                    } else {
                        PermissionDeniedScreen(
                            onRequestPermission = {
                                cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                            }
                        )
                    }
                } else if (showMap) {
                    LaunchedEffect(hasLocationPermission) {
                        if (!hasLocationPermission) {
                            requestLocationPermission()
                        }
                    }
                    val mapViewModel: MainViewModel = viewModel()
                    LaunchedEffect(hasLocationPermission) {
                        if (hasLocationPermission) {
                            mapViewModel.locationProvider.startUpdates()
                        }
                    }
                    val mapLocation by mapViewModel.locationProvider.currentLocation.collectAsState()
                    MapViewScreen(
                        locationLat = mapLocation?.latitude,
                        locationLng = mapLocation?.longitude,
                        onBack = { showMap = false },
                        isScreenshotMode = isScreenshotMode
                    )
                } else if (showReport) {
                    LaunchedEffect(hasLocationPermission) {
                        if (!hasLocationPermission) {
                            requestLocationPermission()
                        }
                    }
                    val reportViewModel: MainViewModel = viewModel()
                    LaunchedEffect(hasLocationPermission) {
                        if (hasLocationPermission) {
                            reportViewModel.locationProvider.startUpdates()
                        }
                    }
                    val location by reportViewModel.locationProvider.currentLocation.collectAsState()
                    ReportICEScreen(
                        latitude = location?.latitude ?: 0.0,
                        longitude = location?.longitude ?: 0.0,
                        hasLocation = location != null,
                        onBack = { showReport = false }
                    )
                } else if (showSettings) {
                    SettingsScreen(onBack = { showSettings = false })
                } else {
                    SplashScreen(
                        onStartCamera = {
                            if (hasCameraPermission) {
                                showCamera = true
                                if (!hasLocationPermission) {
                                    requestLocationPermission()
                                }
                            } else {
                                cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                            }
                        },
                        onReportICE = { showReport = true },
                        onViewMap = { showMap = true },
                        onSettings = { showSettings = true }
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("SHOW_MAP", false)) {
            showMap = true
        }
    }

    override fun onResume() {
        super.onResume()
        BackgroundCaptureService.stop(this)
    }

    override fun onPause() {
        super.onPause()
        val vm = androidx.lifecycle.ViewModelProvider(this)[MainViewModel::class.java]
        val isMotionPaused = vm.isMotionPaused.value
        if (
            !isChangingConfigurations &&
            showCamera &&
            hasCameraPermission &&
            !isMotionPaused
        ) {
            BackgroundCaptureService.start(this)
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            AppConfig.NOTIFICATION_CHANNEL_ID,
            AppConfig.NOTIFICATION_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH
        )
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    private fun registerFcmToken() {
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            DebugLog.d(TAG, "FCM token obtained")
            val viewModel = androidx.lifecycle.ViewModelProvider(this)[MainViewModel::class.java]
            viewModel.apiClient.registerDeviceToken(token)
        }.addOnFailureListener { e ->
            DebugLog.w(TAG, "FCM token fetch failed: ${e.message}")
        }
    }

    private fun requestLocationPermission() {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            permissions.add(Manifest.permission.ACTIVITY_RECOGNITION)
        }
        locationPermissionLauncher.launch(permissions.toTypedArray())
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}

@Composable
fun PermissionDeniedScreen(onRequestPermission: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxSize()
            .testTag("permission_denied_screen"),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Camera permission is required",
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.testTag("permission_message")
        )
        Spacer(modifier = Modifier.height(16.dp))
        Button(
            onClick = onRequestPermission,
            modifier = Modifier.testTag("grant_permission_button")
        ) {
            Text("Grant Permission")
        }
    }
}
