package com.healthmd.data.scheduler

import android.app.ForegroundServiceStartNotAllowedException
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.test.core.app.ApplicationProvider
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.ForegroundUpdater
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.TestListenableWorkerBuilder
import com.google.common.truth.Truth.assertThat
import com.google.common.util.concurrent.Futures
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ScheduledExportForegroundTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val notifications = shadowOf(context.getSystemService(NotificationManager::class.java))
    private val info = ForegroundInfo(29871, NotificationCompat.Builder(context, "exports")
        .setSmallIcon(android.R.drawable.ic_menu_save).setContentTitle("Exporting")
        .setOngoing(true).build())

    @Test
    fun normalPromotionDoesNotPostAnIndependentNotification() = runTest {
        val worker = worker(null)
        assertThat(worker.withScheduledExportForeground(info) {
            assertThat(notifications.getNotification(info.notificationId)).isNull()
            42
        }).isEqualTo(42)
        assertThat(notifications.getNotification(info.notificationId)).isNull()
    }

    @Test
    fun deniedPromotionKeepsProgressVisibleAndClearsItAfterSuccess() = runTest {
        val worker = worker(ForegroundServiceStartNotAllowedException("denied"))
        assertThat(worker.withScheduledExportForeground(info) {
            assertThat(notifications.getNotification(info.notificationId)).isEqualTo(info.notification)
            42
        }).isEqualTo(42)
        assertThat(notifications.getNotification(info.notificationId)).isNull()
    }

    @Test
    fun deniedPromotionClearsItsNotificationWhenExportThrows() = runTest {
        val worker = worker(ForegroundServiceStartNotAllowedException("denied"))
        val failure = IllegalStateException("export failed")
        val result = runCatching {
            worker.withScheduledExportForeground(info) {
                assertThat(notifications.getNotification(info.notificationId)).isNotNull()
                throw failure
            }
        }
        assertThat(result.exceptionOrNull()).isSameInstanceAs(failure)
        assertThat(notifications.getNotification(info.notificationId)).isNull()
    }

    @Test
    fun cancellationAndUnrelatedPromotionFailuresNeverEnterExport() = runTest {
        for (failure in listOf(CancellationException("stopped"), SecurityException("wrong service type"))) {
            var entered = false
            val result = runCatching {
                worker(failure).withScheduledExportForeground(info) { entered = true }
            }
            assertThat(result.exceptionOrNull()).isSameInstanceAs(failure)
            assertThat(entered).isFalse()
            assertThat(notifications.getNotification(info.notificationId)).isNull()
        }
    }

    private fun worker(failure: Throwable?): CoroutineWorker =
        TestListenableWorkerBuilder<ProbeWorker>(context)
            .setWorkerFactory(object : WorkerFactory() {
                override fun createWorker(context: Context, name: String, params: WorkerParameters): ListenableWorker =
                    ProbeWorker(context, params)
            })
            .setForegroundUpdater(ForegroundUpdater { _, _, _ ->
                if (failure == null) Futures.immediateVoidFuture()
                else Futures.immediateFailedFuture<Void>(failure)
            }).build()

    class ProbeWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
        override suspend fun doWork(): Result = Result.success()
    }
}
