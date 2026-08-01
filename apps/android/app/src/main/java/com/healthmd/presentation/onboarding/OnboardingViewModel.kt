package com.healthmd.presentation.onboarding

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.util.runCatchingCancellable
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class OnboardingUiState(
    val healthConnectAvailable: Boolean = false,
    val healthConnectNeedsSetup: Boolean = false,
    val hasPermissions: Boolean = false,
    val healthConnectActionError: HealthConnectActionError? = null,
    val folderUri: String? = null,
    val folderName: String? = null,
)

@HiltViewModel
class OnboardingViewModel @Inject constructor(
    application: Application,
    private val settingsRepository: SettingsRepository,
) : AndroidViewModel(application) {

    private val healthConnectManager = HealthConnectManager(application)

    private val _uiState = MutableStateFlow(OnboardingUiState())
    val uiState: StateFlow<OnboardingUiState> = _uiState.asStateFlow()
    private var healthRefreshJob: Job? = null

    init {
        viewModelScope.launch {
            // Load saved folder
            settingsRepository.exportFolderUri.collect { uri ->
                _uiState.update {
                    it.copy(
                        folderUri = uri,
                        folderName = uri?.let { extractFolderName(it) },
                    )
                }
            }
        }

        refreshPermissions()
    }

    private suspend fun checkHealthConnectStatus() {
        val available = runCatching { healthConnectManager.isAvailable() }
            .getOrElse {
                _uiState.update { state ->
                    state.copy(
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

        runCatchingCancellable { healthConnectManager.hasAllPermissions() }
            .onSuccess { hasPermissions ->
                _uiState.update {
                    it.copy(
                        healthConnectAvailable = true,
                        healthConnectNeedsSetup = false,
                        hasPermissions = hasPermissions,
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
        healthRefreshJob = viewModelScope.launch {
            checkHealthConnectStatus()
        }
    }

    fun reportHealthConnectActionError(error: HealthConnectActionError) {
        _uiState.update { it.copy(healthConnectActionError = error) }
    }

    fun clearHealthConnectActionError() {
        _uiState.update { it.copy(healthConnectActionError = null) }
    }

    fun onFolderSelected(uri: Uri) {
        viewModelScope.launch {
            // Persist permission
            val context = getApplication<Application>()
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            context.contentResolver.takePersistableUriPermission(uri, flags)

            // Save to settings
            settingsRepository.saveExportFolderUri(uri.toString())
        }
    }

    fun completeOnboarding() {
        viewModelScope.launch {
            settingsRepository.setOnboardingCompleted(true)
        }
    }

    private fun extractFolderName(uriString: String): String {
        return try {
            val uri = Uri.parse(uriString)
            val docId = DocumentsContract.getTreeDocumentId(uri)
            // docId is typically "primary:FolderName" or similar
            docId.substringAfterLast(':').substringAfterLast('/')
                .ifBlank { docId.substringAfterLast('/') }
                .ifBlank { "Selected Folder" }
        } catch (e: Exception) {
            "Selected Folder"
        }
    }
}
