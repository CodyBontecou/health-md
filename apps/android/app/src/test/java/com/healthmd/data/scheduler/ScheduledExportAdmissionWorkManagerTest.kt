package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import com.google.common.truth.Truth.assertThat
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ScheduledExportAdmissionWorkManagerTest {
    private lateinit var workManager: WorkManager

    @Before
    fun initializeWorkManager() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            Configuration.Builder()
                .setExecutor(SynchronousExecutor())
                .build(),
        )
        workManager = WorkManager.getInstance(context)
    }

    @Test
    fun recoveryKeepWithThePersistedRequestIdRetainsOneUnfinishedRow() {
        val requestId = UUID.randomUUID()
        val uniqueName = "scheduled-admission-recovery"
        fun request() = OneTimeWorkRequestBuilder<ScheduledExportTriggerWorker>()
            .setId(requestId)
            .setInitialDelay(1, TimeUnit.DAYS)
            .build()

        workManager.enqueueUniqueWork(uniqueName, ExistingWorkPolicy.KEEP, request()).result.get()
        workManager.enqueueUniqueWork(uniqueName, ExistingWorkPolicy.KEEP, request()).result.get()

        val rows = workManager.getWorkInfosForUniqueWork(uniqueName).get()
        assertThat(rows).hasSize(1)
        assertThat(rows.single().id).isEqualTo(requestId)
    }
}
