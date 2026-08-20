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
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

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
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; encodeDefaults = true }

    @Serializable
    private data class ProfileEnvelope(
        val version: Int = PROFILE_ENVELOPE_VERSION,
        val records: List<JsonElement> = emptyList(),
    )

    private data class DecodedProfiles(
        val profiles: List<ExportProfile>,
        val opaque: List<JsonElement>,
        val corruptRoot: Boolean = false,
    ) {
        val blocksDefaultMigration: Boolean get() = corruptRoot || opaque.isNotEmpty()
    }

    private object Keys {
        // V1 stays untouched so an older binary never encounters a GOOGLE_DRIVE enum record.
        val PROFILES = stringPreferencesKey("export_profiles")
        val ACTIVE_PROFILE_ID = stringPreferencesKey("export_profiles_active_id")
        val PROFILES_V2 = stringPreferencesKey("export_profiles_v2")
        val ACTIVE_PROFILE_ID_V2 = stringPreferencesKey("export_profiles_active_id_v2")
    }

    val profiles: Flow<List<ExportProfile>> = dataStore.data.map { prefs ->
        decodeProfiles(prefs).profiles
    }

    val activeProfileId: Flow<String?> = dataStore.data.map { prefs ->
        activeProfileId(prefs)?.takeIf { id ->
            decodeProfiles(prefs).profiles.any { it.id == id }
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
        destinationId: String? = null,
    ): ExportProfile {
        require(ExportProfileRules.isValidName(name)) { "Profile name must not be blank." }
        val existing = getProfiles()
        require(existing.size < ExportProfileRules.MAX_PROFILES) { "Profile limit reached." }
        val now = System.currentTimeMillis()
        val profile = ExportProfile(
            id = UUID.randomUUID().toString(),
            name = ExportProfileRules.uniquifyName(name, existing),
            settingsSnapshotJson = settingsSnapshotJson,
            target = target,
            apiEndpointUrl = apiEndpointUrl?.takeIf { it.isNotBlank() },
            folderUri = folderUri?.takeIf { it.isNotBlank() },
            folderDisplayName = folderDisplayName?.takeIf { it.isNotBlank() },
            destinationId = destinationId?.takeIf { it.isNotBlank() },
            createdAtEpochMillis = now,
            updatedAtEpochMillis = now,
        )
        dataStore.edit { prefs ->
            val decoded = decodeProfiles(prefs)
            check(!decoded.corruptRoot) { "Export profile storage is corrupt." }
            writeProfiles(prefs, decoded, decoded.profiles + profile)
            if (activeProfileId(prefs) == null) {
                prefs[Keys.ACTIVE_PROFILE_ID_V2] = profile.id
            }
        }
        return profile
    }

    /** Binds a profile to a SAF folder tree URI (or clears the binding with nulls). */
    suspend fun bindFolder(
        id: String,
        folderUri: String?,
        folderDisplayName: String?,
    ): Boolean {
        var applied = false
        dataStore.edit { prefs ->
            val decoded = decodeProfiles(prefs)
            if (decoded.corruptRoot) return@edit
            val existing = decoded.profiles
            val index = existing.indexOfFirst { it.id == id }
            if (index >= 0) {
                val updated = existing[index].copy(
                    folderUri = folderUri?.takeIf { it.isNotBlank() },
                    folderDisplayName = folderDisplayName?.takeIf { it.isNotBlank() },
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                writeProfiles(prefs, decoded, existing.toMutableList().apply { set(index, updated) })
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
            val decoded = decodeProfiles(prefs)
            if (decoded.corruptRoot) return@edit
            val existing = decoded.profiles
            val index = existing.indexOfFirst { it.id == id }
            if (index >= 0) {
                val updated = existing[index].copy(
                    settingsSnapshotJson = settingsSnapshotJson ?: existing[index].settingsSnapshotJson,
                    target = target ?: existing[index].target,
                    apiEndpointUrl = apiEndpointUrl ?: existing[index].apiEndpointUrl,
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                writeProfiles(prefs, decoded, existing.toMutableList().apply { set(index, updated) })
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
        destinationId: String? = null,
    ): String? {
        if (!ExportProfileRules.isValidName(rawName)) return null
        var storedName: String? = null
        dataStore.edit { prefs ->
            val decoded = decodeProfiles(prefs)
            if (decoded.corruptRoot) return@edit
            val existing = decoded.profiles
            val index = existing.indexOfFirst { it.id == id }
            if (index >= 0) {
                val others = existing.filterIndexed { i, _ -> i != index }
                val updated = existing[index].copy(
                    name = ExportProfileRules.uniquifyName(rawName, others),
                    settingsSnapshotJson = settingsSnapshotJson,
                    target = target,
                    apiEndpointUrl = when (target) {
                        ExportTarget.API_ENDPOINT -> apiEndpointUrl?.takeIf { it.isNotBlank() }
                        ExportTarget.DEVICE_FOLDER, ExportTarget.GOOGLE_DRIVE -> null
                    },
                    folderUri = when (target) {
                        ExportTarget.DEVICE_FOLDER -> folderUri?.takeIf { it.isNotBlank() }
                        ExportTarget.API_ENDPOINT, ExportTarget.GOOGLE_DRIVE -> null
                    },
                    folderDisplayName = when (target) {
                        ExportTarget.DEVICE_FOLDER -> folderDisplayName?.takeIf { it.isNotBlank() }
                        ExportTarget.API_ENDPOINT, ExportTarget.GOOGLE_DRIVE -> null
                    },
                    destinationId = when (target) {
                        ExportTarget.GOOGLE_DRIVE -> destinationId?.takeIf { it.isNotBlank() }
                        ExportTarget.DEVICE_FOLDER, ExportTarget.API_ENDPOINT -> null
                    },
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                writeProfiles(prefs, decoded, existing.toMutableList().apply { set(index, updated) })
                storedName = updated.name
            }
        }
        return storedName
    }

    /** Clears a local Drive binding without changing profile output settings or target identity. */
    suspend fun clearGoogleDriveDestination(destinationId: String): List<String> {
        val affected = mutableListOf<String>()
        dataStore.edit { prefs ->
            val decoded = decodeProfiles(prefs)
            if (decoded.corruptRoot) return@edit
            val updated = decoded.profiles.map { profile ->
                if (profile.target == ExportTarget.GOOGLE_DRIVE && profile.destinationId == destinationId) {
                    affected += profile.id
                    profile.copy(destinationId = null, updatedAtEpochMillis = System.currentTimeMillis())
                } else profile
            }
            if (affected.isNotEmpty()) writeProfiles(prefs, decoded, updated)
        }
        return affected
    }

    /** Rename with trim + unique suffixing. Returns the stored name, or null when rejected. */
    suspend fun rename(id: String, rawName: String): String? {
        if (!ExportProfileRules.isValidName(rawName)) return null
        var renamed: String? = null
        dataStore.edit { prefs ->
            val decoded = decodeProfiles(prefs)
            if (decoded.corruptRoot) return@edit
            val existing = decoded.profiles
            val index = existing.indexOfFirst { it.id == id }
            if (index >= 0) {
                val others = existing.filterIndexed { i, _ -> i != index }
                val unique = ExportProfileRules.uniquifyName(rawName, others)
                val updated = existing[index].copy(
                    name = unique,
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                writeProfiles(prefs, decoded, existing.toMutableList().apply { set(index, updated) })
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
        val current = getProfiles()
        if (!ExportProfileRules.canDelete(current)) return false
        var deleted = false
        dataStore.edit { prefs ->
            val decoded = decodeProfiles(prefs)
            if (decoded.corruptRoot) return@edit
            val existing = decoded.profiles
            if (existing.any { it.id == id }) {
                val updated = existing.filterNot { it.id == id }
                writeProfiles(prefs, decoded, updated)
                if (activeProfileId(prefs) == id) {
                    updated.firstOrNull()?.let { first -> prefs[Keys.ACTIVE_PROFILE_ID_V2] = first.id }
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
            val decoded = decodeProfiles(prefs)
            if (!decoded.corruptRoot && decoded.profiles.any { it.id == id }) {
                ensureV2Envelope(prefs, decoded)
                prefs[Keys.ACTIVE_PROFILE_ID_V2] = id
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
        val persisted = dataStore.data.first()
        val decoded = decodeProfiles(persisted)
        if (decoded.profiles.isNotEmpty() || decoded.blocksDefaultMigration) return null
        val profile = ExportProfileRules.migrateDefault(
            existing = emptyList(),
            snapshotJson = settingsSnapshotJson,
            target = target,
            nowEpochMillis = System.currentTimeMillis(),
            newId = { UUID.randomUUID().toString() },
            apiEndpointUrl = apiEndpointUrl,
        ) ?: return null
        dataStore.edit { prefs ->
            val current = decodeProfiles(prefs)
            if (current.profiles.isNotEmpty() || current.blocksDefaultMigration) return@edit
            writeProfiles(prefs, current, listOf(profile))
            prefs[Keys.ACTIVE_PROFILE_ID_V2] = profile.id
        }
        return profile.takeIf { profileById(it.id) != null }
    }

    /** True when future/corrupt records are retained and therefore block destructive migration. */
    suspend fun hasOpaqueProfiles(): Boolean = decodeProfiles(dataStore.data.first()).blocksDefaultMigration

    private fun activeProfileId(prefs: Preferences): String? =
        if (prefs[Keys.PROFILES_V2] != null) prefs[Keys.ACTIVE_PROFILE_ID_V2]
        else prefs[Keys.ACTIVE_PROFILE_ID]

    private fun decodeProfiles(prefs: Preferences): DecodedProfiles {
        val rawV2 = prefs[Keys.PROFILES_V2]
        val raw = rawV2 ?: prefs[Keys.PROFILES] ?: return DecodedProfiles(emptyList(), emptyList())
        val records = try {
            val root = json.parseToJsonElement(raw)
            if (rawV2 != null) {
                val envelope = root as? JsonObject ?: return DecodedProfiles(emptyList(), listOf(root), true)
                val version = envelope["version"]?.jsonPrimitive?.intOrNull
                val values = envelope["records"] as? JsonArray
                if (version != PROFILE_ENVELOPE_VERSION || values == null) {
                    return DecodedProfiles(emptyList(), listOf(root), true)
                }
                values.toList()
            } else {
                (root as? JsonArray)?.toList()
                    ?: return DecodedProfiles(emptyList(), listOf(root), true)
            }
        } catch (_: Exception) {
            return DecodedProfiles(emptyList(), emptyList(), corruptRoot = true)
        }

        val known = mutableListOf<ExportProfile>()
        val opaque = mutableListOf<JsonElement>()
        records.forEach { record ->
            val profile = runCatching {
                json.decodeFromJsonElement(ExportProfile.serializer(), record)
            }.getOrNull()
            if (profile == null || known.any { it.id == profile.id }) opaque += record else known += profile
        }
        return DecodedProfiles(known, opaque)
    }

    private fun ensureV2Envelope(prefs: androidx.datastore.preferences.core.MutablePreferences, decoded: DecodedProfiles) {
        if (prefs[Keys.PROFILES_V2] == null) writeProfiles(prefs, decoded, decoded.profiles)
    }

    private fun writeProfiles(
        prefs: androidx.datastore.preferences.core.MutablePreferences,
        decoded: DecodedProfiles,
        profiles: List<ExportProfile>,
    ) {
        check(!decoded.corruptRoot) { "Export profile storage is corrupt." }
        val known = profiles.map { json.encodeToJsonElement(ExportProfile.serializer(), it) }
        prefs[Keys.PROFILES_V2] = json.encodeToString(
            ProfileEnvelope.serializer(),
            ProfileEnvelope(records = known + decoded.opaque),
        )
        if (prefs[Keys.ACTIVE_PROFILE_ID_V2] == null) {
            val migratedActive = prefs[Keys.ACTIVE_PROFILE_ID]?.takeIf { id -> profiles.any { it.id == id } }
            (migratedActive ?: profiles.firstOrNull()?.id)?.let { prefs[Keys.ACTIVE_PROFILE_ID_V2] = it }
        }
    }

    private companion object {
        const val PROFILE_ENVELOPE_VERSION = 2
    }
}
