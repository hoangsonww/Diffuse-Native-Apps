package com.diffuse.android.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF344B87),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDCE3FF),
    onPrimaryContainer = Color(0xFF17254D),
    secondary = Color(0xFF586078),
    background = Color(0xFFF8F7F2),
    surface = Color(0xFFFEFDF8),
    surfaceVariant = Color(0xFFEAE8E0),
    error = Color(0xFFB3261E),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFFB5C4FF),
    primaryContainer = Color(0xFF263D75),
    secondary = Color(0xFFC2C7DD),
    background = Color(0xFF121318),
    surface = Color(0xFF1A1B20),
    surfaceVariant = Color(0xFF34353B),
)

@Composable
fun DiffuseTheme(dark: Boolean = androidx.compose.foundation.isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (dark) DarkColors else LightColors, content = content)
}
