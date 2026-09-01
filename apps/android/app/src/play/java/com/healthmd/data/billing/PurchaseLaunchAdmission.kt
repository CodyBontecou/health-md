package com.healthmd.data.billing

import kotlinx.coroutines.flow.MutableStateFlow

internal suspend fun <T> withPurchaseLaunchAdmission(
    isPurchasing: MutableStateFlow<Boolean>,
    block: suspend (markFlowLaunched: () -> Unit) -> T,
): T? {
    if (!isPurchasing.compareAndSet(expect = false, update = true)) return null

    var flowLaunched = false
    return try {
        block { flowLaunched = true }
    } finally {
        if (!flowLaunched) isPurchasing.value = false
    }
}
