package com.healthmd.presentation.paywall

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.BuildConfig
import com.healthmd.domain.repository.BillingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * ViewModel for the PaywallScreen.
 * 
 * Thin wrapper that exposes PurchaseManager flows for Compose consumption
 * and bridges coroutine operations with viewModelScope.
 */
@HiltViewModel
class PaywallViewModel @Inject constructor(
    private val billingRepository: BillingRepository,
) : ViewModel() {

    /** Whether the user has unlocked premium features */
    val isUnlocked: StateFlow<Boolean> = billingRepository.isUnlocked
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    /** Whether a purchase flow is currently in progress */
    val isPurchasing: StateFlow<Boolean> = billingRepository.isPurchasing
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    /** Whether a restore operation is currently in progress */
    val isRestoring: StateFlow<Boolean> = billingRepository.isRestoring
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    /** Current purchase error message, if any */
    val purchaseError: StateFlow<String?> = billingRepository.purchaseError
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    /** Formatted price string from Google Play (e.g., "$4.99") */
    val priceText: StateFlow<String?> = billingRepository.productDetails
        .map { it?.oneTimePurchaseOfferDetails?.formattedPrice }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    /** Whether this is a debug build (for showing debug controls) */
    val isDebugBuild: Boolean = BuildConfig.DEBUG

    // Debug state for simulating unlock
    private val _debugUnlockOverride = MutableStateFlow<Boolean?>(null)
    val debugUnlockOverride: StateFlow<Boolean?> = _debugUnlockOverride.asStateFlow()

    init {
        // Connect to billing service and query product when ViewModel is created
        billingRepository.startConnection()
    }

    /**
     * Launch the Google Play purchase flow.
     * @param activity The activity to use for launching the purchase dialog
     */
    fun launchPurchaseFlow(activity: Activity) {
        viewModelScope.launch {
            try {
                val success = billingRepository.launchPurchase(activity)
                if (!success) {
                    Timber.w("Purchase flow failed to launch")
                }
            } catch (e: Exception) {
                Timber.e(e, "Error launching purchase flow")
            }
        }
    }

    /**
     * Restore previous purchases for users who reinstall or switch devices.
     */
    fun restorePurchases() {
        viewModelScope.launch {
            try {
                val success = billingRepository.restorePurchase()
                if (success) {
                    Timber.d("Purchases restored successfully")
                } else {
                    Timber.w("Failed to restore purchases")
                }
            } catch (e: Exception) {
                Timber.e(e, "Error restoring purchases")
            }
        }
    }

    /**
     * Clear any current error message.
     */
    fun clearError() {
        billingRepository.clearError()
    }

    // Debug methods (only functional in debug builds)

    /**
     * Debug: Toggle simulated unlock state for testing.
     */
    fun debugToggleUnlock() {
        if (!BuildConfig.DEBUG) return
        val currentUnlocked = billingRepository.isUnlocked.value
        billingRepository.debugSetUnlocked(!currentUnlocked)
        _debugUnlockOverride.value = !currentUnlocked
    }

    /**
     * Debug: Reset all purchase state for testing.
     */
    fun debugResetPurchaseState() {
        if (!BuildConfig.DEBUG) return
        billingRepository.debugResetPurchaseState()
        _debugUnlockOverride.value = null
    }

    override fun onCleared() {
        super.onCleared()
        billingRepository.endConnection()
    }
}
