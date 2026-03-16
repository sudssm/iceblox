package com.iceblox.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.iceblox.app.R

@Composable
fun SplashScreen(
    onStartCamera: () -> Unit,
    onReportICE: () -> Unit = {},
    onViewMap: () -> Unit = {},
    onSettings: () -> Unit = {},
    onHelp: () -> Unit = {},
    onContact: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "IceBlox",
                color = Color.White,
                fontSize = 48.sp,
                fontWeight = FontWeight.Bold
            )

            val buttonWidth = 260.dp

            Button(
                onClick = onStartCamera,
                modifier = Modifier.padding(top = 32.dp).width(buttonWidth),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF4CAF50),
                    contentColor = Color.White
                )
            ) {
                IconButtonContent(
                    icon = Icons.Filled.Videocam,
                    text = "Start Camera"
                )
            }

            Button(
                onClick = onViewMap,
                modifier = Modifier.padding(top = 16.dp).width(buttonWidth),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color.Black
                )
            ) {
                IconButtonContent(
                    icon = Icons.Filled.Map,
                    text = "View Map"
                )
            }

            Button(
                onClick = onReportICE,
                modifier = Modifier.padding(top = 16.dp).width(buttonWidth),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.Red,
                    contentColor = Color.White
                )
            ) {
                IconButtonContent(
                    icon = Icons.Filled.Campaign,
                    text = "Report ICE Activity"
                )
            }
        }

        Row(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 48.dp, end = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            IconButton(
                onClick = onHelp,
                modifier = Modifier.semantics { contentDescription = "Help" }
            ) {
                Icon(
                    painter = painterResource(id = R.drawable.ic_help),
                    contentDescription = "Help",
                    tint = Color.Yellow,
                    modifier = Modifier.size(28.dp)
                )
            }
            IconButton(
                onClick = onSettings,
                modifier = Modifier.semantics { contentDescription = "Settings" }
            ) {
                Icon(
                    Icons.Default.Settings,
                    contentDescription = "Settings",
                    tint = Color.White,
                    modifier = Modifier.size(28.dp)
                )
            }
            IconButton(
                onClick = onContact,
                modifier = Modifier.semantics { contentDescription = "Contact" }
            ) {
                Icon(
                    painter = painterResource(id = R.drawable.ic_chat),
                    contentDescription = "Contact",
                    tint = Color.Green,
                    modifier = Modifier.size(28.dp)
                )
            }
        }
    }
}

@Composable
private fun IconButtonContent(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(24.dp)
        )
        Text(
            text = text,
            fontSize = 20.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f).padding(vertical = 4.dp)
        )
    }
}
