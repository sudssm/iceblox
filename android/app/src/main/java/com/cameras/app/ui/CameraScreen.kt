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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cameras.app.camera.CameraPreview

@Composable
fun CameraScreen(modifier: Modifier = Modifier) {
    var frameCount by remember { mutableLongStateOf(0L) }
    var hasReceivedFrame by remember { mutableStateOf(false) }

    Box(modifier = modifier.fillMaxSize()) {
        CameraPreview(
            modifier = Modifier.fillMaxSize(),
            onFrameCaptured = {
                frameCount++
                hasReceivedFrame = true
            }
        )

        StatusBar(
            isCapturing = hasReceivedFrame,
            framesProcessed = frameCount,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
        )
    }
}

@Composable
fun StatusBar(
    isCapturing: Boolean,
    framesProcessed: Long,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.6f))
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag("status_bar"),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val indicatorColor = if (isCapturing) Color.Green else Color.Red
        Text(
            text = "\u25CF",
            color = indicatorColor,
            fontSize = 12.sp,
            modifier = Modifier.testTag("status_indicator")
        )
        Spacer(modifier = Modifier.width(6.dp))
        Text(
            text = if (isCapturing) "Capturing" else "Starting...",
            color = Color.White,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.testTag("status_text")
        )
        Spacer(modifier = Modifier.width(16.dp))
        Text(
            text = "Frames: $framesProcessed",
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 12.sp,
            modifier = Modifier.testTag("frame_count")
        )
    }
}
