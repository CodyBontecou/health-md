package com.healthmd.presentation.export

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.Image
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import com.healthmd.R
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.presentation.common.*
import com.healthmd.presentation.export.components.ExportProgressDialog
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportScreen(
    viewModel: ExportViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri -> uri?.let { viewModel.onFolderSelected(it) } }

    val healthConnectManager = remember { HealthConnectManager(context) }
    val permissionContract = remember { healthConnectManager.getPermissionContract() }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = permissionContract,
    ) { viewModel.refreshPermissions() }

    var showStartDatePicker by remember { mutableStateOf(false) }
    var showEndDatePicker by remember { mutableStateOf(false) }

    var showDebugPanel by remember { mutableStateOf(false) }
    var debugGranted by remember { mutableStateOf<Set<String>>(emptySet()) }
    var debugLoaded by remember { mutableStateOf(false) }
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        debugGranted = healthConnectManager.getGrantedPermissions()
        debugLoaded = true
    }

    if (uiState.isExporting) {
        ExportProgressDialog(
            current = uiState.exportProgress,
            total = uiState.exportTotal,
            currentDate = uiState.exportProgressDate,
            onCancel = { viewModel.cancelExport() },
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Spacer(modifier = Modifier.height(Spacing.md))

        // App Icon with glow effect
        Box(contentAlignment = Alignment.Center) {
            // Glow layer (subtle shadow instead of blur for performance)
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .clip(RoundedCornerShape(26.dp))
                    .background(AppColors.accent.copy(alpha = 0.25f)),
            )
            // Icon
            Image(
                painter = painterResource(id = R.drawable.app_icon),
                contentDescription = "Health.md",
                modifier = Modifier
                    .size(90.dp)
                    .shadow(12.dp, RoundedCornerShape(22.dp), ambientColor = AppColors.accent.copy(alpha = 0.4f))
                    .clip(RoundedCornerShape(22.dp))
                    .border(
                        width = 1.dp,
                        color = Color.White.copy(alpha = 0.30f),
                        shape = RoundedCornerShape(22.dp),
                    ),
                contentScale = ContentScale.Crop,
            )
        }

        // Title
        Text(
            text = "Health.md",
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 2.sp,
        )
        Text(
            text = "Export your wellness data to markdown",
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Status badges
        Row(
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            val healthConnected = uiState.hasPermissions
            GlassBadge(
                borderColor = if (healthConnected) AppColors.success.copy(alpha = 0.4f) else AppColors.glassBorder,
            ) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(if (healthConnected) AppColors.success else AppColors.textMuted),
                )
                Spacer(modifier = Modifier.width(Spacing.xs))
                Icon(
                    Icons.Filled.Favorite,
                    contentDescription = null,
                    tint = if (healthConnected) AppColors.success else AppColors.textMuted,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.xs))
                Text(
                    if (healthConnected) "Connected" else "Disconnected",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = if (healthConnected) AppColors.textPrimary else AppColors.textMuted,
                )
            }

            val hasFolder = uiState.folderName != null
            GlassBadge(
                borderColor = if (hasFolder) AppColors.success.copy(alpha = 0.4f) else AppColors.glassBorder,
            ) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(if (hasFolder) AppColors.success else AppColors.textMuted),
                )
                Spacer(modifier = Modifier.width(Spacing.xs))
                Icon(
                    Icons.Outlined.Folder,
                    contentDescription = null,
                    tint = if (hasFolder) AppColors.success else AppColors.textMuted,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.xs))
                Text(
                    uiState.folderName ?: "Vault",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = if (hasFolder) AppColors.textPrimary else AppColors.textMuted,
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Permissions card (only if needed)
        if (!uiState.healthConnectAvailable) {
            GlassCard {
                Text("Health Connect Required", style = MaterialTheme.typography.titleMedium, color = AppColors.error)
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    "Install Health Connect from the Play Store to read your health data.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = "Install Health Connect",
                    onClick = { context.startActivity(healthConnectManager.getInstallIntent()) },
                )
            }
        } else if (uiState.healthConnectNeedsSetup) {
            GlassCard {
                Text("Health Connect Setup Required", style = MaterialTheme.typography.titleMedium, color = AppColors.textPrimary)
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    "Open Health Connect and complete the initial setup, then come back to grant permissions.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = "Open Health Connect",
                    onClick = { context.startActivity(healthConnectManager.getOpenHealthConnectIntent()) },
                )
            }
        } else if (!uiState.hasPermissions) {
            GlassCard {
                Text("Permissions Required", style = MaterialTheme.typography.titleMedium, color = AppColors.textPrimary)
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    "Grant Health Connect permissions to export your health data.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = "Grant Permissions",
                    onClick = { permissionLauncher.launch(healthConnectManager.permissions) },
                )
            }
        }

        // Date Range
        GlassCard {
            SectionLabel("Date Range")
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SecondaryButton(
                    text = uiState.startDate.toString(),
                    onClick = { showStartDatePicker = true },
                    modifier = Modifier.weight(1f),
                )
                Text("\u2013", color = AppColors.textMuted)
                SecondaryButton(
                    text = uiState.endDate.toString(),
                    onClick = { showEndDatePicker = true },
                    modifier = Modifier.weight(1f),
                )
            }
        }

        // Date quick shortcuts
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            listOf(
                "1d" to 1L,
                "7d" to 7L,
                "30d" to 30L,
                "90d" to 90L,
            ).forEach { (label, days) ->
                val shape = RoundedCornerShape(100.dp)
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(shape)
                        .background(AppColors.bgSecondary)
                        .border(1.dp, AppColors.glassBorder, shape)
                        .clickable {
                            val end = java.time.LocalDate.now()
                            val start = end.minusDays(days - 1)
                            viewModel.setStartDate(start)
                            viewModel.setEndDate(end)
                        }
                        .padding(vertical = 10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label,
                        color = AppColors.textSecondary,
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
            // All Time shortcut
            val shape = RoundedCornerShape(100.dp)
            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(shape)
                    .background(AppColors.bgSecondary)
                    .border(1.dp, AppColors.glassBorder, shape)
                    .clickable { viewModel.selectAllTime() }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "All",
                    color = AppColors.textSecondary,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }

        // Export Format
        GlassCard {
            SectionLabel("Export Format")
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                ExportFormat.entries.forEach { format ->
                    val selected = uiState.exportFormat == format
                    val shape = RoundedCornerShape(100.dp)
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(shape)
                            .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else Color.Transparent)
                            .border(
                                1.dp,
                                if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder,
                                shape,
                            )
                            .clickable { viewModel.setExportFormat(format) }
                            .padding(horizontal = 8.dp, vertical = 10.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            format.displayName,
                            color = if (selected) AppColors.accent else AppColors.textSecondary,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            maxLines = 1,
                        )
                    }
                }
            }
        }

        // Export Folder
        GlassCardClickable(onClick = { folderPickerLauncher.launch(null) }) {
            Icon(
                Icons.Outlined.Folder,
                contentDescription = null,
                tint = if (uiState.folderName != null) AppColors.accent else AppColors.textMuted,
                modifier = Modifier.size(24.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "EXPORT FOLDER",
                    style = MaterialTheme.typography.labelSmall,
                    color = AppColors.textMuted,
                    letterSpacing = 2.sp,
                )
                Text(
                    uiState.folderName ?: "Select a folder",
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                )
            }
            Text(
                if (uiState.folderName != null) "Change" else "Select",
                color = AppColors.accent,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Medium,
            )
        }

        Spacer(modifier = Modifier.height(Spacing.xs))

        // Export Button
        PrimaryButton(
            text = "Export Health Data",
            onClick = { viewModel.startExport() },
            icon = Icons.Outlined.UploadFile,
            enabled = uiState.hasPermissions && uiState.folderName != null && !uiState.isExporting,
            isLoading = uiState.isExporting,
        )

        // Free exports
        if (!uiState.isPurchased) {
            Text(
                text = "${uiState.freeExportsRemaining} free exports remaining",
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
            if (uiState.freeExportsRemaining <= 0) {
                Spacer(modifier = Modifier.height(Spacing.xs))
                SecondaryButton(
                    text = "Unlock Health.md",
                    onClick = onNavigateToPaywall,
                )
            }
        }

        // Last result
        uiState.lastResult?.let { result ->
            val borderColor = when {
                result.isFullSuccess -> AppColors.success.copy(alpha = 0.5f)
                result.isPartialSuccess -> AppColors.warning.copy(alpha = 0.5f)
                else -> AppColors.error.copy(alpha = 0.5f)
            }
            val iconColor = when {
                result.isFullSuccess -> AppColors.success
                result.isPartialSuccess -> AppColors.warning
                else -> AppColors.error
            }

            GlassBadge(borderColor = borderColor) {
                Text(
                    when {
                        result.isFullSuccess -> "\u2713"
                        result.wasCancelled -> "\u2717"
                        result.isPartialSuccess -> "!"
                        else -> "\u2717"
                    },
                    color = iconColor,
                    fontWeight = FontWeight.Bold,
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Text(
                    "${result.successCount}/${result.totalCount} days exported",
                    color = AppColors.textPrimary,
                    style = MaterialTheme.typography.labelMedium,
                )
            }

            if (!result.isFullSuccess) {
                result.primaryFailureReason?.let { reason ->
                    val message = when (reason) {
                        ExportFailureReason.NO_HEALTH_DATA -> "No health data found for this date range"
                        ExportFailureReason.FILE_WRITE_ERROR -> "Failed to write file \u2014 check folder access"
                        ExportFailureReason.ACCESS_DENIED -> "Access denied to the export folder"
                        ExportFailureReason.NO_FOLDER_SELECTED -> "No export folder selected"
                        ExportFailureReason.HEALTH_CONNECT_ERROR -> "Health Connect error \u2014 check permissions"
                        ExportFailureReason.DEVICE_LOCKED -> "Device was locked during export"
                        ExportFailureReason.UNKNOWN -> "An unexpected error occurred"
                    }
                    Text(
                        message,
                        style = MaterialTheme.typography.bodySmall,
                        color = iconColor,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth(),
                    )
                }
            }
        }

        // Debug panel
        GlassCard {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { showDebugPanel = !showDebugPanel },
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "Debug Info",
                    style = MaterialTheme.typography.labelLarge,
                    color = AppColors.textMuted,
                )
                Text(
                    if (showDebugPanel) "▲" else "▼",
                    color = AppColors.textMuted,
                    style = MaterialTheme.typography.labelSmall,
                )
            }

            if (showDebugPanel) {
                Spacer(modifier = Modifier.height(Spacing.xs))
                HorizontalDivider(color = AppColors.glassBorder)
                Spacer(modifier = Modifier.height(Spacing.xs))

                val grantedCount = if (debugLoaded) "${debugGranted.size}/${healthConnectManager.permissions.size}" else "loading…"
                val rows = listOf(
                    "SDK Status" to healthConnectManager.getSdkStatusString(),
                    "HC Available" to "${uiState.healthConnectAvailable}",
                    "HC Needs Setup" to "${uiState.healthConnectNeedsSetup}",
                    "Has Permissions" to "${uiState.hasPermissions}",
                    "Granted" to grantedCount,
                )

                rows.forEach { (label, value) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 2.dp),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(label, style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
                        Text(value, style = MaterialTheme.typography.bodySmall, color = AppColors.textPrimary, fontWeight = FontWeight.Medium)
                    }
                }

                if (debugLoaded) {
                    val missing = healthConnectManager.permissions - debugGranted
                    if (missing.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(Spacing.xs))
                        Text(
                            "Missing (${missing.size}):",
                            style = MaterialTheme.typography.labelSmall,
                            color = AppColors.textMuted,
                        )
                        missing.forEach { perm ->
                            Text(
                                "• ${perm.substringAfterLast('.')}",
                                style = MaterialTheme.typography.bodySmall,
                                color = AppColors.error,
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = "Refresh",
                    onClick = {
                        debugLoaded = false
                        coroutineScope.launch {
                            debugGranted = healthConnectManager.getGrantedPermissions()
                            debugLoaded = true
                        }
                    },
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }

    // Date pickers
    if (showStartDatePicker) {
        val state = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { showStartDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        viewModel.setStartDate(
                            java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
                        )
                    }
                    showStartDatePicker = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { showStartDatePicker = false }) { Text("Cancel") } },
        ) { DatePicker(state = state) }
    }
    if (showEndDatePicker) {
        val state = rememberDatePickerState()
        DatePickerDialog(
            onDismissRequest = { showEndDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        viewModel.setEndDate(
                            java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
                        )
                    }
                    showEndDatePicker = false
                }) { Text("OK") }
            },
            dismissButton = { TextButton(onClick = { showEndDatePicker = false }) { Text("Cancel") } },
        ) { DatePicker(state = state) }
    }
}
