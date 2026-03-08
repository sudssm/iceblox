package com.cameras.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.cameras.app.MainViewModel
import com.cameras.app.camera.CameraPreview

@Composable
fun CameraScreen(
    modifier: Modifier = Modifier,
    viewModel: MainViewModel = viewModel()
) {
    val plateCount by viewModel.plateCount.collectAsState()
    val targetCount by viewModel.targetCount.collectAsState()
    val lastDetectionTime by viewModel.lastDetectionTime.collectAsState()
    val isConnected by viewModel.connectivityMonitor.isConnected.collectAsState()
    val hasGps by viewModel.locationProvider.hasPermission.collectAsState()

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> viewModel.startPipeline()
                Lifecycle.Event.ON_STOP -> viewModel.stopPipeline()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    Box(modifier = modifier.fillMaxSize()) {
        CameraPreview(
            modifier = Modifier.fillMaxSize(),
            analyzer = viewModel.frameAnalyzer
        )

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
