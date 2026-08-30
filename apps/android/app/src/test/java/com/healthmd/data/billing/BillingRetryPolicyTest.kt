package com.healthmd.data.billing

import com.android.billingclient.api.BillingClient
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test

class BillingRetryPolicyTest {

    @Test
    fun retriesOnlyTransientServiceAndNetworkFailures() {
        val transientCodes = listOf(
            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED,
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE,
            BillingClient.BillingResponseCode.NETWORK_ERROR,
        )
        val terminalCodes = listOf(
            BillingClient.BillingResponseCode.OK,
            BillingClient.BillingResponseCode.USER_CANCELED,
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED,
            BillingClient.BillingResponseCode.DEVELOPER_ERROR,
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE,
        )

        transientCodes.forEach { responseCode ->
            assertThat(BillingRetryPolicy.isTransient(responseCode)).isTrue()
        }
        terminalCodes.forEach { responseCode ->
            assertThat(BillingRetryPolicy.isTransient(responseCode)).isFalse()
        }
    }

    @Test
    fun stopsOnSuccessAfterOneRetry() = runTest {
        val results = ArrayDeque(listOf("retry", "success"))
        val delays = mutableListOf<Long>()
        var invocations = 0

        val result = executeBoundedRetry(
            maxAttempts = BillingRetryPolicy.FOREGROUND_MAX_ATTEMPTS,
            retryDelayMillis = BillingRetryPolicy::foregroundRetryDelayMillis,
            shouldRetry = { it == "retry" },
            sleep = { delays += it },
        ) {
            invocations++
            results.removeFirst()
        }

        assertThat(result).isEqualTo("success")
        assertThat(invocations).isEqualTo(2)
        assertThat(delays).containsExactly(500L).inOrder()
    }

    @Test
    fun terminalResultDoesNotRetry() = runTest {
        val delays = mutableListOf<Long>()
        var invocations = 0

        val result = executeBoundedRetry(
            maxAttempts = BillingRetryPolicy.BACKGROUND_MAX_ATTEMPTS,
            retryDelayMillis = BillingRetryPolicy::backgroundRetryDelayMillis,
            shouldRetry = { false },
            sleep = { delays += it },
        ) {
            invocations++
            "terminal"
        }

        assertThat(result).isEqualTo("terminal")
        assertThat(invocations).isEqualTo(1)
        assertThat(delays).isEmpty()
    }

    @Test
    fun exhaustsMaximumAttemptsWithConfiguredDelaySequence() = runTest {
        val delays = mutableListOf<Long>()
        var invocations = 0

        val result = executeBoundedRetry(
            maxAttempts = BillingRetryPolicy.BACKGROUND_MAX_ATTEMPTS,
            retryDelayMillis = BillingRetryPolicy::backgroundRetryDelayMillis,
            shouldRetry = { true },
            sleep = { delays += it },
        ) {
            ++invocations
        }

        assertThat(result).isEqualTo(3)
        assertThat(invocations).isEqualTo(3)
        assertThat(delays).containsExactly(1_000L, 2_000L).inOrder()
    }

    @Test
    fun cancellationFromDelayPropagatesWithoutAnotherInvocation() = runTest {
        var invocations = 0
        var caught: CancellationException? = null

        try {
            executeBoundedRetry(
                maxAttempts = BillingRetryPolicy.FOREGROUND_MAX_ATTEMPTS,
                retryDelayMillis = BillingRetryPolicy::foregroundRetryDelayMillis,
                shouldRetry = { true },
                sleep = { throw CancellationException("cancel retry") },
            ) {
                ++invocations
            }
        } catch (error: CancellationException) {
            caught = error
        }

        assertThat(caught).isNotNull()
        assertThat(caught?.message).isEqualTo("cancel retry")
        assertThat(invocations).isEqualTo(1)
    }
}
