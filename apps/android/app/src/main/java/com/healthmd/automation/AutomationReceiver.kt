package com.healthmd.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.ExportAwakeCoordinator
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.scheduler.ProfileFolderAdoptionScope
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.export.ExportAccountingPolicy
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.EXPORT_FOLDER_ROOT_TARGET_LABEL
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileResolution
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import timber.log.Timber
import java.time.LocalDate
import javax.inject.Inject

internal fun resolveAutomationProfileReference(
    profiles: List<ExportProfile>,
    reference: String,
): ExportProfileResolution = ExportProfileRules.byId(profiles, reference.trim())
    ?.let { ExportProfileResolution.Resolved(it) }
    ?: ExportProfileRules.resolve(profiles = profiles, id = null, name = reference)

internal fun hasInvalidAutomationProfileSnapshot(
    profile: ExportProfile?,
    restoredSettings: ExportSettings?,
): Boolean = profile != null && restoredSettings == null

/**
 * Explicit automation entrypoint for Tasker/adb/launcher shortcuts.
 *
 * Security model: this receiver is exported but intentionally has no manifest intent-filter.
 * Callers must target the component explicitly, e.g.:
 *
 * `adb shell am broadcast -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
 *   -a com.healthmd.android.action.EXPORT_YESTERDAY`
 *
 * That avoids arbitrary implicit broadcasts exporting health data.
 */
@AndroidEntryPoint
class AutomationReceiver : BroadcastReceiver() {

    @Inject lateinit var healthRepository: HealthRepository
    @Inject lateinit var exportRepository: ExportRepository
    @Inject lateinit var settingsRepository: SettingsRepository
    @Inject lateinit var exportHistoryRepository: ExportHistoryRepository
    @Inject lateinit var exportProfileRepository: ExportProfileRepository
    @Inject lateinit var profileFolderAdoption: ProfileFolderAdoptionScope
    @Inject lateinit var apiEndpointExportRunner: APIEndpointExportRunner
    @Inject lateinit var entitlementRepository: EntitlementRepository
    @Inject lateinit var distributionPolicy: DistributionPolicy

    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                when (intent.action) {
                    ACTION_EXPORT_YESTERDAY -> runExport(context, listOf(LocalDate.now().minusDays(1)), profileReference(intent))
                    ACTION_EXPORT_LAST_DAYS -> {
                        val days = intent.getIntExtra(EXTRA_DAYS, 1).coerceIn(1, 365)
                        val end = LocalDate.now().minusDays(1)
                        val start = end.minusDays((days - 1).toLong())
                        runExport(context, ExportOrchestrator.dateRange(start, end), profileReference(intent))
                    }
                    ACTION_EXPORT_DATE -> {
                        val date = intent.getStringExtra(EXTRA_DATE)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                            ?: LocalDate.now().minusDays(1)
                        runExport(context, listOf(date), profileReference(intent))
                    }
                    ACTION_EXPORT_RANGE -> {
                        val start = intent.getStringExtra(EXTRA_START_DATE)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                        val end = intent.getStringExtra(EXTRA_END_DATE)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                        if (start == null || end == null || end.isBefore(start)) {
                            publishResult(RESULT_INVALID_INPUT, PROTOCOL_INVALID_DATE_RANGE, Bundle.EMPTY)
                        } else {
                            runExport(context, ExportOrchestrator.dateRange(start, end), profileReference(intent))
                        }
                    }
                    ACTION_GET_LAST_STATUS -> publishLastStatus()
                    else -> publishResult(
                        RESULT_INVALID_INPUT,
                        "$PROTOCOL_UNKNOWN_ACTION_PREFIX${intent.action}",
                        Bundle.EMPTY,
                    )
                }
            } catch (e: Exception) {
                Timber.e(e, "Automation intent failed")
                publishResult(RESULT_FAILURE, PROTOCOL_AUTOMATION_FAILED, Bundle.EMPTY)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private suspend fun runExport(context: Context, dates: List<LocalDate>, profileReference: String? = null) =
        ExportAwakeCoordinator.shared.whileExporting {
            runExportWhileAwake(context, dates, profileReference)
        }

    /**
     * Phase-6 profile resolution (mirrors iOS decision 9): an explicit reference resolves by id,
     * then trimmed/case-insensitive name, and fails closed when missing; empty uses the active
     * profile once any profile exists; with no profiles at all, live settings keep pre-profile
     * behavior. Failing resolution publishes a typed error without touching export state.
     */
    /** Resolved run scope: restored profile settings (null = live settings) plus the profile. */
    private data class ProfileRunScope(
        val settings: ExportSettings?,
        val profile: ExportProfile?,
    )

    private suspend fun resolveProfileForRun(
        profileReference: String?,
    ): ProfileRunScope {
        val reference = profileReference?.trim().orEmpty()
        if (reference.isEmpty()) {
            val profiles = exportProfileRepository.getProfiles()
            if (profiles.isEmpty()) return ProfileRunScope(null, null)
            val active = exportProfileRepository.getActiveProfile()
                ?: return ProfileRunScope(null, null)
            return ProfileRunScope(resolveProfileSettings(active), active)
        }
        return when (
            val resolution = resolveAutomationProfileReference(
                profiles = exportProfileRepository.getProfiles(),
                reference = reference,
            )
        ) {
            is ExportProfileResolution.Resolved ->
                ProfileRunScope(resolveProfileSettings(resolution.profile), resolution.profile)
            is ExportProfileResolution.NotFound ->
                throw AutomationProfileNotFound(reference)
            ExportProfileResolution.LegacySettings -> ProfileRunScope(null, null)
        }
    }

    /** Restores the profile's frozen snapshot onto current settings, or null when undecodable. */
    private suspend fun resolveProfileSettings(profile: ExportProfile): ExportSettings? {
        val current = settingsRepository.getExportSettings()
        val snapshot = runCatching {
            AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)
        }.getOrNull() ?: return null
        return runCatching { snapshot.restoreOnto(current) }.getOrNull()
    }

    private suspend fun runExportWhileAwake(context: Context, dates: List<LocalDate>, profileReference: String? = null) {
        if (dates.isEmpty()) {
            publishResult(RESULT_INVALID_INPUT, PROTOCOL_NO_DATES_REQUESTED, Bundle.EMPTY)
            return
        }

        val profileSettingsAndName = try {
            resolveProfileForRun(profileReference)
        } catch (_: AutomationProfileNotFound) {
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = emptyList(),
            )
            publishExportResult(result, "$PROTOCOL_PROFILE_NOT_FOUND:$profileReference")
            return
        }
        val profile = profileSettingsAndName.profile
        val currentSettings = settingsRepository.getExportSettings()
        if (hasInvalidAutomationProfileSnapshot(profile, profileSettingsAndName.settings)) {
            val invalidProfile = requireNotNull(profile)
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map {
                    FailedDateDetail(it, ExportFailureReason.UNKNOWN)
                },
                target = invalidProfile.target,
            )
            recordHistory(
                context,
                dates,
                result,
                ExportFailureReason.UNKNOWN,
                PROTOCOL_PROFILE_SNAPSHOT_INVALID,
                currentSettings,
                invalidProfile,
                invalidProfile.target,
            )
            publishExportResult(result, PROTOCOL_PROFILE_SNAPSHOT_INVALID)
            return
        }
        val settings = profileSettingsAndName.settings ?: currentSettings
        val target = profile?.target ?: settings.exportTarget
        entitlementRepository.refresh()
        val isPurchased = distributionPolicy.fullAccessIncluded ||
            settingsRepository.isPurchased.first() ||
            entitlementRepository.isUnlocked.first()
        val freeExportsRemaining = settingsRepository.getFreeExportsRemaining()
        // A folder-bound profile satisfies the destination requirement on its own.
        val folderUri = settingsRepository.getExportFolderUri()
            ?: profile?.folderUri?.takeIf { it.isNotBlank() }

        if (!isPurchased && freeExportsRemaining <= 0) {
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map { FailedDateDetail(it, ExportFailureReason.PAYWALL_REQUIRED) },
            )
            recordHistory(
                context,
                dates,
                result,
                ExportFailureReason.PAYWALL_REQUIRED,
                PROTOCOL_SCHEDULE_UNLOCK_REQUIRED,
                settings,
                profile,
                target,
            )
            publishExportResult(result, PROTOCOL_UNLOCK_REQUIRED)
            return
        }

        if (target == ExportTarget.DEVICE_FOLDER && folderUri.isNullOrBlank()) {
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map { FailedDateDetail(it, ExportFailureReason.NO_FOLDER_SELECTED) },
            )
            recordHistory(
                context,
                dates,
                result,
                ExportFailureReason.NO_FOLDER_SELECTED,
                PROTOCOL_NO_EXPORT_FOLDER,
                settings,
                profile,
                target,
            )
            publishExportResult(result, PROTOCOL_NO_EXPORT_FOLDER)
            return
        }

        if (!healthRepository.hasPermissions()) {
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map { FailedDateDetail(it, ExportFailureReason.ACCESS_DENIED) },
            )
            recordHistory(
                context,
                dates,
                result,
                ExportFailureReason.ACCESS_DENIED,
                PROTOCOL_HEALTH_PERMISSIONS_MISSING,
                settings,
                profile,
                target,
            )
            publishExportResult(result, PROTOCOL_HEALTH_PERMISSIONS_MISSING)
            return
        }

        val result = when (target) {
            ExportTarget.DEVICE_FOLDER -> {
                val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
                // Per-profile folder: adopt the resolved profile's binding around the run.
                profile?.let {
                    profileFolderAdoption.withProfileFolder(it) {
                        orchestrator.exportDates(dates, settings.copy(exportTarget = target))
                    }
                } ?: orchestrator.exportDates(dates, settings.copy(exportTarget = target))
            }
            ExportTarget.API_ENDPOINT -> apiEndpointExportRunner.exportDates(
                dates = dates,
                settings = settings.copy(exportTarget = target),
            )
        }
        recordHistory(
            context,
            dates,
            result,
            result.primaryFailureReason,
            result.protocolWarningSummary(),
            settings,
            profile,
            target,
        )

        if (ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased)) {
            settingsRepository.recordFreeExportUse()
        }

        publishExportResult(result, protocolDaysExported(result.successCount, result.totalCount))
    }

    private suspend fun publishLastStatus() {
        val entry = exportHistoryRepository.getAllEntries().first().firstOrNull()
        if (entry == null) {
            publishResult(RESULT_SUCCESS, PROTOCOL_NO_EXPORT_HISTORY, Bundle.EMPTY)
            return
        }
        publishResult(
            if (entry.isFailure) RESULT_FAILURE else RESULT_SUCCESS,
            protocolDaysExported(entry.successCount, entry.totalCount),
            Bundle().apply {
                putLong(EXTRA_HISTORY_ID, entry.id)
                putString(EXTRA_SOURCE, entry.source.name)
                putString(EXTRA_START_DATE, entry.dateRangeStart.toString())
                putString(EXTRA_END_DATE, entry.dateRangeEnd.toString())
                putInt(EXTRA_SUCCESS_COUNT, entry.successCount)
                putInt(EXTRA_TOTAL_COUNT, entry.totalCount)
                putString(EXTRA_FAILURE_REASON, entry.failureReason?.name)
                putString(EXTRA_WARNING, entry.warningSummary)
            },
        )
    }

    private suspend fun recordHistory(
        context: Context,
        dates: List<LocalDate>,
        result: ExportResult,
        failureReason: ExportFailureReason?,
        warning: String?,
        settings: ExportSettings,
        profile: ExportProfile?,
        target: ExportTarget,
    ) {
        exportHistoryRepository.insertEntry(
            ExportHistoryEntry(
                timestamp = System.currentTimeMillis(),
                source = ExportSource.SHORTCUT,
                dateRangeStart = dates.first(),
                dateRangeEnd = dates.last(),
                successCount = result.successCount,
                totalCount = result.totalCount,
                failureReason = failureReason,
                failedDateDetails = result.failedDateDetails,
                target = target,
                targetLabel = when (target) {
                    ExportTarget.DEVICE_FOLDER ->
                        profile?.folderDisplayName?.trim()?.takeIf { it.isNotEmpty() }
                            ?: targetLabel(settings)
                    ExportTarget.API_ENDPOINT -> APIExportEndpoint.redactedDescription(
                        profile?.apiEndpointUrl ?: settings.apiEndpointUrl,
                    )
                },
                profileName = profile?.name,
                fileCount = if (target == ExportTarget.DEVICE_FOLDER) {
                    result.successCount * settings.selectedExportFormats.size
                } else {
                    0
                },
                warningSummary = warning,
            )
        )
    }

    private fun targetLabel(settings: com.healthmd.domain.model.ExportSettings): String = buildString {
        val subfolder = settings.subfolder.trim('/').takeIf { it.isNotBlank() }
        append(subfolder ?: EXPORT_FOLDER_ROOT_TARGET_LABEL)
        settings.formatFolderPath(LocalDate.now().minusDays(1))?.takeIf { it.isNotBlank() }?.let {
            append("/").append(it.trim('/'))
        }
    }

    /** Persisted automation output is a public protocol field and must remain locale-invariant. */
    private fun ExportResult.protocolWarningSummary(): String? = when {
        isPartialSuccess -> "${failedDateDetails.size} failed date(s)"
        wasCancelled -> PROTOCOL_EXPORT_CANCELLED
        isFailure -> primaryFailureReason?.name
        else -> null
    }

    /** resultData is an automation protocol field, so its existing English text remains invariant. */
    private fun protocolDaysExported(successCount: Int, totalCount: Int): String =
        "$successCount/$totalCount days exported"

    private fun publishExportResult(result: ExportResult, message: String) {
        publishResult(
            if (result.isFailure) RESULT_FAILURE else RESULT_SUCCESS,
            message,
            Bundle().apply {
                putInt(EXTRA_SUCCESS_COUNT, result.successCount)
                putInt(EXTRA_TOTAL_COUNT, result.totalCount)
                putString(EXTRA_FAILURE_REASON, result.primaryFailureReason?.name)
                putStringArray(EXTRA_FAILED_DATES, result.failedDateDetails.map { it.date.toString() }.toTypedArray())
            },
        )
    }

    /**
     * Sets the ordered-broadcast result when it is still pending. Non-ordered broadcasts (e.g.
     * plain `adb shell am broadcast`) finalize their result before an async goAsync body resumes,
     * and `setResult*` then throws — historically crashing the app from the catch path. Result
     * delivery is best-effort: the durable side effects (export, history, pending work) never
     * depend on it.
     */
    private fun publishResult(code: Int, message: String, extras: Bundle) {
        try {
            resultCode = code
            resultData = message
            setResultExtras(extras)
        } catch (_: IllegalStateException) {
            Timber.d("Automation result not deliverable (broadcast finalized): %s", message)
        }
        Timber.d("Automation result: %s (%s)", message, code)
    }

    private fun profileReference(intent: Intent): String? =
        intent.getStringExtra(EXTRA_PROFILE)?.takeIf { it.isNotBlank() }

    /** Thrown when an explicit profile reference does not resolve; never falls back. */
    private class AutomationProfileNotFound(val reference: String) : Exception(reference)

    companion object {
        const val ACTION_EXPORT_YESTERDAY = "com.healthmd.android.action.EXPORT_YESTERDAY"
        const val ACTION_EXPORT_LAST_DAYS = "com.healthmd.android.action.EXPORT_LAST_DAYS"
        const val ACTION_EXPORT_DATE = "com.healthmd.android.action.EXPORT_DATE"
        const val ACTION_EXPORT_RANGE = "com.healthmd.android.action.EXPORT_RANGE"
        const val ACTION_GET_LAST_STATUS = "com.healthmd.android.action.GET_LAST_STATUS"

        const val EXTRA_DAYS = "com.healthmd.android.extra.DAYS"
        const val EXTRA_DATE = "com.healthmd.android.extra.DATE"
        const val EXTRA_START_DATE = "com.healthmd.android.extra.START_DATE"
        const val EXTRA_END_DATE = "com.healthmd.android.extra.END_DATE"
        /** Optional export profile id or name; empty resolves the active profile. */
        const val EXTRA_PROFILE = "com.healthmd.android.extra.PROFILE"
        const val EXTRA_SUCCESS_COUNT = "com.healthmd.android.extra.SUCCESS_COUNT"
        const val EXTRA_TOTAL_COUNT = "com.healthmd.android.extra.TOTAL_COUNT"
        const val EXTRA_FAILURE_REASON = "com.healthmd.android.extra.FAILURE_REASON"
        const val EXTRA_FAILED_DATES = "com.healthmd.android.extra.FAILED_DATES"
        const val EXTRA_HISTORY_ID = "com.healthmd.android.extra.HISTORY_ID"
        const val EXTRA_SOURCE = "com.healthmd.android.extra.SOURCE"
        const val EXTRA_WARNING = "com.healthmd.android.extra.WARNING"

    const val RESULT_SUCCESS = 1
    const val RESULT_FAILURE = 2
        const val RESULT_INVALID_INPUT = 3

        private const val PROTOCOL_INVALID_DATE_RANGE = "Invalid date range"
        private const val PROTOCOL_UNKNOWN_ACTION_PREFIX = "Unknown action: "
        private const val PROTOCOL_AUTOMATION_FAILED = "Automation failed"
        private const val PROTOCOL_NO_DATES_REQUESTED = "No dates requested"
        private const val PROTOCOL_UNLOCK_REQUIRED = "Unlock Health.md to run automation exports"
        private const val PROTOCOL_SCHEDULE_UNLOCK_REQUIRED = "Unlock Health.md to enable scheduled exports."
        private const val PROTOCOL_NO_EXPORT_FOLDER = "No export folder selected"
        private const val PROTOCOL_HEALTH_PERMISSIONS_MISSING = "Health Connect permissions missing"
        private const val PROTOCOL_NO_EXPORT_HISTORY = "No export history"
        private const val PROTOCOL_EXPORT_CANCELLED = "Export cancelled"
        private const val PROTOCOL_PROFILE_NOT_FOUND = "profile_not_found"
        private const val PROTOCOL_PROFILE_SNAPSHOT_INVALID = "profile_snapshot_invalid"
    }
}
