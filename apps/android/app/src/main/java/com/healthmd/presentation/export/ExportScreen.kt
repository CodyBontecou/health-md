package com.healthmd.presentation.export

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.health.connect.client.contracts.ExerciseRouteRequestContract
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
import android.text.format.Formatter
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForwardIos
import androidx.compose.material.icons.automirrored.outlined.Launch
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOpen
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
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.data.health.HealthConnectFeatureAvailability
import com.healthmd.data.health.HealthConnectIntentLauncher
import com.healthmd.data.health.HealthConnectLaunchResult
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthConnectPermissionPolicy
import com.healthmd.data.health.grantedAllRequestedHealthPermissions
import com.healthmd.data.health.grantedAnyRequestedHealthPermission
import com.healthmd.data.health.tryLaunchHealthConnectPermissions
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.model.ExportPreviewIssue
import com.healthmd.domain.model.ExportPreviewIssueKind
import com.healthmd.domain.model.ExportPreviewSideEffectAction
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
import com.healthmd.util.runCatchingCancellable
import com.healthmd.rawexport.ExportMode
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.text.NumberFormat

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportScreen(
    viewModel: ExportViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
    onNavigateToAdvancedSettings: () -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val protection = LocalConfigurationProtection.current
    val attemptConfigurationChange: (() -> Unit) -> Unit = { action ->
        if (protection.enabled) protection.onBlockedChange() else action()
    }
    val apiConfigurationErrorText = uiState.apiConfigurationError?.localizedText()

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri ->
        uri?.let {
            attemptConfigurationChange { viewModel.onFolderSelected(it) }
        }
    }

    // Health Connect per-session exercise route consent for third-party sessions. Attached for
    // the whole screen lifetime; only manual export coroutines carry the interactive marker.
    // Preview, scheduled, automation, and direct CLI runs never trigger a prompt from here.
    val routeConsentSurface = remember { LauncherExerciseRouteConsentSurface() }
    val routeConsentLauncher = rememberLauncherForActivityResult(
        contract = ExerciseRouteRequestContract(),
    ) { route ->
        // The ViewModel-scoped coordinator retains the originating run/session across rotation.
        viewModel.routeConsentCoordinator.onRouteResult(route)
    }
    DisposableEffect(viewModel.routeConsentCoordinator) {
        routeConsentSurface.bind(routeConsentLauncher)
        viewModel.routeConsentCoordinator.attach(routeConsentSurface)
        onDispose {
            viewModel.routeConsentCoordinator.detach(routeConsentSurface)
        }
    }

    val healthConnectManager = remember { HealthConnectManager(context) }
    val healthConnectIntentLauncher = remember { HealthConnectIntentLauncher(context) }
    var capabilityRefreshGeneration by remember { mutableIntStateOf(0) }
    var dismissedFeatureErrorGeneration by remember { mutableIntStateOf(-1) }
    var pendingPermissionRequest by remember { mutableStateOf<Set<String>>(emptySet()) }
    var pendingRequiredPermissions by remember { mutableStateOf<Set<String>>(emptySet()) }
    val permissionContract = remember { healthConnectManager.getPermissionContract() }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = permissionContract,
    ) { grantedPermissions ->
        capabilityRefreshGeneration++
        val requestWasDenied = if (pendingRequiredPermissions.isNotEmpty()) {
            !grantedAllRequestedHealthPermissions(
                pendingRequiredPermissions,
                grantedPermissions,
            )
        } else {
            pendingPermissionRequest.isNotEmpty() &&
                !grantedAnyRequestedHealthPermission(
                    pendingPermissionRequest,
                    grantedPermissions,
                )
        }
        if (requestWasDenied) {
            viewModel.reportHealthConnectActionError(HealthConnectActionError.PERMISSION_DENIED)
        }
        pendingPermissionRequest = emptySet()
        pendingRequiredPermissions = emptySet()
        viewModel.refreshPermissions()
    }
    val permissionPlan = remember(
        capabilityRefreshGeneration,
        uiState.healthConnectAvailable,
    ) {
        if (uiState.healthConnectAvailable) {
            healthConnectManager.permissionPlan()
        } else {
            HealthConnectPermissionPolicy.create { false }
        }
    }
    val healthDataPermissionsToRequest = permissionPlan.foregroundPermissions +
        if (uiState.requiresHistoricalReadPermission) {
            permissionPlan.historicalReadPermissions
        } else {
            emptySet()
        }
    val historyPermissionAvailable =
        permissionPlan.historicalReadAvailability == HealthConnectFeatureAvailability.AVAILABLE
    val historyPermissionCheckFailed =
        permissionPlan.historicalReadAvailability == HealthConnectFeatureAvailability.ERROR

    val healthConnectError = uiState.healthConnectActionError ?: if (
        permissionPlan.featureStatusCheckFailed &&
        dismissedFeatureErrorGeneration != capabilityRefreshGeneration
    ) {
        HealthConnectActionError.ACCESS_CHECK_FAILED
    } else {
        null
    }

    val launchHealthPermissionRequest: (Set<String>, Set<String>) -> Unit =
        { permissions, requiredPermissions ->
            if (protection.enabled) {
                protection.onBlockedChange()
            } else {
            viewModel.clearHealthConnectActionError()
            pendingPermissionRequest = permissions
            pendingRequiredPermissions = requiredPermissions
            if (!tryLaunchHealthConnectPermissions(permissions) { permissionLauncher.launch(it) }) {
                pendingPermissionRequest = emptySet()
                pendingRequiredPermissions = emptySet()
                viewModel.reportHealthConnectActionError(
                    if (permissions.isEmpty() && uiState.requiresHistoricalReadPermission) {
                        HealthConnectActionError.HISTORY_UNAVAILABLE
                    } else {
                        HealthConnectActionError.PERMISSION_REQUEST_FAILED
                    }
                )
            }
            }
        }

    val openHealthConnectSettings: () -> Unit = {
        if (protection.enabled) {
            protection.onBlockedChange()
        } else {
        viewModel.clearHealthConnectActionError()
        if (healthConnectIntentLauncher.openSettings() == HealthConnectLaunchResult.FAILED) {
            viewModel.reportHealthConnectActionError(HealthConnectActionError.SETTINGS_LAUNCH_FAILED)
        }
        }
    }

    val openHealthConnectInstall: () -> Unit = {
        if (protection.enabled) {
            protection.onBlockedChange()
        } else {
        viewModel.clearHealthConnectActionError()
        if (healthConnectIntentLauncher.openInstallOrUpdate() == HealthConnectLaunchResult.FAILED) {
            viewModel.reportHealthConnectActionError(HealthConnectActionError.INSTALL_LAUNCH_FAILED)
        }
        }
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

    LaunchedEffect(showDebugPanel, uiState.healthConnectAvailable) {
        if (!showDebugPanel) return@LaunchedEffect
        if (!uiState.healthConnectAvailable) {
            debugGranted = emptySet()
            debugLoaded = true
            return@LaunchedEffect
        }
        runCatchingCancellable { healthConnectManager.getGrantedPermissions() }
            .onSuccess { debugGranted = it }
            .onFailure {
                viewModel.reportHealthConnectActionError(HealthConnectActionError.ACCESS_CHECK_FAILED)
            }
        debugLoaded = true
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                capabilityRefreshGeneration++
                viewModel.refreshPermissions()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // The flavor-owned prompter contains every store SDK reference. F-Droid never emits this
    // request, but an unavailable result also fails open without affecting export success.
    val activity = context as? Activity
    LaunchedEffect(Unit) {
        viewModel.requestReview.collect {
            activity?.let(viewModel::performReviewPrompt) ?: viewModel.onReviewRequestFailed()
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

    // Keep export readiness and quota routing identical in the main action bar and preview.
    val hitExportLimit = !uiState.isPurchased && uiState.freeExportsRemaining <= 0
    val hasSelectedFormat = uiState.hasSelectedFormat
    val canUseExportControls = uiState.hasPermissions &&
            !uiState.historyPermissionNeeded &&
            uiState.destinationReady &&
            uiState.rawProviderSupported &&
            uiState.rawSelectionReady &&
            !uiState.isExporting &&
            !uiState.isPreviewing
    val canRunExportAction = canUseExportControls && hasSelectedFormat
    val canExportAction = canRunExportAction || (hitExportLimit && canUseExportControls)
    val canPreview = uiState.previewEnabled &&
            uiState.healthConnectAvailable &&
            !uiState.healthConnectNeedsSetup &&
            hasSelectedFormat &&
            !uiState.isExporting &&
            !uiState.isPreviewing
    val exportButtonClick = if (hitExportLimit) onNavigateToPaywall else viewModel::startExport

    if (uiState.isExporting) {
        ExportProgressDialog(
            current = uiState.exportProgress,
            total = uiState.exportTotal,
            currentDate = uiState.exportProgressDate,
            rangeStart = uiState.startDate,
            rangeEnd = uiState.endDate,
            exportMode = uiState.settings.exportMode,
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
            formatsPerDay = if (uiState.settings.exportMode == ExportMode.RAW_SNAPSHOT) 1 else uiState.exportFormats.size,
            canExport = canExportAction,
            hitExportLimit = hitExportLimit,
            onExport = {
                if (hitExportLimit) viewModel.dismissPreview()
                exportButtonClick()
            },
            onDismiss = { viewModel.dismissPreview() },
            onCancel = { viewModel.cancelExport() },
        )
    }

    // The measured inset lets the final scroll content clear localized and large-text labels.
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
                    onClick = openHealthConnectInstall,
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
                    onClick = openHealthConnectSettings,
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
                    onClick = {
                        launchHealthPermissionRequest(
                            healthDataPermissionsToRequest,
                            emptySet(),
                        )
                    },
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
                    stringResource(
                        when {
                            historyPermissionAvailable -> R.string.history_permission_required_message
                            historyPermissionCheckFailed -> R.string.health_connect_error_access_check
                            else -> R.string.health_connect_error_history_unavailable
                        }
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                SecondaryButton(
                    text = stringResource(
                        if (historyPermissionAvailable) {
                            R.string.history_permission_grant_button
                        } else {
                            R.string.hc_open_button
                        }
                    ),
                    onClick = if (historyPermissionAvailable) {
                        {
                            launchHealthPermissionRequest(
                                healthDataPermissionsToRequest,
                                permissionPlan.historicalReadPermissions,
                            )
                        }
                    } else {
                        openHealthConnectSettings
                    },
                )
            }
        }

        healthConnectError?.let { error ->
            HealthConnectErrorNotice(
                error = error,
                onDismiss = {
                    dismissedFeatureErrorGeneration = capabilityRefreshGeneration
                    viewModel.clearHealthConnectActionError()
                },
            )
        }

        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
        DateRangeSelectionSection(
            selectedOption = selectedDateRangeOption,
            startDate = uiState.startDate,
            endDate = uiState.endDate,
            onOptionSelected = { option ->
                attemptConfigurationChange {
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
                }
            },
            onStartDateClick = {
                attemptConfigurationChange {
                    selectedDateRangeOption = DateRangeOption.Custom
                    showStartDatePicker = true
                }
            },
            onEndDateClick = {
                attemptConfigurationChange {
                    selectedDateRangeOption = DateRangeOption.Custom
                    showEndDatePicker = true
                }
            },
        )
        }

        val apiFormatLabel = if (uiState.settings.exportMode == ExportMode.RAW_SNAPSHOT) {
            stringResource(
                if (uiState.settings.rawSnapshot.format == com.healthmd.rawexport.RawExportFormat.JSON) {
                    R.string.raw_snapshot_format_json
                } else {
                    R.string.raw_snapshot_format_ndjson
                }
            )
        } else {
            stringResource(R.string.format_display_json)
        }
        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
        ExportTargetSelector(
            selectedTarget = uiState.selectedTarget,
            folderSubtitle = uiState.folderName?.let {
                stringResource(R.string.export_target_folder_selected_subtitle, it)
            } ?: stringResource(R.string.export_target_folder_unselected_subtitle),
            apiSubtitle = if (uiState.apiEndpointConfigured) {
                stringResource(
                    R.string.export_target_api_configured_subtitle,
                    apiFormatLabel,
                    APIExportEndpoint.displayName(uiState.settings.apiEndpointUrl),
                )
            } else if (uiState.settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                stringResource(R.string.export_target_api_raw_unconfigured_subtitle)
            } else {
                stringResource(R.string.export_target_api_json_unconfigured_subtitle)
            },
            onTargetSelected = { target ->
                attemptConfigurationChange {
                    viewModel.setExportTarget(target)
                    if (target == ExportTarget.API_ENDPOINT && !uiState.apiEndpointConfigured) {
                        showAPISettings = true
                    }
                }
            },
        )
        }

        ExportConfigurationSection(
            settings = uiState.settings,
            previewDate = uiState.startDate,
            onExportModeChanged = { value -> attemptConfigurationChange { viewModel.setExportMode(value) } },
            onRawExportFormatChanged = { value -> attemptConfigurationChange { viewModel.setRawExportFormat(value) } },
            onRawScopeChanged = { value -> attemptConfigurationChange { viewModel.setRawSnapshotScope(value) } },
            onRawIncludeExerciseRoutesChanged = { value -> attemptConfigurationChange { viewModel.setRawIncludeExerciseRoutes(value) } },
            onToggleExportFormat = { value -> attemptConfigurationChange { viewModel.toggleExportFormat(value) } },
            onWriteModeChanged = { value -> attemptConfigurationChange { viewModel.updateWriteMode(value) } },
            onFilenameFormatChanged = { value -> attemptConfigurationChange { viewModel.updateFilenameFormat(value) } },
            onSubfolderChanged = { value -> attemptConfigurationChange { viewModel.updateSubfolder(value) } },
            onFolderOrganizationChanged = { value -> attemptConfigurationChange { viewModel.updateFolderOrganization(value) } },
            onFolderStructureChanged = { value -> attemptConfigurationChange { viewModel.updateFolderStructure(value) } },
            onIncludeMetadataChanged = { value -> attemptConfigurationChange { viewModel.updateIncludeMetadata(value) } },
            onGroupByCategoryChanged = { value -> attemptConfigurationChange { viewModel.updateGroupByCategory(value) } },
            onUseEmojiChanged = { value -> attemptConfigurationChange { viewModel.updateUseEmoji(value) } },
            onUnitPreferenceChanged = { value -> attemptConfigurationChange { viewModel.updateUnitPreference(value) } },
            onNavigateToAdvancedSettings = onNavigateToAdvancedSettings,
            onResetSettings = { attemptConfigurationChange(viewModel::resetSettings) },
        )

        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
        if (uiState.selectedTarget == ExportTarget.DEVICE_FOLDER) {
            GeistCardClickable(onClick = {
                attemptConfigurationChange { folderPickerLauncher.launch(null) }
            }) {
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
            GeistCardClickable(onClick = {
                attemptConfigurationChange { showAPISettings = true }
            }) {
                Icon(
                    Icons.Outlined.UploadFile,
                    contentDescription = null,
                    tint = if (uiState.apiEndpointConfigured) AppColors.accent else AppColors.textMuted,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.export_preview_api_destination),
                        style = MaterialTheme.typography.labelSmall,
                        color = AppColors.textMuted,
                    )
                    Text(
                        if (uiState.apiEndpointConfigured) {
                            stringResource(
                                R.string.export_api_post_endpoint,
                                APIExportEndpoint.redactedDescription(uiState.settings.apiEndpointUrl),
                            )
                        } else {
                            stringResource(R.string.export_api_configure_endpoint)
                        },
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                    )
                    if (uiState.apiAuthorizationConfigured) {
                        Text(
                            stringResource(R.string.export_api_authorization_secure),
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.success,
                        )
                    }
                    if (uiState.apiRequestHeadersConfigured) {
                        Text(
                            stringResource(R.string.export_api_headers_secure),
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.success,
                        )
                    }
                    apiConfigurationErrorText?.let { error ->
                        Text(
                            error,
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.error,
                        )
                    }
                    Text(
                        if (uiState.settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                            if (uiState.rawApiEndpointConfigured) {
                                stringResource(R.string.export_api_raw_mode_description)
                            } else {
                                stringResource(R.string.raw_snapshot_https_required)
                            }
                        } else {
                            stringResource(R.string.export_api_compatibility_mode_description)
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
                Text(
                    stringResource(
                        if (uiState.apiEndpointConfigured) {
                            R.string.export_api_action_edit
                        } else {
                            R.string.action_configure_endpoint
                        }
                    ),
                    color = AppColors.accent,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
        }

        if (!uiState.rawProviderSupported || !uiState.rawSelectionReady) {
            GeistCard {
                Text(
                    stringResource(
                        if (!uiState.rawProviderSupported) R.string.raw_snapshot_provider_unsupported else R.string.raw_snapshot_selection_required,
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.error,
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
                val isOpenable = result.artifactCount > 0 && visibleFolderUri != null
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
                            attemptConfigurationChange {
                                selectedDateRangeOption = DateRangeOption.Custom
                                viewModel.setDateRange(startDate, endDate)
                            }
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

                val debugPermissions = permissionPlan.foregroundPermissions +
                    permissionPlan.historicalReadPermissions
                val grantedCount = if (debugLoaded) {
                    "${localizedInteger(debugGranted.intersect(debugPermissions).size)}/${localizedInteger(debugPermissions.size)}"
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
                    stringResource(R.string.debug_first_permission_grant) to (uiState.firstHealthPermissionGrantDate?.let { formatPreviewDate(it) } ?: "—"),
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
                        if (uiState.healthConnectAvailable) {
                            coroutineScope.launch {
                                runCatchingCancellable {
                                    healthConnectManager.getGrantedPermissions()
                                }.onSuccess { debugGranted = it }
                                    .onFailure {
                                        viewModel.reportHealthConnectActionError(
                                            HealthConnectActionError.ACCESS_CHECK_FAILED
                                        )
                                    }
                                debugLoaded = true
                            }
                        } else {
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
            previewUnavailableReason = when {
                uiState.settings.exportMode != ExportMode.RAW_SNAPSHOT -> null
                !uiState.rawProviderSupported -> stringResource(R.string.raw_snapshot_provider_unsupported)
                !uiState.rawSelectionReady -> stringResource(R.string.raw_snapshot_selection_required)
                else -> null
            },
            canExport = canExportAction,
            hitExportLimit = hitExportLimit,
            isExporting = uiState.isExporting,
            onPreview = {
                when {
                    !uiState.hasPermissions -> launchHealthPermissionRequest(
                        healthDataPermissionsToRequest,
                        emptySet(),
                    )
                    uiState.historyPermissionNeeded && historyPermissionAvailable ->
                        launchHealthPermissionRequest(
                            healthDataPermissionsToRequest,
                            permissionPlan.historicalReadPermissions,
                        )
                    uiState.historyPermissionNeeded -> viewModel.reportHealthConnectActionError(
                        if (historyPermissionCheckFailed) {
                            HealthConnectActionError.ACCESS_CHECK_FAILED
                        } else {
                            HealthConnectActionError.HISTORY_UNAVAILABLE
                        }
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
            configurationError = apiConfigurationErrorText,
            onDismiss = {
                showAPISettings = false
                viewModel.clearAPIConfigurationError()
            },
            onSave = { endpoint, authorization, headers ->
                attemptConfigurationChange {
                    viewModel.saveAPIExportConfiguration(endpoint, authorization, headers)
                }
            },
            onClearAuthorization = {
                attemptConfigurationChange(viewModel::clearAPIAuthorization)
            },
            onClearRequestHeaders = {
                attemptConfigurationChange(viewModel::clearAPIRequestHeaders)
            },
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
                        icon = Icons.AutoMirrored.Outlined.Launch,
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
                    attemptConfigurationChange {
                        state.selectedDateMillis?.let { millis ->
                            selectedDateRangeOption = DateRangeOption.Custom
                            viewModel.setStartDate(
                                java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
                            )
                        }
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
                    attemptConfigurationChange {
                        state.selectedDateMillis?.let { millis ->
                            selectedDateRangeOption = DateRangeOption.Custom
                            viewModel.setEndDate(
                                java.time.Instant.ofEpochMilli(millis).atZone(java.time.ZoneOffset.UTC).toLocalDate()
                            )
                        }
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
    previewUnavailableReason: String?,
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
                    stringResource(R.string.export_no_format_selected),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.error,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            previewUnavailableReason?.let { reason ->
                Text(
                    text = reason,
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (!isPurchased) {
                Text(
                    text = pluralStringResource(
                        R.plurals.free_exports_remaining,
                        freeExportsRemaining,
                        freeExportsRemaining,
                    ),
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
            if (result.exportMode == ExportMode.RAW_SNAPSHOT) {
                stringResource(
                    if (result.target == ExportTarget.API_ENDPOINT) R.string.raw_snapshot_result_uploaded else R.string.raw_snapshot_result_created,
                ) + (result.httpStatusCode?.let { " · HTTP $it" } ?: "")
            } else if (result.target == ExportTarget.API_ENDPOINT) {
                pluralStringResource(
                    R.plurals.export_result_uploaded_days,
                    result.totalCount,
                    result.successCount,
                    result.totalCount,
                ) + (result.httpStatusCode?.let { " · HTTP $it" } ?: "")
            } else {
                pluralStringResource(
                    R.plurals.export_result_exported_days,
                    result.totalCount,
                    result.successCount,
                    result.totalCount,
                )
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
    val isRawSnapshot = result.exportMode == ExportMode.RAW_SNAPSHOT
    val failedRangeStart = summary.failedRangeStart.takeUnless { isRawSnapshot }
    val failedRangeEnd = summary.failedRangeEnd.takeUnless { isRawSnapshot }

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
                    if (result.exportMode == ExportMode.RAW_SNAPSHOT) {
                        pluralStringResource(
                            R.plurals.raw_snapshot_result_actions,
                            summary.totalCount,
                            summary.successCount,
                            summary.totalCount,
                        )
                    } else {
                        pluralStringResource(
                            R.plurals.export_result_exported_days,
                            summary.totalCount,
                            summary.successCount,
                            summary.totalCount,
                        )
                    },
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
            if (isRawSnapshot) {
                pluralStringResource(
                    R.plurals.raw_snapshot_diagnostics_failed_actions,
                    summary.failedDayCount,
                    summary.failedDayCount,
                )
            } else {
                pluralStringResource(
                    R.plurals.export_diagnostics_failed_days,
                    summary.failedDayCount,
                    summary.failedDayCount,
                )
            },
            style = MaterialTheme.typography.bodyMedium,
            color = statusColor,
            fontWeight = FontWeight.Medium,
        )

        if (summary.wasCancelled) {
            Spacer(modifier = Modifier.height(Spacing.xs))
            Text(
                stringResource(
                    if (isRawSnapshot) R.string.raw_snapshot_diagnostics_cancelled_message else R.string.export_diagnostics_cancelled_message,
                ),
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
                        ExportFailureGroup(group = group, isRawSnapshot = isRawSnapshot)
                    }
                }
            }
        } else {
            Text(
                stringResource(
                    if (isRawSnapshot) R.string.raw_snapshot_diagnostics_no_details else R.string.export_diagnostics_no_details,
                ),
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
private fun ExportFailureGroup(
    group: ExportFailureDiagnosticGroup,
    isRawSnapshot: Boolean,
) {
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
            if (isRawSnapshot) {
                pluralStringResource(
                    R.plurals.raw_snapshot_diagnostics_reason_actions,
                    group.count,
                    group.failureReasonLabel(),
                    group.count,
                )
            } else {
                pluralStringResource(
                    R.plurals.export_diagnostics_reason_days,
                    group.count,
                    group.failureReasonLabel(),
                    group.count,
                )
            },
            style = MaterialTheme.typography.labelLarge,
            color = AppColors.textPrimary,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            group.guidanceText(),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
        )
        if (!isRawSnapshot && group.sampleDates.isNotEmpty()) {
            Text(
                group.dateSampleText(),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }
    }
}

@Composable
fun ExportFailureDiagnosticGroup.failureReasonLabel(): String = reason.localizedFailureLabel()

@Composable
private fun ExportFailureReason.localizedFailureLabel(): String =
    when (this) {
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
        ExportFailureReason.RAW_UNSUPPORTED_PROVIDER -> stringResource(R.string.raw_snapshot_provider_unsupported)
        ExportFailureReason.RAW_PARTIAL -> stringResource(R.string.raw_snapshot_partial_label)
        ExportFailureReason.RAW_CANCELLED -> stringResource(R.string.raw_snapshot_cancelled_label)
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
        ExportDiagnosticGuidance.RAW_PROVIDER -> stringResource(R.string.raw_snapshot_guidance_provider)
        ExportDiagnosticGuidance.RAW_CANCELLED -> stringResource(R.string.raw_snapshot_guidance_cancelled)
        ExportDiagnosticGuidance.UNKNOWN -> stringResource(R.string.export_guidance_unknown)
    }

@Composable
fun ExportFailureDiagnosticGroup.dateSampleText(): String {
    val formatter = localizedMediumDateFormatter()
    val dates = sampleDates.joinToString(", ") { it.format(formatter) }
    return if (remainingDateCount > 0) {
        pluralStringResource(
            R.plurals.export_diagnostics_date_list_more_count,
            remainingDateCount,
            dates,
            remainingDateCount,
        )
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
    canExport: Boolean,
    hitExportLimit: Boolean,
    onExport: () -> Unit,
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
                            contentDescription = stringResource(R.string.export_preview_back_description),
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
            if (!isLoading && preview != null) {
                Button(
                    onClick = onExport,
                    enabled = canExport,
                    shape = RoundedCornerShape(Radii.button),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = AppColors.textPrimary,
                        contentColor = AppColors.bgPrimary,
                        disabledContainerColor = AppColors.bgTertiary,
                        disabledContentColor = AppColors.textMuted,
                    ),
                ) {
                    Icon(Icons.Outlined.UploadFile, contentDescription = null)
                    Spacer(modifier = Modifier.width(Spacing.xs))
                    Text(
                        stringResource(
                            if (hitExportLimit) R.string.unlock_button else R.string.export_button
                        )
                    )
                }
            } else {
                TextButton(onClick = closePreview) {
                    Text(stringResource(R.string.export_preview_done), color = AppColors.accent)
                }
            }
        },
        dismissButton = {
            if (!isLoading && preview != null) {
                TextButton(onClick = closePreview) {
                    Text(stringResource(R.string.export_preview_done), color = AppColors.textSecondary)
                }
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
            isRangeArtifact = preview.isRangeArtifact,
            artifactCount = preview.totalFileCount,
        )

        Text(
            if (preview.isRangeArtifact) {
                stringResource(
                    R.string.export_preview_summary,
                    dayCountLabel(preview.requestedDateCount),
                    artifactCountLabel(preview.totalFileCount),
                    formatBytes(preview.totalByteCount),
                )
            } else {
                stringResource(
                    R.string.export_preview_summary,
                    previewedDayCountLabel(preview.previewedDateCount, preview.requestedDateCount),
                    fileCountLabel(preview.totalFileCount),
                    formatBytes(preview.totalByteCount),
                )
            },
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )
        if (!preview.isRangeArtifact && preview.isTruncated && preview.previewedDateCount > 0) {
            Text(
                pluralStringResource(
                    R.plurals.export_preview_limited_days,
                    preview.previewedDateCount,
                    preview.previewedDateCount,
                ),
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
                if (preview.isRangeArtifact) formatPreviewDateRange(day.requestedDates) else formatPreviewDate(day.date),
                style = MaterialTheme.typography.labelLarge,
                color = AppColors.textMuted,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(top = Spacing.xs),
            )

            day.failureReason?.let { reason ->
                PreviewStatusCard(
                    title = reason.localizedFailureLabel(),
                    message = day.issues.takeIf { it.isNotEmpty() }
                        ?.map { it.localizedMessage() }
                        ?.joinToString("\n")
                        ?: stringResource(R.string.export_preview_no_exportable_file),
                    color = AppColors.error,
                )
            }
            if (day.failureReason == null && day.issues.isNotEmpty()) {
                PreviewStatusCard(
                    title = stringResource(R.string.export_preview_warning_title),
                    message = day.issues.map { it.localizedMessage() }.joinToString("\n"),
                    color = AppColors.warning,
                )
            }

            day.files.forEach { file ->
                val details = PreviewFileDetails(
                    title = file.relativePath.substringAfterLast('/'),
                    subtitle = "${file.formatLabel ?: file.format.localizedDisplayName()} · ${formatBytes(file.byteCount)}",
                    relativePath = file.relativePath,
                    byteCount = file.byteCount,
                    content = file.content,
                    previewOmittedByteCount = file.previewOmittedByteCount,
                    previewTailContent = file.previewTailContent,
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
                    subtitle = effect.action.localizedAction() + if (effect.wouldWrite) " · ${formatBytes(effect.byteCount)}" else "",
                    relativePath = effect.relativePath,
                    byteCount = effect.byteCount,
                    content = effect.content.orEmpty(),
                    previewOmittedByteCount = 0,
                    previewTailContent = "",
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
    isRangeArtifact: Boolean,
    artifactCount: Int,
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
        PreviewSummaryRow(stringResource(R.string.section_date_range), dayCountLabel(requestedDayCount))
        PreviewSummaryRow(
            stringResource(
                if (isRangeArtifact) {
                    R.string.export_preview_artifacts_per_range
                } else {
                    R.string.export_preview_formats_per_day
                }
            ),
            localizedInteger(if (isRangeArtifact) artifactCount else formatsPerDay),
        )
        PreviewSummaryRow(
            stringResource(R.string.export_preview_destination_label),
            destinationLabel ?: stringResource(R.string.export_preview_selected_folder),
        )
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
                    Icons.AutoMirrored.Outlined.ArrowForwardIos,
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
    val displayContent = remember(
        file.content,
        file.previewTailContent,
        file.byteCount,
        file.previewOmittedByteCount,
    ) {
        if (file.previewOmittedByteCount > 0) {
            ExportPreviewDisplayContent(
                text = file.content,
                tailText = file.previewTailContent,
                originalByteCount = file.byteCount,
                omittedByteCount = file.previewOmittedByteCount,
            )
        } else {
            ExportPreviewDisplayContent.make(file.content)
        }
    }
    val renderedContent = displayContent.render(
        emptyFileLabel = stringResource(R.string.export_preview_empty_file),
        truncationMarker = stringResource(
            R.string.export_preview_truncation_marker,
            formatBytes(displayContent.omittedByteCount),
            formatBytes(displayContent.originalByteCount),
        ),
    )

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
                renderedContent,
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
    val previewOmittedByteCount: Int,
    val previewTailContent: String,
    val isWritable: Boolean,
)

@Composable
private fun dayCountLabel(days: Int): String = pluralStringResource(
    R.plurals.export_preview_day_count,
    days,
    days,
)

@Composable
private fun previewedDayCountLabel(previewed: Int, requested: Int): String = pluralStringResource(
    R.plurals.export_preview_days_previewed,
    requested,
    previewed,
    requested,
)

@Composable
private fun artifactCountLabel(artifacts: Int): String = pluralStringResource(
    R.plurals.export_preview_artifact_count,
    artifacts,
    artifacts,
)

@Composable
private fun fileCountLabel(files: Int): String = pluralStringResource(
    R.plurals.export_preview_file_count,
    files,
    files,
)

@Composable
private fun localizedInteger(value: Int): String =
    NumberFormat.getIntegerInstance(LocalConfiguration.current.locales[0]).format(value)

@Composable
private fun localizedMediumDateFormatter(): DateTimeFormatter =
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
        .withLocale(LocalConfiguration.current.locales[0])

@Composable
private fun formatPreviewDate(date: LocalDate): String = date.format(localizedMediumDateFormatter())

@Composable
private fun formatPreviewDateRange(dates: List<LocalDate>): String = when {
    dates.isEmpty() -> stringResource(R.string.export_preview_selected_range)
    dates.size == 1 -> formatPreviewDate(dates.single())
    else -> stringResource(
        R.string.export_selected_range,
        formatPreviewDate(dates.first()),
        formatPreviewDate(dates.last()),
    )
}

@Composable
private fun formatCompactDate(date: LocalDate): String = date.format(
    DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT)
        .withLocale(LocalConfiguration.current.locales[0]),
)

private fun LocalDate.toDatePickerMillis(): Long =
    atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()

private fun parentPathLabel(relativePath: String, destinationLabel: String?): String? {
    val parent = relativePath.substringBeforeLast('/', missingDelimiterValue = "")
    if (parent.isBlank()) return destinationLabel
    return listOfNotNull(destinationLabel?.takeIf { it.isNotBlank() }, parent.trim('/'))
        .joinToString("/") + "/"
}

@Composable
private fun formatBytes(bytes: Int): String =
    Formatter.formatFileSize(LocalContext.current, bytes.coerceAtLeast(0).toLong())

@Composable
private fun APIConfigurationIssue.localizedText(): String = stringResource(
    when (this) {
        APIConfigurationIssue.INVALID_ENDPOINT -> R.string.export_api_error_invalid_endpoint
        APIConfigurationIssue.INVALID_HEADERS -> R.string.export_api_error_invalid_headers
        APIConfigurationIssue.SECURE_SAVE_FAILED -> R.string.export_api_error_secure_save
    }
)

@Composable
private fun localizedProviderName(providerId: String?): String = stringResource(
    when (providerId) {
        "health_connect" -> R.string.health_provider_label_health_connect
        "all_connected" -> R.string.health_provider_label_all_connected
        "fitbit" -> R.string.health_provider_label_fitbit
        "withings" -> R.string.health_provider_label_withings
        "oura" -> R.string.health_provider_label_oura
        "polar" -> R.string.health_provider_label_polar
        "whoop" -> R.string.health_provider_label_whoop
        else -> R.string.health_provider_label_generic
    },
)

@Composable
private fun ExportPreviewIssue.localizedMessage(): String = when (kind) {
    ExportPreviewIssueKind.NO_FORMATS_SELECTED -> stringResource(R.string.export_no_format_selected)
    ExportPreviewIssueKind.NO_FILES_WRITTEN -> stringResource(R.string.export_preview_no_files_written)
    ExportPreviewIssueKind.PLANNING_FAILED -> stringResource(R.string.export_preview_planning_failed)
    ExportPreviewIssueKind.API_PREPARATION_FAILED -> stringResource(R.string.export_preview_api_preparation_failed)
    ExportPreviewIssueKind.RAW_PREVIEW_SERVICE_UNAVAILABLE -> stringResource(R.string.export_preview_raw_service_unavailable)
    ExportPreviewIssueKind.RAW_INVALID_DATE_RANGE -> stringResource(R.string.export_preview_raw_invalid_range)
    ExportPreviewIssueKind.RAW_SELECTION_REQUIRED -> stringResource(R.string.raw_snapshot_selection_required)
    ExportPreviewIssueKind.RAW_PROVIDER_UNAVAILABLE -> stringResource(R.string.export_preview_raw_provider_unavailable)
    ExportPreviewIssueKind.RAW_PROVIDER_UNREGISTERED -> stringResource(
        R.string.export_preview_raw_provider_unregistered,
        localizedProviderName(providerId),
    )
    ExportPreviewIssueKind.RAW_PARTIAL -> stringResource(
        R.string.export_preview_raw_partial,
        localizedProviderName(providerId),
    )
    ExportPreviewIssueKind.RAW_FAILED_MANIFEST -> stringResource(
        R.string.export_preview_raw_failed_manifest,
        localizedProviderName(providerId),
    )
    ExportPreviewIssueKind.RAW_NO_FINAL_STATUS -> stringResource(
        R.string.export_preview_raw_no_final_status,
        localizedProviderName(providerId),
    )
    ExportPreviewIssueKind.RAW_ACCESS_DENIED -> stringResource(
        R.string.export_preview_raw_access_denied,
        localizedProviderName(providerId),
    )
    ExportPreviewIssueKind.RAW_PREVIEW_FAILED -> stringResource(
        R.string.export_preview_raw_failed,
        localizedProviderName(providerId),
    )
}

@Composable
private fun ExportPreviewSideEffectAction.localizedAction(): String = stringResource(
    when (this) {
        ExportPreviewSideEffectAction.UPDATE_DAILY_NOTE -> R.string.export_preview_action_update_daily_note
        ExportPreviewSideEffectAction.CREATE_DAILY_NOTE -> R.string.export_preview_action_create_daily_note
        ExportPreviewSideEffectAction.SKIP_DAILY_NOTE -> R.string.export_preview_action_skip_daily_note
        ExportPreviewSideEffectAction.DAILY_NOTE_FAILED -> R.string.export_preview_action_daily_note_failed
        ExportPreviewSideEffectAction.WRITE_INDIVIDUAL_ENTRY -> R.string.export_preview_action_write_individual_entry
    }
)
