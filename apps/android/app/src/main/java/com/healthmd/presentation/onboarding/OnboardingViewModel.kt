package com.healthmd.presentation.onboarding

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class OnboardingUiState(
    val healthConnectAvailable: Boolean = true,
    val healthConnectNeedsSetup: Boolean = false,
    val hasPermissions: Boolean = false,
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

        viewModelScope.launch {
            checkHealthConnectStatus()
        }
    }

    private suspend fun checkHealthConnectStatus() {
        val available = healthConnectManager.isAvailable()
        // If available but we can't get granted permissions, it might need setup
        val needsSetup = if (available) {
            try {
                healthConnectManager.getGrantedPermissions()
                false
            } catch (_: Exception) {
                true
            }
        } else false
        val hasPermissions = available && !needsSetup && healthConnectManager.hasAllPermissions()

        _uiState.update {
            it.copy(
                healthConnectAvailable = available,
                healthConnectNeedsSetup = needsSetup,
                hasPermissions = hasPermissions,
            )
        }
    }

    fun refreshPermissions() {
        viewModelScope.launch {
            checkHealthConnectStatus()
        }
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
