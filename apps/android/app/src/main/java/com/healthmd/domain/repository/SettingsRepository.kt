package com.healthmd.domain.repository

import com.healthmd.domain.model.ExportSettings
import kotlinx.coroutines.flow.Flow
import java.time.LocalDate

interface SettingsRepository {
    val exportSettings: Flow<ExportSettings>
    suspend fun updateExportSettings(settings: ExportSettings)
    suspend fun getExportSettings(): ExportSettings

    // One bounded, non-secret shared-setup rollback snapshot and pending endpoint hint.
    suspend fun applySharedSetupTransaction(
        expectedCurrent: ExportSettings,
        candidate: ExportSettings,
        pendingEndpoint: String?,
        preservedAppleExtension: String?,
    ): Boolean
    suspend fun getSharedSetupUndo(): ExportSettings?
    suspend fun undoSharedSetupTransaction(expectedCurrent: ExportSettings): ExportSettings?
    suspend fun rollbackSharedSetupTransaction(expectedCurrent: ExportSettings): ExportSettings?
    suspend fun getPendingSharedSetupEndpoint(): String?
    suspend fun confirmSharedSetupEndpoint(
        expectedCurrent: ExportSettings,
        expectedPendingEndpoint: String,
        candidate: ExportSettings,
    ): Boolean
    suspend fun rollbackSharedSetupEndpointConfirmation(
        expectedCurrent: ExportSettings,
        restored: ExportSettings,
        pendingEndpoint: String,
    ): Boolean
    suspend fun getPreservedSharedSetupAppleExtension(): String?

    // Export folder URI (persisted separately for SAF)
    val exportFolderUri: Flow<String?>
    suspend fun saveExportFolderUri(uri: String)
    suspend fun getExportFolderUri(): String?

    // Free export counter
    val freeExportsUsed: Flow<Int>
    val freeExportsRemaining: Flow<Int>
    suspend fun recordFreeExportUse()
    suspend fun recordFreeExportUseOnce(reservationId: String): Boolean {
        recordFreeExportUse()
        return true
    }
    suspend fun decrementFreeExports()
    suspend fun resetFreeExports()
    suspend fun getFreeExportsUsed(): Int
    suspend fun getFreeExportsRemaining(): Int

    // Purchase status
    val isPurchased: Flow<Boolean>
    suspend fun setPurchased(purchased: Boolean)

    // Onboarding
    val hasCompletedOnboarding: Flow<Boolean>
    /** Resolves and persists the legacy-folder migration before navigation chooses its first route. */
    suspend fun resolveOnboardingCompletion(): Boolean
    suspend fun setOnboardingCompleted(completed: Boolean)

    // In-app review tracking
    suspend fun getSuccessfulExportCount(): Int
    suspend fun incrementSuccessfulExportCount()
    suspend fun getLastReviewAttemptEpochMillis(migrationEpochMillis: Long): Long?
    suspend fun recordReviewAttempt(epochMillis: Long)

    // Health provider selection / direct-provider connection state
    val selectedHealthProviderId: Flow<String>
    val connectedHealthProviderIds: Flow<Set<String>>
    suspend fun getSelectedHealthProviderId(): String
    suspend fun setSelectedHealthProviderId(providerId: String)
    suspend fun getConnectedHealthProviderIds(): Set<String>
    suspend fun setHealthProviderConnected(providerId: String, connected: Boolean)

    // Health Connect permission history tracking
    val firstHealthPermissionGrantDate: Flow<LocalDate?>
    suspend fun getFirstHealthPermissionGrantDate(): LocalDate?
    suspend fun recordHealthPermissionGrantDateIfAbsent(date: LocalDate)

    // In-app release notes tracking
    val lastPresentedReleaseVersion: Flow<String?>
    suspend fun getLastPresentedReleaseVersion(): String?
    suspend fun setLastPresentedReleaseVersion(version: String)
}
