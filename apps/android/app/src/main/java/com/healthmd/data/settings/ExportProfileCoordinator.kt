package com.healthmd.data.settings

import androidx.annotation.VisibleForTesting
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.repository.SettingsRepository
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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

    /** Idempotent app bootstrap; call once the main UI process is running. */
    fun ensureStarted() {
        if (!started.compareAndSet(false, true)) return
        scope.launch {
            runCatching { bootstrapAndApply() }
                .onFailure { Timber.e(it, "Export profile bootstrap failed") }
            observeEdits()
        }
    }

    private suspend fun bootstrapAndApply() {
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
        val active = profileRepository.getActiveProfile() ?: return
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
            return applyProfile(profile, settingsRepository.getExportSettings())
        }

        // Stage the restore before any persisted change: an invalid snapshot must not move
        // the pointer (a moved pointer plus stale live settings would let the next flush
        // overwrite the new profile's frozen configuration).
        val staged = snapshotFactory.applyForActivation(profile, settingsRepository.getExportSettings())
            ?: return false

        flushEditsLocked()
        if (!profileRepository.activate(profileId)) return false
        settingsRepository.updateExportSettings(staged)
        adoptFolderBinding(profile)
        return true
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
