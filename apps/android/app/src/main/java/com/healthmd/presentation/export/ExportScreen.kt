package com.healthmd.presentation.export

import android.app.Activity
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
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.ui.draw.scale
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Launch
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
import androidx.compose.ui.res.stringResource
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
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.launch
import timber.log.Timber

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
    val healthDataPermissionsToRequest =
        if (uiState.requiresHistoricalReadPermission) {
            healthConnectManager.permissions + healthConnectManager.historicalReadPermissions
        } else {
            healthConnectManager.permissions
        }

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

    // In-app review flow
    val activity = context as? Activity
    LaunchedEffect(Unit) {
        viewModel.requestReview.collect {
            activity?.let { act ->
                val reviewManager = ReviewManagerFactory.create(act)
                reviewManager.requestReviewFlow().addOnSuccessListener { reviewInfo ->
                    reviewManager.launchReviewFlow(act, reviewInfo)
                }.addOnFailureListener { e ->
                    Timber.e(e, "Failed to request in-app review")
                }
            }
        }
    }

    // Result toast state — kept at composable scope so the dialog can read them after toast dismisses
    var visibleResult by remember { mutableStateOf<com.healthmd.domain.model.ExportResult?>(null) }
    var visibleFolderUri by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(uiState.lastResult) {
        if (uiState.lastResult != null) {
            visibleResult = uiState.lastResult
            visibleFolderUri = uiState.exportedFolderUri
        }
    }

    val obsidianInstalled = remember(context) {
        try { context.packageManager.getPackageInfo("md.obsidian", 0); true }
        catch (_: Exception) { false }
    }
    var showOpenDialog by remember { mutableStateOf(false) }

    val openInFiles: (String) -> Unit = { uriString ->
        try {
            val treeUri = Uri.parse(uriString)
            val docUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri, DocumentsContract.getTreeDocumentId(treeUri)
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(docUri, DocumentsContract.Document.MIME_TYPE_DIR)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
        } catch (_: Exception) { }
    }

    val openInObsidian: (String?) -> Unit = { vaultName ->
        try {
            val vault = if (!vaultName.isNullOrBlank()) "?vault=${Uri.encode(vaultName)}" else ""
            val obsidianUri = Uri.parse("obsidian://open$vault")
            val intent = Intent(Intent.ACTION_VIEW, obsidianUri).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        } catch (_: Exception) { }
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
                contentDescription = stringResource(R.string.app_name),
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
            text = stringResource(R.string.app_name),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 2.sp,
        )
        Text(
            text = stringResource(R.string.export_subtitle),
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
                    if (healthConnected) stringResource(R.string.status_connected) else stringResource(R.string.status_disconnected),
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
                    uiState.folderName ?: stringResource(R.string.status_vault_default),
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
                Text(stringResource(R.string.hc_required_title), style = MaterialTheme.typography.titleMedium, color = AppColors.error)
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    stringResource(R.string.hc_required_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = stringResource(R.string.hc_install_button),
                    onClick = { context.startActivity(healthConnectManager.getInstallIntent()) },
                )
            }
        } else if (uiState.healthConnectNeedsSetup) {
            GlassCard {
                Text(stringResource(R.string.hc_setup_title), style = MaterialTheme.typography.titleMedium, color = AppColors.textPrimary)
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    stringResource(R.string.hc_setup_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = stringResource(R.string.hc_open_button),
                    onClick = { context.startActivity(healthConnectManager.getOpenHealthConnectIntent()) },
                )
            }
        } else if (!uiState.hasPermissions) {
            GlassCard {
                Text(stringResource(R.string.permissions_required_title), style = MaterialTheme.typography.titleMedium, color = AppColors.textPrimary)
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    stringResource(R.string.permissions_required_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = stringResource(R.string.permissions_grant_button),
                    onClick = { permissionLauncher.launch(healthDataPermissionsToRequest) },
                )
            }
        } else if (uiState.historyPermissionNeeded) {
            GlassCard {
                Text(
                    stringResource(R.string.history_permission_required_title),
                    style = MaterialTheme.typography.titleMedium,
                    color = AppColors.textPrimary,
                )
                Spacer(modifier = Modifier.height(Spacing.xs))
                Text(
                    stringResource(R.string.history_permission_required_message),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = stringResource(R.string.history_permission_grant_button),
                    onClick = {
                        permissionLauncher.launch(
                            healthConnectManager.permissions + healthConnectManager.historicalReadPermissions
                        )
                    },
                )
            }
        }

        // Date Range
        GlassCard {
            SectionLabel(stringResource(R.string.section_date_range))
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
                stringResource(R.string.date_shortcut_1d) to 1L,
                stringResource(R.string.date_shortcut_7d) to 7L,
                stringResource(R.string.date_shortcut_30d) to 30L,
                stringResource(R.string.date_shortcut_90d) to 90L,
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
                    stringResource(R.string.date_shortcut_all),
                    color = AppColors.textSecondary,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }

        // Export Format
        GlassCard {
            SectionLabel(stringResource(R.string.section_export_format))
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
                            format.localizedDisplayName(),
                            modifier = Modifier.fillMaxWidth(),
                            color = if (selected) AppColors.accent else AppColors.textSecondary,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            textAlign = TextAlign.Center,
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
                    stringResource(R.string.export_folder_label),
                    style = MaterialTheme.typography.labelSmall,
                    color = AppColors.textMuted,
                    letterSpacing = 2.sp,
                )
                Text(
                    uiState.folderName ?: stringResource(R.string.export_folder_placeholder),
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                )
            }
            Text(
                if (uiState.folderName != null) stringResource(R.string.export_folder_change) else stringResource(R.string.export_folder_select),
                color = AppColors.accent,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.Medium,
            )
        }

        Spacer(modifier = Modifier.height(Spacing.xs))

        // Export Button
        val hitExportLimit = !uiState.isPurchased && uiState.freeExportsRemaining <= 0
        val canExport = uiState.hasPermissions &&
                !uiState.historyPermissionNeeded &&
                uiState.folderName != null &&
                !uiState.isExporting
        PrimaryButton(
            text = if (hitExportLimit) stringResource(R.string.unlock_button) else stringResource(R.string.export_button),
            onClick = if (hitExportLimit) onNavigateToPaywall else {{ viewModel.startExport() }},
            icon = Icons.Outlined.UploadFile,
            enabled = canExport,
            isLoading = uiState.isExporting,
        )

        // Free exports
        if (!uiState.isPurchased) {
            Text(
                text = stringResource(R.string.free_exports_remaining, uiState.freeExportsRemaining),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }

        // Last result — auto-dismissing toast badge
        AnimatedVisibility(
            visible = uiState.lastResult != null,
            enter = fadeIn(tween(250)) + expandVertically(tween(250)),
            exit = fadeOut(tween(400)) + shrinkVertically(tween(400)),
        ) {
            visibleResult?.let { result ->
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

                val isOpenable = result.successCount > 0 && visibleFolderUri != null
                val interactionSource = remember { MutableInteractionSource() }
                val isPressed by interactionSource.collectIsPressedAsState()
                val badgeScale by animateFloatAsState(
                    targetValue = if (isPressed && isOpenable) 0.96f else 1f,
                    animationSpec = spring(dampingRatio = 0.6f, stiffness = 400f),
                    label = "resultBadgeScale",
                )

                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(Spacing.xs),
                ) {
                    GlassBadge(
                        modifier = Modifier
                            .scale(badgeScale)
                            .then(
                                if (isOpenable) {
                                    Modifier.clickable(
                                        interactionSource = interactionSource,
                                        indication = null,
                                    ) {
                                        viewModel.dismissResult()
                                        if (obsidianInstalled) {
                                            showOpenDialog = true
                                        } else {
                                            visibleFolderUri?.let { openInFiles(it) }
                                        }
                                    }
                                } else Modifier,
                            ),
                        borderColor = borderColor,
                    ) {
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
                            stringResource(R.string.export_result_days, result.successCount, result.totalCount),
                            color = AppColors.textPrimary,
                            style = MaterialTheme.typography.labelMedium,
                        )
                        if (isOpenable) {
                            Spacer(modifier = Modifier.width(Spacing.md))
                            Box(
                                modifier = Modifier
                                    .width(1.dp)
                                    .height(14.dp)
                                    .background(AppColors.glassBorder),
                            )
                            Spacer(modifier = Modifier.width(Spacing.sm))
                            Icon(
                                Icons.Outlined.FolderOpen,
                                contentDescription = stringResource(R.string.open_folder),
                                tint = AppColors.success,
                                modifier = Modifier.size(15.dp),
                            )
                        }
                    }

                    if (!result.isFullSuccess) {
                        result.primaryFailureReason?.let { reason ->
                            val message = when (reason) {
                                ExportFailureReason.NO_HEALTH_DATA -> stringResource(R.string.error_no_health_data)
                                ExportFailureReason.FILE_WRITE_ERROR -> stringResource(R.string.error_file_write)
                                ExportFailureReason.ACCESS_DENIED -> stringResource(R.string.error_access_denied)
                                ExportFailureReason.NO_FOLDER_SELECTED -> stringResource(R.string.error_no_folder)
                                ExportFailureReason.HEALTH_CONNECT_ERROR -> stringResource(R.string.error_health_connect)
                                ExportFailureReason.DEVICE_LOCKED -> stringResource(R.string.error_device_locked)
                                ExportFailureReason.BACKGROUND_PERMISSION_DENIED -> stringResource(R.string.error_background_permission_denied)
                                ExportFailureReason.UNKNOWN -> stringResource(R.string.error_unknown)
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
                    stringResource(R.string.debug_panel_title),
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

                val debugPermissions = healthConnectManager.permissions + healthConnectManager.historicalReadPermissions
                val grantedCount = if (debugLoaded) {
                    "${debugGranted.intersect(debugPermissions).size}/${debugPermissions.size}"
                } else {
                    stringResource(R.string.debug_loading)
                }
                val rows = listOf(
                    stringResource(R.string.debug_sdk_status) to healthConnectManager.getSdkStatusString(),
                    stringResource(R.string.debug_hc_available) to "${uiState.healthConnectAvailable}",
                    stringResource(R.string.debug_hc_needs_setup) to "${uiState.healthConnectNeedsSetup}",
                    stringResource(R.string.debug_has_permissions) to "${uiState.hasPermissions}",
                    stringResource(R.string.debug_has_history_permission) to "${uiState.hasHistoricalReadPermission}",
                    stringResource(R.string.debug_requires_history_permission) to "${uiState.requiresHistoricalReadPermission}",
                    stringResource(R.string.debug_granted) to grantedCount,
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
                    val missing = debugPermissions - debugGranted
                    if (missing.isNotEmpty()) {
                        Spacer(modifier = Modifier.height(Spacing.xs))
                        Text(
                            stringResource(R.string.debug_missing_count, missing.size),
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
                    text = stringResource(R.string.refresh),
                    onClick = {
                        viewModel.refreshPermissions()
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

    // Open-with dialog (shown when Obsidian is installed)
    if (showOpenDialog) {
        AlertDialog(
            onDismissRequest = { showOpenDialog = false },
            containerColor = AppColors.bgSecondary,
            tonalElevation = 0.dp,
            title = {
                Text(
                    stringResource(R.string.open_folder),
                    style = MaterialTheme.typography.titleMedium,
                    color = AppColors.textPrimary,
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    SecondaryButton(
                        text = stringResource(R.string.open_with_files),
                        modifier = Modifier.fillMaxWidth(),
                        icon = Icons.Outlined.Folder,
                        onClick = {
                            showOpenDialog = false
                            visibleFolderUri?.let { openInFiles(it) }
                        },
                    )
                    SecondaryButton(
                        text = stringResource(R.string.open_with_obsidian),
                        modifier = Modifier.fillMaxWidth(),
                        icon = Icons.Outlined.Launch,
                        onClick = {
                            showOpenDialog = false
                            openInObsidian(uiState.folderName)
                        },
                    )
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { showOpenDialog = false }) {
                    Text(stringResource(R.string.cancel), color = AppColors.textMuted)
                }
            },
        )
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
                }) { Text(stringResource(R.string.ok)) }
            },
            dismissButton = { TextButton(onClick = { showStartDatePicker = false }) { Text(stringResource(R.string.cancel)) } },
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
                }) { Text(stringResource(R.string.ok)) }
            },
            dismissButton = { TextButton(onClick = { showEndDatePicker = false }) { Text(stringResource(R.string.cancel)) } },
        ) { DatePicker(state = state) }
    }
}
