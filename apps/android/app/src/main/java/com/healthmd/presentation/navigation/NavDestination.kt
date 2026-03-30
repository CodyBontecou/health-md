package com.healthmd.presentation.navigation

import androidx.annotation.StringRes
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.ui.graphics.vector.ImageVector
import com.healthmd.R

enum class NavDestination(
    val route: String,
    val icon: ImageVector,
    @StringRes val label: Int,
) {
    EXPORT("export", Icons.Outlined.FileUpload, R.string.nav_export),
    SCHEDULE("schedule", Icons.Outlined.Schedule, R.string.nav_schedule),
    HISTORY("history", Icons.Outlined.History, R.string.nav_history),
    SETTINGS("settings", Icons.Outlined.Settings, R.string.nav_settings),
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
