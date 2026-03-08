package com.cameras.app.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cameras.app.BuildConfig
import com.cameras.app.MainViewModel
import com.cameras.app.camera.CameraPreview
import com.cameras.app.debug.DebugLog

@Composable
fun CameraScreen(
    modifier: Modifier = Modifier,
    isTestMode: Boolean = false,
    viewModel: MainViewModel = viewModel()
) {
    val plateCount by viewModel.plateCount.collectAsState()
    val targetCount by viewModel.targetCount.collectAsState()
    val lastDetectionTime by viewModel.lastDetectionTime.collectAsState()
    val isConnected by viewModel.connectivityMonitor.isConnected.collectAsState()
    val hasGps by viewModel.locationProvider.hasPermission.collectAsState()
    val queueDepth by viewModel.queueDepth.collectAsState()
    val fps by viewModel.frameAnalyzer.fps.collectAsState()
    val debugDetections by viewModel.frameAnalyzer.debugDetections.collectAsState()
    val rawDetections by viewModel.frameAnalyzer.rawDetections.collectAsState()
    val detectionFeed by viewModel.detectionFeed.collectAsState()
    val logEntries by DebugLog.entries.collectAsState()

    val testBitmap = viewModel.testFrameFeeder?.currentBitmap?.collectAsState()
    val testStatus = viewModel.testFrameFeeder?.status?.collectAsState()

    var debugMode by remember { mutableStateOf(false) }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> viewModel.startPipeline(isTestMode)
                Lifecycle.Event.ON_STOP -> viewModel.stopPipeline()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    // Triple-tap detection for debug mode toggle (debug builds only)
    val tripleTapModifier = if (BuildConfig.DEBUG) {
        Modifier.pointerInput(Unit) {
            var tapCount = 0
            var lastTapTime = 0L
            detectTapGestures {
                val now = System.currentTimeMillis()
                if (now - lastTapTime < 500) {
                    tapCount++
                } else {
                    tapCount = 1
                }
                lastTapTime = now
                if (tapCount >= 3) {
                    debugMode = !debugMode
                    tapCount = 0
                }
            }
        }
    } else {
        Modifier
    }

    Box(modifier = modifier.fillMaxSize().then(tripleTapModifier)) {
        if (isTestMode) {
            TestImagePreview(
                bitmap = testBitmap?.value,
                status = testStatus?.value ?: "",
                modifier = Modifier.fillMaxSize()
            )
        } else {
            CameraPreview(
                modifier = Modifier.fillMaxSize(),
                analyzer = viewModel.frameAnalyzer
            )
        }

        if (isTestMode) {
            Text(
                text = "TEST MODE ${testStatus?.value ?: ""}",
                color = Color.Yellow,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 48.dp)
                    .background(Color.Black.copy(alpha = 0.8f), RoundedCornerShape(6.dp))
                    .padding(horizontal = 12.dp, vertical = 4.dp)
            )
        }

        if (BuildConfig.DEBUG && debugMode) {
            DebugOverlay(
                detections = debugDetections,
                rawDetections = rawDetections,
                feedEntries = detectionFeed,
                fps = fps,
                queueDepth = queueDepth,
                isConnected = isConnected,
                logEntries = logEntries
            )
        }

        StatusBar(
            isConnected = isConnected,
            platesDetected = plateCount,
            targetCount = targetCount,
            lastDetectionTime = lastDetectionTime,
            hasGps = hasGps,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
        )
    }
}

@Composable
fun TestImagePreview(bitmap: Bitmap?, status: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.background(Color.Black),
        contentAlignment = Alignment.Center
    ) {
        if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = "Test image: $status",
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit
            )
        } else {
            Text(
                text = "Loading test images...",
                color = Color.White,
                fontSize = 16.sp
            )
        }
    }
}

@Composable
fun StatusBar(
    isConnected: Boolean,
    platesDetected: Long,
    targetCount: Int,
    lastDetectionTime: Long,
    hasGps: Boolean,
    modifier: Modifier = Modifier
) {
    val lastDetectedText = if (lastDetectionTime > 0) {
        val elapsed = (System.currentTimeMillis() - lastDetectionTime) / 1000
        if (elapsed < 60) "Last: ${elapsed}s ago" else "Last: ${elapsed / 60}m ago"
    } else {
        "Last: --"
    }

    Row(
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.6f))
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag("status_bar"),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val indicatorColor = if (isConnected) Color.Green else Color.Red
        Text(
            text = "\u25CF",
            color = indicatorColor,
            fontSize = 12.sp,
            modifier = Modifier.testTag("status_indicator")
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = if (isConnected) "Online" else "Offline",
            color = Color.White,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.testTag("status_text")
        )
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = lastDetectedText,
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 12.sp
        )
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = "Plates: $platesDetected",
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 12.sp,
            modifier = Modifier.testTag("plate_count")
        )
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = "Targets: $targetCount",
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 12.sp,
            modifier = Modifier.testTag("target_count")
        )
        if (!hasGps) {
            Spacer(modifier = Modifier.width(16.dp))
            Text(
                text = "No GPS",
                color = Color(0xFFFF9800),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.testTag("gps_warning")
            )
        }
    }
}
