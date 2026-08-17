package com.healthmd.data.scheduler

import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Captures and restores frozen snapshots for profile-scoped scheduled runs.
 *
 * A profile's snapshot is captured from current settings with the profile's target (and endpoint
 * URL for API profiles) applied, then restored through the shipped
 * [AndroidExportSettingsSnapshot.restoreOnto] path with the engine pin re-injected — exactly the
 * lifecycle the single-schedule pipeline uses, so profile runs inherit all its frozen-output and
 * fail-closed destination guarantees.
 */
@Singleton
class ScheduledProfileSnapshotFactory @Inject constructor(
    private val enginePinPlanner: ExportEnginePinPlanner,
) {

    /** Captures the canonical frozen snapshot for [profile] from [current] settings. */
    fun capture(profile: ExportProfile, current: ExportSettings): String =
        captureFromCurrent(
            current = current,
            target = profile.target,
            apiEndpointUrl = profile.apiEndpointUrl,
        )

    /** Captures a frozen snapshot of current settings scoped to an explicit target. */
    fun captureFromCurrent(
        current: ExportSettings,
        target: ExportTarget,
        apiEndpointUrl: String? = null,
    ): String {
        val zone = ZoneId.systemDefault()
        val scoped = current.copy(
            exportTarget = target,
            scheduledExportTarget = target,
            apiEndpointUrl = apiEndpointUrl ?: current.apiEndpointUrl,
        )
        val pin = enginePinPlanner.forScheduledExport(scoped, target, zone)
        return AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(scoped, pin, zone),
        )
    }

    /**
     * Restores a profile's frozen snapshot onto current settings for one run. Applies the
     * profile's endpoint URL first so `restoreOnto`'s fail-closed fingerprint check validates
     * against the profile's destination, then re-injects the frozen engine authority.
     *
     * Returns the run settings, or null when the snapshot is undecodable, the destination no
     * longer matches, or validation fails — profile runs never fall back to live settings.
     */
    fun restoreForRun(
        profile: ExportProfile,
        current: ExportSettings,
        lookbackDays: Int,
    ): ExportSettings? {
        val snapshot = AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)
            ?: return null
        val withEndpoint = current.copy(
            apiEndpointUrl = profile.apiEndpointUrl ?: current.apiEndpointUrl,
        )
        val target = profile.target
        val restored = runCatching { snapshot.restoreOnto(withEndpoint) }.getOrNull() ?: return null
        return restored.copy(
            exportTarget = target,
            scheduledExportTarget = target,
            scheduleLookbackDays = lookbackDays,
            executionEnginePin = snapshot.enginePin,
            executionEngineAuthorityIsFrozen = true,
        )
    }
}
