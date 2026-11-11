package com.healthmd.direct

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import com.google.common.truth.Truth.assertThat
import io.mockk.clearAllMocks
import io.mockk.every
import io.mockk.mockk
import io.mockk.spyk
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class DirectCliForegroundServiceTest {
    private lateinit var service: DirectCliForegroundService
    private lateinit var notifications: NotificationManager

    @Before
    fun setUp() {
        // Attach a real Android service context without starting Hilt or a live
        // connection. Only the coordinator is replaced; notification code is real.
        service = Robolectric.buildService(DirectCliForegroundService::class.java).get()
        service.coordinator = mockk(relaxed = true)
        notifications = service.getSystemService(NotificationManager::class.java)
        DirectCliForegroundService.createNotificationChannel(service)
    }

    @After
    fun tearDown() {
        service.onDestroy()
        notifications.cancelAll()
        clearAllMocks()
    }

    @Test
    fun disconnectCannotBeUndoneByAQueuedConnectedNotification() {
        updateNotification(DirectCliConnectionState.Connected("Synthetic listener"))
        assertThat(notifications.activeNotifications).hasLength(1)

        service.onStartCommand(
            Intent(service, DirectCliForegroundService::class.java)
                .setAction("com.healthmd.direct.STOP"),
            0,
            1,
        )
        assertThat(notifications.activeNotifications).isEmpty()

        // collectLatest can already hold this earlier state when ACTION_STOP
        // cancels the connection. It must not resurrect the stopped notification.
        updateNotification(DirectCliConnectionState.Connected("Synthetic listener"))
        assertThat(notifications.activeNotifications).isEmpty()
    }

    @Test
    fun forgettingTheListenerAlsoKeepsQueuedNotificationsRemoved() {
        updateNotification(DirectCliConnectionState.Connected("Synthetic listener"))
        service.onStartCommand(Intent(service, DirectCliForegroundService::class.java)
            .setAction("com.healthmd.direct.FORGET"), 0, 1)
        assertThat(notifications.activeNotifications).isEmpty()
        updateNotification(DirectCliConnectionState.WaitingForCli)
        assertThat(notifications.activeNotifications).isEmpty()
    }

    @Test
    fun normalCompletionAndFailureNotificationsRemainVisible() {
        updateNotification(DirectCliConnectionState.Completed(DirectCliCompletion.SessionFinished))
        assertThat(notifications.activeNotifications.single().notification.extras
            .getCharSequence(Notification.EXTRA_TEXT)?.toString())
            .isEqualTo(service.getString(com.healthmd.R.string.direct_cli_status_session_finished))
        updateNotification(DirectCliConnectionState.Failed(DirectCliFailure.CONNECTION_FAILED))
        assertThat(notifications.activeNotifications.single().notification.extras
            .getCharSequence(Notification.EXTRA_TEXT)?.toString())
            .isEqualTo(service.getString(com.healthmd.R.string.direct_cli_failure_connection))
    }

    @Test
    fun disconnectRemovesAnAlreadyInFlightNotificationPublication() {
        val manager = spyk(notifications)
        val enteredPublication = CountDownLatch(1)
        val releasePublication = CountDownLatch(1)
        val disconnectReached = CountDownLatch(1)
        val disconnectFinished = CountDownLatch(1)
        val failure = AtomicReference<Throwable?>()
        val coordinator = service.coordinator
        service = spyk(service)
        every { service.getSystemService(NotificationManager::class.java) } returns manager
        every { coordinator.reportDisconnected() } answers { disconnectReached.countDown(); Unit }
        every { manager.notify(any<Int>(), any<Notification>()) } answers {
            enteredPublication.countDown()
            check(releasePublication.await(5, TimeUnit.SECONDS))
            callOriginal()
        }
        val publisher = thread(name = "synthetic-notification-publisher") {
            runCatching { updateNotification(DirectCliConnectionState.Connected("Synthetic listener")) }
                .exceptionOrNull()?.let(failure::set)
        }
        var stopper: Thread? = null
        try {
            check(enteredPublication.await(5, TimeUnit.SECONDS))
            stopper = thread(name = "synthetic-notification-disconnect") {
                try {
                    service.onStartCommand(Intent(service, DirectCliForegroundService::class.java)
                        .setAction("com.healthmd.direct.STOP"), 0, 1)
                } catch (error: Throwable) {
                    failure.set(error)
                } finally {
                    disconnectFinished.countDown()
                }
            }
            check(disconnectReached.await(5, TimeUnit.SECONDS))
            // The old implementation finishes removal while publication is
            // still held. A serialized implementation waits for that publisher.
            disconnectFinished.await(1, TimeUnit.SECONDS)
        } finally {
            releasePublication.countDown()
            publisher.join(5_000)
            stopper?.join(5_000)
        }
        assertThat(publisher.isAlive).isFalse()
        assertThat(stopper?.isAlive).isFalse()
        failure.get()?.let { throw AssertionError("Synthetic notification worker failed", it) }
        assertThat(notifications.activeNotifications).isEmpty()
    }

    private fun updateNotification(state: DirectCliConnectionState) {
        DirectCliForegroundService::class.java
            .getDeclaredMethod("updateNotification", DirectCliConnectionState::class.java)
            .apply { isAccessible = true }
            .invoke(service, state)
    }
}
