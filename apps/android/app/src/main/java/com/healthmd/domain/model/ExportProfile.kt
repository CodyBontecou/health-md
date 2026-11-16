package com.healthmd.domain.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * A named, user-managed export configuration (Android phase 6 parity with iOS export profiles).
 *
 * A profile freezes the output-affecting settings as a canonical JSON snapshot string (the same
 * representation the scheduled-export pipeline already persists) and binds a target. Schedules,
 * purchase state, Health Connect authorization, and pending work are deliberately excluded.
 *
 * Identical profile snapshots must produce byte-for-byte identical output; profiles choose which
 * request produces files, never the public export schema.
 */
@Serializable
data class ExportProfile(
    val id: String,
    val name: String,
    /** Canonical JSON of the frozen output settings (validated lazily on restore). */
    val settingsSnapshotJson: String,
    val target: ExportTarget,
    /** Non-secret endpoint URL binding when [target] is [ExportTarget.API_ENDPOINT]. */
    val apiEndpointUrl: String? = null,
    /** Non-secret gateway base-URL binding when [target] is [ExportTarget.AGENT_DATA_GATEWAY]. */
    val agentDataGatewayUrl: String? = null,
    /** Persisted SAF tree-URI binding when [target] is [ExportTarget.DEVICE_FOLDER]. Null keeps
     * the currently selected device folder (the migration default binds it instead of leaving
     * this null, mirroring the iOS folder-vault binding). */
    val folderUri: String? = null,
    /** Privacy-safe display name of [folderUri] for list/detail surfaces. */
    val folderDisplayName: String? = null,
    /** Local-only destination reference. Account/folder authority never enters profile JSON. */
    val destinationId: String? = null,
    /** Legacy marker for the profile synthesized from pre-profile settings during migration. */
    val isMigrationDefault: Boolean = false,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
)

/** Result of resolving a profile reference by id or name. */
sealed interface ExportProfileResolution {
    data class Resolved(val profile: ExportProfile) : ExportProfileResolution
    data object LegacySettings : ExportProfileResolution
    data class NotFound(val reference: String) : ExportProfileResolution
}

/**
 * Pure profile-store semantics mirroring the iOS `ExportProfileStore`: bounded list, unique
 * names, active-profile pointer, one-time migration, and last-profile deletion guard.
 *
 * The repository layer owns DataStore persistence; this type owns every rule that must match
 * cross-platform behavior, so it is fully unit-testable without Android instrumentation.
 */
object ExportProfileRules {

    const val DEFAULT_PROFILE_NAME: String = "Default"
    const val MAX_PROFILES: Int = 100
    private val json = Json { ignoreUnknownKeys = true }

    fun normalizeName(raw: String): String = raw.trim()

    fun isValidName(raw: String): Boolean = normalizeName(raw).isNotEmpty()

    /** Case-insensitive unique naming with " 2", " 3" suffixes, matching the iOS store. */
    fun uniquifyName(raw: String, existing: List<ExportProfile>): String {
        val base = normalizeName(raw).ifEmpty { "Profile" }
        val taken = existing.map { it.name.trim().lowercase() }.toSet()
        if (base.lowercase() !in taken) return base
        var counter = 2
        while ("$base $counter".lowercase() in taken) counter += 1
        return "$base $counter"
    }

    fun byId(profiles: List<ExportProfile>, id: String?): ExportProfile? =
        id?.let { wanted -> profiles.firstOrNull { it.id == wanted } }

    /** Trimmed, case-insensitive display-name lookup used by automation references. */
    fun byName(profiles: List<ExportProfile>, rawName: String): ExportProfile? {
        val normalized = rawName.trim().lowercase()
        if (normalized.isEmpty()) return null
        return profiles.firstOrNull { it.name.trim().lowercase() == normalized }
    }

    /**
     * Resolution used by automation and scheduled work: id first, then name; explicit references
     * fail closed; no profiles at all means legacy live settings.
     */
    fun resolve(
        profiles: List<ExportProfile>,
        id: String?,
        name: String?,
    ): ExportProfileResolution = when {
        profiles.isEmpty() -> ExportProfileResolution.LegacySettings
        !id.isNullOrBlank() ->
            when (val profile = byId(profiles, id.trim())) {
                is ExportProfile -> ExportProfileResolution.Resolved(profile)
                null -> ExportProfileResolution.NotFound(id.trim())
            }
        !name.isNullOrBlank() && name.trim().isNotEmpty() ->
            when (val profile = byName(profiles, name)) {
                is ExportProfile -> ExportProfileResolution.Resolved(profile)
                null -> ExportProfileResolution.NotFound(name.trim())
            }
        else -> active(profiles)?.let { ExportProfileResolution.Resolved(it) }
            ?: ExportProfileResolution.LegacySettings
    }

    fun active(profiles: List<ExportProfile>, activeProfileId: String? = null): ExportProfile? =
        byId(profiles, activeProfileId) ?: profiles.firstOrNull()

    /**
     * One-time migration of current settings into a Default profile bound to the current target
     * (and endpoint URL for API targets, matching the iOS bootstrap binding). Returns null when
     * a profile already exists (idempotent bootstrap).
     */
    fun migrateDefault(
        existing: List<ExportProfile>,
        snapshotJson: String,
        target: ExportTarget,
        nowEpochMillis: Long,
        newId: () -> String,
        apiEndpointUrl: String? = null,
        agentDataGatewayUrl: String? = null,
    ): ExportProfile? {
        if (existing.isNotEmpty()) return null
        return ExportProfile(
            id = newId(),
            name = DEFAULT_PROFILE_NAME,
            settingsSnapshotJson = snapshotJson,
            target = target,
            apiEndpointUrl = apiEndpointUrl,
            agentDataGatewayUrl = agentDataGatewayUrl,
            isMigrationDefault = true,
            createdAtEpochMillis = nowEpochMillis,
            updatedAtEpochMillis = nowEpochMillis,
        )
    }

    /** Outcome of [repairDuplicateDefaults]; [changed] is false when the list is already valid. */
    data class DefaultRepair(
        val profiles: List<ExportProfile>,
        val activeProfileId: String?,
        val removedIds: List<String>,
        val demotedIds: List<String>,
    ) {
        val changed: Boolean get() = removedIds.isNotEmpty() || demotedIds.isNotEmpty()
    }

    /**
     * Startup repair for installs that ended up with more than one migration Default profile
     * (issue #329). Only profiles carrying [ExportProfile.isMigrationDefault] are candidates, so
     * a profile the user created and named is never touched.
     *
     * [pinnedProfileIds] are profiles other state refers to (schedule entries, Shared Setup
     * gates); they are never removed. Exactly one candidate stays the Default: the active one,
     * else a pinned one, else the oldest. Every other candidate is either removed — only when it
     * carries no settings or destination the survivor lacks, is not active, and is not pinned — or
     * demoted to an ordinary profile (marker cleared, name made unique) so nothing the user
     * configured is lost. The result is a fixed point: repairing a repaired list changes nothing.
     */
    fun repairDuplicateDefaults(
        profiles: List<ExportProfile>,
        activeProfileId: String?,
        pinnedProfileIds: Set<String>,
    ): DefaultRepair {
        val candidates = profiles.filter { it.isMigrationDefault }
        if (candidates.size < 2) return DefaultRepair(profiles, activeProfileId, emptyList(), emptyList())

        val survivor = candidates.firstOrNull { it.id == activeProfileId }
            ?: candidates.firstOrNull { it.id in pinnedProfileIds }
            ?: candidates.minBy { it.createdAtEpochMillis }
        val removed = candidates.filter { candidate ->
            candidate.id != survivor.id &&
                candidate.id !in pinnedProfileIds &&
                candidate.id != activeProfileId &&
                sameConfiguration(candidate, survivor)
        }.map { it.id }.toSet()

        val repaired = profiles.filter { it.id !in removed }.toMutableList()
        val demoted = mutableListOf<String>()
        repaired.indices.forEach { index ->
            val profile = repaired[index]
            if (!profile.isMigrationDefault || profile.id == survivor.id) return@forEach
            val others = repaired.filterIndexed { other, _ -> other != index }
            repaired[index] = profile.copy(
                name = uniquifyName(profile.name, others),
                isMigrationDefault = false,
            )
            demoted += profile.id
        }
        val active = if (activeProfileId != null && activeProfileId in removed) survivor.id else activeProfileId
        return DefaultRepair(repaired, active, removed.toList(), demoted)
    }

    /** Output- and destination-affecting fields only; identity, name, and timestamps are ignored. */
    private fun sameConfiguration(a: ExportProfile, b: ExportProfile): Boolean =
        a.settingsSnapshotJson == b.settingsSnapshotJson &&
            a.target == b.target &&
            a.apiEndpointUrl == b.apiEndpointUrl &&
            a.agentDataGatewayUrl == b.agentDataGatewayUrl &&
            a.folderUri == b.folderUri &&
            a.destinationId == b.destinationId

    /** Deleting the last remaining profile is forbidden cross-platform. */
    fun canDelete(profiles: List<ExportProfile>): Boolean = profiles.size > 1

    fun decodeSnapshot(profile: ExportProfile): ExportSettingsSnapshotView? =
        runCatching { json.decodeFromString(ExportSettingsSnapshotView.serializer(), profile.settingsSnapshotJson) }.getOrNull()
}

/** Minimal view over a frozen profile snapshot's output-affecting fields. */
@Serializable
data class ExportSettingsSnapshotView(
    val exportFormats: Set<String> = emptySet(),
    val filenameFormat: String? = null,
    val includeGranularData: Boolean? = null,
    val detailOverrides: Map<String, String>? = null,
    val metricSelection: MetricSelectionView? = null,
) {
    /** Groups whose detail differs from the snapshot default, for profile summaries. */
    val detailOverrideCount: Int
        get() = detailOverrides?.size ?: 0

    /** Number of enabled health metrics in the frozen snapshot. */
    val enabledMetricCount: Int
        get() = metricSelection?.enabledMetrics?.size ?: 0

    /** @Serializable projection of [com.healthmd.domain.model.MetricSelectionState]. */
    @Serializable
    data class MetricSelectionView(
        val enabledMetrics: Set<String> = emptySet(),
    )
}
