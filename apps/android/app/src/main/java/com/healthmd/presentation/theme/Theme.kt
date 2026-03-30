package com.healthmd.presentation.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val HealthMdDarkScheme = darkColorScheme(
    primary = AppColors.accent,
    onPrimary = Color.White,
    primaryContainer = AppColors.accent.copy(alpha = 0.15f),
    onPrimaryContainer = AppColors.accentHover,
    secondary = AppColors.accentHover,
    onSecondary = Color.White,
    secondaryContainer = AppColors.accent.copy(alpha = 0.10f),
    onSecondaryContainer = AppColors.textPrimary,
    tertiary = AppColors.success,
    onTertiary = Color.White,
    tertiaryContainer = AppColors.success.copy(alpha = 0.15f),
    onTertiaryContainer = AppColors.success,
    error = AppColors.error,
    onError = Color.White,
    errorContainer = AppColors.error.copy(alpha = 0.15f),
    onErrorContainer = AppColors.error,
    background = AppColors.bgPrimary,
    onBackground = AppColors.textPrimary,
    surface = AppColors.bgSecondary,
    onSurface = AppColors.textPrimary,
    surfaceVariant = AppColors.bgTertiary,
    onSurfaceVariant = AppColors.textSecondary,
    outline = AppColors.borderDefault,
    outlineVariant = AppColors.borderSubtle,
    inverseSurface = AppColors.textPrimary,
    inverseOnSurface = AppColors.bgPrimary,
    surfaceContainerLowest = AppColors.bgPrimary,
    surfaceContainerLow = Color(0xFF1A1A1A),
    surfaceContainer = AppColors.bgSecondary,
    surfaceContainerHigh = AppColors.bgTertiary,
    surfaceContainerHighest = Color(0xFF2E2E2E),
)

@Composable
fun HealthMdTheme(
    content: @Composable () -> Unit,
) {
    // Always dark — matches iOS app which is dark-only
    MaterialTheme(
        colorScheme = HealthMdDarkScheme,
        typography = Typography,
        content = content,
    )
}
