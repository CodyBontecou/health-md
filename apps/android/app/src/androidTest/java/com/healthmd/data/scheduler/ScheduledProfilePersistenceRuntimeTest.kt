package com.healthmd.data.scheduler

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.await
import androidx.work.workDataOf
import com.healthmd.sharedsetup.SharedSetupInstrumentationEntryPoint
import dagger.hilt.android.EntryPointAccessors
import androidx.lifecycle.Observer
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Physical Android DataStore/WorkManager regression coverage for QA-002 and QA-005. */
@LargeTest
@RunWith(AndroidJUnit4::class)
class ScheduledProfilePersistenceRuntimeTest {

    @Test
    fun freshStoreAcceptsFirstEntryAndRemovalCancelsItsFallbackWork() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            SharedSetupInstrumentationEntryPoint::class.java,
        )
        val store = entryPoint.scheduledProfileEntryStore()
        val scheduler = entryPoint.scheduledProfileScheduler()
        val workManager = WorkManager.getInstance(context)
        val profileId = "instrumentation-${UUID.randomUUID()}"
        val workName = ScheduledProfileScheduler.fallbackName(profileId)

        assertTrue(
            "The dedicated clean-install run must start without schedule rows",
            runBlocking { store.getEntries().isEmpty() },
        )

        try {
            runBlocking {
                store.upsert(
                    ScheduledProfileEntry(
                        profileId = profileId,
                        isEnabled = false,
                        anchorEpochDay = 20_000,
                        zoneId = "UTC",
                    ),
                )
            }
            assertEquals(profileId, runBlocking { store.getEntries().single().profileId })

            val alarmIntent = Intent(context, ScheduledProfileAlarmReceiver::class.java).apply {
                action = ScheduledProfileScheduler.ACTION_PROFILE_SCHEDULE_ALARM
                putExtra(ScheduledProfileAlarmReceiver.EXTRA_PROFILE_ID, profileId)
            }
            assertNotNull(
                PendingIntent.getBroadcast(
                    context,
                    ScheduledProfileScheduler.requestCodeFor(profileId),
                    alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )

            val fallback = OneTimeWorkRequestBuilder<ScheduledProfileTriggerWorker>()
                .setInitialDelay(1, TimeUnit.DAYS)
                .setInputData(workDataOf(ScheduledProfileTriggerWorker.INPUT_PROFILE_ID to profileId))
                .build()
            runBlocking {
                workManager.enqueueUniqueWork(workName, ExistingWorkPolicy.REPLACE, fallback)
                    .await()
            }
            assertTrue(awaitWorkInfos(workManager, workName).any { it.state == WorkInfo.State.ENQUEUED })

            runBlocking { scheduler.removeEntry(profileId) }

            assertTrue(runBlocking { store.getEntries().none { it.profileId == profileId } })
            assertNull(
                PendingIntent.getBroadcast(
                    context,
                    ScheduledProfileScheduler.requestCodeFor(profileId),
                    alarmIntent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            assertTrue(
                awaitWorkInfos(workManager, workName)
                    .all { it.state == WorkInfo.State.CANCELLED },
            )
        } finally {
            runBlocking { scheduler.removeEntry(profileId) }
        }
    }

    private fun awaitWorkInfos(workManager: WorkManager, workName: String): List<WorkInfo> {
        val liveData = workManager.getWorkInfosForUniqueWorkLiveData(workName)
        val latch = CountDownLatch(1)
        var value: List<WorkInfo>? = null
        val observer = Observer<List<WorkInfo>> { infos ->
            value = infos
            latch.countDown()
        }
        androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync {
            liveData.observeForever(observer)
        }
        try {
            assertTrue("Timed out waiting for WorkManager state", latch.await(10, TimeUnit.SECONDS))
            return requireNotNull(value)
        } finally {
            androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().runOnMainSync {
                liveData.removeObserver(observer)
            }
        }
    }
}
