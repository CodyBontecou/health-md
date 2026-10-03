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
    /** Persisted SAF tree-URI binding when [target] is [ExportTarget.DEVICE_FOLDER]. Null keeps
     * the currently selected device folder (the migration default binds it instead of leaving
     * this null, mirroring the iOS folder-vault binding). */
    val folderUri: String? = null,
    /** Privacy-safe display name of [folderUri] for list/detail surfaces. */
    val folderDisplayName: String? = null,
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
    ): ExportProfile? {
        if (existing.isNotEmpty()) return null
        return ExportProfile(
            id = newId(),
            name = DEFAULT_PROFILE_NAME,
            settingsSnapshotJson = snapshotJson,
            target = target,
            apiEndpointUrl = apiEndpointUrl,
            isMigrationDefault = true,
            createdAtEpochMillis = nowEpochMillis,
            updatedAtEpochMillis = nowEpochMillis,
        )
    }

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
    val metricSelection: MetricSelectionView? = null,
) {
    /** Number of enabled health metrics in the frozen snapshot. */
    val enabledMetricCount: Int
        get() = metricSelection?.enabledMetrics?.size ?: 0

    /** @Serializable projection of [com.healthmd.domain.model.MetricSelectionState]. */
    @Serializable
    data class MetricSelectionView(
        val enabledMetrics: Set<String> = emptySet(),
    )
}
