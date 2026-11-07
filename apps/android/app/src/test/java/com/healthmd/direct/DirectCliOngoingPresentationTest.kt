package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class DirectCliOngoingPresentationTest {
    @Test
    fun connectionStatesMapToTheOngoingStages() {
        assertThat(DirectCliOngoingPresentation.stage(DirectCliConnectionState.Idle)).isEqualTo(DirectCliOngoingStage.IDLE)
        assertThat(DirectCliOngoingPresentation.stage(DirectCliConnectionState.Pairing)).isEqualTo(DirectCliOngoingStage.CONNECTING)
        assertThat(DirectCliOngoingPresentation.stage(DirectCliConnectionState.WaitingForCli)).isEqualTo(DirectCliOngoingStage.CONNECTING)
        assertThat(DirectCliOngoingPresentation.stage(DirectCliConnectionState.Connected("laptop")))
            .isEqualTo(DirectCliOngoingStage.CONNECTING)
        assertThat(DirectCliOngoingPresentation.stage(DirectCliConnectionState.Transferring(1, 2)))
            .isEqualTo(DirectCliOngoingStage.TRANSFERRING)
        assertThat(DirectCliOngoingPresentation.stage(DirectCliConnectionState.Failed(DirectCliFailure.EXPORT_FAILED)))
            .isEqualTo(DirectCliOngoingStage.FAILED)
    }

    @Test
    fun onlyAFinishedExportIsCompleted() {
        assertThat(
            DirectCliOngoingPresentation.stage(DirectCliConnectionState.Completed(DirectCliCompletion.ExportCompleted)),
        ).isEqualTo(DirectCliOngoingStage.COMPLETED)
        assertThat(
            DirectCliOngoingPresentation.stage(DirectCliConnectionState.Completed(DirectCliCompletion.ExportCancelled)),
        ).isEqualTo(DirectCliOngoingStage.IDLE)
    }

    @Test
    fun percentIsClampedAndZeroWhileTheTotalIsUnknown() {
        assertThat(DirectCliOngoingPresentation.percent(DirectCliConnectionState.Transferring(57, 100))).isEqualTo(57)
        assertThat(DirectCliOngoingPresentation.percent(DirectCliConnectionState.Transferring(5, 0))).isEqualTo(0)
        assertThat(DirectCliOngoingPresentation.percent(DirectCliConnectionState.Transferring(300, 100))).isEqualTo(100)
    }
}
