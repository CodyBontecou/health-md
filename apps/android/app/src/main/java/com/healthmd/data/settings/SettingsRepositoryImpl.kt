package com.healthmd.data.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.repository.SettingsRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json

class SettingsRepositoryImpl(
    private val dataStore: DataStore<Preferences>,
) : SettingsRepository {

    private val json = Json { ignoreUnknownKeys = true }

    private object Keys {
        val EXPORT_SETTINGS = stringPreferencesKey("export_settings")
        val EXPORT_FOLDER_URI = stringPreferencesKey("export_folder_uri")
        val FREE_EXPORTS_REMAINING = intPreferencesKey("free_exports_remaining")
        val IS_PURCHASED = booleanPreferencesKey("is_purchased")
        val HAS_COMPLETED_ONBOARDING = booleanPreferencesKey("has_completed_onboarding")
        val SUCCESSFUL_EXPORT_COUNT = intPreferencesKey("successful_export_count")
        val HAS_REQUESTED_REVIEW = booleanPreferencesKey("has_requested_review")
    }

    override val exportSettings: Flow<ExportSettings> = dataStore.data.map { prefs ->
        prefs[Keys.EXPORT_SETTINGS]?.let { jsonStr ->
            try {
                json.decodeFromString<ExportSettings>(jsonStr)
            } catch (_: Exception) {
                ExportSettings()
            }
        } ?: ExportSettings()
    }

    override suspend fun updateExportSettings(settings: ExportSettings) {
        dataStore.edit { prefs ->
            prefs[Keys.EXPORT_SETTINGS] = json.encodeToString(ExportSettings.serializer(), settings)
        }
    }

    override suspend fun getExportSettings(): ExportSettings =
        exportSettings.first()

    override val exportFolderUri: Flow<String?> = dataStore.data.map { prefs ->
        prefs[Keys.EXPORT_FOLDER_URI]
    }

    override suspend fun saveExportFolderUri(uri: String) {
        dataStore.edit { prefs ->
            prefs[Keys.EXPORT_FOLDER_URI] = uri
        }
    }

    override suspend fun getExportFolderUri(): String? =
        exportFolderUri.first()

    override val freeExportsRemaining: Flow<Int> = dataStore.data.map { prefs ->
        prefs[Keys.FREE_EXPORTS_REMAINING] ?: FREE_EXPORT_LIMIT
    }

    override suspend fun decrementFreeExports() {
        dataStore.edit { prefs ->
            val current = prefs[Keys.FREE_EXPORTS_REMAINING] ?: FREE_EXPORT_LIMIT
            if (current > 0) {
                prefs[Keys.FREE_EXPORTS_REMAINING] = current - 1
            }
        }
    }

    override suspend fun getFreeExportsRemaining(): Int =
        freeExportsRemaining.first()

    override val isPurchased: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[Keys.IS_PURCHASED] ?: false
    }

    override suspend fun setPurchased(purchased: Boolean) {
        dataStore.edit { prefs ->
            prefs[Keys.IS_PURCHASED] = purchased
        }
    }

    override val hasCompletedOnboarding: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[Keys.HAS_COMPLETED_ONBOARDING] ?: false
    }

    override suspend fun setOnboardingCompleted(completed: Boolean) {
        dataStore.edit { prefs ->
            prefs[Keys.HAS_COMPLETED_ONBOARDING] = completed
        }
    }

    override suspend fun getSuccessfulExportCount(): Int =
        dataStore.data.map { it[Keys.SUCCESSFUL_EXPORT_COUNT] ?: 0 }.first()

    override suspend fun incrementSuccessfulExportCount() {
        dataStore.edit { prefs ->
            val current = prefs[Keys.SUCCESSFUL_EXPORT_COUNT] ?: 0
            prefs[Keys.SUCCESSFUL_EXPORT_COUNT] = current + 1
        }
    }

    override suspend fun hasRequestedReview(): Boolean =
        dataStore.data.map { it[Keys.HAS_REQUESTED_REVIEW] ?: false }.first()

    override suspend fun setReviewRequested() {
        dataStore.edit { prefs ->
            prefs[Keys.HAS_REQUESTED_REVIEW] = true
        }
    }

    companion object {
        const val FREE_EXPORT_LIMIT = 3
    }
}
