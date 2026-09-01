package com.healthmd.presentation.onboarding

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.onboarding.OnboardingEventSink
import com.healthmd.domain.onboarding.OnboardingStep
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.util.runCatchingCancellable
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject

enum class OnboardingPage(val analyticsStep: OnboardingStep) {
    WELCOME(OnboardingStep.WELCOME),
    HEALTH_ACCESS(OnboardingStep.HEALTH_ACCESS),
    FOLDER_SETUP(OnboardingStep.FOLDER_SETUP),
    PLAY_ACCESS(OnboardingStep.ACCESS),
    INCLUDED_ACCESS(OnboardingStep.ACCESS),
    READY(OnboardingStep.READY),
}

fun onboardingPages(policy: DistributionPolicy): List<OnboardingPage> = listOf(
    OnboardingPage.WELCOME,
    OnboardingPage.HEALTH_ACCESS,
    OnboardingPage.FOLDER_SETUP,
    if (policy.purchasesAvailable) OnboardingPage.PLAY_ACCESS else OnboardingPage.INCLUDED_ACCESS,
    OnboardingPage.READY,
)

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
    private val onboardingEvents: OnboardingEventSink,
    val distributionPolicy: DistributionPolicy,
) : AndroidViewModel(application) {

    val pages: List<OnboardingPage> = onboardingPages(distributionPolicy)

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
            runCatchingCancellable { onboardingEvents.folderSelected() }
        }
    }

    fun recordInitialOnboarding() {
        viewModelScope.launch {
            val startRecorded = runCatchingCancellable {
                onboardingEvents.onboardingStarted()
            }.isSuccess
            if (startRecorded) {
                runCatchingCancellable {
                    onboardingEvents.stepViewed(OnboardingStep.WELCOME)
                }
            }
        }
    }

    fun recordSettledPage(page: OnboardingPage) {
        recordAnalytics { onboardingEvents.stepViewed(page.analyticsStep) }
    }

    fun recordHealthSkipped() {
        recordAnalytics { onboardingEvents.healthSkipped() }
    }

    fun recordFolderSkipped() {
        recordAnalytics { onboardingEvents.folderSkipped() }
    }

    fun recordContinueFreeTapped() {
        recordAnalytics { onboardingEvents.continueFreeTapped() }
    }

    fun recordPurchaseTapped() {
        recordAnalytics { onboardingEvents.purchaseTapped() }
    }

    fun completeOnboarding(onComplete: () -> Unit) {
        viewModelScope.launch {
            runCatchingCancellable { settingsRepository.setOnboardingCompleted(true) }
            // Give the durable local queue a brief chance to persist without ever trapping setup.
            withTimeoutOrNull(ANALYTICS_COMPLETION_TIMEOUT_MS) {
                runCatchingCancellable { onboardingEvents.onboardingCompleted() }
            }
            onComplete()
        }
    }

    private fun recordAnalytics(event: suspend () -> Unit) {
        viewModelScope.launch {
            runCatchingCancellable { event() }
        }
    }

    private fun extractFolderName(uriString: String): String? {
        return try {
            val uri = Uri.parse(uriString)
            val docId = DocumentsContract.getTreeDocumentId(uri)
            // docId is typically "primary:FolderName" or similar.
            docId.substringAfterLast(':').substringAfterLast('/')
                .ifBlank { docId.substringAfterLast('/') }
                .takeIf { it.isNotBlank() }
        } catch (_: Exception) {
            null
        }
    }

    private companion object {
        const val ANALYTICS_COMPLETION_TIMEOUT_MS = 500L
    }
}
