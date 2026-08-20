package com.healthmd.domain.exportengine

import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import java.time.LocalDate

/**
 * Pure multi-profile output-path collision detection (Android mirror of iOS
 * `ExportProfileOverlapDetector`).
 *
 * Profile names never appear in file paths: paths come from the bound SAF
 * folder (or the current device folder when unbound) plus the frozen
 * filename/folder templates. Two profiles that resolve the same destination
 * root and render the same relative paths for shared formats will overwrite
 * each other's files — the later run wins — so creation/edit surfaces warn
 * with the other profiles' names. Overlap is legal (updating one note from
 * two cadences); it is surfaced, never blocked.
 *
 * Rendering sample dates catches date-equivalent templates
 * ("{date}" vs "{year}-{month}-{day}") that a raw template comparison misses.
 */
object ExportProfileOverlapDetector {

    /** Path-relevant identity of one profile. */
    data class ProfilePathIdentity(
        val profileId: String,
        val name: String,
        val target: ExportTarget,
        val settings: ExportSettings,
        /** Destination root key; null never overlaps (API endpoint targets, no folder selected). */
        val destinationRootKey: String?,
    )

    /** Dates with different month/quarter/weekday coverage keep equivalence checks honest. */
    private val SAMPLE_DATES = listOf(
        LocalDate.of(2026, 1, 1),
        LocalDate.of(2026, 7, 15),
    )

    /** Names of other profiles whose exports write the same files, sorted for display. */
    fun overlappingProfileNames(
        profileId: String,
        identities: List<ProfilePathIdentity>,
    ): List<String> {
        val subject = identities.firstOrNull { it.profileId == profileId } ?: return emptyList()
        val subjectRoot = subject.destinationRootKey ?: return emptyList()
        if (subject.settings.selectedExportFormats.isEmpty()) return emptyList()

        val subjectPaths = renderedRelativePaths(
            settings = subject.settings,
            formats = subject.settings.selectedExportFormats,
        )

        return identities.asSequence()
            .filter { it.profileId != profileId }
            .filter { it.target == subject.target }
            .mapNotNull { other ->
                val otherRoot = other.destinationRootKey ?: return@mapNotNull null
                if (normalizedRoot(otherRoot) != normalizedRoot(subjectRoot)) return@mapNotNull null
                if (other.settings.selectedExportFormats.isEmpty()) return@mapNotNull null
                val sharedFormats = subject.settings.selectedExportFormats intersect
                    other.settings.selectedExportFormats
                if (sharedFormats.isEmpty()) return@mapNotNull null
                val otherPaths = renderedRelativePaths(
                    settings = other.settings,
                    formats = sharedFormats,
                )
                if (subjectPaths.any { it in otherPaths }) other.name else null
            }
            .sortedBy { it.lowercase() }
            .toList()
    }

    /**
     * Builds identities for every saved profile. [currentFolderUri] is the live device folder
     * used by unbound DEVICE_FOLDER profiles (mirroring iOS's live shared vault fallback).
     */
    fun identities(
        profiles: List<ExportProfile>,
        currentFolderUri: String?,
        currentSettings: ExportSettings,
    ): List<ProfilePathIdentity> = profiles.map { profile ->
        val settings = AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)
            ?.restoreOnto(currentSettings)
            ?: currentSettings
        ProfilePathIdentity(
            profileId = profile.id,
            name = profile.name,
            target = profile.target,
            settings = settings,
            destinationRootKey = destinationRootKey(
                target = profile.target,
                folderUri = profile.folderUri,
                currentFolderUri = currentFolderUri,
            ),
        )
    }

    private fun destinationRootKey(
        target: ExportTarget,
        folderUri: String?,
        currentFolderUri: String?,
    ): String? = when (target) {
        ExportTarget.DEVICE_FOLDER -> (folderUri ?: currentFolderUri)?.let(::normalizedRoot)
        ExportTarget.API_ENDPOINT -> null
    }

    private fun renderedRelativePaths(
        settings: ExportSettings,
        formats: Set<ExportFormat>,
    ): Set<String> = SAMPLE_DATES.flatMap { date ->
        formats.map { format -> settings.aggregateRelativePath(date, format) }
    }.toSet()

    private fun normalizedRoot(root: String): String = root.trim().lowercase()
}
