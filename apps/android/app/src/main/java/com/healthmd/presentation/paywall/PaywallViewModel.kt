package com.healthmd.presentation.paywall

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.domain.repository.BillingRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

@HiltViewModel
class PaywallViewModel @Inject constructor(
    private val billingRepository: BillingRepository,
) : ViewModel() {

    val isPurchased: StateFlow<Boolean> = billingRepository.isPurchased
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    init {
        // Connect to billing service when ViewModel is created
        billingRepository.connect()
    }

    fun launchPurchaseFlow(activityProvider: Any) {
        viewModelScope.launch {
            try {
                val success = billingRepository.launchPurchaseFlow(activityProvider)
                if (!success) {
                    Timber.w("Purchase flow failed to launch")
                }
            } catch (e: Exception) {
                Timber.e(e, "Error launching purchase flow")
            }
        }
    }

    fun restorePurchases() {
        viewModelScope.launch {
            try {
                val success = billingRepository.restorePurchases()
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

    override fun onCleared() {
        super.onCleared()
        billingRepository.disconnect()
    }
}
