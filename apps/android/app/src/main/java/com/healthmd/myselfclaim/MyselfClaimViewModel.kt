package com.healthmd.myselfclaim

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class MyselfClaimState(
    val busy: Boolean = false,
    val awaitingUser: Boolean = false,
    val failure: MyselfClaimFailure? = null,
)

@HiltViewModel
class MyselfClaimViewModel @Inject constructor(
    private val purchases: MyselfClaimPurchaseSource,
    private val verifier: MyselfClaimVerifier,
) : ViewModel() {
    private val mutableState = MutableStateFlow(MyselfClaimState())
    val state = mutableState.asStateFlow()
    private var request: Job? = null

    // Tokens and browser tickets are never written to saved state, preferences or logs.
    fun verify(openBrowser: (String) -> Unit) {
        if (request?.isActive == true) return
        mutableState.value = MyselfClaimState(busy = true)
        request = viewModelScope.launch {
            try {
                val url = verifier.verify(purchases.purchaseToken())
                try {
                    openBrowser(url)
                } catch (_: Exception) {
                    throw MyselfClaimException(MyselfClaimFailure.BROWSER_UNAVAILABLE)
                }
                mutableState.value = MyselfClaimState(awaitingUser = true)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                mutableState.value = MyselfClaimState(failure =
                    (error as? MyselfClaimException)?.failure ?: MyselfClaimFailure.VERIFICATION_FAILED)
            }
        }
    }

    fun cancel() {
        request?.cancel()
        mutableState.value = MyselfClaimState()
    }
}
