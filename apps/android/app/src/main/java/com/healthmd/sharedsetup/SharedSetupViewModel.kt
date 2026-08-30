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
        private const val PHASE_REVIEW = "review"
        private const val PHASE_SUCCESS = "success"
    }

    private val shareLaunchMutex = Mutex()
    private val previewRequestIDs = AtomicLong()
    private val mutableState = MutableStateFlow<SharedSetupUiState>(SharedSetupUiState.Idle())
    val state: StateFlow<SharedSetupUiState> = mutableState.asStateFlow()

    init {
        val restoredBytes = savedStateHandle.get<ByteArray>(RESTORABLE_DOCUMENT_BYTES)
        val restoredPhase = savedStateHandle.get<String>(RESTORABLE_PHASE)
        if (restoredBytes != null && restoredPhase != null) {
            restore(restoredBytes, restoredPhase)
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
        viewModelScope.launch {
            mutableState.value = SharedSetupUiState.Loading
            runCatching { service.exportBytes() }
                .onSuccess { bytes ->
                    runCatching { withContext(Dispatchers.IO) { documentStore.copyTo(bytes, uri) } }
                        .onSuccess { refreshPendingEndpointIfIdle(force = true) }
                        .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
                }
                .onFailure { mutableState.value = SharedSetupUiState.Error(it.safeMessage()) }
        }
    }

    suspend fun shareIntent(): Result<SharedSetupShare> = shareLaunchMutex.withLock {
        if (savedStateHandle.get<String>(PENDING_SHARE_ARTIFACT_ID) != null) {
            return@withLock Result.failure(IllegalStateException("A setup share is already open."))
        }
        runCatching {
            val bytes = service.exportBytes()
            val artifactID = UUID.randomUUID().toString()
            // Reserve the ID before file creation so cancellation can never orphan an untracked file.
            savedStateHandle[PENDING_SHARE_ARTIFACT_ID] = artifactID
            try {
                withContext(Dispatchers.IO) { documentStore.shareIntent(bytes, artifactID) }
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
            service.preview(bytes)
                .onSuccess { preview ->
                    if (previewRequestIDs.get() != requestID) return@onSuccess
                    mutableState.value = if (phase == PHASE_SUCCESS) {
                        SharedSetupUiState.Success(
                            SharedSetupApplyResult(preview.review, canUndo = true),
                            service.pendingEndpoint(),
                        )
                    } else {
                        SharedSetupUiState.Review(preview)
                    }
                }
                .onFailure {
                    if (previewRequestIDs.get() != requestID) return@onFailure
                    clearRestorableImport()
                    mutableState.value = SharedSetupUiState.Error(it.safeMessage())
                }
        }
    }

    private suspend fun preview(bytes: ByteArray, requestID: Long) {
        if (previewRequestIDs.get() != requestID) return
        mutableState.value = SharedSetupUiState.Loading
        service.preview(bytes)
            .onSuccess {
                if (previewRequestIDs.get() != requestID) return@onSuccess
                savedStateHandle[RESTORABLE_DOCUMENT_BYTES] = bytes.copyOf()
                savedStateHandle[RESTORABLE_PHASE] = PHASE_REVIEW
                mutableState.value = SharedSetupUiState.Review(it)
            }
            .onFailure {
                if (previewRequestIDs.get() != requestID) return@onFailure
                clearRestorableImport()
                mutableState.value = SharedSetupUiState.Error(it.safeMessage())
            }
    }

    private fun clearRestorableImport() {
        savedStateHandle.remove<ByteArray>(RESTORABLE_DOCUMENT_BYTES)
        savedStateHandle.remove<String>(RESTORABLE_PHASE)
        coordinator.finishExternalImport()
    }

    private fun Throwable.safeMessage(): String = message?.take(300) ?: "The shared setup could not be processed."
}
