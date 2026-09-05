package com.healthmd.sharedsetup

import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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
    data class Idle(val pendingEndpoint: String? = null) : SharedSetupUiState
    data object Loading : SharedSetupUiState
    data class Review(val preview: SharedSetupPreview) : SharedSetupUiState
    data class Success(val result: SharedSetupApplyResult, val pendingEndpoint: String?) : SharedSetupUiState
    data class Error(val message: String) : SharedSetupUiState
}

@HiltViewModel
class SharedSetupViewModel @Inject constructor(
    private val service: SharedSetupService,
    private val documentStore: SharedSetupDocumentStore,
    private val coordinator: SharedSetupCoordinator,
    private val savedStateHandle: SavedStateHandle,
) : ViewModel() {
    companion object {
        private const val PENDING_SHARE_ARTIFACT_ID = "sharedSetup.pendingShareArtifactID"
        private const val RESTORABLE_DOCUMENT_BYTES = "sharedSetup.restorableDocumentBytes"
        private const val RESTORABLE_PHASE = "sharedSetup.restorablePhase"
        private const val RESTORABLE_V2_SELECTED_BUNDLE_IDS =
            "sharedSetup.restorableV2SelectedBundleIDs"
        private const val RESTORABLE_V2_APPLY_MODE = "sharedSetup.restorableV2ApplyMode"
        private const val PHASE_REVIEW = "review"
        private const val PHASE_SUCCESS = "success"
        private const val PHASE_V2_REVIEW = "v2_review"
        private const val PHASE_V2_SUCCESS = "v2_success"
        private const val V2_DEFERRED_UI_MESSAGE =
            "Shared Setup v2 is ready for multi-profile selection, but Add/Replace is not enabled in this screen yet."
    }

    private val shareLaunchMutex = Mutex()
    private val previewRequestIDs = AtomicLong()
    private val mutableState = MutableStateFlow<SharedSetupUiState>(SharedSetupUiState.Idle())
    val state: StateFlow<SharedSetupUiState> = mutableState.asStateFlow()
    private val mutableVersionedPreview = MutableStateFlow<SharedSetupVersionedPreview?>(null)
    val versionedPreview: StateFlow<SharedSetupVersionedPreview?> =
        mutableVersionedPreview.asStateFlow()
    private val mutableV2TransactionState =
        MutableStateFlow<SharedSetupV2TransactionState>(SharedSetupV2TransactionState.Idle)
    val v2TransactionState: StateFlow<SharedSetupV2TransactionState> =
        mutableV2TransactionState.asStateFlow()

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
        } else {
            refreshPendingEndpointIfIdle()
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

    fun exportTo(uri: Uri) {
        exportTo(uri) { service.exportBytes() }
    }

    /** Explicit v2 writer seam; no current production UI calls this overload. */
    fun exportV2To(uri: Uri, source: SharedSetupV2ExportSource) {
        exportTo(uri) { service.exportV2Bytes(source) }
    }

    private fun exportTo(uri: Uri, bytes: suspend () -> ByteArray) {
        viewModelScope.launch {
            mutableState.value = SharedSetupUiState.Loading
            runCatching { bytes() }
                .onSuccess { encoded ->
                    runCatching { withContext(Dispatchers.IO) { documentStore.copyTo(encoded, uri) } }
                        .onSuccess { refreshPendingEndpointIfIdle(force = true) }
                        .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
                }
                .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
        }
    }

    suspend fun shareIntent(): Result<SharedSetupShare> = createShareIntent {
        service.exportBytes()
    }

    /** Explicit v2 writer seam; the default share action remains byte-identical v1. */
    suspend fun shareV2Intent(source: SharedSetupV2ExportSource): Result<SharedSetupShare> =
        createShareIntent { service.exportV2Bytes(source) }

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

    fun apply() {
        val preview = (mutableState.value as? SharedSetupUiState.Review)?.preview ?: return
        viewModelScope.launch {
            mutableState.value = SharedSetupUiState.Loading
            service.apply(preview)
                .onSuccess {
                    savedStateHandle[RESTORABLE_PHASE] = PHASE_SUCCESS
                    mutableState.value = SharedSetupUiState.Success(it, preview.pendingEndpoint)
                }
                .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
        }
    }

    /**
     * Post-merge v2 apply seam. It is callable only with an explicit transaction callback and an
     * actual v2 plan produced by the latest bounded preview; the current v1 Apply action cannot
     * reach it.
     */
    fun applyV2(
        selectedBundleIds: List<String>,
        mode: SharedSetupV2ApplyMode,
        callback: SharedSetupV2ApplyCallback,
    ) {
        val preview = mutableVersionedPreview.value as? SharedSetupVersionedPreview.V2 ?: return
        val requestID = previewRequestIDs.get()
        viewModelScope.launch {
            mutableV2TransactionState.value = SharedSetupV2TransactionState.Applying
            service.applyV2(preview.plan, selectedBundleIds, mode, callback)
                .onSuccess { result ->
                    // A newer document keeps preview ownership. The completed transaction is still
                    // reported, but must not relabel the newer document's SavedState bytes.
                    if (
                        previewRequestIDs.get() == requestID &&
                        mutableVersionedPreview.value == preview
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

    /** Explicit v2 one-shot Undo seam; no default production callback exists in this lane. */
    fun undoV2(callback: SharedSetupV2UndoCallback) {
        viewModelScope.launch {
            mutableV2TransactionState.value = SharedSetupV2TransactionState.Undoing
            service.undoV2(callback)
                .onSuccess { result ->
                    clearRestorableImport()
                    mutableV2TransactionState.value = SharedSetupV2TransactionState.Undone(result)
                    mutableState.value = SharedSetupUiState.Idle()
                    refreshPendingEndpointIfIdle(force = true)
                }
                .onFailure {
                    mutableV2TransactionState.value =
                        SharedSetupV2TransactionState.Error(it.safeMessage())
                }
        }
    }

    fun confirmPendingEndpoint(authorization: String) {
        val success = mutableState.value as? SharedSetupUiState.Success
        viewModelScope.launch {
            mutableState.value = SharedSetupUiState.Loading
            service.confirmPendingEndpoint(authorization)
                .onSuccess {
                    if (success != null) mutableState.value = success.copy(pendingEndpoint = null)
                    else refreshPendingEndpointIfIdle(force = true)
                }
                .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
        }
    }

    fun undo() {
        viewModelScope.launch {
            mutableState.value = SharedSetupUiState.Loading
            service.undo()
                .onSuccess {
                    clearRestorableImport()
                    refreshPendingEndpointIfIdle(force = true)
                }
                .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
        }
    }

    fun dismiss() {
        previewRequestIDs.incrementAndGet()
        clearRestorableImport()
        mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
        mutableState.value = SharedSetupUiState.Idle()
        refreshPendingEndpointIfIdle(force = true)
    }

    private fun refreshPendingEndpointIfIdle(force: Boolean = false) {
        viewModelScope.launch {
            val endpoint = service.pendingEndpoint()
            if (force || mutableState.value is SharedSetupUiState.Idle) {
                mutableState.value = SharedSetupUiState.Idle(endpoint)
            }
        }
    }

    private fun restore(bytes: ByteArray, phase: String) {
        val requestID = previewRequestIDs.incrementAndGet()
        viewModelScope.launch {
            if (previewRequestIDs.get() != requestID) return@launch
            mutableState.value = SharedSetupUiState.Loading
            service.previewVersioned(bytes)
                .onSuccess { preview ->
                    if (previewRequestIDs.get() != requestID) return@onSuccess
                    runCatching { publishRestoredPreview(preview, phase) }
                        .onFailure {
                            if (previewRequestIDs.get() != requestID) return@onFailure
                            clearRestorableImport()
                            mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
                            mutableState.value = SharedSetupUiState.Error(it.safeMessage())
                        }
                }
                .onFailure {
                    if (previewRequestIDs.get() != requestID) return@onFailure
                    clearRestorableImport()
                    mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
                    mutableState.value = SharedSetupUiState.Error(it.safeMessage())
                }
        }
    }

    private suspend fun publishRestoredPreview(
        preview: SharedSetupVersionedPreview,
        phase: String,
    ) {
        mutableVersionedPreview.value = preview
        when (preview) {
            is SharedSetupVersionedPreview.V1 -> {
                require(phase == PHASE_REVIEW || phase == PHASE_SUCCESS) {
                    "The saved Shared Setup phase does not match its document version."
                }
                mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
                mutableState.value = if (phase == PHASE_SUCCESS) {
                    SharedSetupUiState.Success(
                        SharedSetupApplyResult(preview.preview.review, canUndo = true),
                        service.pendingEndpoint(),
                    )
                } else {
                    SharedSetupUiState.Review(preview.preview)
                }
            }
            is SharedSetupVersionedPreview.V2 -> {
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
                    val sourceOrder = preview.plan.profiles.map { it.bundleId }
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
                // The existing screen is intentionally v1-only. Expose the typed plan through
                // versionedPreview without pretending that one v2 profile represents the bundle.
                mutableState.value = SharedSetupUiState.Error(V2_DEFERRED_UI_MESSAGE)
            }
        }
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
            .onSuccess { preview ->
                if (previewRequestIDs.get() != requestID) return@onSuccess
                savedStateHandle[RESTORABLE_DOCUMENT_BYTES] = bytes.copyOf()
                savedStateHandle[RESTORABLE_PHASE] = when (preview) {
                    is SharedSetupVersionedPreview.V1 -> PHASE_REVIEW
                    is SharedSetupVersionedPreview.V2 -> PHASE_V2_REVIEW
                }
                savedStateHandle.remove<ArrayList<String>>(RESTORABLE_V2_SELECTED_BUNDLE_IDS)
                savedStateHandle.remove<String>(RESTORABLE_V2_APPLY_MODE)
                mutableVersionedPreview.value = preview
                mutableV2TransactionState.value = SharedSetupV2TransactionState.Idle
                mutableState.value = when (preview) {
                    is SharedSetupVersionedPreview.V1 -> SharedSetupUiState.Review(preview.preview)
                    is SharedSetupVersionedPreview.V2 ->
                        SharedSetupUiState.Error(V2_DEFERRED_UI_MESSAGE)
                }
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
