package com.healthmd.util

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CancellationException
import org.junit.Test
import org.junit.Assert.assertThrows

class CoroutineResultsTest {
    @Test
    fun cancellationIsRethrownInsteadOfBecomingAnOperationalFailure() {
        assertThrows(CancellationException::class.java) {
            runCatchingCancellable<Unit> { throw CancellationException("superseded") }
        }
    }

    @Test
    fun operationalFailureRemainsInspectable() {
        val result = runCatchingCancellable<Unit> { error("provider unavailable") }

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
    }
}
