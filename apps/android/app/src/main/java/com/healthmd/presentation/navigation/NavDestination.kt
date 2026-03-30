package com.healthmd.presentation.navigation

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.ui.graphics.vector.ImageVector

enum class NavDestination(
    val route: String,
    val icon: ImageVector,
    val label: String,
) {
    EXPORT("export", Icons.Outlined.FileUpload, "Export"),
    SCHEDULE("schedule", Icons.Outlined.Schedule, "Schedule"),
    HISTORY("history", Icons.Outlined.History, "History"),
    SETTINGS("settings", Icons.Outlined.Settings, "Settings"),
}

// Sub-screen routes (not in bottom nav)
object SubRoutes {
    const val METRIC_SELECTION = "metric_selection"
    const val FORMAT_CUSTOMIZATION = "format_customization"
    const val DAILY_NOTE_INJECTION = "daily_note_injection"
    const val INDIVIDUAL_TRACKING = "individual_tracking"
    const val ADVANCED_SETTINGS = "advanced_settings"
    const val PAYWALL = "paywall"
}
