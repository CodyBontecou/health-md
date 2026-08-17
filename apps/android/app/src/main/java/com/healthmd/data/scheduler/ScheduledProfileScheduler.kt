package com.healthmd.data.scheduler

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.await
import androidx.work.workDataOf
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import timber.log.Timber

/**
 * Arms and re-arms one exact alarm per enabled scheduled-profile entry (Android phase-6 runtime).
 *
 * Deliberately parallel to the single-schedule [ExportScheduler] rather than a refactor of its
 * single-occurrence state machine: per-entry PendingIntent request codes (derived from the
 * profile id) keep alarms independent, and each entry's WorkManager fallback trigger is tagged
 * per entry. Android imposes no iOS-style coalesced wake-up constraint, so N entries arm N alarms.
 *
 * Also owns two cross-platform rules: orphaned entries (profile deleted) are disabled instead of
 * running the wrong profile, and the legacy single schedule migrates into the Default profile's
 * entry exactly once.
 */
@Singleton
class ScheduledProfileScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val workManager: WorkManager,
    private val entryStore: ScheduledProfileEntryStore,
    private val profileRepository: ExportProfileRepository,
    private val legacySettings: com.healthmd.domain.repository.SettingsRepository,
) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)
    private val mutex = Mutex()

    /** Re-arms every enabled entry and applies migration/orphan rules. */
    suspend fun reconcile(forceRecalculate: Boolean = false) {
        mutex.withLock {
            migrateLegacyScheduleIfNeeded()
            val profiles = profileRepository.getProfiles()
            val entries = entryStore.getEntries()

            // Orphan rule: an entry whose profile vanished is disabled, never run.
            entries.filter { it.isEnabled && profiles.none { p -> p.id == it.profileId } }
                .forEach { orphaned ->
                    Timber.w("Disabling orphaned profile schedule profileId=%s", orphaned.profileId)
                    entryStore.update(orphaned.profileId) { it.copy(isEnabled = false) }
                }

            val armed = entryStore.getEntries().filter { it.isEnabled }
            val armedProfileIds = armed.map { it.profileId }.toSet()

            // Cancel alarms and fallbacks for disabled or removed entries.
            entryStore.getEntries().filter { it.profileId !in armedProfileIds }.forEach { entry ->
                cancelEntryAlarm(entry.profileId)
            }

            for (entry in armed) {
                val next = ScheduledProfileOccurrenceMath.nextOccurrence(entry, System.currentTimeMillis())
                if (next == null) {
                    Timber.w("No next occurrence for profile schedule profileId=%s", entry.profileId)
                    cancelEntryAlarm(entry.profileId)
                    continue
                }
                armEntry(entry, next, force = forceRecalculate)
            }
        }
    }

    /** Called by the alarm receiver: enqueue this entry's durable export work immediately. */
    suspend fun handleAlarm(profileId: String) {
        Timber.i("Profile schedule alarm delivered profileId=%s", profileId)
        val entry = entryStore.entry(profileId)
        if (entry == null) {
            Timber.w("Profile schedule alarm unknown entry profileId=%s", profileId)
            return
        }
        if (!entry.isEnabled) {
            Timber.i("Profile schedule alarm entry disabled profileId=%s", profileId)
            return
        }
        enqueueExportWork(entry, expedited = true)
    }

    /** Re-arms one entry after its worker finished; safe to call repeatedly. */
    suspend fun reconcileEntry(profileId: String) {
        val entry = entryStore.entry(profileId) ?: return cancelEntryAlarm(profileId)
        if (!entry.isEnabled) return cancelEntryAlarm(profileId)
        val next = ScheduledProfileOccurrenceMath.nextOccurrence(entry, System.currentTimeMillis())
        if (next == null) return cancelEntryAlarm(profileId)
        armEntry(entry, next, force = false)
    }

    private suspend fun armEntry(
        entry: ScheduledProfileEntry,
        next: Instant,
        force: Boolean,
    ) {
        val pendingIntent = entryAlarmPendingIntent(entry.profileId, create = true)
        val triggerAtMillis = next.toEpochMilli()
        val exactSet = canScheduleExactAlarms() && runCatching {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent)
            true
        }.getOrDefault(false)
        if (!exactSet) {
            runCatching { alarmManager.cancel(pendingIntent) }
            Timber.w(
                "Exact alarm unavailable for profile schedule profileId=%s; WorkManager fallback only",
                entry.profileId,
            )
        }

        // Durable delayed fallback per entry, mirroring the single scheduler's strategy.
        val delay = (triggerAtMillis - System.currentTimeMillis()).coerceAtLeast(0)
        val request = OneTimeWorkRequestBuilder<ScheduledProfileTriggerWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .setInputData(workDataOf(ScheduledProfileTriggerWorker.INPUT_PROFILE_ID to entry.profileId))
            .addTag(fallbackTag(entry.profileId))
            .build()
        workManager.enqueueUniqueWork(
            fallbackName(entry.profileId),
            ExistingWorkPolicy.REPLACE,
            request,
        ).await()
    }

    private suspend fun enqueueExportWork(entry: ScheduledProfileEntry, expedited: Boolean) {
        val constraints = Constraints.Builder().apply {
            // Conservative: run when any network exists; folder exports tolerate none but API needs it.
            setRequiredNetworkType(NetworkType.CONNECTED)
        }.build()
        val request = OneTimeWorkRequestBuilder<ScheduledProfileExportWorker>()
            .setInputData(workDataOf(ScheduledProfileExportWorker.INPUT_PROFILE_ID to entry.profileId))
            .setConstraints(constraints)
            .setBackoffCriteria(androidx.work.BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .addTag(EXPORT_WORK_TAG)
        if (expedited) {
            request.setExpedited(
                androidx.work.OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST,
            )
        }
        workManager.enqueueUniqueWork(
            exportWorkName(entry.profileId),
            ExistingWorkPolicy.KEEP,
            request.build(),
        ).await()
    }

    private fun entryAlarmPendingIntent(profileId: String, create: Boolean): PendingIntent {
        val intent = Intent(context, ScheduledProfileAlarmReceiver::class.java).apply {
            action = ACTION_PROFILE_SCHEDULE_ALARM
            putExtra(ScheduledProfileAlarmReceiver.EXTRA_PROFILE_ID, profileId)
        }
        val flags = if (create) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getBroadcast(context, requestCodeFor(profileId), intent, flags)
    }

    private fun cancelEntryAlarm(profileId: String) {
        val pendingIntent = entryAlarmPendingIntent(profileId, create = false) ?: return
        runCatching { alarmManager.cancel(pendingIntent) }
        pendingIntent.cancel()
    }

    fun canScheduleExactAlarms(): Boolean =
        android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S ||
            alarmManager.canScheduleExactAlarms()

    /**
     * One-time migration: an enabled legacy single schedule becomes the Default profile's entry,
     * then the legacy schedule is disabled so exactly one runtime path owns scheduling.
     */
    private suspend fun migrateLegacyScheduleIfNeeded() {
        val entries = entryStore.getEntries()
        if (entries.isNotEmpty()) return
        val settings = legacySettings.getExportSettings()
        if (!settings.scheduleEnabled) return
        val defaultProfile = profileRepository.getActiveProfile() ?: return

        val zone = ZoneId.systemDefault()
        val entry = ScheduledProfileEntry(
            profileId = defaultProfile.id,
            isEnabled = true,
            anchorEpochDay = LocalDate.now(zone).toEpochDay(),
            weekdayIso = 1,
            hour = settings.scheduleHour.coerceIn(0, 23),
            minute = settings.scheduleMinute.coerceIn(0, 59),
            cadenceValue = settings.scheduleCadenceValue.coerceAtLeast(1),
            cadenceUnit = when (settings.scheduleCadenceUnit) {
                // The legacy single schedule supports minute/hour/day/week cadences only;
                // sub-day cadences map to daily because profile entries are day-granular.
                ScheduleCadenceUnit.MINUTES, ScheduleCadenceUnit.HOURS, ScheduleCadenceUnit.DAYS ->
                    ScheduledProfileCadenceUnit.DAY
                ScheduleCadenceUnit.WEEKS -> ScheduledProfileCadenceUnit.WEEK
            },
            dateWindow = ScheduledProfileDateWindow.PAST_COMPLETE_DAYS,
            lookbackDays = settings.scheduleLookbackDays.coerceIn(1, 30),
            zoneId = zone.id,
        )
        entryStore.upsert(entry)
        Timber.i("Migrated legacy schedule into Default profile entry")
    }

    companion object {
        const val ACTION_PROFILE_SCHEDULE_ALARM = "com.healthmd.android.action.PROFILE_SCHEDULE_ALARM"
        const val EXPORT_WORK_TAG = "scheduled_profile_export"
        private const val ALARM_REQUEST_CODE_BASE = 7_000_000

        /** Stable per-entry request code; hash spread from the legacy single-alarm codes. */
        fun requestCodeFor(profileId: String): Int =
            ALARM_REQUEST_CODE_BASE + (profileId.hashCode() and 0x00FFFFFF)

        fun fallbackTag(profileId: String) = "scheduled_profile_trigger_$profileId"

        fun fallbackName(profileId: String) = "scheduled_profile_trigger_work_$profileId"

        fun exportWorkName(profileId: String) = "profile-export-$profileId"
    }
}
