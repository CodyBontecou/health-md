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
