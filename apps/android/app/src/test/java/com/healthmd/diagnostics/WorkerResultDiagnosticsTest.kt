package com.healthmd.diagnostics

import androidx.work.ListenableWorker
import androidx.work.workDataOf
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class WorkerResultDiagnosticsTest {
    @Test fun publicFactoryResultsKeepTheirOutcome() {
        assertThat(ListenableWorker.Result.success().diagnosticOutcome()).isEqualTo("success")
        assertThat(ListenableWorker.Result.failure().diagnosticOutcome()).isEqualTo("failure")
        assertThat(ListenableWorker.Result.retry().diagnosticOutcome()).isEqualTo("retry")
    }

    @Test fun outputDataDoesNotChangeOrLeakIntoTheOutcome() {
        val data = workDataOf("private_context" to "SYNTHETIC_PRIVATE_SENTINEL")
        for ((result, expected) in listOf(
            ListenableWorker.Result.success(data) to "success",
            ListenableWorker.Result.failure(data) to "failure",
        )) {
            assertThat(result.diagnosticOutcome()).isEqualTo(expected)
            assertThat(result.outputData).isEqualTo(data)
            assertThat(result.diagnosticOutcome()).doesNotContain("SYNTHETIC_PRIVATE_SENTINEL")
        }
    }
}
