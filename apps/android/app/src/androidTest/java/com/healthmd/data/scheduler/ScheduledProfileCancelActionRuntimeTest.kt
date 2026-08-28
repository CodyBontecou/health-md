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
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.sharedsetup.SharedSetupInstrumentationEntryPoint
import dagger.hilt.android.EntryPointAccessors
import java.time.LocalDate
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
 * Live device QA for the scheduled-profile foreground notification cancel action.
 *
 * The profile exact alarm delivers the occurrence on time (proven reliable on device); the host
 * driver opens a slow export endpoint via `adb reverse` and taps the real "Cancel Export"
 * notification action while this test waits. The test then verifies the production contract: only
 * the current attempt stops, the profile schedule stays enabled with a future occurrence,
 * zero-progress cancellation records no failure history, and the unresolved dates stay frozen with
 * their exact destination and settings identity for a later retry.
 */
@LargeTest
@RunWith(AndroidJUnit4::class)
class ScheduledProfileCancelActionRuntimeTest {

    @Test
    fun notificationCancelStopsOnlyCurrentProfileAttemptAndKeepsScheduleEnabled() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            SharedSetupInstrumentationEntryPoint::class.java,
        )
        val settingsRepository = entryPoint.settingsRepository()
        val profileRepository = entryPoint.exportProfileRepository()
        val snapshotFactory = entryPoint.profileSnapshotFactory()
        val entryStore = entryPoint.scheduledProfileEntryStore()
        val scheduler = entryPoint.scheduledProfileScheduler()
        val historyRepository = entryPoint.exportHistoryRepository()
        val healthRepository = entryPoint.healthRepository()
        val workManager = WorkManager.getInstance(context)

        runBlocking {
            val originalPurchased = settingsRepository.isPurchased.first()
            val historyBefore = historyRepository.getAllEntries().first().size
            var profileId: String? = null
            try {
                settingsRepository.setPurchased(true)
                // Warm the Health Connect client in this process and wait until the background-read
                // gate the worker enforces is actually satisfied before arming the occurrence.
                waitForPermission(healthRepository)
                Log.i(TAG, "QA_BACKGROUND_READ_READY")
                val snapshotJson = snapshotFactory.captureFromCurrent(
                    current = settingsRepository.getExportSettings(),
                    target = ExportTarget.API_ENDPOINT,
                    apiEndpointUrl = QA_ENDPOINT_URL,
                )
                val profile = profileRepository.add(
                    name = PROFILE_NAME,
                    settingsSnapshotJson = snapshotJson,
                    target = ExportTarget.API_ENDPOINT,
                    apiEndpointUrl = QA_ENDPOINT_URL,
                )
                profileId = profile.id

                val fireLocal = java.time.Instant.ofEpochMilli(
                    System.currentTimeMillis() + FIRE_DELAY_MILLIS,
                ).atZone(ZoneId.systemDefault())
                val entry = ScheduledProfileEntry(
                    profileId = profile.id,
                    isEnabled = true,
                    anchorEpochDay = LocalDate.now(ZoneId.systemDefault()).toEpochDay(),
                    hour = fireLocal.hour,
                    minute = fireLocal.minute,
                    lookbackDays = 2,
                    zoneId = ZoneId.systemDefault().id,
                )
                entryStore.upsert(entry)
                scheduler.reconcile()
                Log.i(TAG, "QA_ARMED fireAt=${fireLocal.hour}:${fireLocal.minute} profile=${profile.id}")

                // The profile exact alarm delivers the occurrence; its admitted worker must reach
                // RUNNING and post its foreground notification with the cancel action.
                var runningIds = listOf<java.util.UUID>()
                var finishedEarly = emptyList<WorkInfo.State>()
                waitFor("worker running", DEFAULT_TIMEOUT_MILLIS) {
                    val infos = workInfos(workManager)
                    runningIds = infos.filter { it.state == WorkInfo.State.RUNNING }.map { it.id }
                    if (runningIds.isEmpty()) {
                        finishedEarly = infos.filter { it.state.isFinished }.map { it.state }
                    }
                    runningIds.isNotEmpty()
                }
                if (runningIds.isEmpty()) {
                    error(
                        "Scheduled profile export finished before RUNNING (states=$finishedEarly); " +
                            "see QA_HISTORY/QA_ENTRY diagnostics",
                    )
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
                val entryAfter = assertNotNull(entryStore.entry(profile.id))
                val historyAfter = historyRepository.getAllEntries().first()
                assertTrue("Profile schedule must remain enabled", entryAfter.isEnabled)
                assertEquals(
                    "Zero-progress cancellation must not record failure history",
                    historyBefore,
                    historyAfter.size,
                )
                val residuals = entryAfter.pendingExports
                assertTrue("Cancelled occurrence must freeze exact residual work", residuals.isNotEmpty())
                val residual = residuals.single()
                assertEquals("Residual must keep the exact frozen destination", QA_ENDPOINT_URL, residual.apiEndpointUrl)
                assertEquals("Residual must keep the exact frozen settings snapshot", snapshotJson, residual.settingsSnapshotJson)
                assertEquals(ExportTarget.API_ENDPOINT, residual.target)
                assertNotNull("Residual must retain its durable operation identity", residual.durableOperationId)
                assertTrue(
                    "Residual must keep every unresolved owner date",
                    residual.ownerDates.size == 2,
                )
                Log.i(
                    TAG,
                    "QA_ASSERTED pendingDates=${residual.ownerDates} " +
                        "operation=${residual.durableOperationId}",
                )
            } finally {
                logDiagnostics(historyRepository, entryStore)
                profileId?.let { id -> runCatching { scheduler.removeEntry(id) } }
                settingsRepository.setPurchased(originalPurchased)
                Log.i(TAG, "QA_CLEANUP_DONE")
            }
        }
    }

    private suspend fun logDiagnostics(
        historyRepository: ExportHistoryRepository,
        entryStore: ScheduledProfileEntryStore,
    ) {
        historyRepository.getAllEntries().first().takeLast(3).forEach { entry ->
            Log.i(
                TAG,
                "QA_HISTORY timestamp=${entry.timestamp} source=${entry.source} " +
                    "success=${entry.successCount}/${entry.totalCount} reason=${entry.failureReason}",
            )
        }
        entryStore.getEntries().forEach { entry ->
            Log.i(
                TAG,
                "QA_ENTRY profile=${entry.profileId} enabled=${entry.isEnabled} " +
                    "pending=${entry.pendingExports.map { it.ownerDates }}",
            )
        }
    }

    private fun assertNotNull(entry: ScheduledProfileEntry?): ScheduledProfileEntry =
        requireNotNull(entry) { "Profile entry must persist" }

    private fun workInfos(workManager: WorkManager): List<WorkInfo> {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val liveData = workManager.getWorkInfosByTagLiveData(ScheduledProfileScheduler.EXPORT_WORK_TAG)
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

    private suspend fun waitForPermission(healthRepository: com.healthmd.domain.repository.HealthRepository) {
        val deadline = System.currentTimeMillis() + PERMISSION_TIMEOUT_MILLIS
        while (System.currentTimeMillis() < deadline) {
            if (runCatching { healthRepository.hasBackgroundReadPermission() }.getOrDefault(false)) return
            kotlinx.coroutines.delay(POLL_INTERVAL_MILLIS)
        }
        error("Health Connect background read permission was not granted in time")
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
        private const val PROFILE_NAME = "QA Cancel Profile"
        private const val FIRE_DELAY_MILLIS = 70_000L
        private const val DEFAULT_TIMEOUT_MILLIS = 420_000L
        private const val PERMISSION_TIMEOUT_MILLIS = 90_000L
        private const val POLL_INTERVAL_MILLIS = 500L
    }
}
