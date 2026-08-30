package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportTarget
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import timber.log.Timber

/**
 * DataStore-backed repository for export profiles (Android phase 6 parity).
 *
 * Persistence mirrors the settings repository: one JSON payload for the ordered list plus a
 * separate active-profile id. Every mutation routes through [ExportProfileRules] so the
 * cross-platform contract (unique names, bounded size, last-profile deletion guard, one-time
 * migration, fail-closed resolution) stays identical to iOS.
 */
@Singleton
class ExportProfileRepository @Inject constructor(
    private val dataStore: DataStore<Preferences>,
    @ApplicationContext private val context: Context,
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val listSerializer = ListSerializer(ExportProfile.serializer())

    private object Keys {
        val PROFILES = stringPreferencesKey("export_profiles")
        val ACTIVE_PROFILE_ID = stringPreferencesKey("export_profiles_active_id")
    }

    val profiles: Flow<List<ExportProfile>> = dataStore.data.map { prefs ->
        decodeProfiles(prefs[Keys.PROFILES]).orEmpty()
    }

    val activeProfileId: Flow<String?> = dataStore.data.map { prefs ->
        prefs[Keys.ACTIVE_PROFILE_ID]?.takeIf { id ->
            decodeProfiles(prefs[Keys.PROFILES])?.any { it.id == id } == true
        }
    }

    suspend fun getProfiles(): List<ExportProfile> = profiles.first()

    suspend fun getActiveProfile(): ExportProfile? =
        ExportProfileRules.active(getProfiles(), getActiveProfileId())

    suspend fun getActiveProfileId(): String? = activeProfileId.first()

    suspend fun profileById(id: String): ExportProfile? =
        ExportProfileRules.byId(getProfiles(), id)

    suspend fun profileByName(name: String): ExportProfile? =
        ExportProfileRules.byName(getProfiles(), name)

    /** Adds a profile with a unique name; the first profile becomes active. */
    suspend fun add(
        name: String,
        settingsSnapshotJson: String,
        target: ExportTarget,
        apiEndpointUrl: String? = null,
        folderUri: String? = null,
        folderDisplayName: String? = null,
    ): ExportProfile {
        require(ExportProfileRules.isValidName(name)) { "Profile name must not be blank." }
        val newId = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        var added: ExportProfile? = null
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            require(existing.size < ExportProfileRules.MAX_PROFILES) { "Profile limit reached." }
            val profile = ExportProfile(
                id = newId,
                name = ExportProfileRules.uniquifyName(name, existing),
                settingsSnapshotJson = settingsSnapshotJson,
                target = target,
                apiEndpointUrl = apiEndpointUrl?.takeIf { it.isNotBlank() },
                folderUri = folderUri?.takeIf { it.isNotBlank() },
                folderDisplayName = folderDisplayName?.takeIf { it.isNotBlank() },
                createdAtEpochMillis = now,
                updatedAtEpochMillis = now,
            )
            prefs[Keys.PROFILES] = json.encodeToString(listSerializer, existing + profile)
            val activeId = prefs[Keys.ACTIVE_PROFILE_ID]
            if (activeId == null || existing.none { it.id == activeId }) {
                prefs[Keys.ACTIVE_PROFILE_ID] = profile.id
            }
            added = profile
        }
        return checkNotNull(added) { "Export profiles are unavailable because stored data is invalid." }
    }

    /** Binds a profile to a SAF folder tree URI (or clears the binding with nulls). */
    suspend fun bindFolder(
        id: String,
        folderUri: String?,
        folderDisplayName: String?,
    ): Boolean {
        var applied = false
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            val index = existing.indexOfFirst { it.id == id }
            if (index >= 0) {
                val updated = existing[index].copy(
                    folderUri = folderUri?.takeIf { it.isNotBlank() },
                    folderDisplayName = folderDisplayName?.takeIf { it.isNotBlank() },
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                prefs[Keys.PROFILES] = json.encodeToString(
                    listSerializer,
                    existing.toMutableList().apply { set(index, updated) },
                )
                applied = true
            }
        }
        return applied
    }

    /** Replaces the frozen snapshot (and optionally target/endpoint); bumps updatedAt. */
    suspend fun updateProfile(
        id: String,
        settingsSnapshotJson: String? = null,
        target: ExportTarget? = null,
        apiEndpointUrl: String? = null,
    ): Boolean {
        var applied = false
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            val index = existing.indexOfFirst { it.id == id }
            if (index >= 0) {
                val updated = existing[index].copy(
                    settingsSnapshotJson = settingsSnapshotJson ?: existing[index].settingsSnapshotJson,
                    target = target ?: existing[index].target,
                    apiEndpointUrl = apiEndpointUrl ?: existing[index].apiEndpointUrl,
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                prefs[Keys.PROFILES] = json.encodeToString(
                    listSerializer,
                    existing.toMutableList().apply { set(index, updated) },
                )
                applied = true
            }
        }
        return applied
    }

    /**
     * Full editor update in one atomic DataStore edit: rename (trim + unique suffixing),
     * retarget, rebind the destination — endpoint URL for API targets, SAF folder for folder
     * targets (both cleared when switching away) — and replace the frozen snapshot. Returns
     * the stored name, or null when the profile is unknown or the name is invalid.
     */
    suspend fun applyEditorUpdate(
        id: String,
        rawName: String,
        settingsSnapshotJson: String,
        target: ExportTarget,
        apiEndpointUrl: String?,
        folderUri: String?,
        folderDisplayName: String?,
    ): String? {
        if (!ExportProfileRules.isValidName(rawName)) return null
        var storedName: String? = null
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            val index = existing.indexOfFirst { it.id == id }
            if (index >= 0) {
                val others = existing.filterIndexed { i, _ -> i != index }
                val updated = existing[index].copy(
                    name = ExportProfileRules.uniquifyName(rawName, others),
                    settingsSnapshotJson = settingsSnapshotJson,
                    target = target,
                    apiEndpointUrl = when (target) {
                        ExportTarget.API_ENDPOINT -> apiEndpointUrl?.takeIf { it.isNotBlank() }
                        ExportTarget.DEVICE_FOLDER -> null
                    },
                    folderUri = when (target) {
                        ExportTarget.DEVICE_FOLDER -> folderUri?.takeIf { it.isNotBlank() }
                        ExportTarget.API_ENDPOINT -> null
                    },
                    folderDisplayName = when (target) {
                        ExportTarget.DEVICE_FOLDER -> folderDisplayName?.takeIf { it.isNotBlank() }
                        ExportTarget.API_ENDPOINT -> null
                    },
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                prefs[Keys.PROFILES] = json.encodeToString(
                    listSerializer,
                    existing.toMutableList().apply { set(index, updated) },
                )
                storedName = updated.name
            }
        }
        return storedName
    }

    /** Rename with trim + unique suffixing. Returns the stored name, or null when rejected. */
    suspend fun rename(id: String, rawName: String): String? {
        if (!ExportProfileRules.isValidName(rawName)) return null
        var renamed: String? = null
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            val index = existing.indexOfFirst { it.id == id }
            if (index >= 0) {
                val others = existing.filterIndexed { i, _ -> i != index }
                val unique = ExportProfileRules.uniquifyName(rawName, others)
                val updated = existing[index].copy(
                    name = unique,
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                prefs[Keys.PROFILES] = json.encodeToString(
                    listSerializer,
                    existing.toMutableList().apply { set(index, updated) },
                )
                renamed = unique
            }
        }
        return renamed
    }

    /**
     * Deletes a profile. The last remaining profile is never deleted (cross-platform guard);
     * deleting the active profile activates the first remaining one. Returns false when
     * rejected or unknown.
     */
    suspend fun delete(id: String): Boolean {
        var deleted = false
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            if (ExportProfileRules.canDelete(existing) && existing.any { it.id == id }) {
                val updated = existing.filterNot { it.id == id }
                prefs[Keys.PROFILES] = json.encodeToString(listSerializer, updated)
                if (prefs[Keys.ACTIVE_PROFILE_ID] == id) {
                    updated.firstOrNull()?.let { first -> prefs[Keys.ACTIVE_PROFILE_ID] = first.id }
                }
                deleted = true
            }
        }
        return deleted
    }

    /** Activates a profile for manual exports. Returns false for unknown ids. */
    suspend fun activate(id: String): Boolean {
        var activated = false
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            if (existing.any { it.id == id }) {
                prefs[Keys.ACTIVE_PROFILE_ID] = id
                activated = true
            }
        }
        return activated
    }

    /**
     * One-time migration of current settings into a Default profile bound to the current target
     * and endpoint, activated immediately. No-op when any profile exists.
     */
    suspend fun migrateDefaultIfNeeded(
        settingsSnapshotJson: String,
        target: ExportTarget,
        apiEndpointUrl: String? = null,
    ): ExportProfile? {
        var migrated: ExportProfile? = null
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            val profile = ExportProfileRules.migrateDefault(
                existing = existing,
                snapshotJson = settingsSnapshotJson,
                target = target,
                nowEpochMillis = System.currentTimeMillis(),
                newId = { UUID.randomUUID().toString() },
                apiEndpointUrl = apiEndpointUrl,
            ) ?: return@edit
            prefs[Keys.PROFILES] = json.encodeToString(listSerializer, listOf(profile))
            prefs[Keys.ACTIVE_PROFILE_ID] = profile.id
            migrated = profile
        }
        return migrated
    }

    private fun decodeProfiles(raw: String?): List<ExportProfile>? {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching { json.decodeFromString(listSerializer, raw) }.getOrElse { error ->
            Timber.e(error, "Export profiles failed to decode; blocking profile writes")
            null
        }
    }
}
