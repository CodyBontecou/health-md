package com.healthmd.sharedsetup

import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.BuildConfig
import com.healthmd.data.export.APIExportAuthorization
import com.healthmd.data.export.APIExportAuthorizationValidationException
import com.healthmd.data.export.APIExportAuthorizationValidationResult
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ExportProfileRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import javax.inject.Inject

sealed interface SharedSetupUiState {
    data object Idle : SharedSetupUiState
    data object Loading : SharedSetupUiState
    /** Real v2 multi-profile review state. */
    data class ReviewV2(val plan: SharedSetupV2ImportPlan) : SharedSetupUiState
    data class Error(val message: String) : SharedSetupUiState
}

/** Honest per-profile destination-rebind progress for the v2 review screen. */
sealed interface SharedSetupV2RebindState {
    data object Idle : SharedSetupV2RebindState
    data object Rebinding : SharedSetupV2RebindState

    /** A blocked imported profile's retained API endpoint URL is being confirmed and bound. */
    data object ConfirmingApiEndpoint : SharedSetupV2RebindState

    /** A freshly entered API credential is being verified against a blocked profile. */
    data object ConfirmingApiCredential : SharedSetupV2RebindState

    /** A local connected-Mac pairing attestation is being applied to a blocked profile. */
    data object ConfirmingMacPairing : SharedSetupV2RebindState
    data class Failed(val message: String) : SharedSetupV2RebindState
}

@HiltViewModel
class SharedSetupViewModel @Inject constructor(
    private val service: SharedSetupService,
    private val documentStore: SharedSetupDocumentStore,
    private val coordinator: SharedSetupCoordinator,
    private val savedStateHandle: SavedStateHandle,
    private val v2Production: SharedSetupV2ProductionTransaction,
    private val profileRepository: ExportProfileRepository,
    private val scheduledProfileEntryStore: ScheduledProfileEntryStore,
    private val credentialStore: APIExportCredentialStore,
) : ViewModel() {
    companion object {
        private const val PENDING_SHARE_ARTIFACT_ID = "sharedSetup.pendingShareArtifactID"
        private const val RESTORABLE_DOCUMENT_BYTES = "sharedSetup.restorableDocumentBytes"
        private const val RESTORABLE_PHASE = "sharedSetup.restorablePhase"
        private const val RESTORABLE_V2_SELECTED_BUNDLE_IDS =
            "sharedSetup.restorableV2SelectedBundleIDs"
        private const val RESTORABLE_V2_APPLY_MODE = "sharedSetup.restorableV2ApplyMode"
        private const val PHASE_V2_REVIEW = "v2_review"
        private const val PHASE_V2_SUCCESS = "v2_success"
    }

    private val shareLaunchMutex = Mutex()
    private val previewRequestIDs = AtomicLong()
    private val mutableState = MutableStateFlow<SharedSetupUiState>(SharedSetupUiState.Idle)
    val state: StateFlow<SharedSetupUiState> = mutableState.asStateFlow()
    private val mutableVersionedPreview = MutableStateFlow<SharedSetupV2ImportPlan?>(null)
    val versionedPreview: StateFlow<SharedSetupV2ImportPlan?> =
        mutableVersionedPreview.asStateFlow()
    private val mutableV2TransactionState =
        MutableStateFlow<SharedSetupV2TransactionState>(SharedSetupV2TransactionState.Idle)
    val v2TransactionState: StateFlow<SharedSetupV2TransactionState> =
        mutableV2TransactionState.asStateFlow()

    /** Blocked imported profiles after an apply; null when not loaded or unreadable. */
    private val mutableV2BlockedProfiles =
        MutableStateFlow<List<SharedSetupV2BlockedImportedProfile>?>(null)
    val v2BlockedProfiles: StateFlow<List<SharedSetupV2BlockedImportedProfile>?> =
        mutableV2BlockedProfiles.asStateFlow()

    private val mutableV2RebindState =
        MutableStateFlow<SharedSetupV2RebindState>(SharedSetupV2RebindState.Idle)
    val v2RebindState: StateFlow<SharedSetupV2RebindState> =
        mutableV2RebindState.asStateFlow()

    init {
        val restoredBytes = savedStateHandle.get<ByteArray>(RESTORABLE_DOCUMENT_BYTES)
        val restoredPhase = savedStateHandle.get<String>(RESTORABLE_PHASE)
        if (
            restoredBytes != null && restoredPhase != null &&
            restoredBytes.size <= SHARED_SETUP_V2_MAX_BYTES
        ) {
            restore(restoredBytes, restoredPhase)
        } else if (restoredBytes != null || restoredPhase != null) {
            removeRestorableState()
            mutableState.value = SharedSetupUiState.Error(
                if (restoredBytes?.size?.let { it > SHARED_SETUP_V2_MAX_BYTES } == true) {
                    "Shared setup exceeds 4 MiB."
                } else {
                    "The saved shared setup state is incomplete."
                },
            )
        }
        viewModelScope.launch {
            coordinator.imports.collect { pending ->
                if (pending != null) {
                    // The process coordinator retains this request until the user finishes the
                    // external flow. Hidden back-stack ViewModels must never destructively consume
                    // a warm intent before navigation can reveal the active destination.
                    val bytes = pending.bytes
                    val restorableBytes = savedStateHandle.get<ByteArray>(RESTORABLE_DOCUMENT_BYTES)
                    val isRestoredReplay =
                        savedStateHandle.get<String>(RESTORABLE_PHASE) != null &&
                            bytes != null && restorableBytes != null &&
                            bytes.contentEquals(restorableBytes)
                    if (isRestoredReplay) return@collect
                    val requestID = previewRequestIDs.incrementAndGet()
                    if (pending.errorMessage != null) {
                        if (previewRequestIDs.get() == requestID) {
                            mutableState.value = SharedSetupUiState.Error(pending.errorMessage)
                        }
                    } else {
                        preview(requireNotNull(bytes), requestID)
                    }
                }
            }
        }
        viewModelScope.launch {
            v2TransactionState.collect { state ->
                when (state) {
                    is SharedSetupV2TransactionState.Applied -> refreshBlockedImportedProfiles()
                    is SharedSetupV2TransactionState.Undone,
                    SharedSetupV2TransactionState.Idle,
                    -> {
                        mutableV2BlockedProfiles.value = null
                        mutableV2RebindState.value = SharedSetupV2RebindState.Idle
                    }
                    else -> Unit
                }
            }
        }
    }

    fun import(uri: Uri) {
        val requestID = previewRequestIDs.incrementAndGet()
        mutableVersionedPreview.value = null
        mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
        viewModelScope.launch {
            if (previewRequestIDs.get() != requestID) return@launch
            mutableState.value = SharedSetupUiState.Loading
            runCatching { withContext(Dispatchers.IO) { documentStore.read(uri) } }
                .onSuccess { preview(it, requestID) }
                .onFailure {
                    if (previewRequestIDs.get() == requestID) {
                        mutableState.value = SharedSetupUiState.Error(it.safeMessage())
                    }
                }
        }
    }

    /**
     * Default writer action. Production shares the closed Shared Setup v2 writer: ordered
     * repository profile rows, active identity, schedule store entries, the app version, and
     * the v2 transaction's preserved foreign Apple extensions.
     */
    fun exportTo(uri: Uri) {
        exportTo(uri) { service.exportV2Bytes(productionExportSource()) }
    }

    private fun exportTo(uri: Uri, bytes: suspend () -> ByteArray) {
        viewModelScope.launch {
            mutableState.value = SharedSetupUiState.Loading
            runCatching { bytes() }
                .onSuccess { encoded ->
                    runCatching { withContext(Dispatchers.IO) { documentStore.copyTo(encoded, uri) } }
                        .onSuccess { mutableState.value = SharedSetupUiState.Idle }
                        .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
                }
                .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
        }
    }

    /** Default share action; emits `schema_version: 2` exclusively. */
    suspend fun shareIntent(): Result<SharedSetupShare> = createShareIntent {
        service.exportV2Bytes(productionExportSource())
    }

    /**
     * Real owners behind the production v2 writer: the profile repository (ordered rows plus
     * active identity), the scheduled-profile entry store, the app version, and the
     * transaction-owned preserved Apple extensions — never guessed defaults.
     */
    private fun productionExportSource(): SharedSetupV2ExportSource =
        RepositorySharedSetupV2ExportSource(
            profileRepository = profileRepository,
            scheduledProfileEntryStore = scheduledProfileEntryStore,
            appVersion = BuildConfig.VERSION_NAME,
            preservedAppleExtensions = { v2Production.preservedAppleExtensionsByProfileId() },
        )

    private suspend fun createShareIntent(
        bytes: suspend () -> ByteArray,
    ): Result<SharedSetupShare> = shareLaunchMutex.withLock {
        if (savedStateHandle.get<String>(PENDING_SHARE_ARTIFACT_ID) != null) {
            return@withLock Result.failure(IllegalStateException("A setup share is already open."))
        }
        runCatching {
            val encoded = bytes()
            val artifactID = UUID.randomUUID().toString()
            // Reserve the ID before file creation so cancellation can never orphan an untracked file.
            savedStateHandle[PENDING_SHARE_ARTIFACT_ID] = artifactID
            try {
                withContext(Dispatchers.IO) { documentStore.shareIntent(encoded, artifactID) }
            } catch (error: Throwable) {
                if (savedStateHandle.get<String>(PENDING_SHARE_ARTIFACT_ID) == artifactID) {
                    savedStateHandle.remove<String>(PENDING_SHARE_ARTIFACT_ID)
                }
                withContext(NonCancellable) { documentStore.discardShareArtifact(artifactID) }
                throw error
            }
        }
    }

    fun completeShareArtifactHandoff() {
        viewModelScope.launch {
            shareLaunchMutex.withLock {
                val artifactID = savedStateHandle.get<String>(PENDING_SHARE_ARTIFACT_ID) ?: return@withLock
                // Keep the reservation until the IO dispatcher records handoff, so a subsequent
                // share cannot prune this recipient's URI using its older creation timestamp.
                documentStore.scheduleShareArtifactCleanup(artifactID)
                if (savedStateHandle.get<String>(PENDING_SHARE_ARTIFACT_ID) == artifactID) {
                    savedStateHandle.remove<String>(PENDING_SHARE_ARTIFACT_ID)
                }
            }
        }
    }

    fun cancelPendingShareArtifact() {
        viewModelScope.launch {
            shareLaunchMutex.withLock {
                val artifactID = savedStateHandle.get<String>(PENDING_SHARE_ARTIFACT_ID) ?: return@withLock
                documentStore.discardShareArtifact(artifactID)
                if (savedStateHandle.get<String>(PENDING_SHARE_ARTIFACT_ID) == artifactID) {
                    savedStateHandle.remove<String>(PENDING_SHARE_ARTIFACT_ID)
                }
            }
        }
    }

    fun reportError(error: Throwable) {
        mutableState.value = SharedSetupUiState.Error(error.safeMessage())
    }

    /**
     * Post-merge v2 apply seam. It is callable only with an explicit transaction callback and an
     * actual v2 plan produced by the latest bounded preview.
     */
    fun applyV2(
        selectedBundleIds: List<String>,
        mode: SharedSetupV2ApplyMode,
        callback: SharedSetupV2ApplyCallback,
    ) {
        val plan = mutableVersionedPreview.value ?: return
        val requestID = previewRequestIDs.get()
        viewModelScope.launch {
            mutableV2TransactionState.value = SharedSetupV2TransactionState.Applying
            service.applyV2(plan, selectedBundleIds, mode, callback)
                .onSuccess { result ->
                    // A newer document keeps preview ownership. The completed transaction is still
                    // reported, but must not relabel the newer document's SavedState bytes.
                    if (
                        previewRequestIDs.get() == requestID &&
                        mutableVersionedPreview.value == plan
                    ) {
                        savedStateHandle[RESTORABLE_PHASE] = PHASE_V2_SUCCESS
                        savedStateHandle[RESTORABLE_V2_SELECTED_BUNDLE_IDS] =
                            ArrayList(result.selectedBundleIds)
                        savedStateHandle[RESTORABLE_V2_APPLY_MODE] = result.mode.name
                    }
                    mutableV2TransactionState.value = SharedSetupV2TransactionState.Applied(result)
                }
                .onFailure {
                    mutableV2TransactionState.value =
                        SharedSetupV2TransactionState.Error(it.safeMessage())
                }
        }
    }

    /** Production v2 apply through the injected transaction adapter. */
    fun applyV2(selectedBundleIds: List<String>, mode: SharedSetupV2ApplyMode) {
        applyV2(selectedBundleIds, mode, v2Production)
    }

    /** Explicit v2 one-shot Undo seam; callers must pass a transaction adapter. */
    fun undoV2(callback: SharedSetupV2UndoCallback) {
        viewModelScope.launch {
            mutableV2TransactionState.value = SharedSetupV2TransactionState.Undoing
            service.undoV2(callback)
                .onSuccess { result ->
                    clearRestorableImport()
                    mutableV2TransactionState.value = SharedSetupV2TransactionState.Undone(result)
                    if (mutableState.value is SharedSetupUiState.ReviewV2) {
                        // Keep the v2 review screen so the honest undone result stays visible.
                        return@onSuccess
                    }
                    mutableState.value = SharedSetupUiState.Idle
                }
                .onFailure {
                    mutableV2TransactionState.value =
                        SharedSetupV2TransactionState.Error(it.safeMessage())
                }
        }
    }

    /** Production v2 one-shot Undo through the injected transaction adapter. */
    fun undoV2() {
        undoV2(v2Production)
    }

    /** Returns to selection after a failed apply/undo without discarding the reviewed plan. */
    fun resetV2TransactionState() {
        mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
    }

    /**
     * Explicit local folder rebind for one blocked imported profile using the existing
     * blocked-state/rebind-clearing APIs in the production adapter. Refreshes blocked
     * visibility honestly whether or not the rebind cleared the block.
     */
    fun rebindBlockedProfileFolder(profileId: String, uri: Uri, displayName: String?) {
        viewModelScope.launch {
            mutableV2RebindState.value = SharedSetupV2RebindState.Rebinding
            runCatching { v2Production.rebindBlockedFolder(profileId, uri.toString(), displayName) }
                .onSuccess { rebound ->
                    if (rebound) {
                        mutableV2RebindState.value = SharedSetupV2RebindState.Idle
                    } else {
                        mutableV2RebindState.value = SharedSetupV2RebindState.Failed(
                            "The selected folder did not clear this profile’s pending destination state.",
                        )
                    }
                    refreshBlockedImportedProfiles()
                }
                .onFailure {
                    mutableV2RebindState.value = SharedSetupV2RebindState.Failed(it.safeMessage())
                    refreshBlockedImportedProfiles()
                }
        }
    }

    fun dismissRebindFailure() {
        mutableV2RebindState.value = SharedSetupV2RebindState.Idle
    }

    /**
     * In-flow confirmation of the imported API endpoint URL for one blocked imported profile
     * (v2 review), mirroring the Apple twin's explicit-imported-URL confirmation: the URL the
     * user confirmed is exactly what the v2 import retained in its bounded sidecar — this
     * flow never derives, guesses, or accepts a different URL. The trusted repository hook
     * binds it through the editor-path seam (`apiEndpointUrl` binding plus the re-scoped
     * settings-snapshot fingerprint identity) in one DataStore edit. The pending-destination
     * block is NOT cleared here: the existing verified-credential confirmation remains the
     * single clearing gate, and the binding deliberately persists exactly as an editor detour
     * would have left it. Fail-closed: a refused binding writes nothing and keeps the block;
     * failure surfaces honestly.
     */
    fun confirmBlockedApiEndpoint(profileId: String) {
        viewModelScope.launch {
            mutableV2RebindState.value = SharedSetupV2RebindState.ConfirmingApiEndpoint
            runCatching {
                profileRepository.bindSharedSetupV2ApiEndpointAfterConfirmation(profileId)
            }
                .onSuccess { bound ->
                    mutableV2RebindState.value = if (bound) {
                        SharedSetupV2RebindState.Idle
                    } else {
                        SharedSetupV2RebindState.Failed(
                            "The imported endpoint URL could not be confirmed for this " +
                                "profile. It may already be bound to a different endpoint or no " +
                                "longer match an API import; rebind it in the profile editor " +
                                "instead.",
                        )
                    }
                    refreshBlockedImportedProfiles()
                }
                .onFailure {
                    mutableV2RebindState.value = SharedSetupV2RebindState.Failed(it.safeMessage())
                    refreshBlockedImportedProfiles()
                }
        }
    }

    /**
     * In-flow API-credential confirmation for one blocked imported profile (v2 review). The
     * freshly entered credential is persisted through the verified secure-store seam
     * (`APIExportCredentialStore`): prior secure-store state is captured first and the flow
     * fails closed when unreadable, then authorization and custom request headers are cleared
     * so no foreign credential can attach to the imported endpoint, the normalized credential
     * is written and verified, and only then does the trusted repository hook run. When the
     * hook does not clear the block — for example the endpoint URL was never confirmed
     * (in-flow or in the profile editor) — the prior secure-store state is restored (or
     * cleared, fail-closed) and the failure is surfaced honestly; the block always stays
     * until a verified confirmation clears it.
     */
    fun confirmBlockedApiCredential(profileId: String, authorization: String) {
        viewModelScope.launch {
            mutableV2RebindState.value = SharedSetupV2RebindState.ConfirmingApiCredential
            runCatching { persistVerifiedApiCredentialAndClearBlock(profileId, authorization) }
                .onSuccess { cleared ->
                    mutableV2RebindState.value = if (cleared) {
                        SharedSetupV2RebindState.Idle
                    } else {
                        SharedSetupV2RebindState.Failed(
                            "The credential did not clear this profile’s pending destination " +
                                "state. Confirm the imported endpoint URL for this profile " +
                                "first, or rebind its API endpoint in the profile editor, then " +
                                "enter the credential again.",
                        )
                    }
                    refreshBlockedImportedProfiles()
                }
                .onFailure {
                    mutableV2RebindState.value = SharedSetupV2RebindState.Failed(it.safeMessage())
                    refreshBlockedImportedProfiles()
                }
        }
    }

    /**
     * Attestation-only connected-Mac pairing confirmation for one blocked imported profile.
     * There is no credential or endpoint to verify — the explicit local pairing attestation IS
     * the confirmation (Apple's attestation-only precedent) — so the trusted repository hook
     * performs the identity checks (blocked membership, untouched device-folder projection,
     * exact `connected_mac` sidecar kind). The Boolean result is surfaced honestly: failure
     * keeps the block.
     */
    fun confirmBlockedMacPairing(profileId: String) {
        viewModelScope.launch {
            mutableV2RebindState.value = SharedSetupV2RebindState.ConfirmingMacPairing
            runCatching {
                profileRepository.clearSharedSetupV2BlockAfterMacPairingConfirmation(profileId)
            }
                .onSuccess { cleared ->
                    mutableV2RebindState.value = if (cleared) {
                        SharedSetupV2RebindState.Idle
                    } else {
                        SharedSetupV2RebindState.Failed(
                            "This profile’s pending destination state did not match a " +
                                "connected-Mac import, so the pairing confirmation was not applied.",
                        )
                    }
                    refreshBlockedImportedProfiles()
                }
                .onFailure {
                    mutableV2RebindState.value = SharedSetupV2RebindState.Failed(it.safeMessage())
                    refreshBlockedImportedProfiles()
                }
        }
    }

    /**
     * Verified credential write plus block-clearing attempt. Returns whether the block was
     * cleared; on a hook refusal the prior secure-store state is restored and verified, or
     * cleared fail-closed when a verified restore is impossible.
     */
    private suspend fun persistVerifiedApiCredentialAndClearBlock(
        profileId: String,
        authorization: String,
    ): Boolean {
        // Fail closed: if the prior secure-store state cannot be read, no verified rollback
        // would ever be possible, so no credential mutation is attempted at all.
        val priorAuthorizationRead = runCatching { credentialStore.authorizationHeader() }
        val priorHeadersRead = runCatching { credentialStore.requestHeaders() }
        check(priorAuthorizationRead.isSuccess && priorHeadersRead.isSuccess) {
            "Endpoint credentials could not be read safely. Try again."
        }
        val previousAuthorization = priorAuthorizationRead.getOrNull()
        val previousHeaders = priorHeadersRead.getOrDefault(emptyList())
        val expectedAuthorization = when (
            val validated = APIExportAuthorization.validate(authorization)
        ) {
            is APIExportAuthorizationValidationResult.Valid -> validated.normalizedValue
            is APIExportAuthorizationValidationResult.Invalid ->
                throw APIExportAuthorizationValidationException(validated.reason)
        }

        // Clear first so neither authorization nor custom request headers from another
        // destination can become attached to the imported endpoint.
        credentialStore.clearAuthorization()
        credentialStore.clearRequestHeaders()
        credentialStore.saveAuthorization(authorization)
        // The exact normalized credential must be present and no foreign headers may remain
        // before the trusted block-clearing hook may run.
        check(
            credentialStore.authorizationHeader() == expectedAuthorization &&
                credentialStore.requestHeaders().isEmpty()
        ) {
            "The new endpoint credential could not be verified."
        }

        if (profileRepository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(profileId)) {
            return true
        }

        // The block stayed: never leave the unconfirmed credential attached to any endpoint.
        // Restore the prior secure-store state and verify the restoration; when it cannot be
        // verified, attempt a verified clear instead — the same fail-closed rule.
        val credentialRollback = runCatching {
            credentialStore.clearAuthorization()
            credentialStore.clearRequestHeaders()
            previousAuthorization?.let { credentialStore.saveAuthorization(it) }
            if (previousHeaders.isNotEmpty()) {
                credentialStore.saveRequestHeaders(
                    previousHeaders.joinToString("\n") { header -> "${header.name}: ${header.value}" },
                )
            }
        }
        val rollbackVerified = credentialRollback.isSuccess && runCatching {
            credentialStore.authorizationHeader() == previousAuthorization &&
                credentialStore.requestHeaders() == previousHeaders
        }.getOrDefault(false)
        if (!rollbackVerified) {
            val failClosedClear = runCatching {
                credentialStore.clearAuthorization()
                credentialStore.clearRequestHeaders()
            }
            val failClosedVerified = failClosedClear.isSuccess && runCatching {
                credentialStore.authorizationHeader() == null &&
                    credentialStore.requestHeaders().isEmpty()
            }.getOrDefault(false)
            error(
                if (failClosedVerified) {
                    "The confirmation failed and the previous credential could not be verified " +
                        "as restored; credentials were cleared."
                } else {
                    "The confirmation failed and the previous credential could not be verified " +
                        "as restored."
                },
            )
        }
        return false
    }

    private fun refreshBlockedImportedProfiles() {
        viewModelScope.launch {
            // Null keeps the generic pending-destination notice when the sidecar is unreadable.
            mutableV2BlockedProfiles.value = runCatching {
                v2Production.blockedImportedProfiles()
            }.getOrNull()
        }
    }

    fun dismiss() {
        previewRequestIDs.incrementAndGet()
        clearRestorableImport()
        mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
        mutableV2BlockedProfiles.value = null
        mutableV2RebindState.value = SharedSetupV2RebindState.Idle
        mutableState.value = SharedSetupUiState.Idle
    }

    private fun restore(bytes: ByteArray, phase: String) {
        val requestID = previewRequestIDs.incrementAndGet()
        viewModelScope.launch {
            if (previewRequestIDs.get() != requestID) return@launch
            mutableState.value = SharedSetupUiState.Loading
            service.previewVersioned(bytes)
                .onSuccess { plan ->
                    if (previewRequestIDs.get() != requestID) return@onSuccess
                    runCatching { publishRestoredPreview(plan, phase) }
                        .onFailure {
                            if (previewRequestIDs.get() != requestID) return@onFailure
                            clearRestorableImport()
                            mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
                            mutableState.value = SharedSetupUiState.Error(it.safeMessage())
                        }
                }
                .onFailure {
                    // A restored in-flight document that no longer decodes — including a
                    // pre-canonical v1 document saved before this app version — fails honestly:
                    // the bounded error is surfaced, the restorable import is cleared, and no
                    // partial state survives. The v1-era phase strings can no longer publish.
                    if (previewRequestIDs.get() != requestID) return@onFailure
                    clearRestorableImport()
                    mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
                    mutableState.value = SharedSetupUiState.Error(it.safeMessage())
                }
        }
    }

    private fun publishRestoredPreview(
        plan: SharedSetupV2ImportPlan,
        phase: String,
    ) {
        mutableVersionedPreview.value = plan
        require(phase == PHASE_V2_REVIEW || phase == PHASE_V2_SUCCESS) {
            "The saved Shared Setup phase does not match its document version."
        }
        mutableV2TransactionState.value = if (phase == PHASE_V2_SUCCESS) {
            val selected = savedStateHandle
                .get<ArrayList<String>>(RESTORABLE_V2_SELECTED_BUNDLE_IDS)
                ?.toList()
                ?: error("The saved Shared Setup v2 selection is missing.")
            val mode = savedStateHandle.get<String>(RESTORABLE_V2_APPLY_MODE)
                ?.let { runCatching { SharedSetupV2ApplyMode.valueOf(it) }.getOrNull() }
                ?: error("The saved Shared Setup v2 mode is missing.")
            val sourceOrder = plan.profiles.map { it.bundleId }
            require(
                selected.isNotEmpty() && selected == selected.distinct() &&
                    selected == sourceOrder.filter(selected.toSet()::contains)
            ) { "The saved Shared Setup v2 selection is invalid." }
            SharedSetupV2TransactionState.Applied(
                SharedSetupV2ApplyResult(selected, mode, canUndo = true),
            )
        } else {
            SharedSetupV2TransactionState.Idle
        }
        // The typed plan drives the real multi-profile selection screen.
        mutableState.value = SharedSetupUiState.ReviewV2(plan)
    }

    private suspend fun preview(bytes: ByteArray, requestID: Long) {
        if (previewRequestIDs.get() != requestID) return
        if (bytes.size > SHARED_SETUP_V2_MAX_BYTES) {
            clearRestorableImport()
            mutableState.value = SharedSetupUiState.Error("Shared setup exceeds 4 MiB.")
            return
        }
        mutableState.value = SharedSetupUiState.Loading
        service.previewVersioned(bytes)
            .onSuccess { plan ->
                if (previewRequestIDs.get() != requestID) return@onSuccess
                savedStateHandle[RESTORABLE_DOCUMENT_BYTES] = bytes.copyOf()
                savedStateHandle[RESTORABLE_PHASE] = PHASE_V2_REVIEW
                savedStateHandle.remove<ArrayList<String>>(RESTORABLE_V2_SELECTED_BUNDLE_IDS)
                savedStateHandle.remove<String>(RESTORABLE_V2_APPLY_MODE)
                mutableVersionedPreview.value = plan
                mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
                mutableState.value = SharedSetupUiState.ReviewV2(plan)
            }
            .onFailure {
                if (previewRequestIDs.get() != requestID) return@onFailure
                clearRestorableImport()
                mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
                mutableState.value = SharedSetupUiState.Error(it.safeMessage())
            }
    }

    private fun removeRestorableState() {
        savedStateHandle.remove<ByteArray>(RESTORABLE_DOCUMENT_BYTES)
        savedStateHandle.remove<String>(RESTORABLE_PHASE)
        savedStateHandle.remove<ArrayList<String>>(RESTORABLE_V2_SELECTED_BUNDLE_IDS)
        savedStateHandle.remove<String>(RESTORABLE_V2_APPLY_MODE)
    }

    private fun clearRestorableImport() {
        removeRestorableState()
        mutableVersionedPreview.value = null
        coordinator.finishExternalImport()
    }

    private fun Throwable.safeMessage(): String = message?.take(300) ?: "The shared setup could not be processed."
}
