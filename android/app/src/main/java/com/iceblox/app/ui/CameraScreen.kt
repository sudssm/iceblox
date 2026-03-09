package com.iceblox.app.ui

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
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
import com.iceblox.app.BuildConfig
import com.iceblox.app.MainViewModel
import com.iceblox.app.SessionSummary
import com.iceblox.app.camera.CameraPreview
import com.iceblox.app.debug.DebugLog

@Composable
fun CameraScreen(
    modifier: Modifier = Modifier,
    isTestMode: Boolean = false,
    onSessionFinished: () -> Unit = {},
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
    val sessionSummary by viewModel.sessionSummary.collectAsState()

    val testBitmap by viewModel.testBitmap.collectAsState()
    val testStatus by viewModel.testStatus.collectAsState()

    var debugMode by remember { mutableStateOf(false) }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> viewModel.startForegroundPipeline(isTestMode)

                Lifecycle.Event.ON_STOP -> {
                    if (!isTestMode) {
                        viewModel.stopForegroundPipeline()
                    }
                }

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
        if (sessionSummary != null) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black)
            )
        } else if (isTestMode) {
            TestImagePreview(
                bitmap = testBitmap,
                status = testStatus,
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
                text = "TEST MODE $testStatus",
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

        if (BuildConfig.DEBUG && debugMode && sessionSummary == null) {
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

        if (sessionSummary == null) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
            ) {
                Button(
                    onClick = { viewModel.stopRecordingSession() },
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFC62828)),
                    modifier = Modifier
                        .padding(bottom = 12.dp)
                        .testTag("stop_recording_button")
                ) {
                    Text("Stop Recording")
                }

                if (queueDepth > 0) {
                    UploadQueueBanner(
                        count = queueDepth,
                        onClear = { viewModel.clearUploadQueue() }
                    )
                }

                StatusBar(
                    isConnected = isConnected,
                    platesDetected = plateCount,
                    targetCount = targetCount,
                    lastDetectionTime = lastDetectionTime,
                    hasGps = hasGps,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }

        sessionSummary?.let { summary ->
            SessionSummaryOverlay(
                summary = summary,
                onDone = {
                    viewModel.dismissSessionSummary()
                    onSessionFinished()
                },
                modifier = Modifier.align(Alignment.Center)
            )
        }
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
fun SessionSummaryOverlay(summary: SessionSummary, onDone: () -> Unit, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.padding(24.dp),
        color = Color.Black.copy(alpha = 0.92f),
        shape = RoundedCornerShape(20.dp),
        border = BorderStroke(1.dp, Color.White.copy(alpha = 0.15f))
    ) {
        Column(
            modifier = Modifier
                .padding(24.dp)
                .fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(
                text = "Session Summary",
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    "Plates seen: ${summary.platesSeen}",
                    color = Color.White,
                    fontFamily = FontFamily.Monospace
                )
                Text(
                    "ICE vehicles: ${summary.iceVehicles}",
                    color = Color.White,
                    fontFamily = FontFamily.Monospace
                )
                Text(
                    "Duration: ${formatSessionDuration(summary.durationMs)}",
                    color = Color.White,
                    fontFamily = FontFamily.Monospace
                )
                if (summary.pendingUploads > 0) {
                    Text(
                        "Pending sync: ${summary.pendingUploads} uploads",
                        color = Color(0xFFFFB300),
                        fontFamily = FontFamily.Monospace
                    )
                    Text(
                        "ICE vehicles reflects confirmed matches received so far.",
                        color = Color.White.copy(alpha = 0.7f),
                        fontSize = 12.sp
                    )
                }
            }
            Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) {
                Text("Done")
            }
        }
    }
}

fun formatSessionDuration(durationMs: Long): String {
    val totalSeconds = (durationMs.coerceAtLeast(0L) / 1000L).toInt()
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return "${minutes}m ${seconds.toString().padStart(2, '0')}s"
}

@Composable
fun UploadQueueBanner(count: Int, onClear: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.75f), RoundedCornerShape(50))
            .padding(start = 12.dp, top = 4.dp, bottom = 4.dp, end = 4.dp)
    ) {
        Text(
            text = "$count uploads queued",
            color = Color(0xFFFFB300),
            fontSize = 12.sp,
            fontFamily = FontFamily.Monospace
        )
        Spacer(modifier = Modifier.width(4.dp))
        IconButton(
            onClick = onClear,
            modifier = Modifier.size(24.dp)
        ) {
            Text(
                text = "\u2715",
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )
        }
    }
    Spacer(modifier = Modifier.height(4.dp))
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
