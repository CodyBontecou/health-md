package com.healthmd.data.billing

import com.android.billingclient.api.BillingClient

internal object BillingRetryPolicy {
    const val FOREGROUND_MAX_ATTEMPTS = 2
    const val BACKGROUND_MAX_ATTEMPTS = 3

    private const val FOREGROUND_RETRY_DELAY_MS = 500L
    private const val BACKGROUND_RETRY_BASE_DELAY_MS = 1000L

    fun isTransient(responseCode: Int): Boolean = when (responseCode) {
        BillingClient.BillingResponseCode.SERVICE_DISCONNECTED,
        BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE,
        BillingClient.BillingResponseCode.NETWORK_ERROR -> true
        else -> false
    }

    fun foregroundRetryDelayMillis(failedAttempt: Int): Long {
        require(failedAttempt in 1 until FOREGROUND_MAX_ATTEMPTS)
        return FOREGROUND_RETRY_DELAY_MS
    }

    fun backgroundRetryDelayMillis(failedAttempt: Int): Long {
        require(failedAttempt in 1 until BACKGROUND_MAX_ATTEMPTS)
        return BACKGROUND_RETRY_BASE_DELAY_MS * (1L shl (failedAttempt - 1))
    }
}
