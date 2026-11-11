package com.healthmd.presentation.export

import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.text.style.TextIndent
import androidx.compose.ui.text.ParagraphStyle
import androidx.compose.material.icons.outlined.DataObject
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.runtime.produceState
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.outlined.WrapText
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.IconToggleButton
import androidx.compose.material3.Surface
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.common.EdgeToEdgeDialogWindow
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.dialogNavigationBarsPadding
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.LocalGeistColors
import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.compose.ui.platform.testTag
import com.healthmd.presentation.export.components.ExportDecisionAction
import com.healthmd.presentation.export.components.ExportDecisionDialog
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
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.ExpandLess
import androidx.compose.material.icons.outlined.ExpandMore
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
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
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.presentation.common.HealthDatePicker
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
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
import com.healthmd.domain.model.AgentDataGatewayEndpoint
import com.healthmd.domain.model.AgentDataArtifactOutcome
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.model.ExportPreviewIssue
import com.healthmd.domain.model.ExportPreviewIssueKind
import com.healthmd.domain.model.ExportPreviewSideEffectAction
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthMetricCategory
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.presentation.common.*
import com.healthmd.presentation.export.components.ExportProgressDialog
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistElevation
import com.healthmd.presentation.theme.GeistMono
import com.healthmd.presentation.theme.GeistType
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
    onNavigateToSchedule: () -> Unit = {},
    onNavigateToUpgrade: () -> Unit = onNavigateToPaywall,
    sleepDayAttribution: SleepDayAttribution = SleepDayAttribution.DEFAULT,
    /** Set when Export now opens over the Archive; shows Back and the screen title. */
    onBack: (() -> Unit)? = null,
    /** Presets the range to this one date (Backfill from the Archive), once per entry. */
    backfillDate: LocalDate? = null,
    /** Shown as the Export now bottom sheet: a title row with Close instead of Back. */
    asSheet: Boolean = false,
    /** Optional control under the sheet title, such as the profile segmented buttons. */
    profileSelector: (@Composable () -> Unit)? = null,
    /** "See in archive" on the finished Export moment; null hides it. */
    onSeeInArchive: (() -> Unit)? = null,
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val clinicAccess: com.healthmd.presentation.clinic.ClinicAccessViewModel = hiltViewModel()
    val clinicStatus by clinicAccess.status.collectAsStateWithLifecycle()
    val independentAccess by clinicAccess.independentAccess.collectAsStateWithLifecycle()
    val managedClinicEndpoint = clinicStatus.endpoint.takeIf { clinicStatus.active && !independentAccess }
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

    var showStartDatePicker by rememberSaveable { mutableStateOf(false) }
    var showEndDatePicker by rememberSaveable { mutableStateOf(false) }
    var showAPISettings by remember { mutableStateOf(false) }
    var showGatewaySettings by remember { mutableStateOf(false) }
    var selectedDateRangeOption by rememberSaveable {
        mutableStateOf(
            DateRangeOption.fromDates(
                startDate = uiState.startDate,
                endDate = uiState.endDate,
                allTimeSelected = uiState.allTimeSelected,
            )
        )
    }
    var backfillApplied by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(backfillDate) {
        if (backfillApplied) return@LaunchedEffect
        if (backfillDate != null) {
            viewModel.setDateRange(backfillDate, backfillDate)
            selectedDateRangeOption = DateRangeOption.Custom
        } else if (asSheet) {
            // As on iOS, Export now opens on Yesterday unless it was asked for other dates.
            val (start, end) = requireNotNull(ExportNowFlow.presetDates(DateRangeOption.Yesterday, LocalDate.now()))
            viewModel.setDateRange(start, end)
            selectedDateRangeOption = DateRangeOption.Yesterday
        }
        backfillApplied = true
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
    val hitExportLimit = !uiState.isPurchased && !uiState.clinicDestinationAuthorized && uiState.freeExportsRemaining <= 0
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
    val previewClick: () -> Unit = {
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
    }
    var confirmLargeExport by rememberSaveable { mutableStateOf(false) }
    val requestedExportDays = remember(uiState.startDate, uiState.endDate) {
        java.time.temporal.ChronoUnit.DAYS.between(uiState.startDate, uiState.endDate).toInt() + 1
    }
    val exportButtonClick: () -> Unit = when {
        hitExportLimit -> onNavigateToPaywall
        // A long range writes many files and takes minutes: confirm before starting.
        isLargeExport(requestedExportDays, uiState.settings.exportMode) -> { { confirmLargeExport = true } }
        else -> viewModel::startExport
    }
    if (confirmLargeExport) {
        val files = requestedExportDays * uiState.exportFormats.size.coerceAtLeast(1)
        ExportDecisionDialog(
            title = pluralStringResource(R.plurals.large_export_title, requestedExportDays, requestedExportDays),
            message = pluralStringResource(R.plurals.large_export_body, files, files),
            actions = listOf(
                ExportDecisionAction(
                    title = pluralStringResource(R.plurals.large_export_confirm, requestedExportDays, requestedExportDays),
                    role = ExportDecisionAction.Role.PRIMARY,
                    testTag = "export.now.largeConfirm",
                ) {
                    confirmLargeExport = false
                    viewModel.startExport()
                },
                ExportDecisionAction(title = stringResource(R.string.cancel)) { confirmLargeExport = false },
            ),
        )
    }

    uiState.postExportMilestone?.takeIf { !uiState.isPurchased }?.let { milestone ->
        PostExportGuidanceDialog(
            milestone = milestone,
            remaining = uiState.freeExportsRemaining,
            onSchedule = {
                viewModel.dismissPostExportGuidance()
                onNavigateToSchedule()
            },
            onUpgrade = {
                viewModel.dismissPostExportGuidance()
                onNavigateToUpgrade()
            },
            onDismiss = viewModel::dismissPostExportGuidance,
        )
    }

    // The moment stays up, full, after a run that wrote every day; partial, failed and
    // cancelled runs go straight to the result below, which explains them.
    var sawExport by remember { mutableStateOf(false) }
    var finishedRun by remember { mutableStateOf<ExportResult?>(null) }
    LaunchedEffect(uiState.isExporting, uiState.lastResult) {
        if (uiState.isExporting) {
            sawExport = true
            finishedRun = null
        } else if (sawExport) {
            sawExport = false
            finishedRun = uiState.lastResult?.takeIf(::momentShowsDone)
        }
    }
    val doneRun = finishedRun
    if (uiState.isExporting || doneRun != null) {
        ExportProgressDialog(
            current = doneRun?.successCount ?: uiState.exportProgress,
            total = doneRun?.totalCount ?: uiState.exportTotal,
            currentDate = if (doneRun != null) null else uiState.exportProgressDate,
            rangeStart = uiState.startDate,
            rangeEnd = uiState.endDate,
            exportMode = uiState.settings.exportMode,
            onCancel = { viewModel.cancelExport() },
            isDone = doneRun != null,
            onSeeInArchive = onSeeInArchive?.let { open -> { finishedRun = null; open() } },
            onClose = { finishedRun = null },
            doneSubtitle = doneRun?.let { momentDoneSubtitle(it, uiState.startDate, uiState.endDate) },
        )
    }

    val previewDestinationLabel = uiState.destinationLabel ?: stringResource(
        when (uiState.selectedTarget) {
            ExportTarget.API_ENDPOINT -> R.string.export_preview_api_destination
            ExportTarget.AGENT_DATA_GATEWAY -> R.string.export_preview_gateway_destination
            ExportTarget.DEVICE_FOLDER -> R.string.export_preview_device_destination
        }
    )
    val previewFormatsPerDay = if (uiState.settings.exportMode == ExportMode.RAW_SNAPSHOT) 1 else uiState.exportFormats.size
    val previewExport: () -> Unit = {
        if (hitExportLimit) viewModel.dismissPreview()
        exportButtonClick()
    }
    val previewShown = uiState.isPreviewing || uiState.preview != null
    if (previewShown && !asSheet) {
        ExportPreviewDialog(
            preview = uiState.preview,
            isLoading = uiState.isPreviewing,
            destinationLabel = uiState.destinationLabel ?: stringResource(
                when (uiState.selectedTarget) {
                    ExportTarget.API_ENDPOINT -> R.string.export_preview_api_destination
                    ExportTarget.AGENT_DATA_GATEWAY -> R.string.export_preview_gateway_destination
                    ExportTarget.DEVICE_FOLDER -> R.string.export_preview_device_destination
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

    // Inside the sheet, as on iOS, the preview is pushed over the form and a run that did not
    // write every day ends on its result.
    val sheetResult = uiState.lastResult?.takeIf { asSheet && !uiState.isExporting && ExportNowFlow.showsResultSheet(it) }
    if (asSheet && previewShown) {
        ExportPreviewPage(
            preview = uiState.preview,
            isLoading = uiState.isPreviewing,
            destinationLabel = previewDestinationLabel,
            formatsPerDay = previewFormatsPerDay,
            canExport = canExportAction,
            hitExportLimit = hitExportLimit,
            onExport = previewExport,
            onDismiss = { viewModel.dismissPreview() },
            onCancel = { viewModel.cancelExport() },
            pushed = true,
        )
    } else if (sheetResult != null) {
        val folderUri = uiState.exportedFolderUri
        ExportResultContent(
            result = sheetResult,
            rangeStart = uiState.startDate,
            rangeEnd = uiState.endDate,
            profileName = profilesViewModel.uiState.collectAsStateWithLifecycle().value.activeProfileName,
            onRetry = { start, end ->
                viewModel.dismissResult()
                selectedDateRangeOption = DateRangeOption.Custom
                viewModel.setDateRange(start, end)
            },
            onShowInFiles = folderUri?.takeIf {
                sheetResult.target == ExportTarget.DEVICE_FOLDER && sheetResult.artifactCount > 0
            }?.let { uri -> { openInFiles(uri) } },
            onDone = {
                viewModel.dismissResult()
                onBack?.invoke()
            },
        )
    } else Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.md)
                .padding(
                    top = if (asSheet) 0.dp else Spacing.lg,
                    bottom = floatingActionBarHeight + Spacing.lg,
                ),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
        if (asSheet && onBack != null) {
            // As on iOS: a plain-text Cancel beside the centred title.
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    text = stringResource(R.string.export_now_title),
                    style = GeistType.heading16,
                    color = AppColors.textPrimary,
                    modifier = Modifier.semantics { heading() },
                )
                TextButton(
                    onClick = onBack,
                    modifier = Modifier.align(Alignment.CenterStart).testTag("export.now.cancel"),
                ) {
                    Text(stringResource(R.string.cancel), style = GeistType.label16, color = AppColors.textSecondary)
                }
            }
            profileSelector?.invoke()
        } else if (onBack != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        Icons.AutoMirrored.Outlined.ArrowBack,
                        contentDescription = stringResource(R.string.back),
                        tint = AppColors.textPrimary,
                    )
                }
                Text(
                    text = stringResource(R.string.export_now_title),
                    style = MaterialTheme.typography.headlineSmall,
                    color = AppColors.textPrimary,
                )
            }
        } else {
        Spacer(modifier = Modifier.height(Spacing.md))
        }

        if (onBack == null) Row(
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

        // The sheet names its destination in "Will write"; Health Connect problems show as cards.
        if (!asSheet) {
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
        }

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

        // The dates are a one-off choice for this run, not saved configuration, so Lock
        // configuration never blocks them (as on iOS).
        DateRangeSelectionSection(
            sleepDayAttribution = sleepDayAttribution,
            selectedOption = selectedDateRangeOption,
            showSleepGuidance = uiState.settings.exportMode != ExportMode.RAW_SNAPSHOT &&
                uiState.settings.metricSelection.enabledMetricCount(HealthMetricCategory.SLEEP) > 0,
            startDate = uiState.startDate,
            endDate = uiState.endDate,
            onOptionSelected = { option ->
                selectedDateRangeOption = option
                val preset = ExportNowFlow.presetDates(option, LocalDate.now())
                when {
                    preset != null -> viewModel.setDateRange(preset.first, preset.second)
                    option == DateRangeOption.AllTime -> viewModel.selectAllTime()
                    else -> viewModel.setDateRange(uiState.startDate, uiState.endDate)
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

        if (asSheet) {
            ExportWillWriteCard(
                destination = willWriteDestination(uiState),
                summary = willWriteSummary(uiState, requestedExportDays),
                canPreview = canPreview,
                onPreview = previewClick,
            )
            if (ExportNowFlow.showsLargeExportBanner(requestedExportDays, uiState.settings.exportMode)) {
                ExportNowBanner(
                    title = stringResource(R.string.export_now_large_title),
                    message = stringResource(R.string.export_now_large_body),
                )
            }
            // No "More options": the profile decides where and how the export writes. A run
            // that cannot reach its destination says so here, with the one action that fixes it.
            val destinationReady by rememberUpdatedState(uiState.destinationReady)
            var settled by remember { mutableStateOf(false) }
            LaunchedEffect(Unit) {
                // Settings load just after the sheet opens; do not flash the setup card.
                kotlinx.coroutines.delay(800)
                settled = true
            }
            if (settled && !destinationReady) {
                ExportDestinationSetupCard(
                    target = uiState.selectedTarget,
                    onSetUp = {
                        attemptConfigurationChange {
                            when (uiState.selectedTarget) {
                                ExportTarget.DEVICE_FOLDER -> folderPickerLauncher.launch(null)
                                ExportTarget.API_ENDPOINT -> showAPISettings = true
                                ExportTarget.AGENT_DATA_GATEWAY -> showGatewaySettings = true
                            }
                        }
                    },
                )
            }
            // Without profiles to choose between, the sheet still lets the run pick among the
            // destinations that are already set up.
            val configuredTargets = listOfNotNull(
                ExportTarget.DEVICE_FOLDER.takeIf { uiState.folderName != null },
                ExportTarget.API_ENDPOINT.takeIf { uiState.apiEndpointConfigured },
                ExportTarget.AGENT_DATA_GATEWAY.takeIf { uiState.agentDataGatewayConfigured },
            )
            val profileState by profilesViewModel.uiState.collectAsStateWithLifecycle()
            if (profileState.rows.size < 2 && configuredTargets.size >= 2 && managedClinicEndpoint == null) {
                ExportNowDestinationChoice(
                    targets = configuredTargets,
                    selected = uiState.selectedTarget,
                    onSelect = { target -> attemptConfigurationChange { viewModel.setExportTarget(target) } },
                )
            }
        }

        if (!asSheet) {
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
            managedClinicEndpoint = managedClinicEndpoint,
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
            gatewaySubtitle = if (uiState.agentDataGatewayConfigured) {
                stringResource(
                    R.string.export_target_gateway_configured_subtitle,
                    AgentDataGatewayEndpoint.displayName(uiState.settings.agentDataGatewayUrl),
                )
            } else {
                stringResource(R.string.export_target_gateway_unconfigured_subtitle)
            },
            onTargetSelected = { target ->
                attemptConfigurationChange {
                    viewModel.setExportTarget(target)
                    if (target == ExportTarget.API_ENDPOINT && !uiState.apiEndpointConfigured) {
                        showAPISettings = true
                    }
                    if (target == ExportTarget.AGENT_DATA_GATEWAY && !uiState.agentDataGatewayConfigured) {
                        showGatewaySettings = true
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
        } else if (uiState.selectedTarget == ExportTarget.API_ENDPOINT) {
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
        } else if (uiState.selectedTarget == ExportTarget.AGENT_DATA_GATEWAY) {
            GeistCardClickable(onClick = {
                attemptConfigurationChange { showGatewaySettings = true }
            }) {
                Icon(
                    Icons.Outlined.UploadFile,
                    contentDescription = null,
                    tint = if (uiState.agentDataGatewayConfigured) AppColors.accent else AppColors.textMuted,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.export_preview_gateway_destination),
                        style = MaterialTheme.typography.labelSmall,
                        color = AppColors.textMuted,
                    )
                    Text(
                        if (uiState.agentDataGatewayConfigured) {
                            AgentDataGatewayEndpoint.redactedDescription(uiState.settings.agentDataGatewayUrl)
                        } else {
                            stringResource(R.string.export_target_gateway_unconfigured_subtitle)
                        },
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                    )
                    apiConfigurationErrorText?.let { error ->
                        Text(
                            error,
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.error,
                        )
                    }
                }
                Text(
                    stringResource(
                        if (uiState.agentDataGatewayConfigured) {
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

                // Per-artifact Agent Data gateway outcomes (health-free labels).
                if (result.agentDataOutcomes.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(Spacing.xs))
                    GeistCard {
                        Column(
                            modifier = Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
                        ) {
                            Text(
                                stringResource(R.string.agent_data_gateway_outcomes_title),
                                style = MaterialTheme.typography.labelSmall,
                                color = AppColors.textMuted,
                            )
                            result.agentDataOutcomes.forEach { outcome ->
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Text(
                                        text = outcome.relativePath.substringAfterLast('/'),
                                        style = GeistType.copy13Mono,
                                        color = AppColors.textPrimary,
                                        modifier = Modifier.weight(1f),
                                    )
                                    val label = when (outcome.state) {
                                        AgentDataArtifactOutcome.State.ACCEPTED ->
                                            stringResource(R.string.agent_data_gateway_outcome_accepted)
                                        AgentDataArtifactOutcome.State.REJECTED ->
                                            stringResource(
                                                R.string.agent_data_gateway_outcome_rejected,
                                                outcome.rejectionCode.orEmpty(),
                                            )
                                        AgentDataArtifactOutcome.State.UPLOAD_FAILED ->
                                            stringResource(R.string.agent_data_gateway_outcome_upload_failed)
                                    }
                                    Text(
                                        text = label,
                                        style = GeistType.copy13,
                                        color = when (outcome.state) {
                                            AgentDataArtifactOutcome.State.ACCEPTED -> AppColors.success
                                            else -> AppColors.error
                                        },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // Debug panel: diagnostics for development builds only.
        if (BuildConfig.DEBUG) GeistCard {
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

        val previewUnavailableReason = when {
            uiState.settings.exportMode != ExportMode.RAW_SNAPSHOT -> null
            !uiState.rawProviderSupported -> stringResource(R.string.raw_snapshot_provider_unsupported)
            !uiState.rawSelectionReady -> stringResource(R.string.raw_snapshot_selection_required)
            else -> null
        }
        if (asSheet) {
            // The board's single 56dp call to action; Preview sits in the "Will write" card.
            ExportNowCta(
                label = when {
                    hitExportLimit -> stringResource(R.string.unlock_button)
                    selectedDateRangeOption == DateRangeOption.Yesterday -> stringResource(R.string.export_now_cta_yesterday)
                    else -> pluralStringResource(R.plurals.export_now_cta_days, requestedExportDays, requestedExportDays)
                },
                // Clinic-sponsored delivery has no free-export allowance to show.
                isPurchased = uiState.isPurchased || uiState.clinicDestinationAuthorized,
                freeExportsRemaining = uiState.freeExportsRemaining,
                hasSelectedFormat = hasSelectedFormat,
                notice = previewUnavailableReason,
                enabled = canExportAction,
                isExporting = uiState.isExporting,
                onExport = exportButtonClick,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .onSizeChanged { floatingActionBarHeightPx = it.height },
            )
        } else FloatingExportActionBar(
            clinicDestinationAuthorized = uiState.clinicDestinationAuthorized,
            isPurchased = uiState.isPurchased,
            freeExportsRemaining = uiState.freeExportsRemaining,
            hasSelectedFormat = hasSelectedFormat,
            canPreview = canPreview,
            previewUnavailableReason = previewUnavailableReason,
            canExport = canExportAction,
            hitExportLimit = hitExportLimit,
            isExporting = uiState.isExporting,
            onPreview = previewClick,
            onExport = exportButtonClick,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .onSizeChanged { floatingActionBarHeightPx = it.height },
        )
    }

    if (showAPISettings) {
        APIExportSettingsDialog(
            managedClinicEndpoint = managedClinicEndpoint,
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

    if (showGatewaySettings) {
        AgentDataGatewaySettingsDialog(
            initialEndpointUrl = uiState.settings.agentDataGatewayUrl,
            configurationError = apiConfigurationErrorText,
            onDismiss = {
                showGatewaySettings = false
                viewModel.clearAPIConfigurationError()
            },
            onSave = { endpoint ->
                attemptConfigurationChange {
                    viewModel.saveAgentDataGatewayConfiguration(endpoint)
                }
            },
        )
    }

    // Open-with dialog (shown when Obsidian is installed)
    if (showOpenDialog) {
        val openDialogColors = LocalGeistColors.current
        AlertDialog(
            onDismissRequest = { showOpenDialog = false },
            containerColor = openDialogColors.gray.c200,
            shape = RoundedCornerShape(GeistRadii.large),
            icon = {
                Box(
                    Modifier
                        .size(GeistSizes.controlLarge)
                        .background(openDialogColors.brandSubtle, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Outlined.FolderOpen, contentDescription = null, tint = openDialogColors.brandOnSubtle)
                }
            },
            title = {
                Text(
                    stringResource(R.string.open_folder),
                    style = GeistType.heading20,
                    color = openDialogColors.primary,
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
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
                    Text(
                        stringResource(R.string.action_close_options),
                        style = GeistType.button14,
                        color = openDialogColors.brandPrimary,
                    )
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
                TextButton(enabled = state.selectedDateMillis != null, onClick = {
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
        ) { HealthDatePicker(state = state) }
    }
    if (showEndDatePicker) {
        val state = rememberDatePickerState(initialSelectedDateMillis = uiState.endDate.toDatePickerMillis())
        DatePickerDialog(
            onDismissRequest = { showEndDatePicker = false },
            confirmButton = {
                TextButton(enabled = state.selectedDateMillis != null, onClick = {
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
        ) { HealthDatePicker(state = state) }
    }
}

/** Files one export writes: one per day and format, or one per day for raw snapshots. */
internal fun willWriteFileCount(state: ExportUiState, days: Int): Int =
    if (state.settings.exportMode == ExportMode.RAW_SNAPSHOT) days else days * state.exportFormats.size.coerceAtLeast(1)

/** The destination line: the folder path, `POST host/path`, or the gateway host. */
@Composable
private fun willWriteDestination(state: ExportUiState): String = when (state.selectedTarget) {
    ExportTarget.DEVICE_FOLDER -> state.folderName?.let { "$it/" }
        ?: stringResource(R.string.export_target_folder_unselected_subtitle)
    ExportTarget.API_ENDPOINT -> com.healthmd.presentation.archive.ArchiveCoverage.endpointLine(state.settings.apiEndpointUrl)
        ?: stringResource(R.string.export_target_api_json_unconfigured_subtitle)
    ExportTarget.AGENT_DATA_GATEWAY -> state.destinationLabel?.takeIf { state.agentDataGatewayConfigured }
        ?: stringResource(R.string.export_target_gateway_unconfigured_subtitle)
}

/** iOS's "Will write" line: "About 14 files · 7 days · daily notes updated". */
@Composable
private fun willWriteSummary(state: ExportUiState, days: Int): String {
    val files = willWriteFileCount(state, days)
    val writesNotes = state.selectedTarget == ExportTarget.DEVICE_FOLDER &&
        state.settings.exportMode != ExportMode.RAW_SNAPSHOT &&
        state.settings.dailyNoteInjection.enabled
    return listOfNotNull(
        pluralStringResource(R.plurals.export_now_about_files, files, files),
        pluralStringResource(R.plurals.export_now_days, days, days),
        stringResource(R.string.export_now_daily_notes_updated).takeIf { writesNotes },
    ).joinToString(" · ")
}

/** The board's "Will write" card: where the export goes and what it writes, with Preview. */
@Composable
private fun ExportWillWriteCard(
    destination: String,
    summary: String,
    canPreview: Boolean,
    onPreview: () -> Unit,
) {
    val colors = com.healthmd.presentation.theme.LocalGeistColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(com.healthmd.presentation.theme.GeistRadii.listGroup))
            .background(colors.gray.c300)
            .padding(start = Spacing.lg - Spacing.xxs, end = Spacing.xs, top = Spacing.xs, bottom = Spacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.export_will_write).uppercase(),
                style = GeistType.label12,
                fontWeight = FontWeight.SemiBold,
                color = colors.secondary,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onPreview, enabled = canPreview) {
                Text(stringResource(R.string.export_preview_button), style = GeistType.button14)
            }
        }
        Text(destination, style = GeistType.copy13Mono, color = colors.primary)
        Spacer(Modifier.height(Spacing.xxs))
        Text(summary, style = GeistType.copy14, color = colors.secondary)
    }
}

/** One full-width 56dp primary action, with the free-export count and blocking notes above it. */
@Composable
private fun ExportNowCta(
    label: String,
    isPurchased: Boolean,
    freeExportsRemaining: Int,
    hasSelectedFormat: Boolean,
    notice: String?,
    enabled: Boolean,
    isExporting: Boolean,
    onExport: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = com.healthmd.presentation.theme.LocalGeistColors.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(colors.background200)
            .padding(horizontal = Spacing.lg - Spacing.xxs, vertical = Spacing.sm),
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
        notice?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary,
                textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
        if (!isPurchased) {
            Text(
                pluralStringResource(R.plurals.free_exports_remaining, freeExportsRemaining, freeExportsRemaining),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
            )
        }
        Button(
            onClick = onExport,
            enabled = enabled && !isExporting,
            shape = RoundedCornerShape(com.healthmd.presentation.theme.GeistRadii.full),
            colors = ButtonDefaults.buttonColors(
                containerColor = colors.brandPrimary,
                contentColor = colors.brandOnPrimary,
            ),
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
        ) {
            if (isExporting) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = colors.brandOnPrimary,
                )
            } else {
                Text(label, style = GeistType.button16, textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
internal fun FloatingExportActionBar(
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
    clinicDestinationAuthorized: Boolean = false,
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
                    color = AppColors.textSecondary,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            if (!isPurchased && !clinicDestinationAuthorized) {
                Text(
                    text = pluralStringResource(
                        R.plurals.free_exports_remaining,
                        freeExportsRemaining,
                        freeExportsRemaining,
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
            }

            AdaptiveActionPair(
                primaryAction = { actionModifier ->
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
                        modifier = actionModifier,
                    )
                },
                secondaryAction = { actionModifier ->
                    SecondaryButton(
                        text = stringResource(R.string.export_preview_button),
                        onClick = onPreview,
                        icon = Icons.Outlined.Visibility,
                        enabled = canPreview,
                        modifier = actionModifier,
                    )
                },
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
            } else if (result.target == ExportTarget.AGENT_DATA_GATEWAY) {
                stringResource(R.string.agent_data_gateway_result_uploaded) +
                    (result.httpStatusCode?.let { " · HTTP $it" } ?: "")
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
    val colors = LocalGeistColors.current
    // A tonal well inside the diagnostics card; hierarchy from fill, not a border.
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.medium))
            .background(colors.gray.c200)
            .padding(GeistSpacing.space3),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
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
            style = GeistType.heading14,
            color = colors.primary,
        )
        Text(
            group.guidanceText(),
            style = GeistType.copy14,
            color = colors.secondary,
        )
        if (!isRawSnapshot && group.sampleDates.isNotEmpty()) {
            Text(
                group.dateSampleText(),
                style = GeistType.copy13,
                color = colors.secondary,
            )
        }
    }
}

@Composable
fun ExportFailureDiagnosticGroup.failureReasonLabel(): String = reason.localizedFailureLabel()

@Composable
internal fun ExportFailureReason.localizedFailureLabel(): String =
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
        ExportFailureReason.GATEWAY_FORMAT_UNSUPPORTED -> stringResource(R.string.export_failure_gateway_format_label)
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
        ExportDiagnosticGuidance.GATEWAY_FORMAT -> stringResource(R.string.export_guidance_gateway_format)
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

/**
 * Export preview as a full-screen Material 3 surface: a top app bar (Close on the file list,
 * Back on a file), the list of files grouped by day as list-group rows, a full-height file
 * reader, and a pinned action bar with Export as the one filled action.
 */
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
    val colors = LocalGeistColors.current
    Dialog(
        onDismissRequest = if (isLoading) onCancel else onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        EdgeToEdgeDialogWindow(fullScreenPage = true)
        Surface(modifier = Modifier.fillMaxSize(), color = colors.background100) {
            ExportPreviewPage(
                preview = preview,
                isLoading = isLoading,
                destinationLabel = destinationLabel,
                formatsPerDay = formatsPerDay,
                canExport = canExport,
                hitExportLimit = hitExportLimit,
                onExport = onExport,
                onDismiss = onDismiss,
                onCancel = onCancel,
                modifier = Modifier
                    .windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout))
                    .dialogNavigationBarsPadding(),
            )
        }
    }
}

/**
 * The preview's page: the file list or one file, a top bar whose Back leaves the file (or the
 * preview), and the pinned Export action. Export now pushes it inside its sheet, as iOS does.
 */
@Composable
private fun ExportPreviewPage(
    preview: ExportPreview?,
    isLoading: Boolean,
    destinationLabel: String?,
    formatsPerDay: Int,
    canExport: Boolean,
    hitExportLimit: Boolean,
    onExport: () -> Unit,
    onDismiss: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
    /** Inside the sheet the list's Back returns to the sheet, so it reads as Back, not Close. */
    pushed: Boolean = false,
) {
    var selectedFile by remember(preview) { mutableStateOf<PreviewFileDetails?>(null) }
    var wrapLines by rememberSaveable { mutableStateOf(true) }
    var formatted by rememberSaveable { mutableStateOf(true) }
    val closePreview = if (isLoading) onCancel else onDismiss
    BackHandler { if (selectedFile != null) selectedFile = null else closePreview() }
    Column(modifier.fillMaxSize()) {
        val file = selectedFile
        PreviewTopBar(
            title = file?.title ?: stringResource(R.string.export_preview_title),
            subtitle = file?.subtitle,
            isFile = file != null || pushed,
            onNavigate = { if (file != null) selectedFile = null else closePreview() },
            wrapLines = wrapLines,
            onWrapLinesChange = { wrapLines = it },
            canFormat = file != null && PreviewSyntax.forPath(file.relativePath) != PreviewSyntax.PLAIN,
            formatted = formatted,
            onFormattedChange = { formatted = it },
            showsFileControls = file != null,
        )
        Box(
            Modifier
                .weight(1f)
                .fillMaxWidth(),
            contentAlignment = Alignment.TopCenter,
        ) {
            Box(
                Modifier
                    .widthIn(max = GeistSizes.readableContentMaxWidth)
                    .fillMaxSize(),
            ) {
                when {
                    isLoading -> ExportPreviewLoadingContent()
                    file != null -> PreviewFileContent(file, destinationLabel, wrapLines, formatted)
                    preview != null -> ExportPreviewFileList(
                        preview = preview,
                        destinationLabel = destinationLabel,
                        formatsPerDay = formatsPerDay,
                        onFileSelected = { selectedFile = it },
                    )
                }
            }
        }
        PreviewActionBar(
            showExport = !isLoading && preview != null,
            canExport = canExport,
            hitExportLimit = hitExportLimit,
            onExport = onExport,
            onDone = closePreview,
        )
    }
}

/** Sub-screen top app bar: navigation icon, a one-line `heading-20` title and optional subtitle. */
@Composable
private fun PreviewTopBar(
    title: String,
    subtitle: String?,
    isFile: Boolean,
    onNavigate: () -> Unit,
    wrapLines: Boolean,
    onWrapLinesChange: (Boolean) -> Unit,
    canFormat: Boolean,
    formatted: Boolean,
    onFormattedChange: (Boolean) -> Unit,
    showsFileControls: Boolean = isFile,
) {
    val colors = LocalGeistColors.current
    val toggleColors = IconButtonDefaults.iconToggleButtonColors(
        contentColor = colors.secondary,
        checkedContentColor = colors.onSecondaryContainer,
        checkedContainerColor = colors.secondaryContainer,
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .padding(horizontal = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconButton(onClick = onNavigate, modifier = Modifier.size(GeistSizes.minimumTouchTarget)) {
            Icon(
                if (isFile) Icons.AutoMirrored.Outlined.ArrowBack else Icons.Outlined.Close,
                contentDescription = stringResource(
                    if (isFile) R.string.export_preview_back_description else R.string.close
                ),
                tint = colors.primary,
            )
        }
        Column(
            Modifier
                .weight(1f)
                .padding(horizontal = GeistSpacing.space1, vertical = GeistSpacing.space2),
        ) {
            Text(
                title,
                style = GeistType.heading20,
                color = colors.primary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics { heading() },
            )
            subtitle?.let {
                Text(it, style = GeistType.copy13, color = colors.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (showsFileControls && canFormat) {
            val formatLabel = stringResource(R.string.export_preview_format_text)
            IconToggleButton(
                checked = formatted,
                onCheckedChange = onFormattedChange,
                modifier = Modifier
                    .size(GeistSizes.minimumTouchTarget)
                    .semantics { contentDescription = formatLabel },
                colors = toggleColors,
            ) {
                Icon(Icons.Outlined.DataObject, contentDescription = null)
            }
        }
        if (showsFileControls) {
            val wrapLabel = stringResource(R.string.export_preview_wrap_lines)
            IconToggleButton(
                checked = wrapLines,
                onCheckedChange = onWrapLinesChange,
                modifier = Modifier
                    .size(GeistSizes.minimumTouchTarget)
                    .semantics { contentDescription = wrapLabel },
                colors = toggleColors,
            ) {
                Icon(Icons.AutoMirrored.Outlined.WrapText, contentDescription = null)
            }
        }
    }
}

/** Pinned footer: Done beside the one filled Export action, stacking when labels would crowd. */
@Composable
private fun PreviewActionBar(
    showExport: Boolean,
    canExport: Boolean,
    hitExportLimit: Boolean,
    onExport: () -> Unit,
    onDone: () -> Unit,
) {
    val colors = LocalGeistColors.current
    Box(
        Modifier
            .fillMaxWidth()
            .background(colors.background200)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.widthIn(max = GeistSizes.readableContentMaxWidth)) {
            if (showExport) {
                AdaptiveActionPair(
                    primaryAction = { modifier ->
                        PrimaryButton(
                            text = stringResource(if (hitExportLimit) R.string.unlock_button else R.string.export_button),
                            onClick = onExport,
                            enabled = canExport,
                            icon = Icons.Outlined.UploadFile,
                            modifier = modifier,
                        )
                    },
                    secondaryAction = { modifier ->
                        SecondaryButton(
                            text = stringResource(R.string.export_preview_done),
                            onClick = onDone,
                            modifier = modifier,
                        )
                    },
                )
            } else {
                SecondaryButton(
                    text = stringResource(R.string.export_preview_done),
                    onClick = onDone,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun ExportPreviewLoadingContent() {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(GeistSpacing.space4),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = colors.brandPrimary)
        Spacer(modifier = Modifier.height(GeistSpacing.space4))
        Text(
            stringResource(R.string.export_preview_building),
            style = GeistType.copy14,
            color = colors.secondary,
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
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4)
            .padding(bottom = GeistSpacing.space6),
    ) {
        PreviewSummaryCard(
            requestedDayCount = preview.requestedDateCount,
            formatsPerDay = formatsPerDay,
            destinationLabel = destinationLabel,
            isRangeArtifact = preview.isRangeArtifact,
            artifactCount = preview.totalFileCount,
            totals = if (preview.isRangeArtifact) {
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
            limitNote = if (!preview.isRangeArtifact && preview.isTruncated && preview.previewedDateCount > 0) {
                pluralStringResource(
                    R.plurals.export_preview_limited_days,
                    preview.previewedDateCount,
                    preview.previewedDateCount,
                )
            } else null,
        )

        preview.sleepWindow?.let { window ->
            val morningEnds = window.captureContext.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS
            PreviewNote(
                tone = PreviewNoteTone.INFO,
                title = null,
                message = stringResource(
                    if (morningEnds) R.string.export_sleep_preview_window_morning_ends
                    else R.string.export_sleep_preview_window,
                    formatPreviewDate(window.startDate),
                    formatPreviewDate(if (morningEnds) window.endDate else window.endDate.plusDays(1)),
                    window.captureContext.zoneId.id,
                ) + "\n" + stringResource(
                    if (morningEnds) R.string.export_sleep_preview_guidance_morning_ends
                    else R.string.export_sleep_preview_guidance
                ),
                modifier = Modifier.padding(top = GeistSpacing.space3),
            )
        }

        if (preview.days.isEmpty()) {
            PreviewNote(
                tone = PreviewNoteTone.INFO,
                title = stringResource(R.string.export_preview_no_data_title),
                message = stringResource(R.string.export_preview_no_data_message),
                modifier = Modifier.padding(top = GeistSpacing.space3),
            )
        }

        preview.days.forEach { day ->
            Text(
                if (preview.isRangeArtifact) formatPreviewDateRange(day.requestedDates) else formatPreviewDate(day.date),
                style = GeistType.heading14,
                color = colors.brandPrimary,
                modifier = Modifier
                    .padding(start = GeistSpacing.space4, top = GeistSpacing.space6, bottom = GeistSpacing.space2)
                    .semantics { heading() },
            )

            day.failureReason?.let { reason ->
                PreviewNote(
                    tone = PreviewNoteTone.ERROR,
                    title = reason.localizedFailureLabel(),
                    message = day.issues.takeIf { it.isNotEmpty() }
                        ?.map { it.localizedMessage() }
                        ?.joinToString("\n")
                        ?: stringResource(R.string.export_preview_no_exportable_file),
                    modifier = Modifier.padding(bottom = GeistSpacing.space2),
                )
            }
            if (day.failureReason == null && day.issues.isNotEmpty()) {
                PreviewNote(
                    tone = PreviewNoteTone.WARNING,
                    title = stringResource(R.string.export_preview_warning_title),
                    message = day.issues.map { it.localizedMessage() }.joinToString("\n"),
                    modifier = Modifier.padding(bottom = GeistSpacing.space2),
                )
            }

            val rows = day.files.map { file ->
                PreviewFileDetails(
                    title = file.relativePath.substringAfterLast('/'),
                    subtitle = "${file.formatLabel ?: file.format.localizedDisplayName()} · ${formatBytes(file.byteCount)}",
                    relativePath = file.relativePath,
                    byteCount = file.byteCount,
                    content = file.content,
                    previewOmittedByteCount = file.previewOmittedByteCount,
                    previewTailContent = file.previewTailContent,
                    isWritable = true,
                ) to true
            } + day.sideEffects.map { effect ->
                PreviewFileDetails(
                    title = effect.relativePath.substringAfterLast('/'),
                    subtitle = effect.action.localizedAction() + if (effect.wouldWrite) " · ${formatBytes(effect.byteCount)}" else "",
                    relativePath = effect.relativePath,
                    byteCount = effect.byteCount,
                    content = effect.content.orEmpty(),
                    previewOmittedByteCount = 0,
                    previewTailContent = "",
                    isWritable = effect.wouldWrite,
                ) to (effect.content != null)
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                rows.forEachIndexed { index, (details, openable) ->
                    PreviewFileRow(
                        file = details,
                        destinationLabel = destinationLabel,
                        shape = groupRowShape(index, rows.size),
                        onClick = { onFileSelected(details) },
                        enabled = openable,
                    )
                }
            }
        }
    }
}

/** What the export writes and where, as a tonal card with the totals beneath. */
@Composable
private fun PreviewSummaryCard(
    requestedDayCount: Int,
    formatsPerDay: Int,
    destinationLabel: String?,
    isRangeArtifact: Boolean,
    artifactCount: Int,
    totals: String,
    limitNote: String?,
) {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.large))
            .background(colors.background200)
            .padding(GeistSpacing.space4 + GeistSpacing.space1),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        PreviewSummaryRow(stringResource(R.string.section_date_range), dayCountLabel(requestedDayCount))
        PreviewSummaryRow(
            stringResource(
                if (isRangeArtifact) R.string.export_preview_artifacts_per_range
                else R.string.export_preview_formats_per_day
            ),
            localizedInteger(if (isRangeArtifact) artifactCount else formatsPerDay),
        )
        PreviewSummaryRow(
            stringResource(R.string.export_preview_destination_label),
            destinationLabel ?: stringResource(R.string.export_preview_selected_folder),
            mono = true,
        )
        Text(
            totals,
            style = GeistType.copy14,
            color = colors.secondary,
            modifier = Modifier.padding(top = GeistSpacing.space1),
        )
        limitNote?.let { Text(it, style = GeistType.copy13, color = colors.secondary) }
    }
}

@Composable
private fun PreviewSummaryRow(label: String, value: String, mono: Boolean = false) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.Top,
    ) {
        Text(label, style = GeistType.copy14, color = colors.secondary)
        Text(
            value,
            modifier = Modifier.padding(start = GeistSpacing.space4),
            style = if (mono) GeistType.label13Mono else GeistType.label14,
            color = colors.primary,
            textAlign = TextAlign.End,
        )
    }
}

private enum class PreviewNoteTone { INFO, WARNING, ERROR }

/** A tonal note (no border) whose tone is carried by its icon and title as well as color. */
@Composable
private fun PreviewNote(
    tone: PreviewNoteTone,
    title: String?,
    message: String,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val (container, accent, icon) = when (tone) {
        PreviewNoteTone.INFO -> Triple(colors.gray.c200, colors.secondary, Icons.Outlined.Info)
        PreviewNoteTone.WARNING -> Triple(colors.amber.c100, colors.warning, Icons.Outlined.WarningAmber)
        PreviewNoteTone.ERROR -> Triple(colors.red.c100, colors.error, Icons.Outlined.ErrorOutline)
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.medium))
            .background(container)
            .padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
            title?.let { Text(it, style = GeistType.heading14, color = accent) }
            Text(message, style = GeistType.copy14, color = colors.primary)
        }
    }
}

/** One file as a list-group row: icon circle, name, format and size, and its folder in mono. */
@Composable
private fun PreviewFileRow(
    file: PreviewFileDetails,
    destinationLabel: String?,
    shape: Shape,
    onClick: () -> Unit,
    enabled: Boolean = true,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .heightIn(min = 72.dp)
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space3, top = GeistSpacing.space3, bottom = GeistSpacing.space3),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Box(
            modifier = Modifier
                .size(GeistSizes.control)
                .background(if (file.isWritable) colors.brandSubtle else colors.gray.c300, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Outlined.Description,
                contentDescription = null,
                tint = if (file.isWritable) colors.brandOnSubtle else colors.secondary,
                modifier = Modifier.size(22.dp),
            )
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                file.title,
                style = GeistType.label16,
                color = if (enabled) colors.primary else colors.secondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(file.subtitle, style = GeistType.copy14, color = colors.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            parentPathLabel(file.relativePath, destinationLabel)?.let { path ->
                Text(
                    path,
                    style = GeistType.label12Mono,
                    color = colors.secondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.padding(top = GeistSpacing.space1),
                )
            }
        }
        if (enabled) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = colors.secondary,
            )
        }
    }
}

/** The file reader: where it is written, then the content on a full-height mono surface. */
@Composable
private fun PreviewFileContent(
    file: PreviewFileDetails,
    destinationLabel: String?,
    wrapLines: Boolean,
    formatted: Boolean,
) {
    val colors = LocalGeistColors.current
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
    val emptyFileLabel = stringResource(R.string.export_preview_empty_file)
    val truncationMarker = stringResource(
        R.string.export_preview_truncation_marker,
        formatBytes(displayContent.omittedByteCount),
        formatBytes(displayContent.originalByteCount),
    )
    val syntax = remember(file.relativePath) { PreviewSyntax.forPath(file.relativePath) }
    val palette = PreviewPalette(
        key = colors.brandPrimary,
        string = colors.teal.c900,
        literal = colors.pink.c900,
        punctuation = colors.secondary,
        heading = colors.primary,
    )
    // One monospace column, for hanging indents that keep wrapped values under their indent.
    val textMeasurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val columnWidth = remember(textMeasurer, density) {
        with(density) { (textMeasurer.measure("0000000000", GeistType.label12Mono).size.width / 10f).toSp() }
    }
    val hangIndents = formatted && wrapLines &&
        (syntax == PreviewSyntax.JSON || syntax == PreviewSyntax.NDJSON || syntax == PreviewSyntax.YAML)
    // Formatting runs off the main thread: a preview holds up to 64 KB of text.
    val renderedContent by produceState<AnnotatedString?>(
        initialValue = null,
        displayContent, formatted, hangIndents, syntax, palette, emptyFileLabel, truncationMarker, columnWidth,
    ) {
        value = null
        value = withContext(Dispatchers.Default) {
            when {
                displayContent.isEmpty -> AnnotatedString(emptyFileLabel)
                !formatted || syntax == PreviewSyntax.PLAIN -> AnnotatedString(
                    displayContent.render(emptyFileLabel = emptyFileLabel, truncationMarker = truncationMarker),
                )
                else -> buildAnnotatedString {
                    val head = ExportPreviewFormatter.format(displayContent.text, syntax, palette)
                    append(if (hangIndents) head.withHangingIndents(columnWidth) else head)
                    if (displayContent.isTruncated) {
                        withStyle(SpanStyle(color = palette.punctuation)) { append(truncationMarker) }
                        val tail = ExportPreviewFormatter.format(displayContent.tailText, syntax, palette)
                        append(if (hangIndents) tail.withHangingIndents(columnWidth) else tail)
                    }
                }
            }
        }
    }
    val fullPath = listOfNotNull(destinationLabel?.takeIf { it.isNotBlank() }, file.relativePath.trim('/'))
        .joinToString("/")

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space3),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.listGroup))
                .background(colors.background200)
                .padding(GeistSpacing.space4),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1),
        ) {
            SelectionContainer {
                Text(fullPath, style = GeistType.label12Mono, color = colors.primary)
            }
            Text(
                stringResource(
                    if (displayContent.isTruncated) R.string.export_preview_truncated_file
                    else R.string.export_preview_complete_file,
                    formatBytes(displayContent.originalByteCount),
                ),
                style = GeistType.copy13,
                color = colors.secondary,
            )
        }
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.medium))
                .background(colors.gray.c100)
                .verticalScroll(rememberScrollState())
                .then(if (wrapLines) Modifier else Modifier.horizontalScroll(rememberScrollState()))
                .padding(GeistSpacing.space4),
        ) {
            val content = renderedContent
            if (content == null) {
                CircularProgressIndicator(
                    color = colors.brandPrimary,
                    modifier = Modifier.size(GeistSpacing.space6),
                )
            } else {
                SelectionContainer {
                    Text(
                        content,
                        style = GeistType.label12Mono,
                        color = colors.primary,
                        softWrap = wrapLines,
                    )
                }
            }
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

/** Ranges longer than this ask before exporting; raw snapshots are one artifact and do not. */
internal const val LARGE_EXPORT_DAY_THRESHOLD = 90

internal fun isLargeExport(days: Int, mode: ExportMode): Boolean =
    mode != ExportMode.RAW_SNAPSHOT && days > LARGE_EXPORT_DAY_THRESHOLD

/** A run that wrote every requested day ends on the moment's done state. */
internal fun momentShowsDone(result: ExportResult): Boolean =
    !result.wasCancelled && result.totalCount > 0 && result.successCount == result.totalCount &&
        result.failedDateDetails.isEmpty() && result.exportMode != ExportMode.RAW_SNAPSHOT

/**
 * Turns each line's leading spaces into a paragraph indent whose wrapped lines hang one level
 * deeper, so a long value wraps under its own indent instead of breaking after the spaces and
 * restarting at the left edge. Display only: copied text loses its indentation.
 */
private fun AnnotatedString.withHangingIndents(column: TextUnit): AnnotatedString = buildAnnotatedString {
    val source = this@withHangingIndents
    var lineStart = 0
    while (lineStart <= source.length) {
        val lineEnd = source.text.indexOf('\n', lineStart).let { if (it < 0) source.length else it }
        var contentStart = lineStart
        while (contentStart < lineEnd && source.text[contentStart] == ' ') contentStart++
        val indent = contentStart - lineStart
        withStyle(
            ParagraphStyle(
                textIndent = TextIndent(
                    firstLine = (column.value * indent).sp,
                    restLine = (column.value * (indent + 2)).sp,
                ),
            ),
        ) {
            // An empty paragraph collapses; a single space keeps blank lines. Paragraph boundaries
            // replace the newlines (a kept newline adds a blank line), so copy exact text from the
            // raw view.
            if (contentStart == lineEnd) append(' ') else append(source.subSequence(contentStart, lineEnd))
        }
        if (lineEnd == source.length) break
        lineStart = lineEnd + 1
    }
}
