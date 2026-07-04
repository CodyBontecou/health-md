package com.healthmd.domain.repository

import com.healthmd.domain.model.ExportSettings
import kotlinx.coroutines.flow.Flow
import java.time.LocalDate

interface SettingsRepository {
    val exportSettings: Flow<ExportSettings>
    suspend fun updateExportSettings(settings: ExportSettings)
    suspend fun getExportSettings(): ExportSettings

    // Export folder URI (persisted separately for SAF)
    val exportFolderUri: Flow<String?>
    suspend fun saveExportFolderUri(uri: String)
    suspend fun getExportFolderUri(): String?

    // Free export counter
    val freeExportsUsed: Flow<Int>
    val freeExportsRemaining: Flow<Int>
    suspend fun recordFreeExportUse()
    suspend fun decrementFreeExports()
    suspend fun resetFreeExports()
    suspend fun getFreeExportsUsed(): Int
    suspend fun getFreeExportsRemaining(): Int

    // Purchase status
    val isPurchased: Flow<Boolean>
    suspend fun setPurchased(purchased: Boolean)

    // Onboarding
    val hasCompletedOnboarding: Flow<Boolean>
    suspend fun setOnboardingCompleted(completed: Boolean)

    // In-app review tracking
    suspend fun getSuccessfulExportCount(): Int
    suspend fun incrementSuccessfulExportCount()
    suspend fun hasRequestedReview(): Boolean
    suspend fun setReviewRequested()

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
