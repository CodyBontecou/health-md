package com.healthmd.presentation.onboarding

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.data.health.HealthConnectIntentLauncher
import com.healthmd.data.health.HealthConnectLaunchResult
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.tryLaunchHealthConnectPermissions
import com.healthmd.data.drive.GoogleDriveAuthorizationAction
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.presentation.drive.GoogleDrivePrivacyDisclosureDialog
import com.healthmd.presentation.drive.GoogleDriveViewModel
import com.healthmd.presentation.endpoints.APIEndpointSheet
import com.healthmd.presentation.endpoints.APIEndpointsViewModel
import com.healthmd.presentation.export.ExportUiState
import com.healthmd.presentation.export.ExportViewModel
import com.healthmd.presentation.theme.GeistMotion
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class PendingPermission { PACKS, BACKGROUND }

/**
 * Onboarding v2 (Welcome → Packs → Health Connect → Folder → First note → Make it daily).
 * It configures the existing default automation ("Daily note"), writes the last seven days
 * with the single free export through the normal export pipeline, and offers the trial only
 * after the user has seen their notes. Completion lands on Automations.
 */
@Composable
fun OnboardingScreen(
    onComplete: () -> Unit,
    onUseSharedSetup: () -> Unit = {},
    initialStep: OnboardingStep = OnboardingStep.WELCOME,
    viewModel: OnboardingViewModel = hiltViewModel(),
    exportViewModel: ExportViewModel = hiltViewModel(),
    endpointsViewModel: APIEndpointsViewModel = hiltViewModel(),
    driveViewModel: GoogleDriveViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val exportState by exportViewModel.uiState.collectAsStateWithLifecycle()
    val endpointSheet by endpointsViewModel.sheet.collectAsStateWithLifecycle()
    val driveState by driveViewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    val healthConnectManager = remember { HealthConnectManager(context) }
    val intentLauncher = remember { HealthConnectIntentLauncher(context) }

    var appliedInitialStep by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        if (!appliedInitialStep) {
            appliedInitialStep = true
            if (initialStep != OnboardingStep.WELCOME) viewModel.goTo(initialStep)
        }
    }

    var pendingPermission by remember { mutableStateOf<PendingPermission?>(null) }
    var pendingRequest by remember { mutableStateOf<Set<String>>(emptySet()) }
    var afterBackground by remember { mutableStateOf<(() -> Unit)?>(null) }
    val permissionLauncher = rememberLauncherForActivityResult(healthConnectManager.getPermissionContract()) { granted ->
        when (pendingPermission) {
            PendingPermission.PACKS -> viewModel.onPackPermissionsResult(pendingRequest, granted)
            // A denied background grant leaves the schedule to report its own repair notice.
            PendingPermission.BACKGROUND -> afterBackground?.invoke()
            null -> viewModel.refreshPermissions()
        }
        pendingPermission = null
        pendingRequest = emptySet()
        afterBackground = null
        exportViewModel.refreshPermissions()
    }

    var advanceAfterFolder by remember { mutableStateOf(true) }
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri?.let { viewModel.onFolderSelected(it, advance = advanceAfterFolder) }
    }
    val pickFolder: (Boolean) -> Unit = { advance ->
        advanceAfterFolder = advance
        runCatching { folderPicker.launch(null) }
    }

    // Google Drive (PR #138): privacy disclosure → Google consent + folder Picker → bind. The
    // Drive view model owns authorization; onboarding binds the result to the Daily note.
    var showDrivePrivacy by rememberSaveable { mutableStateOf(false) }
    var driveConnectRequested by rememberSaveable { mutableStateOf(false) }
    val driveLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        driveViewModel.finish(result.data)
    }
    val connectDrive: () -> Unit = {
        viewModel.clearDriveError()
        showDrivePrivacy = true
    }
    LaunchedEffect(driveConnectRequested, driveState.busy, driveState.destination, driveState.error) {
        if (!driveConnectRequested || driveState.busy) return@LaunchedEffect
        val error = driveState.error
        val destination = driveState.destination
        when {
            error != null -> {
                driveConnectRequested = false
                driveViewModel.clearError()
                viewModel.onDriveConnectFailed(error)
            }
            destination != null -> {
                driveConnectRequested = false
                viewModel.onDriveConnected(destination)
            }
        }
    }
    if (showDrivePrivacy) {
        GoogleDrivePrivacyDisclosureDialog(
            readiness = driveState.readiness,
            onConnect = {
                showDrivePrivacy = false
                driveConnectRequested = true
                viewModel.onDriveConnectStarted()
                // Connect and Change always pick a folder; a different folder becomes a new destination.
                driveViewModel.begin(replaceDestination = true) { action ->
                    if (action is GoogleDriveAuthorizationAction.Launch) {
                        runCatching {
                            driveLauncher.launch(IntentSenderRequest.Builder(action.pendingIntent.intentSender).build())
                        }.onFailure { viewModel.onDriveConnectFailed(com.healthmd.data.drive.GoogleDriveErrorId.REAUTHORIZATION_REQUIRED) }
                    }
                }
            },
            onDismiss = { showDrivePrivacy = false },
        )
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshPermissions()
                exportViewModel.refreshPermissions()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    // Make it daily has no Back: the export already happened. Other steps step back in place.
    BackHandler(enabled = state.step != OnboardingStep.WELCOME) {
        viewModel.back()
    }

    val connectHealth: () -> Unit = {
        viewModel.clearHealthConnectActionError()
        when {
            !state.healthConnectAvailable -> if (intentLauncher.openInstallOrUpdate() == HealthConnectLaunchResult.FAILED) {
                viewModel.reportHealthConnectActionError(HealthConnectActionError.INSTALL_LAUNCH_FAILED)
            }
            state.healthConnectNeedsSetup -> if (intentLauncher.openSettings() == HealthConnectLaunchResult.FAILED) {
                viewModel.reportHealthConnectActionError(HealthConnectActionError.SETTINGS_LAUNCH_FAILED)
            }
            else -> {
                val request = viewModel.packPermissions()
                pendingPermission = PendingPermission.PACKS
                pendingRequest = request
                if (!tryLaunchHealthConnectPermissions(request, permissionLauncher::launch)) {
                    pendingPermission = null
                    pendingRequest = emptySet()
                    viewModel.reportHealthConnectActionError(HealthConnectActionError.PERMISSION_REQUEST_FAILED)
                }
            }
        }
    }

    /** "Make it daily" asks for background read first, then continues regardless of the answer. */
    val withBackgroundAccess: (() -> Unit) -> Unit = { action ->
        scope.launch {
            val missing = viewModel.missingBackgroundPermissions()
            if (missing.isEmpty()) {
                action()
            } else {
                pendingPermission = PendingPermission.BACKGROUND
                afterBackground = action
                if (!tryLaunchHealthConnectPermissions(missing, permissionLauncher::launch)) {
                    pendingPermission = null
                    afterBackground = null
                    action()
                }
            }
        }
    }

    // Onboarding's save is an ordinary manual export of the seven days: the export view model
    // applies paid access / the one free export, history and accounting exactly as Export now.
    var saveRequested by rememberSaveable { mutableStateOf(false) }
    var sawExporting by remember { mutableStateOf(false) }
    var saveFailed by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(saveRequested, exportState.isExporting, exportState.lastResult, exportState.frontmatterKeyConflict) {
        if (!saveRequested) return@LaunchedEffect
        if (exportState.isExporting) sawExporting = true
        val result = exportState.lastResult
        when {
            exportState.frontmatterKeyConflict -> {
                exportViewModel.dismissFrontmatterKeyConflict()
                saveRequested = false
                saveFailed = true
            }
            !exportState.isExporting && result != null -> {
                saveRequested = false
                exportViewModel.dismissResult()
                if (result.successCount > 0) viewModel.onNotesSaved(result.successCount) else saveFailed = true
            }
        }
    }
    LaunchedEffect(saveRequested) {
        if (!saveRequested) return@LaunchedEffect
        // startExport can decline before it begins (e.g. access re-verification); don't spin forever.
        delay(SAVE_START_TIMEOUT_MS)
        if (saveRequested && !sawExporting && !exportViewModel.uiState.value.isExporting) {
            saveRequested = false
            saveFailed = true
        }
    }

    val firstNoteAction = firstNoteAction(state, exportState)
    val saveNotes: () -> Unit = {
        val days = (state.note as? NotePreviewState.Ready)?.days.orEmpty()
        if (days.isNotEmpty()) {
            saveFailed = false
            sawExporting = false
            exportViewModel.dismissResult()
            exportViewModel.setDateRange(days.first().date, days.last().date)
            saveRequested = true
            exportViewModel.startExport()
        }
    }

    endpointSheet?.let { sheet ->
        APIEndpointSheet(
            state = sheet,
            onUpdate = endpointsViewModel::update,
            onTest = endpointsViewModel::testConnection,
            onSave = { endpointsViewModel.save(onSaved = viewModel::onEndpointSaved) },
            onDismiss = endpointsViewModel::dismiss,
            onRequestDelete = endpointsViewModel::requestDelete,
            onDelete = { endpointsViewModel.delete() },
        )
    }

    AnimatedContent(
        targetState = state.step,
        transitionSpec = { fadeIn(tween(GeistMotion.stateChange)) togetherWith fadeOut(tween(GeistMotion.stateChange)) },
        label = "onboardingStep",
    ) { step ->
        when (step) {
            OnboardingStep.WELCOME -> WelcomeStep(onStart = viewModel::next, onUseSharedSetup = onUseSharedSetup)
            OnboardingStep.PACKS -> PacksStep(
                selected = state.selectedPacks,
                unavailable = state.unavailablePacks,
                onToggle = viewModel::togglePack,
                onToggleAll = viewModel::toggleAllPacks,
                onContinue = viewModel::confirmPacks,
                onBack = { viewModel.back() },
            )
            OnboardingStep.HEALTH -> HealthStep(
                selected = state.selectedPacks,
                healthConnectAvailable = state.healthConnectAvailable,
                needsSetup = state.healthConnectNeedsSetup,
                actionError = state.healthConnectActionError,
                onDismissError = viewModel::clearHealthConnectActionError,
                onConnect = connectHealth,
                onSkip = viewModel::next,
                onBack = { viewModel.back() },
            )
            OnboardingStep.FOLDER -> FolderStep(
                destination = state.destination,
                folderName = state.folderName?.takeIf { state.folderUri != null },
                subfolder = state.subfolder,
                apiEndpoint = state.apiEndpoint,
                metricCount = state.metricCount,
                driveAvailable = state.driveAvailable,
                driveDestination = state.driveDestination,
                driveConnecting = state.driveConnecting || driveState.busy,
                driveError = state.driveError,
                onSelectDestination = { destination ->
                    viewModel.selectDestination(destination)
                    when {
                        destination == OnboardingDestination.API_ENDPOINT -> if (state.apiEndpoint == null) endpointsViewModel.openNew()
                        destination == OnboardingDestination.GOOGLE_DRIVE && state.driveAvailable ->
                            if (state.driveDestination == null) connectDrive()
                        state.folderUri == null -> pickFolder(true)
                    }
                },
                onConnectDrive = connectDrive,
                onPickFolder = { pickFolder(true) },
                onAddEndpoint = endpointsViewModel::openNew,
                onEditEndpoint = { state.apiEndpoint?.let { endpointsViewModel.openEdit(it.id) } },
                onContinue = viewModel::next,
                onSkip = viewModel::next,
                onBack = { viewModel.back() },
            )
            OnboardingStep.FIRST_NOTE -> FirstNoteStep(
                note = state.note,
                selectedDay = state.selectedDay,
                showRaw = state.showRaw,
                action = firstNoteAction,
                isSaving = saveRequested,
                saveFailed = saveFailed,
                onSelectDay = viewModel::selectDay,
                onToggleRaw = viewModel::toggleRaw,
                onPrimary = {
                    when (firstNoteAction) {
                        is FirstNoteAction.Save -> saveNotes()
                        FirstNoteAction.ChooseFolder -> pickFolder(false)
                        FirstNoteAction.Finish, FirstNoteAction.FreeUsed -> viewModel.onNotesSaved(null)
                    }
                },
                onContinueWithoutSaving = { viewModel.onNotesSaved(null) },
                onBack = { viewModel.back() },
            )
            OnboardingStep.DAILY -> DailyStep(
                savedNoteCount = state.savedNoteCount,
                destinationLabel = state.destinationLabel,
                offer = OnboardingFlow.dailyOffer(viewModel.distributionPolicy, state.hasPaidAccess),
                trialOffer = state.trialOffer,
                purchasesAvailable = state.purchasesAvailable,
                isBusy = state.isPurchasing || state.isCompleting,
                purchaseFailed = state.purchaseError != null,
                onStartTrial = {
                    viewModel.clearPurchaseError()
                    withBackgroundAccess {
                        viewModel.registerTrialCompletion(onComplete)
                        context.findActivity()?.let(viewModel::startTrial)
                    }
                },
                onEnable = { withBackgroundAccess { viewModel.enableDailyAndFinish(onComplete) } },
                onNotNow = { viewModel.skipDaily(onComplete) },
            )
        }
    }
}

private const val SAVE_START_TIMEOUT_MS = 15_000L

/** Chooses the First note primary action from the preview, destination and access. */
internal fun firstNoteAction(state: OnboardingUiState, exportState: ExportUiState): FirstNoteAction {
    val ready = state.note as? NotePreviewState.Ready ?: return FirstNoteAction.Finish
    if (!state.destinationReady) {
        // An API endpoint or Drive folder that isn't set up has nowhere to send: finish without exporting.
        return if (state.usesFolder) FirstNoteAction.ChooseFolder else FirstNoteAction.Finish
    }
    val canExport = state.hasPaidAccess || exportState.isPurchased || exportState.clinicDestinationAuthorized ||
        exportState.freeExportsRemaining > 0
    if (!canExport) return FirstNoteAction.FreeUsed
    return FirstNoteAction.Save(
        count = ready.days.count { it.hasNote },
        destination = state.destinationLabel.orEmpty(),
        sends = state.destination == OnboardingDestination.API_ENDPOINT,
    )
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
