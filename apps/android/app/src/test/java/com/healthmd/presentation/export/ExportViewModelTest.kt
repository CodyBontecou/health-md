package com.healthmd.presentation.export

import com.android.billingclient.api.ProductDetails
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.APIExportUploadResult
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.export.APIExportUploader
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.data.health.HealthProviderDiagnosticsReporter
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.billing.FreemiumPolicy
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.BillingRepository
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.settings.SettingsViewModel
import com.healthmd.rawexport.ExportMode
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import java.time.LocalDate

@OptIn(ExperimentalCoroutinesApi::class)
class ExportViewModelTest {

    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    @Test
    fun largeExportMissingHistoricalPermissionDoesNotExport() = runTest {
        val healthRepository = FakeHealthRepository(
            hasPermissions = true,
            hasHistoricalReadPermission = false,
        )
        val exportRepository = FakeExportRepository()
        val historyRepository = FakeExportHistoryRepository()
        val viewModel = createViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            exportHistoryRepository = historyRepository,
        )
        advanceUntilIdle()

        val today = LocalDate.now()
        viewModel.setStartDate(today.minusDays(89))
        viewModel.setEndDate(today)

        assertThat(viewModel.uiState.value.requiresHistoricalReadPermission).isTrue()
        assertThat(viewModel.uiState.value.historyPermissionNeeded).isTrue()

        viewModel.startExport()
        advanceUntilIdle()

        assertThat(healthRepository.fetchCalls).isEqualTo(0)
        assertThat(exportRepository.exportCalls).isEqualTo(0)
        assertThat(historyRepository.entries).isEmpty()
        assertThat(viewModel.uiState.value.isExporting).isFalse()
    }

    @Test
    fun recentExportWithRegularPermissionsOnlyExports() = runTest {
        val healthRepository = FakeHealthRepository(
            hasPermissions = true,
            hasHistoricalReadPermission = false,
        )
        val exportRepository = FakeExportRepository()
        val historyRepository = FakeExportHistoryRepository()
        val viewModel = createViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            exportHistoryRepository = historyRepository,
        )
        advanceUntilIdle()

        val today = LocalDate.now()
        viewModel.setStartDate(today.minusDays(6))
        viewModel.setEndDate(today)

        assertThat(viewModel.uiState.value.requiresHistoricalReadPermission).isFalse()
        assertThat(viewModel.uiState.value.historyPermissionNeeded).isFalse()

        viewModel.startExport()
        advanceUntilIdle()

        assertThat(healthRepository.fetchCalls).isEqualTo(7)
        assertThat(exportRepository.exportCalls).isEqualTo(7)
        assertThat(historyRepository.entries).hasSize(1)
        assertThat(historyRepository.entries.single().successCount).isEqualTo(7)
        assertThat(historyRepository.entries.single().totalCount).isEqualTo(7)
    }

    @Test
    fun previewDoesNotRequireAnExportDestination() = runTest {
        val today = LocalDate.now()
        val healthRepository = FakeHealthRepository(hasPermissions = true)
        val exportRepository = FakeExportRepository()
        val settingsRepository = FakeSettingsRepository(initialFolderUri = null)
        val viewModel = createViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
        )
        advanceUntilIdle()
        viewModel.setDateRange(today, today)

        viewModel.buildPreview()
        advanceUntilIdle()

        assertThat(viewModel.uiState.value.folderName).isNull()
        assertThat(viewModel.uiState.value.preview).isNotNull()
        assertThat(viewModel.uiState.value.preview?.totalFileCount).isEqualTo(1)
        assertThat(exportRepository.previewCalls).isEqualTo(1)
        assertThat(exportRepository.exportCalls).isEqualTo(0)
    }

    @Test
    fun apiExportDoesNotRequireFolderAndRecordsApiHistoryAndAccounting() = runTest {
        val today = LocalDate.now()
        val healthRepository = FakeHealthRepository(hasPermissions = true)
        val exportRepository = FakeExportRepository()
        val historyRepository = FakeExportHistoryRepository()
        val settingsRepository = FakeSettingsRepository(
            initialSettings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
            ),
            initialFolderUri = null,
        )
        var uploadCalls = 0
        val uploader = object : APIExportUploader {
            override suspend fun upload(
                endpointUrl: String,
                payload: String,
                authorizationHeader: String?,
                requestHeaders: List<APIExportRequestHeader>,
            ): APIExportUploadResult {
                uploadCalls++
                return APIExportUploadResult(202)
            }
        }
        val credentials = object : APIExportCredentialStore {
            override suspend fun authorizationHeader(): String? = null
            override suspend fun hasAuthorization(): Boolean = false
            override suspend fun saveAuthorization(value: String) = Unit
            override suspend fun clearAuthorization() = Unit
        }
        val jsonExporter = JsonExporter()
        val apiRunner = APIEndpointExportRunner(
            healthRepository = healthRepository,
            envelopeBuilder = APIExportEnvelopeBuilder(jsonExporter),
            jsonExporter = jsonExporter,
            uploader = uploader,
            credentialStore = credentials,
        )
        val viewModel = createViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
            exportHistoryRepository = historyRepository,
            apiEndpointExportRunner = apiRunner,
        )
        advanceUntilIdle()
        viewModel.setDateRange(today, today)

        viewModel.startExport()
        advanceUntilIdle()

        assertThat(uploadCalls).isEqualTo(1)
        assertThat(exportRepository.exportCalls).isEqualTo(0)
        assertThat(historyRepository.entries).hasSize(1)
        assertThat(historyRepository.entries.single().target).isEqualTo(ExportTarget.API_ENDPOINT)
        assertThat(historyRepository.entries.single().fileCount).isEqualTo(0)
        assertThat(settingsRepository.getFreeExportsUsed()).isEqualTo(1)
        assertThat(viewModel.uiState.value.exportedFolderUri).isNull()
    }

    @Test
    fun rawExportDispatchesOnceWithoutCompatibilityHealthDataAndPreviewStaysDisabled() = runTest {
        val today = LocalDate.now()
        val healthRepository = FakeHealthRepository(hasPermissions = true)
        val exportRepository = FakeExportRepository()
        val historyRepository = FakeExportHistoryRepository()
        val settingsRepository = FakeSettingsRepository(
            initialSettings = ExportSettings(exportMode = ExportMode.RAW_SNAPSHOT),
        )
        var rawCalls = 0
        val rawService = object : RawSnapshotService {
            override suspend fun exportRange(
                startDate: LocalDate,
                endDate: LocalDate,
                settings: ExportSettings,
                target: ExportTarget,
                expectedDestinationFingerprint: String?,
            ): ExportResult {
                rawCalls++
                return ExportResult(1, 1, target = target)
            }
        }
        val viewModel = createViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
            exportHistoryRepository = historyRepository,
            rawSnapshotService = rawService,
        )
        advanceUntilIdle()
        viewModel.setDateRange(today.minusDays(2), today)

        viewModel.buildPreview()
        advanceUntilIdle()
        assertThat(exportRepository.previewCalls).isEqualTo(0)
        assertThat(viewModel.uiState.value.preview).isNull()

        viewModel.startExport()
        advanceUntilIdle()

        assertThat(rawCalls).isEqualTo(1)
        assertThat(healthRepository.fetchCalls).isEqualTo(0)
        assertThat(exportRepository.exportCalls).isEqualTo(0)
        assertThat(historyRepository.entries.single().totalCount).isEqualTo(1)
        assertThat(settingsRepository.getFreeExportsUsed()).isEqualTo(1)
    }

    @Test
    fun rangeInsideThirtyDaysFromTodayButOlderThanFirstGrantNeedsHistoricalPermission() = runTest {
        val today = LocalDate.now()
        val healthRepository = FakeHealthRepository(
            hasPermissions = true,
            hasHistoricalReadPermission = false,
        )
        val exportRepository = FakeExportRepository()
        val historyRepository = FakeExportHistoryRepository()
        val settingsRepository = FakeSettingsRepository(
            initialFirstHealthPermissionGrantDate = today,
        )
        val viewModel = createViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
            exportHistoryRepository = historyRepository,
        )
        advanceUntilIdle()

        viewModel.setStartDate(today.minusDays(30))
        viewModel.setEndDate(today.minusDays(26))

        assertThat(viewModel.uiState.value.requiresHistoricalReadPermission).isTrue()
        assertThat(viewModel.uiState.value.historyPermissionNeeded).isTrue()

        viewModel.startExport()
        advanceUntilIdle()

        assertThat(healthRepository.fetchCalls).isEqualTo(0)
        assertThat(exportRepository.exportCalls).isEqualTo(0)
        assertThat(historyRepository.entries).isEmpty()
    }

    @Test
    fun allTimeExportMissingHistoricalPermissionDoesNotExportEvenWhenVisibleDataIsRecent() = runTest {
        val today = LocalDate.now()
        val healthRepository = FakeHealthRepository(
            hasPermissions = true,
            hasHistoricalReadPermission = false,
            earliestDataDate = today.minusDays(6),
        )
        val exportRepository = FakeExportRepository()
        val historyRepository = FakeExportHistoryRepository()
        val viewModel = createViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            exportHistoryRepository = historyRepository,
        )
        advanceUntilIdle()

        viewModel.selectAllTime()
        advanceUntilIdle()

        assertThat(viewModel.uiState.value.allTimeSelected).isTrue()
        assertThat(viewModel.uiState.value.requiresHistoricalReadPermission).isTrue()
        assertThat(viewModel.uiState.value.historyPermissionNeeded).isTrue()

        viewModel.startExport()
        advanceUntilIdle()

        assertThat(healthRepository.fetchCalls).isEqualTo(0)
        assertThat(exportRepository.exportCalls).isEqualTo(0)
        assertThat(historyRepository.entries).isEmpty()
    }

    @Test
    fun bothResetActionsUseNewInstallAnalyticalDefaults() = runTest {
        val frozen = ExportSettings(
            exportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/raw",
            formatCustomization = FormatCustomization(
                compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
            ),
        )
        val exportSettings = FakeSettingsRepository(initialSettings = frozen)
        val exportViewModel = createViewModel(
            healthRepository = FakeHealthRepository(hasPermissions = true),
            settingsRepository = exportSettings,
        )
        advanceUntilIdle()

        exportViewModel.resetSettings()
        advanceUntilIdle()

        val exportReset = exportSettings.getExportSettings()
        assertThat(exportReset.formatCustomization.compatibilitySchemaProfile)
            .isEqualTo(CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5)
        assertThat(exportReset.formatCustomization.includeAndroidNativeFields).isTrue()
        assertThat(exportReset.exportTarget).isEqualTo(ExportTarget.API_ENDPOINT)
        assertThat(exportReset.apiEndpointUrl).isEqualTo("https://example.test/raw")

        val settingsRepository = FakeSettingsRepository(initialSettings = frozen)
        val settingsViewModel = SettingsViewModel(
            settingsRepository,
            mockk<HealthProviderCatalog>(relaxed = true),
            mockk<OAuthAuthorizationManager>(relaxed = true),
            mockk<HealthProviderDiagnosticsReporter>(relaxed = true),
        )
        settingsViewModel.resetSettings()
        advanceUntilIdle()

        val settingsReset = settingsRepository.getExportSettings()
        assertThat(settingsReset.formatCustomization.compatibilitySchemaProfile)
            .isEqualTo(CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5)
        assertThat(settingsReset.formatCustomization.includeAndroidNativeFields).isTrue()
    }

    private fun createViewModel(
        healthRepository: HealthRepository,
        exportRepository: ExportRepository = FakeExportRepository(),
        settingsRepository: SettingsRepository = FakeSettingsRepository(),
        billingRepository: BillingRepository = FakeBillingRepository(),
        exportHistoryRepository: ExportHistoryRepository = FakeExportHistoryRepository(),
        apiEndpointExportRunner: APIEndpointExportRunner? = null,
        rawSnapshotService: RawSnapshotService? = null,
    ): ExportViewModel {
        val fileExportManager = mockk<FileExportManager>(relaxed = true)
        every { fileExportManager.getFolderDisplayName(any()) } returns "Health.md"

        return ExportViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
            billingRepository = billingRepository,
            exportHistoryRepository = exportHistoryRepository,
            fileExportManager = fileExportManager,
            apiEndpointExportRunner = apiEndpointExportRunner,
            rawSnapshotExportRunner = rawSnapshotService,
        )
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    private val testDispatcher: TestDispatcher = StandardTestDispatcher(),
) : TestWatcher() {
    override fun starting(description: Description) {
        Dispatchers.setMain(testDispatcher)
    }

    override fun finished(description: Description) {
        Dispatchers.resetMain()
    }
}

private class FakeHealthRepository(
    private val hasPermissions: Boolean = true,
    private val hasHistoricalReadPermission: Boolean = true,
    private val earliestDataDate: LocalDate? = null,
) : HealthRepository {
    var fetchCalls = 0
        private set

    override suspend fun fetchHealthData(date: LocalDate): HealthData {
        fetchCalls++
        return HealthData(
            date = date,
            activity = ActivityData(steps = 1),
        )
    }

    override suspend fun isAvailable(): Boolean = true

    override suspend fun hasPermissions(): Boolean = hasPermissions

    override suspend fun hasHistoricalReadPermission(): Boolean = hasHistoricalReadPermission

    override suspend fun hasBackgroundReadPermission(): Boolean = true

    override suspend fun getEarliestDataDate(): LocalDate? = earliestDataDate

    override fun isBeforeFirstUnlock(): Boolean = false
}

private class FakeExportRepository : ExportRepository {
    var exportCalls = 0
        private set
    var previewCalls = 0
        private set

    override suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean {
        exportCalls++
        return true
    }

    override suspend fun previewHealthData(data: HealthData, settings: ExportSettings): ExportPreviewDay {
        previewCalls++
        return ExportPreviewDay(
            date = data.date,
            files = listOf(
                ExportPreviewFile(
                    format = ExportFormat.MARKDOWN,
                    relativePath = "health/${data.date}.md",
                    byteCount = 7,
                    content = "preview",
                )
            ),
        )
    }

    override suspend fun hasExportFolder(): Boolean = true

    override fun getExportFolderName(): String? = "Health.md"
}

private class FakeSettingsRepository(
    initialFirstHealthPermissionGrantDate: LocalDate? = null,
    initialSettings: ExportSettings = ExportSettings(),
    initialFolderUri: String? = "content://health-md",
) : SettingsRepository {
    private val exportSettingsState = MutableStateFlow(initialSettings)
    private val exportFolderUriState = MutableStateFlow(initialFolderUri)
    private val freeExportsUsedState = MutableStateFlow(0)
    private val isPurchasedState = MutableStateFlow(false)
    private val hasCompletedOnboardingState = MutableStateFlow(true)
    private val selectedHealthProviderIdState = MutableStateFlow("health_connect")
    private val connectedHealthProviderIdsState = MutableStateFlow(setOf("health_connect"))
    private val firstHealthPermissionGrantDateState = MutableStateFlow(initialFirstHealthPermissionGrantDate)
    private val lastPresentedReleaseVersionState = MutableStateFlow<String?>(null)
    private var successfulExportCount = 0
    private var requestedReview = false

    override val exportSettings: Flow<ExportSettings> = exportSettingsState
    override val exportFolderUri: Flow<String?> = exportFolderUriState
    override val freeExportsUsed: Flow<Int> = freeExportsUsedState
    override val freeExportsRemaining: Flow<Int> = freeExportsUsedState.map { FreemiumPolicy.remainingExports(it) }
    override val isPurchased: Flow<Boolean> = isPurchasedState
    override val hasCompletedOnboarding: Flow<Boolean> = hasCompletedOnboardingState
    override val selectedHealthProviderId: Flow<String> = selectedHealthProviderIdState
    override val connectedHealthProviderIds: Flow<Set<String>> = connectedHealthProviderIdsState
    override val firstHealthPermissionGrantDate: Flow<LocalDate?> = firstHealthPermissionGrantDateState
    override val lastPresentedReleaseVersion: Flow<String?> = lastPresentedReleaseVersionState

    override suspend fun updateExportSettings(settings: ExportSettings) {
        exportSettingsState.value = settings
    }

    override suspend fun getExportSettings(): ExportSettings = exportSettingsState.value

    override suspend fun saveExportFolderUri(uri: String) {
        exportFolderUriState.value = uri
    }

    override suspend fun getExportFolderUri(): String? = exportFolderUriState.value

    override suspend fun recordFreeExportUse() {
        freeExportsUsedState.value = FreemiumPolicy.sanitizedUsedCount(freeExportsUsedState.value + 1)
    }

    override suspend fun decrementFreeExports() {
        recordFreeExportUse()
    }

    override suspend fun resetFreeExports() {
        freeExportsUsedState.value = 0
    }

    override suspend fun getFreeExportsUsed(): Int = freeExportsUsedState.value

    override suspend fun getFreeExportsRemaining(): Int = FreemiumPolicy.remainingExports(freeExportsUsedState.value)

    override suspend fun setPurchased(purchased: Boolean) {
        val wasPurchased = isPurchasedState.value
        isPurchasedState.value = purchased
        if (purchased && !wasPurchased) resetFreeExports()
    }

    override suspend fun setOnboardingCompleted(completed: Boolean) {
        hasCompletedOnboardingState.value = completed
    }

    override suspend fun getSuccessfulExportCount(): Int = successfulExportCount

    override suspend fun incrementSuccessfulExportCount() {
        successfulExportCount++
    }

    override suspend fun hasRequestedReview(): Boolean = requestedReview

    override suspend fun setReviewRequested() {
        requestedReview = true
    }

    override suspend fun getSelectedHealthProviderId(): String = selectedHealthProviderIdState.value

    override suspend fun setSelectedHealthProviderId(providerId: String) {
        selectedHealthProviderIdState.value = providerId
    }

    override suspend fun getConnectedHealthProviderIds(): Set<String> = connectedHealthProviderIdsState.value

    override suspend fun setHealthProviderConnected(providerId: String, connected: Boolean) {
        connectedHealthProviderIdsState.value = if (connected) {
            connectedHealthProviderIdsState.value + providerId
        } else {
            connectedHealthProviderIdsState.value - providerId
        }
    }

    override suspend fun getFirstHealthPermissionGrantDate(): LocalDate? = firstHealthPermissionGrantDateState.value

    override suspend fun recordHealthPermissionGrantDateIfAbsent(date: LocalDate) {
        if (firstHealthPermissionGrantDateState.value == null) {
            firstHealthPermissionGrantDateState.value = date
        }
    }

    override suspend fun getLastPresentedReleaseVersion(): String? = lastPresentedReleaseVersionState.value

    override suspend fun setLastPresentedReleaseVersion(version: String) {
        lastPresentedReleaseVersionState.value = version
    }
}

private class FakeBillingRepository : BillingRepository {
    override val isUnlocked: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    override val isPurchasing: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    override val isRestoring: StateFlow<Boolean> = MutableStateFlow(false).asStateFlow()
    override val purchaseError: StateFlow<String?> = MutableStateFlow<String?>(null).asStateFlow()
    override val productDetails: StateFlow<ProductDetails?> = MutableStateFlow<ProductDetails?>(null).asStateFlow()

    override fun startConnection() = Unit
    override suspend fun queryProduct() = Unit
    override suspend fun launchPurchase(activity: android.app.Activity): Boolean = true
    override suspend fun refreshPurchaseStatus() = Unit
    override suspend fun restorePurchase(): Boolean = false
    override suspend fun acknowledgePurchase(purchaseToken: String) = Unit
    override fun clearError() = Unit
    override fun endConnection() = Unit
    override fun debugSetUnlocked(unlocked: Boolean) = Unit
    override fun debugResetPurchaseState() = Unit
}

private class FakeExportHistoryRepository : ExportHistoryRepository {
    val entries = mutableListOf<ExportHistoryEntry>()

    override fun getAllEntries(): Flow<List<ExportHistoryEntry>> = MutableStateFlow(entries)

    override suspend fun insertEntry(entry: ExportHistoryEntry) {
        entries += entry
    }

    override suspend fun deleteEntry(id: Long) = Unit

    override suspend fun clearAll() {
        entries.clear()
    }
}
