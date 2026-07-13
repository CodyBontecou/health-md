package com.healthmd.presentation.export

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
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
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Launch
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.*
import com.healthmd.presentation.export.components.ExportProgressDialog
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistElevation
import com.healthmd.presentation.theme.GeistMono
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.launch
import timber.log.Timber
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportScreen(
    viewModel: ExportViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
    onNavigateToAdvancedSettings: () -> Unit = {},
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
    var showAPISettings by remember { mutableStateOf(false) }
    var selectedDateRangeOption by remember {
        mutableStateOf(
            DateRangeOption.fromDates(
                startDate = uiState.startDate,
                endDate = uiState.endDate,
                allTimeSelected = uiState.allTimeSelected,
            )
        )
    }

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

    // Result state — kept at composable scope so the open-with dialog can read it after dismissal.
    var visibleResult by remember { mutableStateOf<ExportResult?>(null) }
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

    if (uiState.isPreviewing || uiState.preview != null) {
        ExportPreviewDialog(
            preview = uiState.preview,
            isLoading = uiState.isPreviewing,
            destinationLabel = uiState.destinationLabel ?: stringResource(
                if (uiState.selectedTarget == ExportTarget.API_ENDPOINT) {
                    R.string.export_preview_api_destination
                } else {
                    R.string.export_preview_device_destination
                }
            ),
            formatsPerDay = uiState.exportFormats.size,
            onDismiss = { viewModel.dismissPreview() },
            onCancel = { viewModel.cancelExport() },
        )
    }

    // Keep the primary export actions visible above the app's bottom navigation, matching iOS.
    // The measured inset lets the final scroll content clear localized and large-text labels.
    val hitExportLimit = !uiState.isPurchased && uiState.freeExportsRemaining <= 0
    val hasSelectedFormat = uiState.exportFormats.isNotEmpty()
    val canUseExportControls = uiState.hasPermissions &&
            !uiState.historyPermissionNeeded &&
            uiState.destinationReady &&
            !uiState.isExporting &&
            !uiState.isPreviewing
    val canRunExportAction = canUseExportControls && hasSelectedFormat
    val canPreview = uiState.healthConnectAvailable &&
            !uiState.healthConnectNeedsSetup &&
            hasSelectedFormat &&
            !uiState.isExporting &&
            !uiState.isPreviewing
    val exportButtonClick = if (hitExportLimit) onNavigateToPaywall else viewModel::startExport
    var floatingActionBarHeightPx by remember { mutableIntStateOf(0) }
    val floatingActionBarHeight = with(LocalDensity.current) { floatingActionBarHeightPx.toDp() }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.md)
                .padding(
                    top = Spacing.lg,
                    bottom = floatingActionBarHeight + Spacing.lg,
                ),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
        Spacer(modifier = Modifier.height(Spacing.md))

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Image(
                painter = painterResource(id = R.drawable.app_icon),
                contentDescription = stringResource(R.string.app_name),
                modifier = Modifier
                    .size(48.dp)
                    .clip(RoundedCornerShape(Radii.card))
                    .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card)),
                contentScale = ContentScale.Crop,
            )
            Column {
                Text(
                    text = stringResource(R.string.app_name),
                    style = MaterialTheme.typography.headlineMedium,
                    color = AppColors.textPrimary,
                )
                Text(
                    text = stringResource(R.string.export_subtitle),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Status badges
        Row(
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            val healthConnected = uiState.hasPermissions
            GeistBadge(
                borderColor = if (healthConnected) AppColors.successBorder else AppColors.borderDefault,
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

            val destinationReady = uiState.destinationReady
            GeistBadge(
                borderColor = if (destinationReady) AppColors.successBorder else AppColors.borderDefault,
            ) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(if (destinationReady) AppColors.success else AppColors.textMuted),
                )
                Spacer(modifier = Modifier.width(Spacing.xs))
                Icon(
                    if (uiState.selectedTarget == ExportTarget.API_ENDPOINT) Icons.Outlined.UploadFile else Icons.Outlined.Folder,
                    contentDescription = null,
                    tint = if (destinationReady) AppColors.success else AppColors.textMuted,
                    modifier = Modifier.size(16.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.xs))
                Text(
                    uiState.destinationLabel ?: stringResource(R.string.status_vault_default),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.Medium,
                    color = if (destinationReady) AppColors.textPrimary else AppColors.textMuted,
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Permissions card (only if needed)
        if (!uiState.healthConnectAvailable) {
            GeistCard {
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
            GeistCard {
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
            GeistCard {
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
            GeistCard {
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

        DateRangeSelectionSection(
            selectedOption = selectedDateRangeOption,
            startDate = uiState.startDate,
            endDate = uiState.endDate,
            onOptionSelected = { option ->
                selectedDateRangeOption = option
                when (option) {
                    DateRangeOption.Today -> {
                        val today = LocalDate.now()
                        viewModel.setDateRange(today, today)
                    }
                    DateRangeOption.Yesterday -> {
                        val yesterday = LocalDate.now().minusDays(1)
                        viewModel.setDateRange(yesterday, yesterday)
                    }
                    DateRangeOption.AllTime -> viewModel.selectAllTime()
                    DateRangeOption.Custom -> viewModel.setDateRange(uiState.startDate, uiState.endDate)
                }
            },
            onStartDateClick = {
                selectedDateRangeOption = DateRangeOption.Custom
                showStartDatePicker = true
            },
            onEndDateClick = {
                selectedDateRangeOption = DateRangeOption.Custom
                showEndDatePicker = true
            },
        )

        ExportTargetSelector(
            selectedTarget = uiState.selectedTarget,
            folderSubtitle = uiState.folderName?.let { "Write files to $it" }
                ?: "Choose a local or provider-backed folder",
            apiSubtitle = if (uiState.apiEndpointConfigured) {
                "POST JSON to ${APIExportEndpoint.displayName(uiState.settings.apiEndpointUrl)}"
            } else {
                "Send JSON to your API endpoint"
            },
            onTargetSelected = { target ->
                viewModel.setExportTarget(target)
                if (target == ExportTarget.API_ENDPOINT && !uiState.apiEndpointConfigured) {
                    showAPISettings = true
                }
            },
        )

        ExportConfigurationSection(
            settings = uiState.settings,
            previewDate = uiState.startDate,
            onToggleExportFormat = viewModel::toggleExportFormat,
            onWriteModeChanged = viewModel::updateWriteMode,
            onFilenameFormatChanged = viewModel::updateFilenameFormat,
            onSubfolderChanged = viewModel::updateSubfolder,
            onFolderOrganizationChanged = viewModel::updateFolderOrganization,
            onFolderStructureChanged = viewModel::updateFolderStructure,
            onIncludeMetadataChanged = viewModel::updateIncludeMetadata,
            onGroupByCategoryChanged = viewModel::updateGroupByCategory,
            onUseEmojiChanged = viewModel::updateUseEmoji,
            onUnitPreferenceChanged = viewModel::updateUnitPreference,
            onNavigateToAdvancedSettings = onNavigateToAdvancedSettings,
            onResetSettings = viewModel::resetSettings,
        )

        if (uiState.selectedTarget == ExportTarget.DEVICE_FOLDER) {
            GeistCardClickable(onClick = { folderPickerLauncher.launch(null) }) {
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
        } else {
            GeistCardClickable(onClick = { showAPISettings = true }) {
                Icon(
                    Icons.Outlined.UploadFile,
                    contentDescription = null,
                    tint = if (uiState.apiEndpointConfigured) AppColors.accent else AppColors.textMuted,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "API Endpoint",
                        style = MaterialTheme.typography.labelSmall,
                        color = AppColors.textMuted,
                    )
                    Text(
                        if (uiState.apiEndpointConfigured) {
                            "POST ${APIExportEndpoint.redactedDescription(uiState.settings.apiEndpointUrl)}"
                        } else {
                            "Configure an API endpoint"
                        },
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                    )
                    if (uiState.apiAuthorizationConfigured) {
                        Text(
                            "Authorization stored securely",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.success,
                        )
                    }
                    if (uiState.apiRequestHeadersConfigured) {
                        Text(
                            "Custom request headers stored securely",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.success,
                        )
                    }
                    uiState.apiConfigurationError?.let { error ->
                        Text(
                            error,
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.error,
                        )
                    }
                    Text(
                        "API exports always send JSON. Metric and time-series settings apply; file paths and write modes do not.",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
                Text(
                    if (uiState.apiEndpointConfigured) "Edit" else "Configure",
                    color = AppColors.accent,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium,
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xs))

        // Last result
        AnimatedVisibility(
            visible = uiState.lastResult != null,
            enter = fadeIn(tween(250)) + expandVertically(tween(250)),
            exit = fadeOut(tween(400)) + shrinkVertically(tween(400)),
        ) {
            visibleResult?.let { result ->
                val isOpenable = result.successCount > 0 && visibleFolderUri != null
                val openExportFolder = {
                    if (obsidianInstalled) {
                        showOpenDialog = true
                    } else {
                        visibleFolderUri?.let { openInFiles(it) }
                    }
                    Unit
                }

                if (result.toDiagnosticsSummary().shouldAutoDismiss) {
                    ExportResultBadge(
                        result = result,
                        isOpenable = isOpenable,
                        onClick = {
                            viewModel.dismissResult()
                            openExportFolder()
                        },
                    )
                } else {
                    ExportDiagnosticsPanel(
                        result = result,
                        isOpenable = isOpenable,
                        onDismiss = { viewModel.dismissResult() },
                        onOpenFolder = openExportFolder,
                        onUseFailedRange = { startDate, endDate ->
                            selectedDateRangeOption = DateRangeOption.Custom
                            viewModel.setDateRange(startDate, endDate)
                        },
                    )
                }
            }
        }

        // Debug panel
        GeistCard {
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
                HorizontalDivider(color = AppColors.borderDefault)
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
                    stringResource(R.string.debug_first_permission_grant) to (uiState.firstHealthPermissionGrantDate?.toString() ?: "—"),
                    stringResource(R.string.debug_granted) to grantedCount,
                )

                rows.forEach { (label, value) ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = Spacing.xxs),
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

        FloatingExportActionBar(
            isPurchased = uiState.isPurchased,
            freeExportsRemaining = uiState.freeExportsRemaining,
            hasSelectedFormat = hasSelectedFormat,
            canPreview = canPreview,
            canExport = canRunExportAction || (hitExportLimit && canUseExportControls),
            hitExportLimit = hitExportLimit,
            isExporting = uiState.isExporting,
            onPreview = {
                when {
                    !uiState.hasPermissions -> permissionLauncher.launch(healthDataPermissionsToRequest)
                    uiState.historyPermissionNeeded -> permissionLauncher.launch(
                        healthConnectManager.permissions + healthConnectManager.historicalReadPermissions
                    )
                    else -> viewModel.buildPreview()
                }
            },
            onExport = exportButtonClick,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .onSizeChanged { floatingActionBarHeightPx = it.height },
        )
    }

    if (showAPISettings) {
        APIExportSettingsDialog(
            initialEndpointUrl = uiState.settings.apiEndpointUrl,
            authorizationConfigured = uiState.apiAuthorizationConfigured,
            requestHeadersConfigured = uiState.apiRequestHeadersConfigured,
            configurationError = uiState.apiConfigurationError,
            onDismiss = {
                showAPISettings = false
                viewModel.clearAPIConfigurationError()
            },
            onSave = viewModel::saveAPIExportConfiguration,
            onClearAuthorization = viewModel::clearAPIAuthorization,
            onClearRequestHeaders = viewModel::clearAPIRequestHeaders,
        )
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
                    Text(stringResource(R.string.action_close_options), color = AppColors.textMuted)
                }
            },
        )
    }

    // Date pickers
    if (showStartDatePicker) {
        val state = rememberDatePickerState(initialSelectedDateMillis = uiState.startDate.toDatePickerMillis())
        DatePickerDialog(
            onDismissRequest = { showStartDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        selectedDateRangeOption = DateRangeOption.Custom
                        viewModel.setStartDate(
                            java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
                        )
                    }
                    showStartDatePicker = false
                }) { Text(stringResource(R.string.action_set_start_date)) }
            },
            dismissButton = { TextButton(onClick = { showStartDatePicker = false }) { Text(stringResource(R.string.action_cancel_selection)) } },
        ) { DatePicker(state = state) }
    }
    if (showEndDatePicker) {
        val state = rememberDatePickerState(initialSelectedDateMillis = uiState.endDate.toDatePickerMillis())
        DatePickerDialog(
            onDismissRequest = { showEndDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    state.selectedDateMillis?.let { millis ->
                        selectedDateRangeOption = DateRangeOption.Custom
                        viewModel.setEndDate(
                            java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
                        )
                    }
                    showEndDatePicker = false
                }) { Text(stringResource(R.string.action_set_end_date)) }
            },
            dismissButton = { TextButton(onClick = { showEndDatePicker = false }) { Text(stringResource(R.string.action_cancel_selection)) } },
        ) { DatePicker(state = state) }
    }
}

@Composable
private fun FloatingExportActionBar(
    isPurchased: Boolean,
    freeExportsRemaining: Int,
    hasSelectedFormat: Boolean,
    canPreview: Boolean,
    canExport: Boolean,
    hitExportLimit: Boolean,
    isExporting: Boolean,
    onPreview: () -> Unit,
    onExport: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.md, vertical = Spacing.sm),
        shape = RoundedCornerShape(Radii.navBar),
        color = AppColors.bgPrimary,
        border = BorderStroke(1.dp, AppColors.borderDefault),
        tonalElevation = 0.dp,
        shadowElevation = GeistElevation.raisedCard,
    ) {
        Column(
            modifier = Modifier.padding(Spacing.xs),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            if (!hasSelectedFormat) {
                Text(
                    "Select at least one export format to continue.",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.error,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (!isPurchased) {
                Text(
                    text = stringResource(R.string.free_exports_remaining, freeExportsRemaining),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                SecondaryButton(
                    text = stringResource(R.string.export_preview_button),
                    onClick = onPreview,
                    icon = Icons.Outlined.Visibility,
                    enabled = canPreview,
                    modifier = Modifier.weight(1f),
                )
                PrimaryButton(
                    text = if (hitExportLimit) {
                        stringResource(R.string.unlock_button)
                    } else {
                        stringResource(R.string.export_button)
                    },
                    onClick = onExport,
                    icon = Icons.Outlined.UploadFile,
                    enabled = canExport,
                    isLoading = isExporting,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

private enum class DateRangeOption {
    Today,
    Yesterday,
    AllTime,
    Custom;

    companion object {
        fun fromDates(
            startDate: LocalDate,
            endDate: LocalDate,
            allTimeSelected: Boolean,
        ): DateRangeOption {
            val today = LocalDate.now()
            val yesterday = today.minusDays(1)
            return when {
                allTimeSelected -> AllTime
                startDate == today && endDate == today -> Today
                startDate == yesterday && endDate == yesterday -> Yesterday
                else -> Custom
            }
        }
    }
}

@Composable
private fun DateRangeSelectionSection(
    selectedOption: DateRangeOption,
    startDate: LocalDate,
    endDate: LocalDate,
    onOptionSelected: (DateRangeOption) -> Unit,
    onStartDateClick: () -> Unit,
    onEndDateClick: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        SectionLabel(stringResource(R.string.section_date_range))
        GeistCard(padding = Spacing.md) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                DateRangeOptionButton(
                    text = stringResource(R.string.date_option_today),
                    selected = selectedOption == DateRangeOption.Today,
                    onClick = { onOptionSelected(DateRangeOption.Today) },
                    modifier = Modifier.weight(1f),
                )
                DateRangeOptionButton(
                    text = stringResource(R.string.date_option_yesterday),
                    selected = selectedOption == DateRangeOption.Yesterday,
                    onClick = { onOptionSelected(DateRangeOption.Yesterday) },
                    modifier = Modifier.weight(1f),
                )
            }
            Spacer(modifier = Modifier.height(Spacing.xs))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                DateRangeOptionButton(
                    text = stringResource(R.string.date_option_all_time),
                    selected = selectedOption == DateRangeOption.AllTime,
                    onClick = { onOptionSelected(DateRangeOption.AllTime) },
                    modifier = Modifier.weight(1f),
                )
                DateRangeOptionButton(
                    text = stringResource(R.string.date_option_custom),
                    selected = selectedOption == DateRangeOption.Custom,
                    onClick = { onOptionSelected(DateRangeOption.Custom) },
                    modifier = Modifier.weight(1f),
                )
            }

            AnimatedVisibility(
                visible = selectedOption == DateRangeOption.Custom,
                enter = fadeIn(animationSpec = tween(160)) + expandVertically(animationSpec = tween(180)),
                exit = fadeOut(animationSpec = tween(120)) + shrinkVertically(animationSpec = tween(160)),
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Spacer(modifier = Modifier.height(Spacing.md))
                    HorizontalDivider(color = AppColors.borderDefault)
                    DateRangeDateRow(
                        label = stringResource(R.string.date_start_label),
                        date = startDate,
                        onClick = onStartDateClick,
                    )
                    HorizontalDivider(color = AppColors.borderDefault)
                    DateRangeDateRow(
                        label = stringResource(R.string.date_end_label),
                        date = endDate,
                        onClick = onEndDateClick,
                    )
                }
            }
        }
    }
}

@Composable
private fun DateRangeOptionButton(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(Radii.badge)
    Row(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(shape)
            .background(if (selected) AppColors.accentSubtle else Color.Transparent)
            .then(
                if (selected) {
                    Modifier.border(1.dp, AppColors.accentBorder, shape)
                } else {
                    Modifier
                }
            )
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.sm, vertical = Spacing.xs),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (selected) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(22.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.xs))
        }
        Text(
            text = text,
            color = if (selected) AppColors.accent else AppColors.textSecondary,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

@Composable
private fun DateRangeDateRow(
    label: String,
    date: LocalDate,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .clickable(onClick = onClick)
            .padding(vertical = Spacing.md),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.titleLarge,
            color = AppColors.textPrimary,
        )
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(Radii.badge))
                .background(AppColors.bgSecondary)
                .padding(horizontal = Spacing.md, vertical = Spacing.xs),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = formatCompactDate(date),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
            )
        }
    }
}

@Composable
private fun ExportResultBadge(
    result: ExportResult,
    isOpenable: Boolean,
    onClick: () -> Unit,
) {
    GeistBadge(
        modifier = Modifier.then(
            if (isOpenable) Modifier.clickable(onClick = onClick) else Modifier,
        ),
        borderColor = AppColors.successBorder,
    ) {
        Text(
            "\u2713",
            color = AppColors.success,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.width(Spacing.sm))
        Text(
            if (result.target == ExportTarget.API_ENDPOINT) {
                "${result.successCount}/${result.totalCount} days uploaded" +
                    (result.httpStatusCode?.let { " · HTTP $it" } ?: "")
            } else {
                stringResource(R.string.export_result_days, result.successCount, result.totalCount)
            },
            color = AppColors.textPrimary,
            style = MaterialTheme.typography.labelMedium,
        )
        if (isOpenable) {
            Spacer(modifier = Modifier.width(Spacing.md))
            Box(
                modifier = Modifier
                    .width(1.dp)
                    .height(16.dp)
                    .background(AppColors.borderDefault),
            )
            Spacer(modifier = Modifier.width(Spacing.sm))
            Icon(
                Icons.Outlined.FolderOpen,
                contentDescription = stringResource(R.string.open_folder),
                tint = AppColors.success,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

@Composable
private fun ExportDiagnosticsPanel(
    result: ExportResult,
    isOpenable: Boolean,
    onDismiss: () -> Unit,
    onOpenFolder: () -> Unit,
    onUseFailedRange: (startDate: java.time.LocalDate, endDate: java.time.LocalDate) -> Unit,
) {
    val summary = remember(result) { result.toDiagnosticsSummary() }
    var expanded by remember(result) { mutableStateOf(true) }
    val statusColor = when {
        summary.isPartial -> AppColors.warning
        else -> AppColors.error
    }
    val title = when {
        summary.wasCancelled -> stringResource(R.string.export_diagnostics_title_cancelled)
        summary.isPartial -> stringResource(R.string.export_diagnostics_title_partial)
        else -> stringResource(R.string.export_diagnostics_title_failed)
    }
    val failedRangeStart = summary.failedRangeStart
    val failedRangeEnd = summary.failedRangeEnd

    GeistCard(padding = Spacing.md) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalAlignment = Alignment.Top,
        ) {
            Text(
                when {
                    summary.wasCancelled -> "\u2717"
                    summary.isPartial -> "!"
                    else -> "\u2717"
                },
                color = statusColor,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    title,
                    style = MaterialTheme.typography.titleMedium,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    stringResource(R.string.export_result_days, summary.successCount, summary.totalCount),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.size(32.dp),
            ) {
                Icon(
                    Icons.Outlined.Close,
                    contentDescription = stringResource(R.string.close),
                    tint = AppColors.textMuted,
                    modifier = Modifier.size(18.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        Text(
            stringResource(R.string.export_diagnostics_failed_count, summary.failedDayCount),
            style = MaterialTheme.typography.bodyMedium,
            color = statusColor,
            fontWeight = FontWeight.Medium,
        )

        if (summary.wasCancelled) {
            Spacer(modifier = Modifier.height(Spacing.xs))
            Text(
                stringResource(R.string.export_diagnostics_cancelled_message),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
            )
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        if (summary.hasDetailedFailures) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(Radii.card))
                    .clickable { expanded = !expanded }
                    .padding(vertical = Spacing.xs),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    stringResource(R.string.export_diagnostics_reasons_title),
                    style = MaterialTheme.typography.labelLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.Medium,
                )
                Icon(
                    if (expanded) Icons.Outlined.ExpandLess else Icons.Outlined.ExpandMore,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier.size(20.dp),
                )
            }

            AnimatedVisibility(visible = expanded) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    summary.failureGroups.forEach { group ->
                        ExportFailureGroup(group = group)
                    }
                }
            }
        } else {
            Text(
                stringResource(R.string.export_diagnostics_no_details),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
            )
        }

        if (isOpenable || (failedRangeStart != null && failedRangeEnd != null)) {
            Spacer(modifier = Modifier.height(Spacing.sm))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                if (failedRangeStart != null && failedRangeEnd != null) {
                    SecondaryButton(
                        text = stringResource(R.string.export_diagnostics_use_failed_range),
                        modifier = Modifier.weight(1f),
                        icon = Icons.Outlined.UploadFile,
                        onClick = { onUseFailedRange(failedRangeStart, failedRangeEnd) },
                    )
                }
                if (isOpenable) {
                    SecondaryButton(
                        text = stringResource(R.string.open_folder),
                        modifier = Modifier.weight(1f),
                        icon = Icons.Outlined.FolderOpen,
                        onClick = onOpenFolder,
                    )
                }
            }
        }
    }
}

@Composable
private fun ExportFailureGroup(group: ExportFailureDiagnosticGroup) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(AppColors.bgSecondary)
            .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card))
            .padding(Spacing.sm),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
    ) {
        Text(
            stringResource(
                R.string.export_diagnostics_reason_count,
                group.failureReasonLabel(),
                group.count,
            ),
            style = MaterialTheme.typography.labelLarge,
            color = AppColors.textPrimary,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            group.guidanceText(),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
        )
        if (group.sampleDates.isNotEmpty()) {
            Text(
                group.dateSampleText(),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }
    }
}

@Composable
fun ExportFailureDiagnosticGroup.failureReasonLabel(): String =
    when (reason) {
        ExportFailureReason.NO_FOLDER_SELECTED -> stringResource(R.string.export_failure_no_folder_label)
        ExportFailureReason.NO_HEALTH_DATA -> stringResource(R.string.export_failure_no_data_label)
        ExportFailureReason.ACCESS_DENIED -> stringResource(R.string.export_failure_access_denied_label)
        ExportFailureReason.FILE_WRITE_ERROR -> stringResource(R.string.export_failure_file_write_label)
        ExportFailureReason.RATE_LIMITED -> stringResource(R.string.export_failure_rate_limited_label)
        ExportFailureReason.HEALTH_CONNECT_ERROR -> stringResource(R.string.export_failure_health_connect_label)
        ExportFailureReason.DEVICE_LOCKED -> stringResource(R.string.export_failure_device_locked_label)
        ExportFailureReason.BACKGROUND_PERMISSION_DENIED -> stringResource(R.string.export_failure_background_permission_label)
        ExportFailureReason.PAYWALL_REQUIRED -> stringResource(R.string.export_failure_paywall_label)
        ExportFailureReason.INVALID_API_ENDPOINT -> stringResource(R.string.export_failure_invalid_api_endpoint_label)
        ExportFailureReason.NETWORK_ERROR -> stringResource(R.string.export_failure_network_label)
        ExportFailureReason.API_REJECTED -> stringResource(R.string.export_failure_api_rejected_label)
        ExportFailureReason.UNKNOWN -> stringResource(R.string.export_failure_unknown_label)
    }

@Composable
fun ExportFailureDiagnosticGroup.guidanceText(): String =
    when (guidance) {
        ExportDiagnosticGuidance.RATE_LIMIT -> stringResource(R.string.export_guidance_rate_limit)
        ExportDiagnosticGuidance.HISTORICAL_PERMISSION -> stringResource(R.string.export_guidance_historical_permission)
        ExportDiagnosticGuidance.FILE_WRITE -> stringResource(R.string.export_guidance_file_write)
        ExportDiagnosticGuidance.NO_DATA -> stringResource(R.string.export_guidance_no_data)
        ExportDiagnosticGuidance.BACKGROUND_PERMISSION -> stringResource(R.string.export_guidance_background_permission)
        ExportDiagnosticGuidance.DEVICE_LOCKED -> stringResource(R.string.export_guidance_device_locked)
        ExportDiagnosticGuidance.NO_FOLDER -> stringResource(R.string.export_guidance_no_folder)
        ExportDiagnosticGuidance.PAYWALL -> stringResource(R.string.export_guidance_paywall)
        ExportDiagnosticGuidance.HEALTH_CONNECT -> stringResource(R.string.export_guidance_health_connect)
        ExportDiagnosticGuidance.API_CONFIGURATION -> stringResource(R.string.export_guidance_api_configuration)
        ExportDiagnosticGuidance.NETWORK -> stringResource(R.string.export_guidance_network)
        ExportDiagnosticGuidance.API_REJECTED -> stringResource(R.string.export_guidance_api_rejected)
        ExportDiagnosticGuidance.UNKNOWN -> stringResource(R.string.export_guidance_unknown)
    }

@Composable
fun ExportFailureDiagnosticGroup.dateSampleText(): String {
    val dates = sampleDates.joinToString(", ") { it.toString() }
    return if (remainingDateCount > 0) {
        stringResource(R.string.export_diagnostics_date_list_more, dates, remainingDateCount)
    } else {
        stringResource(R.string.export_diagnostics_date_list, dates)
    }
}

@Composable
private fun ExportPreviewDialog(
    preview: ExportPreview?,
    isLoading: Boolean,
    destinationLabel: String?,
    formatsPerDay: Int,
    onDismiss: () -> Unit,
    onCancel: () -> Unit,
) {
    var selectedFile by remember(preview) { mutableStateOf<PreviewFileDetails?>(null) }
    val closePreview = if (isLoading) onCancel else onDismiss

    AlertDialog(
        onDismissRequest = closePreview,
        containerColor = AppColors.bgSecondary,
        tonalElevation = 0.dp,
        title = {
            selectedFile?.let { file ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(
                        onClick = { selectedFile = null },
                        modifier = Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(AppColors.bgTertiary),
                    ) {
                        Icon(
                            Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = "Back to export preview",
                            tint = AppColors.textPrimary,
                        )
                    }
                    Spacer(modifier = Modifier.width(Spacing.sm))
                    Text(
                        file.title,
                        style = MaterialTheme.typography.titleLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            } ?: Text(
                stringResource(R.string.export_preview_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.SemiBold,
            )
        },
        text = {
            when {
                isLoading -> ExportPreviewLoadingContent()
                selectedFile != null -> PreviewFileContent(selectedFile!!)
                preview != null -> ExportPreviewFileList(
                    preview = preview,
                    destinationLabel = destinationLabel,
                    formatsPerDay = formatsPerDay,
                    onFileSelected = { selectedFile = it },
                )
            }
        },
        confirmButton = {
            TextButton(onClick = closePreview) {
                Text(stringResource(R.string.export_preview_done), color = AppColors.accent)
            }
        },
    )
}

@Composable
private fun ExportPreviewLoadingContent() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 260.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = AppColors.accent)
        Spacer(modifier = Modifier.height(Spacing.md))
        Text(
            stringResource(R.string.export_preview_building),
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textMuted,
        )
    }
}

@Composable
private fun ExportPreviewFileList(
    preview: ExportPreview,
    destinationLabel: String?,
    formatsPerDay: Int,
    onFileSelected: (PreviewFileDetails) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 560.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        PreviewSummaryCard(
            requestedDayCount = preview.requestedDateCount,
            formatsPerDay = formatsPerDay,
            destinationLabel = destinationLabel,
        )

        Text(
            "${preview.previewedDateCount}/${preview.requestedDateCount} days • ${preview.totalFileCount} files • ${formatBytes(preview.totalByteCount)}",
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )
        if (preview.isTruncated && preview.previewedDateCount > 0) {
            Text(
                if (preview.previewedDateCount == 1) {
                    stringResource(R.string.export_preview_limited_one)
                } else {
                    stringResource(R.string.export_preview_limited_other, preview.previewedDateCount)
                },
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }
        if (preview.days.isEmpty()) {
            PreviewStatusCard(
                title = stringResource(R.string.export_preview_no_data_title),
                message = stringResource(R.string.export_preview_no_data_message),
                color = AppColors.textMuted,
            )
        }

        preview.days.forEach { day ->
            Text(
                formatPreviewDate(day.date),
                style = MaterialTheme.typography.labelLarge,
                color = AppColors.textMuted,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = Spacing.xs),
            )

            day.failureReason?.let { reason ->
                PreviewStatusCard(
                    title = reason.name,
                    message = day.warning ?: "No exportable file for this date.",
                    color = AppColors.error,
                )
            }
            day.warning?.takeIf { day.failureReason == null }?.let { warning ->
                PreviewStatusCard(
                    title = "Warning",
                    message = warning,
                    color = AppColors.warning,
                )
            }

            day.files.forEach { file ->
                val details = PreviewFileDetails(
                    title = file.relativePath.substringAfterLast('/'),
                    subtitle = "${file.format.localizedDisplayName()} · ${formatBytes(file.byteCount)}",
                    relativePath = file.relativePath,
                    byteCount = file.byteCount,
                    content = file.content,
                    isWritable = true,
                )
                PreviewFileRow(
                    file = details,
                    destinationLabel = destinationLabel,
                    onClick = { onFileSelected(details) },
                )
            }

            day.sideEffects.forEach { effect ->
                val details = PreviewFileDetails(
                    title = effect.relativePath.substringAfterLast('/'),
                    subtitle = effect.action + if (effect.wouldWrite) " · ${formatBytes(effect.byteCount)}" else "",
                    relativePath = effect.relativePath,
                    byteCount = effect.byteCount,
                    content = effect.content.orEmpty(),
                    isWritable = effect.wouldWrite,
                )
                PreviewFileRow(
                    file = details,
                    destinationLabel = destinationLabel,
                    onClick = { if (effect.content != null) onFileSelected(details) },
                    enabled = effect.content != null,
                )
            }
        }
    }
}

@Composable
private fun PreviewSummaryCard(
    requestedDayCount: Int,
    formatsPerDay: Int,
    destinationLabel: String?,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(AppColors.bgPrimary)
            .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card))
            .padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
    ) {
        PreviewSummaryRow("Date range", dayCountLabel(requestedDayCount))
        PreviewSummaryRow("Formats per day", formatsPerDay.toString())
        PreviewSummaryRow("Destination", destinationLabel ?: "Selected folder")
    }
}

@Composable
private fun PreviewSummaryRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )
        Text(
            value,
            modifier = Modifier.padding(start = Spacing.md),
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textPrimary,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun PreviewStatusCard(title: String, message: String, color: Color) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(AppColors.bgPrimary)
            .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card))
            .padding(Spacing.sm),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.labelLarge,
            color = color,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            message,
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
        )
    }
}

@Composable
private fun PreviewFileRow(
    file: PreviewFileDetails,
    destinationLabel: String?,
    onClick: () -> Unit,
    enabled: Boolean = true,
) {
    val rowColor = if (file.isWritable) AppColors.accent else AppColors.textMuted
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(Radii.card))
                .background(AppColors.bgPrimary)
                .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card))
                .clickable(enabled = enabled, onClick = onClick)
                .padding(Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(if (file.isWritable) AppColors.accentSubtle else AppColors.bgSecondary),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.Description,
                    contentDescription = null,
                    tint = rowColor,
                    modifier = Modifier.size(22.dp),
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    file.title,
                    style = MaterialTheme.typography.titleMedium,
                    color = if (enabled) AppColors.textPrimary else AppColors.textMuted,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    file.subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            if (enabled) {
                Icon(
                    Icons.Outlined.ChevronRight,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                )
            }
        }
        parentPathLabel(file.relativePath, destinationLabel)?.let { path ->
            Text(
                path,
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
                modifier = Modifier.padding(start = Spacing.md),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun PreviewFileContent(file: PreviewFileDetails) {
    val displayContent = remember(file.content) {
        ExportPreviewDisplayContent.make(file.content)
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 560.dp),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Text(
            stringResource(
                if (displayContent.isTruncated) {
                    R.string.export_preview_truncated_file
                } else {
                    R.string.export_preview_complete_file
                },
                formatBytes(displayContent.originalByteCount),
            ),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
        )
        Text(
            file.relativePath,
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textMuted,
        )
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 260.dp, max = 460.dp)
                .clip(RoundedCornerShape(Radii.card))
                .background(AppColors.bgPrimary)
                .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card))
                .verticalScroll(rememberScrollState())
                .padding(Spacing.sm),
        ) {
            Text(
                displayContent.text,
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textPrimary,
                fontFamily = GeistMono,
            )
        }
    }
}

private data class PreviewFileDetails(
    val title: String,
    val subtitle: String,
    val relativePath: String,
    val byteCount: Int,
    val content: String,
    val isWritable: Boolean,
)

private fun dayCountLabel(days: Int): String = if (days == 1) "1 day" else "$days days"

private fun formatPreviewDate(date: LocalDate): String =
    date.format(DateTimeFormatter.ofPattern("EEE, MMM d, yyyy", Locale.getDefault()))

private fun formatCompactDate(date: LocalDate): String =
    date.format(DateTimeFormatter.ofPattern("M/d/yy", Locale.getDefault()))

private fun LocalDate.toDatePickerMillis(): Long =
    atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()

private fun parentPathLabel(relativePath: String, destinationLabel: String?): String? {
    val parent = relativePath.substringBeforeLast('/', missingDelimiterValue = "")
    if (parent.isBlank()) return destinationLabel
    return listOfNotNull(destinationLabel?.takeIf { it.isNotBlank() }, parent.trim('/'))
        .joinToString("/") + "/"
}

private fun formatBytes(bytes: Int): String = when {
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> {
        val kb = bytes / 1024.0
        if (kb < 10) String.format(Locale.US, "%.1f KB", kb) else String.format(Locale.US, "%.0f KB", kb)
    }
    else -> String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
}
