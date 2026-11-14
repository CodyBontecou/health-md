package com.healthmd.presentation.onboarding

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.drive.GoogleDriveAuthorizationManager
import com.healthmd.data.drive.GoogleDriveDestination
import com.healthmd.data.drive.GoogleDriveDestinationStore
import com.healthmd.data.drive.GoogleDriveErrorId
import com.healthmd.data.drive.GoogleDriveReadiness
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.domain.model.SavedAPIEndpoint
import com.healthmd.domain.model.SavedAPIEndpointRules
import com.healthmd.data.settings.SavedAPIEndpointCoordinator
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthConnectPermissionPlan
import com.healthmd.data.health.HealthConnectPermissionPolicy
import com.healthmd.data.health.HealthPackPermissions
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileScheduler
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.onboarding.HealthPack
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchaseRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.util.runCatchingCancellable
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber

data class OnboardingUiState(
    val step: OnboardingStep = OnboardingStep.WELCOME,
    val selectedPacks: Set<HealthPack> = HealthPack.defaults,
    /** Packs this Health Connect provider cannot grant (for example Mind before mindfulness). */
    val unavailablePacks: Set<HealthPack> = emptySet(),
    val healthConnectAvailable: Boolean = false,
    val healthConnectNeedsSetup: Boolean = false,
    val hasPermissions: Boolean = false,
    val healthConnectActionError: HealthConnectActionError? = null,
    val destination: OnboardingDestination = OnboardingDestination.LOCAL_FOLDER,
    val folderUri: String? = null,
    val folderName: String? = null,
    val subfolder: String = "health",
    /** The saved endpoint the Daily note sends to (API destination only). */
    val apiEndpoint: SavedAPIEndpoint? = null,
    /** True when this build/flavor can connect Google Drive (Play with OAuth configuration). */
    val driveAvailable: Boolean = false,
    /** The connected Drive folder bound to the Daily note (Google Drive destination only). */
    val driveDestination: GoogleDriveDestination? = null,
    val driveConnecting: Boolean = false,
    /** The last Drive connect failure or cancel, shown inline on the Folder step. */
    val driveError: GoogleDriveErrorId? = null,
    val note: NotePreviewState = NotePreviewState.Idle,
    /** Index into the seven preview days; the most recent day by default. */
    val selectedDay: Int = OnboardingFlow.FIRST_NOTE_DAYS.toInt() - 1,
    val showRaw: Boolean = false,
    /** Notes written by onboarding's export, or null when nothing was exported. */
    val savedNoteCount: Int? = null,
    val hasPaidAccess: Boolean = false,
    val trialOffer: PurchaseOffer? = null,
    val purchasesAvailable: Boolean = false,
    val isPurchasing: Boolean = false,
    val purchaseError: BillingError? = null,
    /** Set while a started trial waits for the store entitlement to arrive. */
    val awaitingTrial: Boolean = false,
    val isCompleting: Boolean = false,
) {
    val metricCount: Int get() = HealthPack.metricCount(selectedPacks)

    /** Google Drive uses PR #138's Drive destination; without it, Drive is a system-picker folder. */
    val usesDrive: Boolean get() = destination == OnboardingDestination.GOOGLE_DRIVE && driveAvailable
    val usesFolder: Boolean get() = destination != OnboardingDestination.API_ENDPOINT && !usesDrive

    /** "Obsidian/health", "Google Drive/Health", or the endpoint name. */
    val destinationLabel: String?
        get() = when {
            usesDrive -> driveDestination?.let { OnboardingFlow.driveLabel(it.folderLabel) }
            usesFolder -> folderName?.let { name -> listOf(name, subfolder).filter { it.isNotBlank() }.joinToString("/") }
            else -> apiEndpoint?.name
        }

    val destinationReady: Boolean
        get() = when {
            usesDrive -> driveDestination != null
            usesFolder -> folderUri != null
            else -> apiEndpoint != null
        }

    /** A daily schedule is enabled only when a Drive destination is bound (folders/API unchanged). */
    val dailyScheduleReady: Boolean get() = !usesDrive || driveDestination != null
}

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    application: Application,
    private val settingsRepository: SettingsRepository,
    val distributionPolicy: DistributionPolicy,
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val profileRepository: ExportProfileRepository,
    private val profileCoordinator: ExportProfileCoordinator,
    private val entryStore: ScheduledProfileEntryStore,
    private val profileScheduler: ScheduledProfileScheduler,
    private val entitlementRepository: EntitlementRepository,
    private val purchaseRepository: PurchaseRepository,
    private val endpointCoordinator: SavedAPIEndpointCoordinator,
    private val driveAuthorization: GoogleDriveAuthorizationManager,
    private val driveDestinationStore: GoogleDriveDestinationStore,
) : AndroidViewModel(application) {

    private val healthConnectManager = HealthConnectManager(application)

    private val _uiState = MutableStateFlow(
        OnboardingUiState(
            hasPaidAccess = distributionPolicy.fullAccessIncluded,
            purchasesAvailable = distributionPolicy.purchasesAvailable && purchaseRepository.isAvailable,
            driveAvailable = runCatching { driveAuthorization.readiness() is GoogleDriveReadiness.Ready }.getOrDefault(false),
        ),
    )
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()
    private var healthRefreshJob: Job? = null
    private var previewJob: Job? = null
    private var onCompleteCallback: (() -> Unit)? = null

    init {
        viewModelScope.launch {
            settingsRepository.exportFolderUri.collect { uri ->
                _uiState.update { it.copy(folderUri = uri, folderName = uri?.let(::extractFolderName)) }
            }
        }
        viewModelScope.launch {
            runCatchingCancellable { settingsRepository.getExportSettings() }.getOrNull()?.let { settings ->
                // A replay keeps a Drive-bound Daily note on Drive with its connected folder.
                val drive = if (settings.exportTarget == com.healthmd.domain.model.ExportTarget.GOOGLE_DRIVE && _uiState.value.driveAvailable) {
                    runCatchingCancellable {
                        profileRepository.getActiveProfile()
                            ?.takeIf { it.target == com.healthmd.domain.model.ExportTarget.GOOGLE_DRIVE }
                            ?.destinationId?.let { id -> driveDestinationStore.find(id) }
                    }.getOrNull()
                } else null
                _uiState.update {
                    it.copy(
                        subfolder = settings.subfolder,
                        destination = when (settings.exportTarget) {
                            com.healthmd.domain.model.ExportTarget.API_ENDPOINT -> OnboardingDestination.API_ENDPOINT
                            com.healthmd.domain.model.ExportTarget.GOOGLE_DRIVE ->
                                if (it.driveAvailable) OnboardingDestination.GOOGLE_DRIVE else it.destination
                            else -> it.destination
                        },
                        driveDestination = drive ?: it.driveDestination,
                    )
                }
            }
        }
        viewModelScope.launch {
            runCatchingCancellable { endpointCoordinator.load() }
            combine(settingsRepository.exportSettings, endpointCoordinator.endpoints) { settings, endpoints ->
                SavedAPIEndpointRules.byUrl(endpoints, settings.apiEndpointUrl)
            }.collect { endpoint -> _uiState.update { it.copy(apiEndpoint = endpoint) } }
        }
        viewModelScope.launch {
            combine(settingsRepository.isPurchased, entitlementRepository.isUnlocked) { persisted, live ->
                distributionPolicy.fullAccessIncluded || persisted || live
            }.collect { paid ->
                _uiState.update { it.copy(hasPaidAccess = paid) }
                if (paid && _uiState.value.awaitingTrial) finishTrial()
            }
        }
        if (distributionPolicy.purchasesAvailable) {
            viewModelScope.launch {
                purchaseRepository.offers.collect { offers ->
                    _uiState.update { it.copy(trialOffer = OnboardingFlow.trialOffer(offers)) }
                }
            }
            viewModelScope.launch {
                purchaseRepository.isPurchasing.collect { purchasing -> _uiState.update { it.copy(isPurchasing = purchasing) } }
            }
            viewModelScope.launch {
                purchaseRepository.purchaseError.collect { error -> _uiState.update { it.copy(purchaseError = error) } }
            }
            entitlementRepository.refresh()
            purchaseRepository.refresh()
        }
        refreshPermissions()
    }

    // region Steps

    fun goTo(step: OnboardingStep) {
        _uiState.update { it.copy(step = step, showRaw = false) }
        if (step == OnboardingStep.FIRST_NOTE) loadFirstNote()
    }

    fun next() = goTo(OnboardingFlow.next(_uiState.value.step))

    /** Returns false when the current step has no Back (Welcome, Make it daily). */
    fun back(): Boolean {
        val previous = OnboardingFlow.previous(_uiState.value.step) ?: return false
        goTo(previous)
        return true
    }

    // endregion

    // region Packs

    fun togglePack(pack: HealthPack) {
        if (pack in _uiState.value.unavailablePacks) return
        _uiState.update {
            it.copy(selectedPacks = if (pack in it.selectedPacks) it.selectedPacks - pack else it.selectedPacks + pack)
        }
    }

    /** Select all available packs, or clear them when all are already selected. */
    fun toggleAllPacks() {
        _uiState.update { state ->
            val available = HealthPack.entries.toSet() - state.unavailablePacks
            state.copy(selectedPacks = if (state.selectedPacks.containsAll(available)) emptySet() else available)
        }
    }

    /** Writes the packs as the Daily note's metric selection (the active profile's live settings). */
    fun confirmPacks() {
        val packs = _uiState.value.selectedPacks
        if (!OnboardingFlow.canContinueFromPacks(packs.size)) return
        viewModelScope.launch {
            runCatchingCancellable {
                val enabled = HealthPack.metricIds(packs)
                settingsRepository.updateExportSettingsAtomically { current ->
                    current.copy(metricSelection = current.metricSelection.copy(enabledMetrics = enabled))
                }
            }.onFailure { Timber.e(it, "Could not save onboarding packs") }
        }
        next()
    }

    // endregion

    // region Health Connect

    fun permissionPlan(): HealthConnectPermissionPlan =
        if (_uiState.value.healthConnectAvailable) {
            runCatching { healthConnectManager.permissionPlan() }.getOrElse { HealthConnectPermissionPolicy.create { false } }
        } else {
            HealthConnectPermissionPolicy.create { false }
        }

    /** Read permissions for the selected packs only. */
    fun packPermissions(): Set<String> =
        HealthPackPermissions.forPacks(_uiState.value.selectedPacks, permissionPlan())

    /** Background read permissions still missing for a daily schedule (empty when not needed). */
    suspend fun missingBackgroundPermissions(): Set<String> {
        if (!_uiState.value.healthConnectAvailable) return emptySet()
        val plan = permissionPlan()
        if (plan.backgroundReadPermissions.isEmpty()) return emptySet()
        val granted = runCatchingCancellable { healthConnectManager.getGrantedPermissions() }.getOrDefault(emptySet())
        return plan.backgroundReadPermissions - granted
    }

    private suspend fun checkHealthConnectStatus() {
        val available = runCatching { healthConnectManager.isAvailable() }.getOrElse {
            _uiState.update {
                it.copy(
                    healthConnectAvailable = false,
                    hasPermissions = false,
                    healthConnectActionError = HealthConnectActionError.ACCESS_CHECK_FAILED,
                )
            }
            return
        }
        if (!available) {
            _uiState.update {
                it.copy(
                    healthConnectAvailable = false,
                    healthConnectNeedsSetup = false,
                    hasPermissions = false,
                    healthConnectActionError = it.healthConnectActionError
                        .takeUnless { error -> error == HealthConnectActionError.ACCESS_CHECK_FAILED },
                )
            }
            return
        }
        val unavailable = runCatching { HealthPackPermissions.unavailablePacks(healthConnectManager.permissionPlan()) }
            .getOrDefault(emptySet())
        runCatchingCancellable { healthConnectManager.hasAllPermissions() }
            .onSuccess { hasPermissions ->
                _uiState.update {
                    it.copy(
                        healthConnectAvailable = true,
                        healthConnectNeedsSetup = false,
                        hasPermissions = hasPermissions,
                        unavailablePacks = unavailable,
                        selectedPacks = it.selectedPacks - unavailable,
                        healthConnectActionError = it.healthConnectActionError
                            .takeUnless { error -> error == HealthConnectActionError.ACCESS_CHECK_FAILED },
                    )
                }
            }
            .onFailure {
                _uiState.update {
                    it.copy(
                        healthConnectAvailable = true,
                        healthConnectNeedsSetup = true,
                        hasPermissions = false,
                        healthConnectActionError = HealthConnectActionError.ACCESS_CHECK_FAILED,
                    )
                }
            }
    }

    fun refreshPermissions() {
        healthRefreshJob?.cancel()
        healthRefreshJob = viewModelScope.launch { checkHealthConnectStatus() }
    }

    /** Called with the permission sheet result; any granted pack permission continues to Folder. */
    fun onPackPermissionsResult(requested: Set<String>, granted: Set<String>) {
        refreshPermissions()
        if (requested.isNotEmpty() && granted.any { it in requested }) {
            _uiState.update { it.copy(hasPermissions = true, healthConnectActionError = null) }
            if (_uiState.value.step == OnboardingStep.HEALTH) next()
        } else {
            reportHealthConnectActionError(HealthConnectActionError.PERMISSION_DENIED)
        }
    }

    fun reportHealthConnectActionError(error: HealthConnectActionError) {
        _uiState.update { it.copy(healthConnectActionError = error) }
    }

    fun clearHealthConnectActionError() {
        _uiState.update { it.copy(healthConnectActionError = null) }
    }

    // endregion

    // region Destination

    /**
     * Switches the Daily note's destination. An already-chosen folder, saved endpoint or connected
     * Drive folder is bound immediately; otherwise the screen opens the folder picker, the
     * endpoint sheet, or the Drive privacy disclosure.
     */
    fun selectDestination(destination: OnboardingDestination) {
        _uiState.update { it.copy(destination = destination, driveError = null) }
        val state = _uiState.value
        viewModelScope.launch {
            runCatchingCancellable {
                when {
                    destination == OnboardingDestination.API_ENDPOINT -> state.apiEndpoint?.let { endpointCoordinator.bindToActive(it) }
                    state.usesDrive -> state.driveDestination?.let { profileCoordinator.googleDriveDestinationWasSelected(it.id) }
                    state.folderUri != null -> {
                        settingsRepository.updateExportSettingsAtomically { current ->
                            current.copy(
                                exportTarget = com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER,
                                scheduledExportTarget = com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER,
                            )
                        }
                        profileCoordinator.folderWasSelected(state.folderUri, state.folderName)
                    }
                }
            }.onFailure { Timber.e(it, "Could not switch the onboarding destination") }
        }
    }

    /** A saved (new or edited) endpoint becomes the Daily note's destination. */
    fun onEndpointSaved(endpoint: SavedAPIEndpoint) {
        _uiState.update { it.copy(destination = OnboardingDestination.API_ENDPOINT, apiEndpoint = endpoint) }
        viewModelScope.launch {
            runCatchingCancellable { endpointCoordinator.bindToActive(endpoint) }
                .onFailure { Timber.e(it, "Could not bind the saved endpoint") }
        }
    }

    /** Google consent + Picker is running (privacy disclosure confirmed). */
    fun onDriveConnectStarted() {
        _uiState.update { it.copy(driveConnecting = true, driveError = null) }
    }

    /**
     * The Drive connect flow bound [destination]: it becomes the Daily note's destination (target
     * Google Drive + destinationId on the active profile). The user stays on the Folder step.
     */
    fun onDriveConnected(destination: GoogleDriveDestination) {
        viewModelScope.launch {
            val bound = runCatchingCancellable { profileCoordinator.googleDriveDestinationWasSelected(destination.id) }
                .onFailure { Timber.e(it, "Could not bind the Google Drive destination") }
                .getOrDefault(false)
            _uiState.update {
                if (bound) {
                    it.copy(
                        destination = OnboardingDestination.GOOGLE_DRIVE,
                        driveDestination = destination,
                        driveConnecting = false,
                        driveError = null,
                    )
                } else {
                    it.copy(driveConnecting = false, driveError = GoogleDriveErrorId.PERMISSION_DENIED)
                }
            }
        }
    }

    /** Consent/Picker failed or was cancelled: keep the step and any earlier binding. */
    fun onDriveConnectFailed(error: GoogleDriveErrorId) {
        _uiState.update { it.copy(driveConnecting = false, driveError = error) }
    }

    fun clearDriveError() = _uiState.update { it.copy(driveError = null) }

    fun onFolderSelected(uri: Uri, advance: Boolean) {
        viewModelScope.launch {
            val context = getApplication<Application>()
            val persisted = runCatching {
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                context.contentResolver.takePersistableUriPermission(uri, flags)
            }.onFailure { Timber.w(it, "Folder grant was not persistable") }.isSuccess
            if (!persisted) return@launch
            val uriString = uri.toString()
            runCatchingCancellable {
                settingsRepository.saveExportFolderUri(uriString)
                settingsRepository.updateExportSettingsAtomically { current ->
                    current.copy(
                        exportTarget = com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER,
                        scheduledExportTarget = com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER,
                    )
                }
                // Bind the Daily note (active profile) to the picked folder.
                profileCoordinator.folderWasSelected(uriString, extractFolderName(uriString))
            }.onFailure { Timber.e(it, "Could not save onboarding folder") }
            _uiState.update {
                it.copy(
                    folderUri = uriString,
                    folderName = extractFolderName(uriString),
                    destination = if (it.usesFolder) it.destination else OnboardingDestination.LOCAL_FOLDER,
                )
            }
            if (advance && _uiState.value.step == OnboardingStep.FOLDER) next()
        }
    }

    // endregion

    // region First note

    fun selectDay(index: Int) {
        _uiState.update { it.copy(selectedDay = index.coerceIn(0, OnboardingFlow.FIRST_NOTE_DAYS.toInt() - 1), showRaw = false) }
    }

    fun toggleRaw() = _uiState.update { it.copy(showRaw = !it.showRaw) }

    /**
     * Dry-runs the real export pipeline for the last seven days. Nothing is written and the free
     * export is untouched. Without Health Connect access or any data, a sample note is shown.
     */
    fun loadFirstNote(today: LocalDate = LocalDate.now(ZoneId.systemDefault())) {
        previewJob?.cancel()
        val dates = OnboardingFlow.firstNoteDates(today)
        _uiState.update { it.copy(note = NotePreviewState.Loading, selectedDay = dates.lastIndex) }
        previewJob = viewModelScope.launch {
            val packs = _uiState.value.selectedPacks
            val hasAccess = runCatchingCancellable { healthRepository.hasPermissions() }.getOrDefault(false)
            val state = if (!hasAccess) {
                NotePreviewState.Sample(SampleReason.NO_HEALTH_ACCESS, OnboardingSampleNote.days(dates, packs))
            } else {
                runCatchingCancellable {
                    val settings = settingsRepository.getExportSettings()
                    val preview = ExportOrchestrator(healthRepository, exportRepository)
                        .previewDates(dates, settings, maxPreviewDays = dates.size)
                    OnboardingNoteParser.days(dates, preview)
                }.onFailure { Timber.e(it, "First-note preview failed") }
                    .getOrNull()
                    ?.takeIf { days -> days.any { it.hasNote } }
                    ?.let { days -> NotePreviewState.Ready(days) }
                    ?: NotePreviewState.Sample(SampleReason.NO_DATA, OnboardingSampleNote.days(dates, packs))
            }
            val selected = (state as? NotePreviewState.Ready)?.days?.indexOfLast { it.hasNote }
                ?.takeIf { it >= 0 } ?: dates.lastIndex
            _uiState.update { it.copy(note = state, selectedDay = selected) }
        }
    }

    /** Records the onboarding export result shown on Make it daily. */
    fun onNotesSaved(count: Int?) {
        _uiState.update { it.copy(savedNoteCount = count) }
        goTo(OnboardingStep.DAILY)
    }

    // endregion

    // region Make it daily

    /** Starts the store trial. The schedule is enabled once the entitlement arrives. */
    fun startTrial(activity: Activity) {
        val offer = _uiState.value.trialOffer ?: return
        _uiState.update { it.copy(awaitingTrial = true) }
        purchaseRepository.clearError()
        viewModelScope.launch {
            val launched = runCatchingCancellable { purchaseRepository.launchPurchase(activity, offer.plan) }
                .getOrDefault(false)
            if (!launched) _uiState.update { it.copy(awaitingTrial = false) }
        }
    }

    fun clearPurchaseError() {
        purchaseRepository.clearError()
        _uiState.update { it.copy(awaitingTrial = false) }
    }

    /** F-Droid or active access: turn the 8:00 schedule on and finish. */
    fun enableDailyAndFinish(onComplete: () -> Unit) {
        if (!_uiState.value.hasPaidAccess) return
        viewModelScope.launch {
            enableDailySchedule()
            completeOnboarding(onComplete)
        }
    }

    /** Remember the completion callback while the store purchase flow is open. */
    fun registerTrialCompletion(onComplete: () -> Unit) {
        onCompleteCallback = onComplete
    }

    private fun finishTrial() {
        val callback = onCompleteCallback ?: return
        _uiState.update { it.copy(awaitingTrial = false) }
        viewModelScope.launch {
            enableDailySchedule()
            completeOnboarding(callback)
        }
    }

    /** "Not now": keep the Daily note manual; no schedule is enabled. */
    fun skipDaily(onComplete: () -> Unit) {
        viewModelScope.launch { completeOnboarding(onComplete) }
    }

    private suspend fun enableDailySchedule() {
        if (!_uiState.value.dailyScheduleReady) {
            Timber.w("Daily note schedule left off: Google Drive is not connected")
            return
        }
        runCatchingCancellable {
            val profile = profileRepository.getActiveProfile() ?: return@runCatchingCancellable
            val existing = entryStore.entry(profile.id)
            val entry = existing?.copy(
                isEnabled = true,
                hour = OnboardingFlow.DAILY_HOUR,
                minute = OnboardingFlow.DAILY_MINUTE,
                cadenceValue = 1,
                cadenceUnit = ScheduledProfileCadenceUnit.DAY,
            ) ?: ScheduledProfileEntry(
                profileId = profile.id,
                isEnabled = true,
                anchorEpochDay = LocalDate.now().toEpochDay(),
                hour = OnboardingFlow.DAILY_HOUR,
                minute = OnboardingFlow.DAILY_MINUTE,
                cadenceUnit = ScheduledProfileCadenceUnit.DAY,
                lookbackDays = 1,
                zoneId = ZoneId.systemDefault().id,
            )
            entryStore.upsert(entry)
            profileScheduler.reconcile()
        }.onFailure { Timber.e(it, "Could not enable the Daily note schedule") }
    }

    /**
     * Freezes the onboarding configuration into the existing default automation, names it
     * "Daily note" (a user-chosen name is kept), and marks setup complete. No second profile.
     */
    private suspend fun completeOnboarding(onComplete: () -> Unit) {
        if (_uiState.value.isCompleting) return
        _uiState.update { it.copy(isCompleting = true) }
        runCatchingCancellable {
            profileCoordinator.flushEdits()
            profileRepository.getActiveProfile()?.let { active ->
                if (active.name.trim().equals(ExportProfileRules.DEFAULT_PROFILE_NAME, ignoreCase = true)) {
                    profileRepository.rename(active.id, OnboardingFlow.DAILY_NOTE_NAME)
                }
            }
        }.onFailure { Timber.e(it, "Could not name the Daily note automation") }
        runCatchingCancellable { settingsRepository.setOnboardingCompleted(true) }
        onCompleteCallback = null
        onComplete()
    }

    // endregion

    private fun extractFolderName(uriString: String): String? = try {
        val docId = DocumentsContract.getTreeDocumentId(Uri.parse(uriString))
        docId.substringAfterLast(':').substringAfterLast('/')
            .ifBlank { docId.substringAfterLast('/') }
            .takeIf { it.isNotBlank() }
    } catch (_: Exception) {
        null
    }
}
