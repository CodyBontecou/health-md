package com.healthmd.data.scheduler

import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import timber.log.Timber

/**
 * Per-profile folder adoption for scheduled and automation runs (cross-platform parity with the
 * iOS `runProfileScopedExport` folder gate): the live `exportFolderUri` is process-global
 * installation plumbing, so a folder-target profile run whose profile binds its own folder swaps
 * the live URI to the profile's binding for the duration of the run and restores the previous
 * value afterwards, under one mutex — two concurrent profile runs never observe each other's
 * adopted folder.
 *
 * Rules mirroring the documented iOS semantics:
 * - API-target profiles and folder profiles without a binding run unchanged (they use whatever
 *   folder the device currently has selected).
 * - Adoption only happens when a previous live URI exists; restoring "no folder at all" is not a
 *   representable state, and a device with no selected folder cannot have adopted one either.
 * - If the process dies mid-run the live URI stays on the run profile's folder; the next
 *   activation/launch re-adopts the active profile's binding (same documented recovery as iOS).
 */
@Singleton
class ProfileFolderAdoptionScope @Inject constructor(
    private val settingsRepository: SettingsRepository,
) {
    private val mutex = Mutex()

    /**
     * Runs [block] with the live folder URI adopted to [profile]'s binding when required,
     * restoring the previous value afterwards — including on failure.
     */
    suspend fun <T> withProfileFolder(profile: ExportProfile, block: suspend () -> T): T {
        val folderUri = profile.folderUri?.takeIf { it.isNotBlank() }
        val needsAdoption = profile.target == ExportTarget.DEVICE_FOLDER && folderUri != null
        if (!needsAdoption) return block()

        return mutex.withLock {
            val previous = settingsRepository.getExportFolderUri()?.takeIf { it.isNotBlank() }
            if (previous == null) {
                Timber.w(
                    "Profile folder adoption skipped: no previous live folder profileId=%s",
                    profile.id,
                )
                return@withLock block()
            }
            if (previous == folderUri) {
                // Already the live folder: nothing to adopt or restore.
                return@withLock block()
            }
            settingsRepository.saveExportFolderUri(folderUri)
            try {
                block()
            } finally {
                withContext(NonCancellable) {
                    settingsRepository.saveExportFolderUri(previous)
                }
            }
        }
    }
}
