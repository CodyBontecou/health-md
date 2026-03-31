package com.healthmd.domain.repository

import kotlinx.coroutines.flow.StateFlow

interface BillingRepository {
    val isPurchased: StateFlow<Boolean>
    suspend fun launchPurchaseFlow(activityProvider: Any): Boolean
    suspend fun restorePurchases(): Boolean
    fun connect()
    fun disconnect()
}
