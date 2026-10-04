package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportTarget
import com.healthmd.sharedsetup.SharedSetupV2ProfileExecutionAccess
import com.healthmd.sharedsetup.SharedSetupV2ProfilePersistence
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

    /** Central non-secret execution gate for imported profiles awaiting local rebinding. */
    suspend fun sharedSetupV2ExecutionAccess(id: String): SharedSetupV2ProfileExecutionAccess =
        if (id in dataStore.data.first()[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()) {
            SharedSetupV2ProfileExecutionAccess.DestinationRebindRequired
        } else {
            SharedSetupV2ProfileExecutionAccess.Allowed
        }

    suspend fun isSharedSetupV2Blocked(id: String): Boolean =
        sharedSetupV2ExecutionAccess(id) ==
            SharedSetupV2ProfileExecutionAccess.DestinationRebindRequired

    /** Manual-export gate for the effective active row, including first-row fallback semantics. */
    suspend fun activeSharedSetupV2ExecutionAccess(): SharedSetupV2ProfileExecutionAccess {
        val prefs = dataStore.data.first()
        val blocked = prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
        if (blocked.isEmpty()) return SharedSetupV2ProfileExecutionAccess.Allowed
        val profiles = decodeProfiles(prefs[Keys.PROFILES])
            ?: return SharedSetupV2ProfileExecutionAccess.DestinationRebindRequired
        val effectiveActive = profiles.firstOrNull { it.id == prefs[Keys.ACTIVE_PROFILE_ID] }
            ?: profiles.firstOrNull()
            ?: return SharedSetupV2ProfileExecutionAccess.DestinationRebindRequired
        return if (effectiveActive.id in blocked) {
            SharedSetupV2ProfileExecutionAccess.DestinationRebindRequired
        } else {
            SharedSetupV2ProfileExecutionAccess.Allowed
        }
    }

    /** Adds a profile with a unique name; the first profile becomes active. */
    suspend fun add(
        name: String,
        settingsSnapshotJson: String,
        target: ExportTarget,
        apiEndpointUrl: String? = null,
        folderUri: String? = null,
        folderDisplayName: String? = null,
        derivedFromProfileId: String? = null,
        agentDataGatewayUrl: String? = null,
    ): ExportProfile {
        require(ExportProfileRules.isValidName(name)) { "Profile name must not be blank." }
        val newId = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        var added: ExportProfile? = null
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            require(existing.size < ExportProfileRules.MAX_PROFILES) { "Profile limit reached." }
            if (derivedFromProfileId != null && existing.none { it.id == derivedFromProfileId }) {
                return@edit
            }
            val blocked = prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
            val derivedSidecar = derivedFromProfileId
                ?.takeIf { it in blocked }
                ?.let { sourceId ->
                    try {
                        SharedSetupV2ProfilePersistence.decodeProfileStateOrNull(
                            prefs[SharedSetupV2ProfilePersistence.profileStateKey],
                        )
                    } catch (error: Exception) {
                        Timber.e(error, "Shared Setup v2 profile state failed to decode; blocking duplicate")
                        return@edit
                    }?.takeIf { state ->
                        state.profiles.count { it.profileId == sourceId } == 1
                    } ?: return@edit
                }
            val profile = ExportProfile(
                id = newId,
                name = ExportProfileRules.uniquifyName(name, existing),
                settingsSnapshotJson = settingsSnapshotJson,
                target = target,
                apiEndpointUrl = apiEndpointUrl?.takeIf { it.isNotBlank() },
                agentDataGatewayUrl = agentDataGatewayUrl?.takeIf { it.isNotBlank() },
                folderUri = folderUri?.takeIf { it.isNotBlank() },
                folderDisplayName = folderDisplayName?.takeIf { it.isNotBlank() },
                createdAtEpochMillis = now,
                updatedAtEpochMillis = now,
            )
            val encodedProfiles = json.encodeToString(listSerializer, existing + profile)
            val encodedDerivedSidecar = derivedSidecar?.let { state ->
                val sourceRow = state.profiles.single {
                    it.profileId == derivedFromProfileId
                }
                SharedSetupV2ProfilePersistence.encodeProfileState(
                    state.copy(
                        profiles = state.profiles + sourceRow.copy(profileId = profile.id),
                    ),
                )
            }
            prefs[Keys.PROFILES] = encodedProfiles
            if (encodedDerivedSidecar != null) {
                prefs[SharedSetupV2ProfilePersistence.profileStateKey] = encodedDerivedSidecar
                prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey] = blocked + profile.id
            }
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
                val concreteFolderUri = folderUri
                    ?.takeIf { it.isNotBlank() && it.startsWith("content://", ignoreCase = true) }
                val updated = existing[index].copy(
                    folderUri = folderUri?.takeIf { it.isNotBlank() },
                    folderDisplayName = folderDisplayName?.takeIf { it.isNotBlank() },
                    updatedAtEpochMillis = System.currentTimeMillis(),
                )
                prefs[Keys.PROFILES] = json.encodeToString(
                    listSerializer,
                    existing.toMutableList().apply { set(index, updated) },
                )
                // Only the explicit SAF picker binding path may clear device-folder intent.
                // Connected-Mac/cloud imports project to DEVICE_FOLDER for display but remain
                // blocked because their exact source destination is retained in the sidecar.
                if (
                    updated.target == ExportTarget.DEVICE_FOLDER &&
                    concreteFolderUri != null &&
                    SharedSetupV2ProfilePersistence.sourceDestinationKind(
                        prefs[SharedSetupV2ProfilePersistence.profileStateKey],
                        id,
                    ) == "device_folder"
                ) {
                    removeBlockedId(prefs, id)
                }
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
        agentDataGatewayUrl: String? = null,
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
                    agentDataGatewayUrl = agentDataGatewayUrl ?: existing[index].agentDataGatewayUrl,
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
        agentDataGatewayUrl: String? = null,
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
                        ExportTarget.AGENT_DATA_GATEWAY -> null
                    },
                    agentDataGatewayUrl = when (target) {
                        ExportTarget.AGENT_DATA_GATEWAY -> agentDataGatewayUrl?.takeIf { it.isNotBlank() }
                        ExportTarget.DEVICE_FOLDER -> null
                        ExportTarget.API_ENDPOINT -> null
                    },
                    folderUri = when (target) {
                        ExportTarget.DEVICE_FOLDER -> folderUri?.takeIf { it.isNotBlank() }
                        ExportTarget.API_ENDPOINT -> null
                        ExportTarget.AGENT_DATA_GATEWAY -> null
                    },
                    folderDisplayName = when (target) {
                        ExportTarget.DEVICE_FOLDER -> folderDisplayName?.takeIf { it.isNotBlank() }
                        ExportTarget.API_ENDPOINT -> null
                        ExportTarget.AGENT_DATA_GATEWAY -> null
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
                val sidecarRaw = prefs[SharedSetupV2ProfilePersistence.profileStateKey]
                val sidecar = try {
                    SharedSetupV2ProfilePersistence.decodeProfileStateOrNull(sidecarRaw)
                } catch (error: Exception) {
                    Timber.e(error, "Shared Setup v2 profile state failed to decode; blocking delete")
                    return@edit
                }
                val updated = existing.filterNot { it.id == id }
                val updatedSidecar = sidecar?.copy(
                    profiles = sidecar.profiles.filterNot { it.profileId == id },
                )
                val encodedSidecar = SharedSetupV2ProfilePersistence.encodeProfileState(
                    updatedSidecar?.takeIf { it.profiles.isNotEmpty() },
                )
                prefs[Keys.PROFILES] = json.encodeToString(listSerializer, updated)
                if (prefs[Keys.ACTIVE_PROFILE_ID] == id) {
                    updated.firstOrNull()?.let { first -> prefs[Keys.ACTIVE_PROFILE_ID] = first.id }
                }
                if (encodedSidecar == null) {
                    prefs.remove(SharedSetupV2ProfilePersistence.profileStateKey)
                } else {
                    prefs[SharedSetupV2ProfilePersistence.profileStateKey] = encodedSidecar
                }
                removeBlockedId(prefs, id)
                deleted = true
            }
        }
        return deleted
    }

    /** Activates a profile for manual exports. Blocked imports never move the pointer. */
    suspend fun activate(id: String): Boolean {
        var activated = false
        dataStore.edit { prefs ->
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            val blocked = prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
            if (existing.any { it.id == id } && id !in blocked) {
                prefs[Keys.ACTIVE_PROFILE_ID] = id
                activated = true
            }
        }
        return activated
    }

    /**
     * Separate trusted hook for the in-flow endpoint-URL confirmation of one blocked imported
     * profile (Shared Setup v2 review), mirroring the Apple twin's explicit-imported-URL
     * confirmation. The bound URL is derived exclusively from the bounded sidecar's retained
     * `api_endpoint` hint — never from caller input — and is bound through the same editor-path
     * semantics the profile editor produces (see [applyEditorUpdate] and
     * `ExportProfilesViewModel.endpointBinding`): the profile's [ExportProfile.apiEndpointUrl]
     * plus its frozen settings snapshot re-scoped to [ExportTarget.API_ENDPOINT] so that
     * `apiEndpointIdentitySha256` is the [APIExportEndpoint.fingerprint] of exactly that URL.
     * Every frozen output choice and the frozen engine pin are preserved; only the destination
     * fields change. An API-scoped snapshot's operation profile is always the frozen v4
     * profile (`expectedScheduledExportProfile` semantics), so the re-scope pins it.
     *
     * This hook NEVER clears the pending-destination block:
     * [clearSharedSetupV2BlockAfterApiCredentialConfirmation] remains the single clearing
     * authority — its unchanged fingerprint verification is what a later verified credential
     * must satisfy. The binding deliberately persists even when no credential is ever
     * confirmed (exactly the state an editor detour would have produced), so no profile-store
     * rollback path exists here; the credential hook alone decides when the block clears.
     *
     * Fail-closed (returns false, writes nothing) when the id is not blocked, the profile is
     * unknown or no longer targets [ExportTarget.API_ENDPOINT], the sidecar row is missing or
     * not exactly `api_endpoint`, the retained URL does not normalize, the profile is already
     * bound to a different local endpoint (an explicit editor choice is never overwritten),
     * or the frozen snapshot cannot be decoded or validly re-scoped. Idempotent: returns true
     * without rewriting when the exact binding already exists.
     */
    suspend fun bindSharedSetupV2ApiEndpointAfterConfirmation(id: String): Boolean {
        var bound = false
        dataStore.edit { prefs ->
            val blocked = prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
            if (id !in blocked) return@edit
            val existing = decodeProfiles(prefs[Keys.PROFILES]) ?: return@edit
            val index = existing.indexOfFirst { it.id == id }
            if (index < 0) return@edit
            val profile = existing[index]
            if (profile.target != ExportTarget.API_ENDPOINT) return@edit
            val endpoint = SharedSetupV2ProfilePersistence.retainedApiEndpointUrl(
                prefs[SharedSetupV2ProfilePersistence.profileStateKey],
                id,
            ) ?: return@edit
            val snapshot = AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)
                ?: return@edit
            val identity = APIExportEndpoint.fingerprint(endpoint)
            if (profile.apiEndpointUrl != null && profile.apiEndpointUrl != endpoint) {
                // An explicit local binding to another endpoint is never overwritten in-flow.
                return@edit
            }
            if (
                profile.apiEndpointUrl == endpoint &&
                snapshot.scheduledExportTarget == ExportTarget.API_ENDPOINT &&
                snapshot.apiEndpointIdentitySha256 == identity
            ) {
                // Already exactly bound (prior in-flow confirmation or editor save of the
                // imported URL): confirm without rewriting anything.
                bound = true
                return@edit
            }
            val reboundSnapshot = snapshot.copy(
                exportTarget = ExportTarget.API_ENDPOINT,
                scheduledExportTarget = ExportTarget.API_ENDPOINT,
                exportProfile = AndroidExportProfile.android_frozen_v4,
                apiEndpointIdentitySha256 = identity,
            )
            val encodedSnapshot = runCatching {
                AndroidExportSettingsSnapshotCodec.encodeCanonical(reboundSnapshot)
            }.getOrNull() ?: return@edit
            val updated = profile.copy(
                apiEndpointUrl = endpoint,
                settingsSnapshotJson = encodedSnapshot,
                updatedAtEpochMillis = System.currentTimeMillis(),
            )
            prefs[Keys.PROFILES] = json.encodeToString(
                listSerializer,
                existing.toMutableList().apply { set(index, updated) },
            )
            bound = true
        }
        return bound
    }

    /**
     * Separate trusted hook for a credential coordinator after it has persisted and verified the
     * endpoint plus local credentials. Merely editing an API URL never calls this method and never
     * clears a block. The canonical snapshot must already bind the same local endpoint identity.
     */
    suspend fun clearSharedSetupV2BlockAfterApiCredentialConfirmation(id: String): Boolean {
        var cleared = false
        dataStore.edit { prefs ->
            val blocked = prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
            if (id !in blocked) return@edit
            val profile = decodeProfiles(prefs[Keys.PROFILES])
                ?.singleOrNull { it.id == id }
                ?: return@edit
            val endpoint = profile.apiEndpointUrl
                ?.let(APIExportEndpoint::normalizedOrNull)
                ?: return@edit
            val snapshot = AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)
                ?: return@edit
            val sourceKind = SharedSetupV2ProfilePersistence.sourceDestinationKind(
                prefs[SharedSetupV2ProfilePersistence.profileStateKey],
                id,
            )
            if (
                profile.target != ExportTarget.API_ENDPOINT ||
                sourceKind != "api_endpoint" ||
                snapshot.scheduledExportTarget != ExportTarget.API_ENDPOINT ||
                snapshot.apiEndpointIdentitySha256 != APIExportEndpoint.fingerprint(endpoint)
            ) {
                return@edit
            }
            removeBlockedId(prefs, id)
            cleared = true
        }
        return cleared
    }

    /**
     * Separate trusted hook for the connected-Mac pairing confirmation flow. This mirrors the
     * verification shape of [clearSharedSetupV2BlockAfterApiCredentialConfirmation] minus the
     * endpoint fingerprint: the id must still be blocked, and the bounded sidecar must retain
     * the exact `connected_mac` source destination kind. Android has no `CONNECTED_MAC`
     * [ExportTarget] — connected-Mac imports project to [ExportTarget.DEVICE_FOLDER] for display
     * (see `SharedSetupV2ProfileTransaction.materializeProfile`) — so the profile must still
     * carry that untouched projection; a locally retargeted profile no longer represents the
     * imported Mac intent and stays blocked. No endpoint or credential fingerprint applies: the
     * explicit local pairing attestation IS the confirmation (Apple's attestation-only
     * precedent, "Mac Is Paired — Rebind"). Fail-closed: any mismatch returns false and keeps
     * the block. Cloud intent is never cleared here.
     */
    suspend fun clearSharedSetupV2BlockAfterMacPairingConfirmation(id: String): Boolean {
        var cleared = false
        dataStore.edit { prefs ->
            val blocked = prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
            if (id !in blocked) return@edit
            val profile = decodeProfiles(prefs[Keys.PROFILES])
                ?.singleOrNull { it.id == id }
                ?: return@edit
            val sourceKind = SharedSetupV2ProfilePersistence.sourceDestinationKind(
                prefs[SharedSetupV2ProfilePersistence.profileStateKey],
                id,
            )
            if (
                profile.target != ExportTarget.DEVICE_FOLDER ||
                sourceKind != "connected_mac"
            ) {
                return@edit
            }
            removeBlockedId(prefs, id)
            cleared = true
        }
        return cleared
    }

    /**
     * One-time migration of current settings into a Default profile bound to the current target
     * and endpoint, activated immediately. No-op when any profile exists.
     */
    suspend fun migrateDefaultIfNeeded(
        settingsSnapshotJson: String,
        target: ExportTarget,
        apiEndpointUrl: String? = null,
        agentDataGatewayUrl: String? = null,
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
                agentDataGatewayUrl = agentDataGatewayUrl,
            ) ?: return@edit
            prefs[Keys.PROFILES] = json.encodeToString(listSerializer, listOf(profile))
            prefs[Keys.ACTIVE_PROFILE_ID] = profile.id
            migrated = profile
        }
        return migrated
    }

    private fun removeBlockedId(prefs: androidx.datastore.preferences.core.MutablePreferences, id: String) {
        val remaining = prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty() - id
        if (remaining.isEmpty()) {
            prefs.remove(SharedSetupV2ProfilePersistence.blockedProfileIdsKey)
        } else {
            prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey] = remaining
        }
    }

    private fun decodeProfiles(raw: String?): List<ExportProfile>? {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching { json.decodeFromString(listSerializer, raw) }.getOrElse { error ->
            Timber.e(error, "Export profiles failed to decode; blocking profile writes")
            null
        }
    }
}
