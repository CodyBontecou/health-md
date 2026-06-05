package com.healthmd.export

import android.app.Activity
import com.android.billingclient.api.ProductDetails
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.BillingRepository
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import java.time.LocalDate

class FakeHealthRepository : HealthRepository {
    private val dataByDate = mutableMapOf<LocalDate, HealthData>()

    val fetchedDates = mutableListOf<LocalDate>()
    var available: Boolean = true
    var permissionsGranted: Boolean = true
    var historicalReadPermissionGranted: Boolean = true
    var backgroundReadPermissionGranted: Boolean = true
    var earliestDataDate: LocalDate? = null
    var beforeFirstUnlock: Boolean = false
    var fetchBehavior: suspend (LocalDate) -> HealthData = { date ->
        dataByDate[date] ?: HealthData(date)
    }

    fun putData(data: HealthData) {
        dataByDate[data.date] = data
    }

    override suspend fun fetchHealthData(date: LocalDate): HealthData {
        fetchedDates.add(date)
        return fetchBehavior(date)
    }

    override suspend fun isAvailable(): Boolean = available

    override suspend fun hasPermissions(): Boolean = permissionsGranted

    override suspend fun hasHistoricalReadPermission(): Boolean = historicalReadPermissionGranted

    override suspend fun hasBackgroundReadPermission(): Boolean = backgroundReadPermissionGranted

    override suspend fun getEarliestDataDate(): LocalDate? = earliestDataDate

    override fun isBeforeFirstUnlock(): Boolean = beforeFirstUnlock
}

class FakeExportRepository : ExportRepository {
    val exportedDates = mutableListOf<LocalDate>()
    val exportedData = mutableListOf<HealthData>()
    val exportSettings = mutableListOf<ExportSettings>()
    val resultsByDate = mutableMapOf<LocalDate, Boolean>()
    var defaultResult: Boolean = true
    var hasFolder: Boolean = true
    var folderName: String? = "Health.md"
    var exportBehavior: suspend (HealthData, ExportSettings) -> Boolean = { data, _ ->
        resultsByDate[data.date] ?: defaultResult
    }

    override suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean {
        exportedDates.add(data.date)
        exportedData.add(data)
        exportSettings.add(settings)
        return exportBehavior(data, settings)
    }

    override suspend fun hasExportFolder(): Boolean = hasFolder

    override fun getExportFolderName(): String? = folderName
}

class FakeSettingsRepository(
    initialSettings: ExportSettings = ExportSettings(),
    initialFolderUri: String? = "content://exports",
    initialFreeExportsRemaining: Int = 3,
    initialPurchased: Boolean = false,
) : SettingsRepository {
    private val exportSettingsState = MutableStateFlow(initialSettings)
    private val exportFolderUriState = MutableStateFlow(initialFolderUri)
    private val freeExportsRemainingState = MutableStateFlow(initialFreeExportsRemaining)
    private val isPurchasedState = MutableStateFlow(initialPurchased)
    private val hasCompletedOnboardingState = MutableStateFlow(false)
    private val lastPresentedReleaseVersionState = MutableStateFlow<String?>(null)

    var decrementFreeExportsCalls: Int = 0
        private set
    var successfulExportCount: Int = 0
        private set
    var reviewRequested: Boolean = false
        private set

    override val exportSettings: Flow<ExportSettings> = exportSettingsState

    override suspend fun updateExportSettings(settings: ExportSettings) {
        exportSettingsState.value = settings
    }

    override suspend fun getExportSettings(): ExportSettings = exportSettingsState.value

    override val exportFolderUri: Flow<String?> = exportFolderUriState

    override suspend fun saveExportFolderUri(uri: String) {
        exportFolderUriState.value = uri
    }

    override suspend fun getExportFolderUri(): String? = exportFolderUriState.value

    override val freeExportsRemaining: Flow<Int> = freeExportsRemainingState

    override suspend fun decrementFreeExports() {
        decrementFreeExportsCalls++
        if (freeExportsRemainingState.value > 0) {
            freeExportsRemainingState.value = freeExportsRemainingState.value - 1
        }
    }

    override suspend fun getFreeExportsRemaining(): Int = freeExportsRemainingState.value

    override val isPurchased: Flow<Boolean> = isPurchasedState

    override suspend fun setPurchased(purchased: Boolean) {
        isPurchasedState.value = purchased
    }

    override val hasCompletedOnboarding: Flow<Boolean> = hasCompletedOnboardingState

    override suspend fun setOnboardingCompleted(completed: Boolean) {
        hasCompletedOnboardingState.value = completed
    }

    override suspend fun getSuccessfulExportCount(): Int = successfulExportCount

    override suspend fun incrementSuccessfulExportCount() {
        successfulExportCount++
    }

    override suspend fun hasRequestedReview(): Boolean = reviewRequested

    override suspend fun setReviewRequested() {
        reviewRequested = true
    }

    override val lastPresentedReleaseVersion: Flow<String?> = lastPresentedReleaseVersionState

    override suspend fun getLastPresentedReleaseVersion(): String? = lastPresentedReleaseVersionState.value

    override suspend fun setLastPresentedReleaseVersion(version: String) {
        lastPresentedReleaseVersionState.value = version
    }
}

class FakeExportHistoryRepository : ExportHistoryRepository {
    private val entriesState = MutableStateFlow<List<ExportHistoryEntry>>(emptyList())
    val entries = mutableListOf<ExportHistoryEntry>()

    override fun getAllEntries(): Flow<List<ExportHistoryEntry>> = entriesState

    override suspend fun insertEntry(entry: ExportHistoryEntry) {
        entries.add(entry)
        entriesState.value = entries.toList()
    }

    override suspend fun deleteEntry(id: Long) {
        entries.removeAll { it.id == id }
        entriesState.value = entries.toList()
    }

    override suspend fun clearAll() {
        entries.clear()
        entriesState.value = emptyList()
    }
}

class FakeBillingRepository(initialUnlocked: Boolean = false) : BillingRepository {
    override val isUnlocked = MutableStateFlow(initialUnlocked)
    override val isPurchasing = MutableStateFlow(false)
    override val isRestoring = MutableStateFlow(false)
    override val purchaseError = MutableStateFlow<String?>(null)
    override val productDetails = MutableStateFlow<ProductDetails?>(null)

    var startConnectionCalls: Int = 0
        private set

    override fun startConnection() {
        startConnectionCalls++
    }

    override suspend fun queryProduct() = Unit

    override suspend fun launchPurchase(activity: Activity): Boolean = true

    override suspend fun refreshPurchaseStatus() = Unit

    override suspend fun restorePurchase(): Boolean = isUnlocked.value

    override suspend fun acknowledgePurchase(purchaseToken: String) = Unit

    override fun clearError() {
        purchaseError.value = null
    }

    override fun endConnection() = Unit

    override fun debugSetUnlocked(unlocked: Boolean) {
        isUnlocked.value = unlocked
    }

    override fun debugResetPurchaseState() {
        isUnlocked.value = false
        purchaseError.value = null
    }
}

@OptIn(ExperimentalCoroutinesApi::class)
class MainDispatcherRule(
    val testDispatcher: TestDispatcher = StandardTestDispatcher(),
) : TestWatcher() {
    override fun starting(description: Description) {
        Dispatchers.setMain(testDispatcher)
    }

    override fun finished(description: Description) {
        Dispatchers.resetMain()
    }
}
