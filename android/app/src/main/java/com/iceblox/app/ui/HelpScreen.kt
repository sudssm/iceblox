package com.iceblox.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Help", color = Color.White) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(
                            Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Back",
                            tint = Color.White
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Black)
            )
        },
        containerColor = Color.Black
    ) { padding ->
        Column(
            modifier = modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState())
        ) {
            HelpSection(
                title = "Getting Started",
                body = "Mount your phone on the dashboard with the camera facing forward."
            )
            Spacer(modifier = Modifier.height(24.dp))
            HelpSection(
                title = "How It Works",
                body = "IceBlox automatically scans license plates using your camera. If a match is found, nearby users are alerted via push notification."
            )
            Spacer(modifier = Modifier.height(24.dp))
            HelpSection(
                title = "Push Notifications",
                body = "Notifications are enabled by default. You can toggle them in Settings."
            )
            Spacer(modifier = Modifier.height(24.dp))
            HelpSection(
                title = "Privacy",
                body = "All plate data is hashed on-device before being sent to the server. No raw plate numbers leave your phone."
            )
        }
    }
}

@Composable
private fun HelpSection(title: String, body: String) {
    Column {
        Text(
            text = title,
            color = Color.White,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = body,
            color = Color.White.copy(alpha = 0.8f),
            fontSize = 14.sp
        )
    }
}
