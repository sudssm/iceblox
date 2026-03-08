package com.iceblox.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.iceblox.app.debug.LogEntry
import com.iceblox.app.debug.LogLevel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun DebugLogPanel(entries: List<LogEntry>, modifier: Modifier = Modifier) {
    val scrollState = rememberScrollState()

    LaunchedEffect(entries.size) {
        scrollState.animateScrollTo(scrollState.maxValue)
    }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(max = 150.dp)
            .background(Color.Black.copy(alpha = 0.75f), RoundedCornerShape(topStart = 6.dp, topEnd = 6.dp))
            .padding(6.dp)
            .verticalScroll(scrollState)
    ) {
        val timeFormat = SimpleDateFormat("HH:mm:ss", Locale.US)
        for (entry in entries) {
            val color = when (entry.level) {
                LogLevel.DEBUG -> Color.LightGray
                LogLevel.WARNING -> Color.Yellow
                LogLevel.ERROR -> Color.Red
            }
            val prefix = when (entry.level) {
                LogLevel.DEBUG -> "D"
                LogLevel.WARNING -> "W"
                LogLevel.ERROR -> "E"
            }
            Text(
                text = "${timeFormat.format(Date(entry.timestamp))} $prefix/${entry.tag}: ${entry.message}",
                color = color,
                fontSize = 8.sp,
                fontFamily = FontFamily.Monospace,
                maxLines = 2
            )
        }
    }
}
