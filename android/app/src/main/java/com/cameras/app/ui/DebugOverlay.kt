package com.cameras.app.ui

import android.graphics.RectF
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

data class DebugDetection(
    val plateText: String,
    val hash: String,
    val boundingBox: RectF,
    val imageWidth: Int,
    val imageHeight: Int
)

@Composable
fun DebugOverlay(
    detections: List<DebugDetection>,
    fps: Double,
    queueDepth: Int,
    isConnected: Boolean,
    modifier: Modifier = Modifier
) {
    Box(modifier = modifier.fillMaxSize()) {
        // Debug header (top-left) — matches iOS DebugOverlayView
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
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
            )
            Spacer(modifier = Modifier.width(16.dp))
            Text(
                text = "Queue: $queueDepth",
                color = Color.White,
                fontSize = 11.sp,
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
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
                fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace
            )
        }

        // Bounding boxes with plate text and hash
        Canvas(modifier = Modifier.fillMaxSize()) {
            for (detection in detections) {
                val scaleX = size.width / detection.imageWidth
                val scaleY = size.height / detection.imageHeight
                val box = detection.boundingBox

                val left = box.left * scaleX
                val top = box.top * scaleY
                val right = box.right * scaleX
                val bottom = box.bottom * scaleY
                val boxWidth = right - left
                val boxHeight = bottom - top

                // Bounding box
                drawRect(
                    color = Color.Green,
                    topLeft = Offset(left, top),
                    size = Size(boxWidth, boxHeight),
                    style = Stroke(width = 2.dp.toPx())
                )

                // Plate text above box
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

                // Hash (truncated to 8 chars) below box
                drawContext.canvas.nativeCanvas.drawText(
                    detection.hash.take(8),
                    left,
                    bottom + 14.dp.toPx(),
                    android.graphics.Paint().apply {
                        color = android.graphics.Color.argb(180, 255, 255, 255)
                        textSize = 10.sp.toPx()
                        isAntiAlias = true
                        setShadowLayer(2f, 1f, 1f, android.graphics.Color.BLACK)
                    }
                )
            }
        }

        // [DEBUG MODE] label (bottom-left) — matches iOS
        Text(
            text = "[DEBUG MODE]",
            color = Color.Yellow,
            fontSize = 11.sp,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(8.dp)
        )
    }
}
