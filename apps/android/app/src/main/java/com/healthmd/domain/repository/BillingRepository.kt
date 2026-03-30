package com.healthmd.domain.repository

import kotlinx.coroutines.flow.Flow

interface BillingRepository {
    val isPurchased: Flow<Boolean>
    suspend fun launchPurchaseFlow(activityProvider: Any): Boolean
    suspend fun restorePurchases(): Boolean
    fun connect()
    fun disconnect()
}
