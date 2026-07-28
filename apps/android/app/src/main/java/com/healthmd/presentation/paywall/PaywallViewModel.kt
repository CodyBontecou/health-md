package com.healthmd.presentation.paywall

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.BuildConfig
import com.healthmd.domain.repository.BillingRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
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
import javax.inject.Inject

@HiltViewModel
class PaywallViewModel @Inject constructor(
    private val billingRepository: BillingRepository,
    private val settingsRepository: SettingsRepository,
) : ViewModel() {

    /** Whether the user has unlocked premium features */
    val isUnlocked: StateFlow<Boolean> = combine(
        settingsRepository.isPurchased,
        billingRepository.isUnlocked,
    ) { persisted, live -> persisted || live }
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

    /** Formatted price string from Google Play, falling back to the planned $9.99 lifetime price. */
    val priceText: StateFlow<String?> = billingRepository.productDetails
        .map { it?.oneTimePurchaseOfferDetails?.formattedPrice ?: FALLBACK_PRICE_TEXT }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), FALLBACK_PRICE_TEXT)

    /** Whether this is a debug build (for showing debug controls) */
    val isDebugBuild: Boolean = BuildConfig.DEBUG

    // Debug state for simulating unlock
    private val _debugUnlockOverride = MutableStateFlow<Boolean?>(null)
    val debugUnlockOverride: StateFlow<Boolean?> = _debugUnlockOverride.asStateFlow()

    private companion object {
        const val FALLBACK_PRICE_TEXT = "\$9.99"
    }

    init {
        // Connect to billing service and query product when ViewModel is created
        billingRepository.startConnection()
        viewModelScope.launch {
            billingRepository.isUnlocked
                .filter { it }
                .collect { settingsRepository.setPurchased(true) }
        }
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
        val newState = !currentUnlocked
        billingRepository.debugSetUnlocked(newState)
        _debugUnlockOverride.value = newState
        viewModelScope.launch { settingsRepository.setPurchased(newState) }
    }

    fun debugResetPurchaseState() {
        if (!BuildConfig.DEBUG) return
        billingRepository.debugResetPurchaseState()
        _debugUnlockOverride.value = null
        viewModelScope.launch {
            settingsRepository.setPurchased(false)
            settingsRepository.resetFreeExports()
        }
    }

    override fun onCleared() {
        super.onCleared()
        billingRepository.endConnection()
    }
}
