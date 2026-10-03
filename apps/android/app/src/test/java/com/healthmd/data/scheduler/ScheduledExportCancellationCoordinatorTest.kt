package com.healthmd.data.scheduler

import com.google.common.truth.Truth.assertThat
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test

class ScheduledExportCancellationCoordinatorTest {
    @Before
    fun setUp() {
        ScheduledExportCancellationCoordinator.resetForTests()
    }

    @After
    fun tearDown() {
        ScheduledExportCancellationCoordinator.resetForTests()
    }

    @Test
    fun `request cancels only the exact active exporter child`() = runTest {
        val target = UUID.randomUUID()
        val foreign = UUID.randomUUID()
        val started = CompletableDeferred<Unit>()
        val outcome = async {
            runCatching {
                ScheduledExportCancellationCoordinator.run(target) {
                    started.complete(Unit)
                    awaitCancellation()
                }
            }
        }

        started.await()
        assertThat(ScheduledExportCancellationCoordinator.requestCancellation(foreign)).isFalse()
        assertThat(ScheduledExportCancellationCoordinator.requestCancellation(target)).isTrue()
        assertThat(outcome.await().exceptionOrNull())
            .isInstanceOf(kotlinx.coroutines.CancellationException::class.java)
    }

    @Test
    fun `cooperative exporter result remains available after its child job is cancelled`() = runTest {
        val operationID = UUID.randomUUID()
        val started = CompletableDeferred<Unit>()
        val outcome = async {
            ScheduledExportCancellationCoordinator.run(operationID) {
                try {
                    started.complete(Unit)
                    awaitCancellation()
                } catch (_: kotlinx.coroutines.CancellationException) {
                    "cancelled-result"
                }
            }
        }

        started.await()
        assertThat(ScheduledExportCancellationCoordinator.requestCancellation(operationID)).isTrue()
        assertThat(outcome.await()).isEqualTo("cancelled-result")
    }

    @Test
    fun `parent cancellation propagates even when exporter constructs a cooperative result`() = runTest {
        val operationID = UUID.randomUUID()
        val started = CompletableDeferred<Unit>()
        val parent = async {
            ScheduledExportCancellationCoordinator.run(operationID) {
                try {
                    started.complete(Unit)
                    awaitCancellation()
                } catch (_: kotlinx.coroutines.CancellationException) {
                    "must-not-escape-parent-cancellation"
                }
            }
        }

        started.await()
        parent.cancel()
        val outcome = runCatching { parent.await() }

        assertThat(outcome.exceptionOrNull())
            .isInstanceOf(kotlinx.coroutines.CancellationException::class.java)
    }

    @Test
    fun `request racing exporter registration is consumed before provider work starts`() = runTest {
        val operationID = UUID.randomUUID()
        var invoked = false
        ScheduledExportCancellationCoordinator.prepare(operationID)

        assertThat(
            ScheduledExportCancellationCoordinator.requestCancellation(operationID),
        ).isTrue()
        val outcome = runCatching {
            ScheduledExportCancellationCoordinator.run(operationID) {
                invoked = true
                "completed"
            }
        }

        assertThat(invoked).isFalse()
        assertThat(outcome.exceptionOrNull())
            .isInstanceOf(kotlinx.coroutines.CancellationException::class.java)
    }

    @Test
    fun `concurrent operations receive distinct stable notification ids`() {
        val first = UUID.randomUUID()
        val second = UUID.randomUUID()

        val firstID = ScheduledExportCancellationCoordinator.foregroundNotificationID(first)
        val secondID = ScheduledExportCancellationCoordinator.foregroundNotificationID(second)

        assertThat(firstID).isNotEqualTo(secondID)
        assertThat(ScheduledExportCancellationCoordinator.foregroundNotificationID(first))
            .isEqualTo(firstID)
    }

    @Test
    fun `finished and stale operation ids cannot cancel newer work`() {
        val finished = UUID.randomUUID()
        ScheduledExportCancellationCoordinator.prepare(finished)
        ScheduledExportCancellationCoordinator.finish(finished)

        assertThat(ScheduledExportCancellationCoordinator.requestCancellation(finished)).isFalse()
        assertThat(ScheduledExportCancellationCoordinator.requestCancellation(UUID.randomUUID())).isFalse()
    }
}
