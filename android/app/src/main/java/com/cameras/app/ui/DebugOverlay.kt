package com.cameras.app.ui

import android.graphics.RectF
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cameras.app.debug.LogEntry

data class DebugDetection(
    val plateText: String,
    val hash: String,
    val boundingBox: RectF,
    val imageWidth: Int,
    val imageHeight: Int
)

data class RawDetectionBox(val boundingBox: RectF, val confidence: Float, val imageWidth: Int, val imageHeight: Int)

data class DetectionFeedEntry(
    val plateText: String,
    val hashPrefix: String,
    val state: DetectionState,
    val timestamp: Long = System.currentTimeMillis()
)

enum class DetectionState { QUEUED, SENT, MATCHED }

@Composable
fun DebugOverlay(
    detections: List<DebugDetection>,
    rawDetections: List<RawDetectionBox>,
    feedEntries: List<DetectionFeedEntry>,
    fps: Double,
    queueDepth: Int,
    isConnected: Boolean,
    logEntries: List<LogEntry> = emptyList(),
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.fillMaxSize()) {
        // Debug header (top-left)
        Row(
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(8.dp)
                .background(Color.Black.copy(alpha = 0.7f), RoundedCornerShape(6.dp))
                .padding(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "FPS: ${fps.toInt()}",
                color = Color.White,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace
            )
            Spacer(modifier = Modifier.width(16.dp))
            Text(
                text = "Queue: $queueDepth",
                color = Color.White,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace
            )
            Spacer(modifier = Modifier.width(16.dp))
            Text(
                text = "\u25CF",
                color = if (isConnected) Color.Green else Color.Red,
                fontSize = 11.sp
            )
            Spacer(modifier = Modifier.width(4.dp))
            Text(
                text = if (isConnected) "Online" else "Offline",
                color = Color.White,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace
            )
            Spacer(modifier = Modifier.width(16.dp))
            Text(
                text = "Raw: ${rawDetections.size}",
                color = Color.Yellow,
                fontSize = 11.sp,
                fontFamily = FontFamily.Monospace
            )
        }

        // Bounding boxes
        Canvas(modifier = Modifier.fillMaxSize()) {
            // Yellow boxes for raw detections (pre-OCR)
            for (raw in rawDetections) {
                val scaleX = size.width / raw.imageWidth
                val scaleY = size.height / raw.imageHeight
                val box = raw.boundingBox

                val left = box.left * scaleX
                val top = box.top * scaleY
                val boxWidth = (box.right - box.left) * scaleX
                val boxHeight = (box.bottom - box.top) * scaleY

                drawRect(
                    color = Color.Yellow,
                    topLeft = Offset(left, top),
                    size = Size(boxWidth, boxHeight),
                    style = Stroke(width = 1.5f.dp.toPx())
                )

                drawContext.canvas.nativeCanvas.drawText(
                    "%.0f%%".format(raw.confidence * 100),
                    left,
                    top - 2.dp.toPx(),
                    android.graphics.Paint().apply {
                        color = android.graphics.Color.YELLOW
                        textSize = 9.sp.toPx()
                        isAntiAlias = true
                        setShadowLayer(2f, 1f, 1f, android.graphics.Color.BLACK)
                    }
                )
            }

            // Green boxes for OCR'd plates
            for (detection in detections) {
                val scaleX = size.width / detection.imageWidth
                val scaleY = size.height / detection.imageHeight
                val box = detection.boundingBox

                val left = box.left * scaleX
                val top = box.top * scaleY
                val boxWidth = (box.right - box.left) * scaleX
                val boxHeight = (box.bottom - box.top) * scaleY

                drawRect(
                    color = Color.Green,
                    topLeft = Offset(left, top),
                    size = Size(boxWidth, boxHeight),
                    style = Stroke(width = 2.dp.toPx())
                )

                drawContext.canvas.nativeCanvas.drawText(
                    detection.plateText,
                    left,
                    top - 4.dp.toPx(),
                    android.graphics.Paint().apply {
                        color = android.graphics.Color.WHITE
                        textSize = 12.sp.toPx()
                        isAntiAlias = true
                        setShadowLayer(2f, 1f, 1f, android.graphics.Color.BLACK)
                    }
                )

                drawContext.canvas.nativeCanvas.drawText(
                    detection.hash.take(8),
                    left,
                    top + boxHeight + 14.dp.toPx(),
                    android.graphics.Paint().apply {
                        color = android.graphics.Color.argb(180, 255, 255, 255)
                        textSize = 10.sp.toPx()
                        isAntiAlias = true
                        setShadowLayer(2f, 1f, 1f, android.graphics.Color.BLACK)
                    }
                )
            }
        }

        // Detection feed (right side)
        if (feedEntries.isNotEmpty()) {
            Column(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(top = 40.dp, end = 8.dp, bottom = 40.dp)
                    .widthIn(max = 200.dp)
                    .fillMaxHeight()
                    .background(Color.Black.copy(alpha = 0.7f), RoundedCornerShape(6.dp))
                    .padding(6.dp)
                    .verticalScroll(rememberScrollState())
            ) {
                Text(
                    text = "Detection Feed",
                    color = Color.White,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace
                )
                for (entry in feedEntries) {
                    val stateColor = when (entry.state) {
                        DetectionState.QUEUED -> Color.White
                        DetectionState.SENT -> Color.Green
                        DetectionState.MATCHED -> Color(0xFFFFD700)
                    }
                    val stateLabel = when (entry.state) {
                        DetectionState.QUEUED -> "QUED"
                        DetectionState.SENT -> "SENT"
                        DetectionState.MATCHED -> "MTCH"
                    }
                    Text(
                        text = "${entry.plateText} ${entry.hashPrefix} [$stateLabel]",
                        color = stateColor,
                        fontSize = 9.sp,
                        fontFamily = FontFamily.Monospace,
                        maxLines = 1
                    )
                }
            }
        }

        // Log panel (bottom)
        DebugLogPanel(
            entries = logEntries,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 32.dp)
        )

        Text(
            text = "[DEBUG MODE]",
            color = Color.Yellow,
            fontSize = 11.sp,
            fontFamily = FontFamily.Monospace,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(start = 8.dp, bottom = 186.dp)
        )
    }
}
