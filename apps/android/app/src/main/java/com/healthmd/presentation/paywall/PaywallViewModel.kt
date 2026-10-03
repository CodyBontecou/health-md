package com.healthmd.presentation.paywall

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.BuildConfig
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import timber.log.Timber

@HiltViewModel
class PaywallViewModel @Inject constructor(
    private val entitlementRepository: EntitlementRepository,
    private val purchaseRepository: PurchaseRepository,
    private val settingsRepository: SettingsRepository,
    val distributionPolicy: DistributionPolicy,
) : ViewModel() {

    val isUnlocked: StateFlow<Boolean> = combine(
        settingsRepository.isPurchased,
        entitlementRepository.isUnlocked,
    ) { persisted, live -> distributionPolicy.fullAccessIncluded || persisted || live }
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5000),
            distributionPolicy.fullAccessIncluded,
        )

    val isPurchasing: StateFlow<Boolean> = purchaseRepository.isPurchasing
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    val isRestoring: StateFlow<Boolean> = purchaseRepository.isRestoring
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    val purchaseError: StateFlow<BillingError?> = purchaseRepository.purchaseError
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    /** Region-correct price supplied by the active store; null until available. */
    val priceText: StateFlow<String?> = purchaseRepository.offer
        .map { it?.localizedPriceText }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val purchasesAvailable: Boolean =
        distributionPolicy.purchasesAvailable && purchaseRepository.isAvailable
    val isDebugBuild: Boolean = BuildConfig.DEBUG && purchasesAvailable

    private val _debugUnlockOverride = MutableStateFlow<Boolean?>(null)
    val debugUnlockOverride: StateFlow<Boolean?> = _debugUnlockOverride.asStateFlow()

    init {
        purchaseRepository.clearError()
        entitlementRepository.refresh()
        purchaseRepository.refresh()
        // Included F-Droid access must not create or mutate Play purchase persistence.
        if (!distributionPolicy.fullAccessIncluded) {
            viewModelScope.launch {
                entitlementRepository.isUnlocked
                    .filter { it }
                    .collect { settingsRepository.setPurchased(true) }
            }
        }
    }

    fun launchPurchaseFlow(activity: Activity) {
        if (!purchasesAvailable) return
        viewModelScope.launch {
            try {
                if (!purchaseRepository.launchPurchase(activity)) {
                    Timber.w("Purchase flow failed to launch")
                }
            } catch (error: Exception) {
                Timber.e(error, "Error launching purchase flow")
            }
        }
    }

    fun restorePurchases() {
        if (!purchasesAvailable) return
        viewModelScope.launch {
            try {
                if (purchaseRepository.restorePurchase()) {
                    Timber.d("Purchases restored successfully")
                } else {
                    Timber.w("Failed to restore purchases")
                }
            } catch (error: Exception) {
                Timber.e(error, "Error restoring purchases")
            }
        }
    }

    fun clearError() {
        purchaseRepository.clearError()
    }

    fun debugToggleUnlock() {
        if (!BuildConfig.DEBUG || !purchasesAvailable) return
        val newState = !entitlementRepository.isUnlocked.value
        entitlementRepository.debugSetUnlocked(newState)
        _debugUnlockOverride.value = newState
        viewModelScope.launch { settingsRepository.setPurchased(newState) }
    }

    fun debugResetPurchaseState() {
        if (!BuildConfig.DEBUG || !purchasesAvailable) return
        entitlementRepository.debugReset()
        _debugUnlockOverride.value = null
        viewModelScope.launch {
            settingsRepository.setPurchased(false)
            settingsRepository.resetFreeExports()
        }
    }
}
