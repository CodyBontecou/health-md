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
        prefs[Keys.IS_PURCHASED] ?: true // TODO: restore to `false` before release; wire real BillingRepository
    }

    override suspend fun setPurchased(purchased: Boolean) {
        dataStore.edit { prefs ->
            prefs[Keys.IS_PURCHASED] = purchased
        }
    }

    companion object {
        const val FREE_EXPORT_LIMIT = 3
    }
}
