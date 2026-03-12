package com.iceblox.app.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.iceblox.app.settings.UserSettings

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onBack: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    var pushEnabled by remember { mutableStateOf(UserSettings.isPushNotificationsEnabled(context)) }

    var userDebugEnabled by remember { mutableStateOf(UserSettings.isUserDebugEnabled(context)) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings", color = Color.White) },
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
                .padding(horizontal = 16.dp, vertical = 12.dp)
                .fillMaxWidth()
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Push Notifications",
                    color = Color.White,
                    fontSize = 16.sp,
                    modifier = Modifier.weight(1f).padding(top = 8.dp)
                )
                Switch(
                    checked = pushEnabled,
                    onCheckedChange = { enabled ->
                        pushEnabled = enabled
                        UserSettings.setPushNotificationsEnabled(context, enabled)
                    }
                )
            }
            Spacer(modifier = Modifier.height(16.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = "Debug Mode",
                        color = Color.White,
                        fontSize = 16.sp,
                        modifier = Modifier.padding(top = 8.dp)
                    )
                    Text(
                        text = "Shows detection bounding boxes on the camera preview",
                        color = Color.White.copy(alpha = 0.5f),
                        fontSize = 12.sp,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
                Switch(
                    checked = userDebugEnabled,
                    onCheckedChange = { enabled ->
                        userDebugEnabled = enabled
                        UserSettings.setUserDebugEnabled(context, enabled)
                    }
                )
            }
        }
    }
}
