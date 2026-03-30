package com.healthmd.presentation.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

// Color Palette - matches iOS DesignSystem.swift
object AppColors {
    // Backgrounds
    val bgPrimary = Color(0xFF141414)
    val bgSecondary = Color(0xFF1E1E1E)
    val bgTertiary = Color(0xFF262626)

    // Borders
    val borderSubtle = Color(0xFF2E2E2E)
    val borderDefault = Color(0xFF3E3E3E)
    val borderStrong = Color(0xFF4E4E4E)

    // Text
    val textPrimary = Color(0xFFE8E8E8)
    val textSecondary = Color(0xFFA8A8A8)
    val textMuted = Color(0xFF6A6A6E)

    // Accent (Signature Purple)
    val accent = Color(0xFF9B6DD7)
    val accentHover = Color(0xFFB48BE8)
    val accentSubtle = Color(0x269B6DD7) // 15% opacity

    // Semantic
    val success = Color(0xFF4A9B6D)
    val error = Color(0xFFC74545)
    val warning = Color(0xFFD4A958)

    // Glass effect colors
    val glassBorder = Color.White.copy(alpha = 0.15f)
    val glassBackground = Color.White.copy(alpha = 0.06f)
    val glassShadow = Color.Black.copy(alpha = 0.15f)
    val navBarBorder = Color.White.copy(alpha = 0.10f)
}

// Spacing - matches iOS DesignSystem.swift
object Spacing {
    val xs = 6.dp
    val sm = 12.dp
    val md = 20.dp
    val lg = 32.dp
    val xl = 48.dp
    val xxl = 64.dp
}

// Corner Radii
object Radii {
    val card = 20.dp
    val button = 16.dp
    val badge = 100.dp // capsule
    val navBar = 100.dp // capsule
    val icon = 100.dp // circle
}
