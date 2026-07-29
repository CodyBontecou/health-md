package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import org.junit.Assert.assertThrows
import org.junit.Test

class ExportCommitBarrierTest {
    @Test
    fun validTransitionsAreOneWayAndTerminal() {
        val barrier = ExportCommitBarrier()

        assertThat(barrier.state).isEqualTo(ExportCommitState.planned)
        assertThat(barrier.markMaterialized()).isEqualTo(ExportCommitState.materialized)
        assertThat(barrier.markCommitting()).isEqualTo(ExportCommitState.committing)
        assertThat(barrier.markCompleted()).isEqualTo(ExportCommitState.completed)
        assertThat(barrier.markCompleted()).isEqualTo(ExportCommitState.completed)

        assertThrows(ExportCommitBarrierException::class.java) { barrier.markFailed() }
        assertThrows(ExportCommitBarrierException::class.java) { barrier.markMaterialized() }
    }

    @Test
    fun engineSwitchAndRerenderAreForbiddenFromCommittingOnward() {
        val barrier = ExportCommitBarrier()
        var guardedActions = 0
        barrier.withEngineSwitch { guardedActions += 1 }
        barrier.markMaterialized()
        barrier.withRerender { guardedActions += 1 }
        assertThat(guardedActions).isEqualTo(2)

        barrier.markCommitting()
        assertThrows(ExportCommitBarrierException::class.java) {
            barrier.withEngineSwitch { guardedActions += 1 }
        }
        assertThrows(ExportCommitBarrierException::class.java) {
            barrier.withRerender { guardedActions += 1 }
        }
        assertThat(guardedActions).isEqualTo(2)

        barrier.markFailed()
        assertThrows(ExportCommitBarrierException::class.java) {
            barrier.requireRerenderAllowed()
        }
    }

    @Test
    fun restoredCommittingStateStillClosesThePlanMutationGate() {
        val barrier = ExportCommitBarrier(ExportCommitState.committing)

        assertThrows(ExportCommitBarrierException::class.java) {
            barrier.withEngineSwitch { error("must not run") }
        }
        assertThrows(ExportCommitBarrierException::class.java) {
            barrier.withRerender { error("must not run") }
        }
        assertThat(barrier.markCompleted()).isEqualTo(ExportCommitState.completed)
    }

    @Test
    fun skippedAndBackwardTransitionsFailClosed() {
        val barrier = ExportCommitBarrier()
        assertThrows(ExportCommitBarrierException::class.java) { barrier.markCommitting() }
        barrier.markMaterialized()
        assertThrows(ExportCommitBarrierException::class.java) {
            barrier.transition(ExportCommitState.planned)
        }
        barrier.markFailed()
        assertThrows(ExportCommitBarrierException::class.java) { barrier.markCommitting() }
    }
}
