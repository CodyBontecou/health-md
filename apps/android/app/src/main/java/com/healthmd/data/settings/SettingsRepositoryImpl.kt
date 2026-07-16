package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import com.healthmd.domain.billing.FreemiumPolicy
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.repository.SettingsRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import java.time.LocalDate

class SettingsRepositoryImpl(
    private val dataStore: DataStore<Preferences>,
    private val context: Context,
) : SettingsRepository {

    private val json = Json { ignoreUnknownKeys = true }

    private object Keys {
        val EXPORT_SETTINGS = stringPreferencesKey("export_settings")
        val EXPORT_FOLDER_URI = stringPreferencesKey("export_folder_uri")
        val FREE_EXPORTS_USED = intPreferencesKey("free_exports_used")
        val LEGACY_FREE_EXPORTS_REMAINING = intPreferencesKey("free_exports_remaining")
        val IS_PURCHASED = booleanPreferencesKey("is_purchased")
        val HAS_COMPLETED_ONBOARDING = booleanPreferencesKey("has_completed_onboarding")
        val SUCCESSFUL_EXPORT_COUNT = intPreferencesKey("successful_export_count")
        val HAS_REQUESTED_REVIEW = booleanPreferencesKey("has_requested_review")
        val FIRST_HEALTH_PERMISSION_GRANT_DATE = stringPreferencesKey("first_health_permission_grant_date")
        val SELECTED_HEALTH_PROVIDER_ID = stringPreferencesKey("selected_health_provider_id")
        val CONNECTED_HEALTH_PROVIDER_IDS = stringSetPreferencesKey("connected_health_provider_ids")
        val LAST_PRESENTED_RELEASE_VERSION = stringPreferencesKey("last_presented_release_version")
    }

    override val exportSettings: Flow<ExportSettings> = dataStore.data.map { prefs ->
        prefs[Keys.EXPORT_SETTINGS]?.let { jsonStr ->
            try {
                decodePersistedExportSettings(jsonStr)
            } catch (_: Exception) {
                ExportSettings()
            }
        } ?: ExportSettings.newInstallDefaults()
    }

    override suspend fun updateExportSettings(settings: ExportSettings) {
        dataStore.edit { prefs ->
            prefs[Keys.EXPORT_SETTINGS] = json.encodeToString(ExportSettings.serializer(), settings.normalized())
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

    override val freeExportsUsed: Flow<Int> = dataStore.data.map { prefs ->
        prefs.freeExportsUsedValue()
    }

    override val freeExportsRemaining: Flow<Int> = freeExportsUsed.map { used ->
        FreemiumPolicy.remainingExports(used)
    }

    override suspend fun recordFreeExportUse() {
        dataStore.edit { prefs ->
            val next = FreemiumPolicy.sanitizedUsedCount(prefs.freeExportsUsedValue() + 1)
            prefs[Keys.FREE_EXPORTS_USED] = next
            prefs.remove(Keys.LEGACY_FREE_EXPORTS_REMAINING)
        }
    }

    override suspend fun decrementFreeExports() {
        recordFreeExportUse()
    }

    override suspend fun resetFreeExports() {
        dataStore.edit { prefs ->
            prefs[Keys.FREE_EXPORTS_USED] = 0
            prefs.remove(Keys.LEGACY_FREE_EXPORTS_REMAINING)
        }
    }

    override suspend fun getFreeExportsUsed(): Int =
        freeExportsUsed.first()

    override suspend fun getFreeExportsRemaining(): Int =
        freeExportsRemaining.first()

    private fun Preferences.freeExportsUsedValue(): Int {
        prefsFreeExportsUsed()?.let { return it }
        val legacyRemaining = this[Keys.LEGACY_FREE_EXPORTS_REMAINING] ?: FreemiumPolicy.FREE_EXPORT_LIMIT
        return FreemiumPolicy.usedCountFromLegacyRemaining(legacyRemaining)
    }

    private fun Preferences.prefsFreeExportsUsed(): Int? =
        this[Keys.FREE_EXPORTS_USED]?.let { FreemiumPolicy.sanitizedUsedCount(it) }

    override val isPurchased: Flow<Boolean> = dataStore.data.map { prefs ->
        prefs[Keys.IS_PURCHASED] ?: isLegacyInstall()
    }

    private fun isLegacyInstall(): Boolean = runCatching {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        FreemiumPolicy.isLegacyUnlock(packageInfo.firstInstallTime)
    }.getOrDefault(false)

    override suspend fun setPurchased(purchased: Boolean) {
        dataStore.edit { prefs ->
            val wasPurchased = prefs[Keys.IS_PURCHASED] ?: false
            prefs[Keys.IS_PURCHASED] = purchased
            if (purchased && !wasPurchased) {
                prefs[Keys.FREE_EXPORTS_USED] = 0
                prefs.remove(Keys.LEGACY_FREE_EXPORTS_REMAINING)
            }
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

    override val selectedHealthProviderId: Flow<String> = dataStore.data.map { prefs ->
        prefs[Keys.SELECTED_HEALTH_PROVIDER_ID] ?: DEFAULT_HEALTH_PROVIDER_ID
    }

    override val connectedHealthProviderIds: Flow<Set<String>> = dataStore.data.map { prefs ->
        prefs[Keys.CONNECTED_HEALTH_PROVIDER_IDS] ?: setOf(DEFAULT_HEALTH_PROVIDER_ID)
    }

    override suspend fun getSelectedHealthProviderId(): String =
        selectedHealthProviderId.first()

    override suspend fun setSelectedHealthProviderId(providerId: String) {
        dataStore.edit { prefs ->
            prefs[Keys.SELECTED_HEALTH_PROVIDER_ID] = providerId
        }
    }

    override suspend fun getConnectedHealthProviderIds(): Set<String> =
        connectedHealthProviderIds.first()

    override suspend fun setHealthProviderConnected(providerId: String, connected: Boolean) {
        dataStore.edit { prefs ->
            val current = prefs[Keys.CONNECTED_HEALTH_PROVIDER_IDS] ?: setOf(DEFAULT_HEALTH_PROVIDER_ID)
            prefs[Keys.CONNECTED_HEALTH_PROVIDER_IDS] = if (connected) {
                current + providerId
            } else {
                (current - providerId).ifEmpty { setOf(DEFAULT_HEALTH_PROVIDER_ID) }
            }
        }
    }

    override val firstHealthPermissionGrantDate: Flow<LocalDate?> = dataStore.data.map { prefs ->
        prefs[Keys.FIRST_HEALTH_PERMISSION_GRANT_DATE]?.let { rawDate ->
            runCatching { LocalDate.parse(rawDate) }.getOrNull()
        }
    }

    override suspend fun getFirstHealthPermissionGrantDate(): LocalDate? =
        firstHealthPermissionGrantDate.first()

    override suspend fun recordHealthPermissionGrantDateIfAbsent(date: LocalDate) {
        dataStore.edit { prefs ->
            if (prefs[Keys.FIRST_HEALTH_PERMISSION_GRANT_DATE].isNullOrBlank()) {
                prefs[Keys.FIRST_HEALTH_PERMISSION_GRANT_DATE] = date.toString()
            }
        }
    }

    override val lastPresentedReleaseVersion: Flow<String?> = dataStore.data.map { prefs ->
        prefs[Keys.LAST_PRESENTED_RELEASE_VERSION]
    }

    override suspend fun getLastPresentedReleaseVersion(): String? =
        lastPresentedReleaseVersion.first()

    override suspend fun setLastPresentedReleaseVersion(version: String) {
        dataStore.edit { prefs ->
            prefs[Keys.LAST_PRESENTED_RELEASE_VERSION] = version
        }
    }

    companion object {
        const val FREE_EXPORT_LIMIT = FreemiumPolicy.FREE_EXPORT_LIMIT
        const val DEFAULT_HEALTH_PROVIDER_ID = "health_connect"
    }
}

internal fun decodePersistedExportSettings(rawJson: String): ExportSettings {
    val json = Json { ignoreUnknownKeys = true }
    val root = json.parseToJsonElement(rawJson).jsonObject
    val decoded = json.decodeFromString<ExportSettings>(rawJson)
    val hasMultiFormatKey = root.containsKey("exportFormats")
    var migrated = if (hasMultiFormatKey) decoded else decoded.copy(exportFormats = setOf(decoded.exportFormat))

    // Before the split, this one switch controlled both aliases and otherwise-lost native values.
    // Freeze that exact behavior explicitly so old scripts/plugins cannot change on upgrade.
    val formatObject = root["formatCustomization"]?.let { element ->
        runCatching { element.jsonObject }.getOrNull()
    }
    val hasSplitSwitches = formatObject?.containsKey("includeLegacyAndroidAliases") == true ||
        formatObject?.containsKey("includeAndroidNativeFields") == true
    if (!hasSplitSwitches) {
        @Suppress("DEPRECATION")
        val legacy = migrated.formatCustomization.includeAndroidCompatibilityKeys
        migrated = migrated.copy(
            formatCustomization = migrated.formatCustomization.copy(
                includeLegacyAndroidAliases = legacy,
                includeAndroidNativeFields = legacy,
                compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
            )
        )
    }
    return migrated.normalized()
}
