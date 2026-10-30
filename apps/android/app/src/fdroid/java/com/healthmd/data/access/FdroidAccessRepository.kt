package com.healthmd.data.access

import android.app.Activity
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchaseRepository
import com.healthmd.domain.repository.PurchasePlan
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** F-Droid includes full access and intentionally exposes no purchase simulation or store state. */
class FdroidAccessRepository : EntitlementRepository, PurchaseRepository {
    private val unlocked = MutableStateFlow(true)
    private val idle = MutableStateFlow(false)
    private val noError = MutableStateFlow<BillingError?>(null)
    private val noOffer = MutableStateFlow<PurchaseOffer?>(null)

    override val isUnlocked: StateFlow<Boolean> = unlocked.asStateFlow()
    override val isAvailable: Boolean = false
    override val isPurchasing: StateFlow<Boolean> = idle.asStateFlow()
    override val isRestoring: StateFlow<Boolean> = idle.asStateFlow()
    override val purchaseError: StateFlow<BillingError?> = noError.asStateFlow()
    override val offer: StateFlow<PurchaseOffer?> = noOffer.asStateFlow()
    override val offers: StateFlow<List<PurchaseOffer>> = MutableStateFlow(emptyList())

    override fun refresh() = Unit
    override suspend fun launchPurchase(activity: Activity, plan: PurchasePlan): Boolean = false
    override suspend fun restorePurchase(): Boolean = false
    override fun clearError() = Unit
    override fun debugSetUnlocked(unlocked: Boolean) = Unit
    override fun debugReset() = Unit
}
