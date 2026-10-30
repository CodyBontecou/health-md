package com.healthmd.data.scheduler

import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.repository.SettingsRepository
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
    private val settingsRepository: SettingsRepository,
) {

    /** Captures the canonical frozen snapshot for [profile] from [current] settings. */
    suspend fun capture(profile: ExportProfile, current: ExportSettings): String =
        captureFromCurrent(
            current = current,
            target = profile.target,
            apiEndpointUrl = profile.apiEndpointUrl,
            agentDataGatewayUrl = profile.agentDataGatewayUrl,
        )

    /** Captures a frozen snapshot of current settings scoped to an explicit target. */
    suspend fun captureFromCurrent(
        current: ExportSettings,
        target: ExportTarget,
        apiEndpointUrl: String? = null,
        agentDataGatewayUrl: String? = null,
    ): String {
        val zone = ZoneId.systemDefault()
        // Acceptance is a NEW operation. Read the device setting once; activation/run restore
        // below never manufactures authority from a mutable preference.
        val context = AndroidCaptureContext(zone, settingsRepository.getSleepDayAttribution())
            .also { it.requireShippedProfile() }
        val scoped = current.copy(
            executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true,
            executionProviderCaptureAuthority = null,
            executionProviderCaptureAuthorityIsFrozen = false,
            exportTarget = target,
            scheduledExportTarget = target,
            apiEndpointUrl = apiEndpointUrl ?: current.apiEndpointUrl,
            agentDataGatewayUrl = agentDataGatewayUrl ?: current.agentDataGatewayUrl,
        )
        val pin = enginePinPlanner.forScheduledExport(scoped, target, zone)
        return AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(scoped, pin, zone, context),
        )
    }

    /** New occurrence only. Pending work must restore its saved profile without calling this. */
    suspend fun captureForNewOccurrence(
        profile: ExportProfile,
        current: ExportSettings,
        zone: ZoneId,
        source: com.healthmd.domain.repository.HealthRepository,
    ): ExportProfile? {
        val original = AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson) ?: return null
        val attribution = settingsRepository.getSleepDayAttribution()
        // Preserve historical Night profile pins and canonical bytes when no transition is needed.
        if (attribution == com.healthmd.domain.model.SleepDayAttribution.NIGHT_BEGINS &&
            original.sleepCaptureContext?.sleepDayAttribution != com.healthmd.domain.model.SleepDayAttribution.MORNING_ENDS) return profile
        val frozen = restoreFrozenSnapshot(profile, current) ?: return null
        val context = AndroidCaptureContext(zone, attribution).also { it.requireShippedProfile() }
        val authority = if (attribution == com.healthmd.domain.model.SleepDayAttribution.MORNING_ENDS)
            (source as? com.healthmd.domain.repository.RestorableHealthRepository
                ?: error("Provider capture authority is unavailable")).captureProviderAuthority() else null
        val settings = frozen.copy(executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
            executionProviderCaptureAuthority = authority, executionProviderCaptureAuthorityIsFrozen = authority != null,
            executionEnginePin = null, executionEngineAuthorityIsFrozen = false)
        val pin = enginePinPlanner.forScheduledExport(settings, profile.target, zone)
        return profile.copy(settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, pin, zone, context)))
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
    ): ExportSettings? = restoreFrozenSnapshot(profile, current)?.copy(
        scheduleLookbackDays = lookbackDays,
    )

    /**
     * Restores a profile's frozen snapshot onto live settings for interactive editing (profile
     * activation). Same restore semantics as [restoreForRun] — endpoint URL applied first so
     * `restoreOnto`'s fail-closed fingerprint check validates, frozen engine authority
     * re-injected, targets forced to the profile binding — except run-scoped fields (lookback)
     * stay at the user's live values. Returns null when the snapshot is undecodable or invalid;
     * callers fail closed and keep live settings unchanged.
     */
    fun applyForActivation(
        profile: ExportProfile,
        current: ExportSettings,
    ): ExportSettings? = restoreFrozenSnapshot(profile, current)?.copy(
        // Editing/activation is not a pending capture. A separately requested new export
        // resolves its current device setting, while restoreForRun preserves accepted authority.
        executionSleepCaptureContext = null,
        executionSleepCaptureAuthorityIsFrozen = false,
        executionProviderCaptureAuthority = null,
        executionProviderCaptureAuthorityIsFrozen = false,
    )

    private fun restoreFrozenSnapshot(profile: ExportProfile, current: ExportSettings): ExportSettings? {
        val snapshot = AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)
            ?: return null
        val withDestination = current.copy(
            apiEndpointUrl = profile.apiEndpointUrl ?: current.apiEndpointUrl,
            agentDataGatewayUrl = profile.agentDataGatewayUrl ?: current.agentDataGatewayUrl,
        )
        val target = profile.target
        val restored = runCatching { snapshot.restoreOnto(withDestination) }.getOrNull() ?: return null
        return restored.copy(
            exportTarget = target,
            scheduledExportTarget = target,
            executionEnginePin = snapshot.enginePin,
            executionEngineAuthorityIsFrozen = true,
        )
    }
}
