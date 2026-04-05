package com.healthmd.domain.repository

import com.healthmd.domain.model.ExportSettings
import kotlinx.coroutines.flow.Flow

interface SettingsRepository {
    val exportSettings: Flow<ExportSettings>
    suspend fun updateExportSettings(settings: ExportSettings)
    suspend fun getExportSettings(): ExportSettings

    // Export folder URI (persisted separately for SAF)
    val exportFolderUri: Flow<String?>
    suspend fun saveExportFolderUri(uri: String)
    suspend fun getExportFolderUri(): String?

    // Free export counter
    val freeExportsRemaining: Flow<Int>
    suspend fun decrementFreeExports()
    suspend fun getFreeExportsRemaining(): Int

    // Purchase status
    val isPurchased: Flow<Boolean>
    suspend fun setPurchased(purchased: Boolean)

    // Onboarding
    val hasCompletedOnboarding: Flow<Boolean>
    suspend fun setOnboardingCompleted(completed: Boolean)
}
