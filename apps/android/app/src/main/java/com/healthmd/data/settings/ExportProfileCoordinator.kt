package com.healthmd.data.settings

import androidx.annotation.VisibleForTesting
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.repository.SettingsRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android editing-authority coordinator (cross-platform parity with the iOS
 * `ExportProfileCoordinator`, feature decision 1): once any profile exists, the live
 * `ExportSettings` are the active profile's editable projection.
 *
 * - **Bootstrap** (launch): synthesizes the Default profile from current settings when no
 *   profile exists (binding the current target and endpoint), then applies the active
 *   profile's frozen snapshot onto live settings so both always agree.
 * - **Activation**: stages the incoming profile's restore onto live settings first and only
 *   switches the active pointer after the snapshot validates — a corrupt snapshot fails
 *   closed without leaving a pointer/snapshot mismatch that a later flush could freeze.
 *   Outgoing edits are flushed into the outgoing profile before the switch.
 * - **Edit flush**: live-settings changes are frozen back into the active profile after a
 *   short debounce, with an equality guard so schedule/retry bookkeeping writes and the
 *   activation apply itself do not churn the stored profile.
 *
 * Scheduled and automation runs never write restored run settings back to live settings, so
 * this observer only ever sees user-facing edits.
 */
@Singleton
class ExportProfileCoordinator @Inject constructor(
    private val profileRepository: ExportProfileRepository,
    private val settingsRepository: SettingsRepository,
    private val snapshotFactory: ScheduledProfileSnapshotFactory,
) {
    /** Owns the app-lifetime edit observer; overridable in tests before [ensureStarted]. */
    @VisibleForTesting
    internal var scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    /** Debounce window for flushing live edits into the active profile (iOS parity: 0.6s). */
    @VisibleForTesting
    internal var editFlushIntervalMillis: Long = EDIT_FLUSH_INTERVAL_MILLIS

    private val mutex = Mutex()
    private val started = AtomicBoolean(false)
    private val editFlushEnabled = AtomicBoolean(true)

    /** Idempotent app bootstrap; call once the main UI process is running. */
    fun ensureStarted() {
        if (!started.compareAndSet(false, true)) return
        scope.launch {
            val ready = runCatching { bootstrapAndApply() }
                .onFailure { Timber.e(it, "Export profile bootstrap failed") }
                .getOrDefault(false)
            if (ready) {
                observeEdits()
            } else {
                Timber.e("Export profile editing observer disabled because bootstrap did not validate")
            }
        }
    }

    private suspend fun bootstrapAndApply(): Boolean = mutex.withLock {
        val current = settingsRepository.getExportSettings()
        if (profileRepository.getProfiles().isEmpty()) {
            val target = current.scheduledExportTarget
            val endpointUrl = current.apiEndpointUrl.takeIf { it.isNotBlank() }
            profileRepository.migrateDefaultIfNeeded(
                settingsSnapshotJson = snapshotFactory.captureFromCurrent(current, target, endpointUrl),
                target = target,
                apiEndpointUrl = endpointUrl,
            )
        }
        val active = profileRepository.getActiveProfile() ?: return@withLock false
        applyProfile(active, settingsRepository.getExportSettings())
    }

    /**
     * Activates a profile for manual export and interactive editing: the incoming snapshot is
     * restored onto live settings only after it validates; the outgoing active profile's
     * unflushed edits are frozen before the switch; and the profile's folder binding (when set)
     * is adopted as the live device folder so manual exports write to the profile's destination.
     * Returns false (nothing changed) for unknown ids or a snapshot that fails closed.
     */
    suspend fun activate(profileId: String): Boolean = mutex.withLock {
        val profile = profileRepository.profileById(profileId) ?: return false
        val active = profileRepository.getActiveProfile()
        if (active?.id == profile.id) {
            // Re-applying the already-active profile (editor save, folder rebind): the frozen
            // snapshot refreshes live settings and the binding follows so manual exports
            // immediately write to the profile's destination. Once persistence begins, finish
            // even if the initiating screen leaves.
            return withContext(NonCancellable) {
                val applied = applyProfile(profile, settingsRepository.getExportSettings())
                if (applied) adoptFolderBinding(profile)
                applied
            }
        }

        // Stage the restore before any persisted change: an invalid snapshot must not move
        // the pointer (a moved pointer plus stale live settings would let the next flush
        // overwrite the new profile's frozen configuration).
        val staged = snapshotFactory.applyForActivation(profile, settingsRepository.getExportSettings())
            ?: return false

        flushEditsLocked()
        val outgoingSettings = settingsRepository.getExportSettings()
        return withContext(NonCancellable) {
            // Persist the incoming projection before moving the pointer. The mutex hides this
            // temporary pairing from the edit observer; process death is repaired by bootstrap.
            settingsRepository.updateExportSettings(staged)
            val activated = try {
                profileRepository.activate(profileId)
            } catch (error: Throwable) {
                rollbackLiveSettings(outgoingSettings, error)
                throw error
            }
            if (!activated) {
                if (!rollbackLiveSettings(outgoingSettings)) {
                    error("Profile activation failed and live settings could not be restored.")
                }
                return@withContext false
            }
            adoptFolderBinding(profile)
            true
        }
    }

    /**
     * Deletes a profile through the same editing-authority transaction as activation. When the
     * active profile is removed, outgoing edits are flushed while it still owns the pointer, the
     * deterministic successor is validated before destructive work, and the successor is applied
     * before the mutex is released. A pending debounced flush can therefore never freeze outgoing
     * live settings into the successor. Invalid successors and the last-profile guard fail closed.
     */
    suspend fun delete(profileId: String): Boolean = mutex.withLock {
        val profiles = profileRepository.getProfiles()
        val deleting = profiles.firstOrNull { it.id == profileId } ?: return false
        if (!ExportProfileRules.canDelete(profiles)) return false

        val active = profileRepository.getActiveProfile()
        if (active?.id != deleting.id) {
            return profileRepository.delete(profileId)
        }

        flushEditsLocked()
        val outgoingSettings = settingsRepository.getExportSettings()
        val successor = profileRepository.getProfiles().firstOrNull { it.id != profileId }
            ?: return false
        val staged = snapshotFactory.applyForActivation(successor, outgoingSettings)
            ?: return false

        // Once the staged projection begins writing, complete or roll back the authority move even
        // if the initiating screen leaves and cancels its viewModelScope.
        withContext(NonCancellable) {
            // Persist the staged live projection before moving the active pointer. The coordinator
            // mutex keeps the edit observer from seeing this temporary pairing, while process death
            // is self-repairing: bootstrap reapplies whichever profile pointer actually committed.
            settingsRepository.updateExportSettings(staged)
            val deleted = try {
                profileRepository.delete(profileId)
            } catch (error: Throwable) {
                rollbackLiveSettings(outgoingSettings, error)
                throw error
            }
            if (!deleted) {
                if (!rollbackLiveSettings(outgoingSettings)) {
                    error("Profile deletion failed and live settings could not be restored.")
                }
                return@withContext false
            }
            adoptFolderBinding(successor)
            true
        }
    }

    /** Adopts the profile's bound folder as the live device folder (nil binding keeps the
     * current selection, matching the iOS unbound-vault rule). */
    private suspend fun adoptFolderBinding(profile: ExportProfile) {
        val folderUri = profile.folderUri?.takeIf { it.isNotBlank() } ?: return
        val current = settingsRepository.getExportFolderUri()
        if (current != folderUri) {
            settingsRepository.saveExportFolderUri(folderUri)
        }
    }

    /**
     * Called after the user picks a new device folder from the Export screen while a profile is
     * active: rebinds that profile to the newly selected folder (iOS `vaultFolderWasSelected`
     * parity). Re-selecting a folder another profile already bound is fine — grants are shared
     * per URI, not per profile.
     */
    suspend fun folderWasSelected(uri: String, displayName: String?) {
        mutex.withLock {
            val active = profileRepository.getActiveProfile() ?: return
            profileRepository.bindFolder(active.id, uri, displayName)
        }
    }

    /** Freezes current live settings into the active profile (debounce expiry, exports). */
    suspend fun flushEdits(): Unit = mutex.withLock { flushEditsLocked() }

    private suspend fun flushEditsLocked() {
        if (!editFlushEnabled.get()) return
        val active = profileRepository.getActiveProfile() ?: return
        val current = settingsRepository.getExportSettings()
        val target = current.scheduledExportTarget
        val endpointUrl = current.apiEndpointUrl.takeIf { it.isNotBlank() }
        val snapshotJson = snapshotFactory.captureFromCurrent(current, target, endpointUrl)
        if (snapshotJson == active.settingsSnapshotJson &&
            target == active.target &&
            endpointUrl == active.apiEndpointUrl
        ) {
            // Nothing output-affecting changed: schedule/retry bookkeeping writes or the
            // activation apply round-trip. Skip the write and the timestamp churn.
            return
        }
        profileRepository.updateProfile(
            id = active.id,
            settingsSnapshotJson = snapshotJson,
            target = target,
            apiEndpointUrl = endpointUrl,
        )
    }

    private suspend fun rollbackLiveSettings(
        settings: ExportSettings,
        primaryError: Throwable? = null,
    ): Boolean = try {
        settingsRepository.updateExportSettings(settings)
        true
    } catch (rollbackError: Throwable) {
        // Never let the observer freeze a mismatched live projection into the still-active row.
        // A process restart will bootstrap from the authoritative profile pointer.
        editFlushEnabled.set(false)
        primaryError?.addSuppressed(rollbackError)
        Timber.e(rollbackError, "Profile authority rollback failed; disabling edit flush")
        false
    }

    private suspend fun applyProfile(profile: ExportProfile, current: ExportSettings): Boolean {
        val applied = snapshotFactory.applyForActivation(profile, current) ?: run {
            Timber.w("Export profile snapshot invalid, keeping live settings profileId=%s", profile.id)
            return false
        }
        settingsRepository.updateExportSettings(applied)
        return true
    }

    private suspend fun observeEdits() {
        var pendingFlush: Job? = null
        settingsRepository.exportSettings.collect {
            pendingFlush?.cancel()
            pendingFlush = scope.launch {
                delay(editFlushIntervalMillis)
                runCatching { flushEdits() }
                    .onFailure { Timber.e(it, "Export profile edit flush failed") }
            }
        }
    }

    companion object {
        const val EDIT_FLUSH_INTERVAL_MILLIS: Long = 600L
    }
}
