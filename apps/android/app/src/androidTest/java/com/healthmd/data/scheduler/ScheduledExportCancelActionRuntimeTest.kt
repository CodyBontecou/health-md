package com.healthmd.data.scheduler

import android.content.Context
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.healthmd.domain.model.ExportTarget
import com.healthmd.sharedsetup.SharedSetupInstrumentationEntryPoint
import dagger.hilt.android.EntryPointAccessors
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Live device QA for the scheduled-export foreground notification cancel action.
 *
 * The production alarm/fallback delivery admits the occurrence; the external host driver opens a
 * slow export endpoint via `adb reverse` and taps the real "Cancel Export" notification action
 * while this test waits. The test then verifies the production contract: only the current attempt
 * stops, the schedule stays enabled with a future occurrence, zero-progress cancellation records
 * no history, and the unresolved dates stay frozen for a later retry.
 */
@LargeTest
@RunWith(AndroidJUnit4::class)
class ScheduledExportCancelActionRuntimeTest {

    @Test
    fun notificationCancelStopsOnlyCurrentAttemptAndKeepsScheduleEnabled() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            SharedSetupInstrumentationEntryPoint::class.java,
        )
        val settingsRepository = entryPoint.settingsRepository()
        val scheduler = entryPoint.exportScheduler()
        val historyRepository = entryPoint.exportHistoryRepository()
        val workManager = WorkManager.getInstance(context)

        runBlocking {
            val original = settingsRepository.getExportSettings()
            val originalPurchased = settingsRepository.isPurchased.first()
            val historyBefore = historyRepository.getAllEntries().first().size
            try {
                // Clean slate for the e2e app, then a fresh schedule aimed about one minute out.
                scheduler.cancel()
                settingsRepository.setPurchased(true)
                val fireAt = System.currentTimeMillis() + FIRE_DELAY_MILLIS
                val fireLocal = Instant.ofEpochMilli(fireAt).atZone(ZoneId.systemDefault())
                settingsRepository.updateExportSettingsAtomically { settings ->
                    settings.copy(
                        scheduleEnabled = true,
                        scheduledExportTarget = ExportTarget.API_ENDPOINT,
                        apiEndpointUrl = QA_ENDPOINT_URL,
                        scheduleCadenceValue = 1,
                        scheduleHour = fireLocal.hour,
                        scheduleMinute = fireLocal.minute,
                        pendingScheduledRetryDates = emptyList(),
                        pendingScheduledExportRequests = emptyList(),
                    )
                }
                scheduler.reconcile()
                val armedAt = requireNotNull(scheduler.nextScheduledAtMillis()) {
                    "Reconcile must arm a scheduled-export occurrence."
                }
                Log.i(TAG, "QA_ARMED triggerAt=$armedAt")

                // The exact alarm or durable fallback delivers the occurrence; its admitted
                // ExportWorker must reach RUNNING and post its foreground notification.
                var runningIds = listOf<java.util.UUID>()
                waitFor("worker running") {
                    runningIds = workInfos(workManager)
                        .filter { it.state == WorkInfo.State.RUNNING }
                        .map { it.id }
                    runningIds.isNotEmpty()
                }
                Log.i(TAG, "QA_CANCEL_WINDOW_OPEN ids=$runningIds tap the notification action now")

                // The host driver taps the real notification action; the worker then finishes.
                waitFor("worker terminal") {
                    val tracked = workInfos(workManager).filter { it.id in runningIds }
                    tracked.isNotEmpty() && tracked.all { it.state.isFinished }
                }
                val terminalStates = workInfos(workManager)
                    .filter { it.id in runningIds }
                    .associate { it.id to it.state }
                Log.i(TAG, "QA_WORKER_FINISHED states=$terminalStates")
                assertTrue(
                    "Cancelled scheduled export must complete its own durable reconciliation",
                    terminalStates.values.all { it == WorkInfo.State.SUCCEEDED },
                )

                // Contract assertions after the real notification-driven cancellation.
                val after = settingsRepository.getExportSettings()
                val historyAfter = historyRepository.getAllEntries().first()
                assertTrue("Schedule must remain enabled after cancellation", after.scheduleEnabled)
                val next = scheduler.nextScheduledAtMillis()
                assertNotNull("Schedule must stay armed for the next occurrence", next)
                assertTrue(
                    "Next occurrence must remain in the future",
                    requireNotNull(next) > System.currentTimeMillis(),
                )
                assertEquals(
                    "Zero-progress cancellation must not record failure history",
                    historyBefore,
                    historyAfter.size,
                )
                assertTrue(
                    "Unresolved dates must stay frozen for a later retry",
                    after.pendingScheduledRetryDates.isNotEmpty(),
                )
                Log.i(
                    TAG,
                    "QA_ASSERTED pendingDates=${after.pendingScheduledRetryDates.size} " +
                        "nextTriggerAt=${scheduler.nextScheduledAtMillis()}",
                )
            } finally {
                logDiagnostics(historyRepository, settingsRepository)
                scheduler.cancel()
                settingsRepository.setPurchased(originalPurchased)
                settingsRepository.updateExportSettingsAtomically { settings ->
                    settings.copy(
                        scheduleEnabled = original.scheduleEnabled,
                        apiEndpointUrl = original.apiEndpointUrl,
                        pendingScheduledRetryDates = emptyList(),
                        pendingScheduledExportRequests = emptyList(),
                    )
                }
                Log.i(TAG, "QA_CLEANUP_DONE")
            }
        }
    }

    private suspend fun logDiagnostics(
        historyRepository: com.healthmd.domain.repository.ExportHistoryRepository,
        settingsRepository: com.healthmd.domain.repository.SettingsRepository,
    ) {
        val entries = historyRepository.getAllEntries().first().takeLast(4)
        entries.forEach { entry ->
            Log.i(
                TAG,
                "QA_HISTORY timestamp=${entry.timestamp} source=${entry.source} " +
                    "success=${entry.successCount}/${entry.totalCount} " +
                    "reason=${entry.failureReason} failedDates=${entry.failedDateDetails.size} " +
                    "warning=${entry.warningSummary}",
            )
        }
        val settings = settingsRepository.getExportSettings()
        Log.i(
            TAG,
            "QA_SETTINGS scheduleEnabled=${settings.scheduleEnabled} " +
                "pendingRetryDates=${settings.pendingScheduledRetryDates} " +
                "pendingRequests=${settings.pendingScheduledExportRequests.size}",
        )
    }

    private fun workInfos(workManager: WorkManager): List<WorkInfo> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val liveData = workManager.getWorkInfosByTagLiveData(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        val latch = CountDownLatch(1)
        var value: List<WorkInfo>? = null
        val observer = androidx.lifecycle.Observer<List<WorkInfo>> { infos ->
            value = infos
            latch.countDown()
        }
        instrumentation.runOnMainSync { liveData.observeForever(observer) }
        try {
            latch.await(5, TimeUnit.SECONDS)
            return value.orEmpty()
        } finally {
            instrumentation.runOnMainSync { liveData.removeObserver(observer) }
        }
    }

    private fun waitFor(what: String, timeoutMillis: Long = DEFAULT_TIMEOUT_MILLIS, condition: () -> Boolean) {
        val deadline = System.currentTimeMillis() + timeoutMillis
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return
            Thread.sleep(POLL_INTERVAL_MILLIS)
        }
        error("Timed out after ${timeoutMillis}ms waiting for $what")
    }

    companion object {
        private const val TAG = "HealthMdCancelQA"
        private const val QA_ENDPOINT_URL = "http://127.0.0.1:8931/healthmd-qa"
        private const val FIRE_DELAY_MILLIS = 70_000L
        private const val DEFAULT_TIMEOUT_MILLIS = 420_000L
        private const val POLL_INTERVAL_MILLIS = 2_000L
    }
}
