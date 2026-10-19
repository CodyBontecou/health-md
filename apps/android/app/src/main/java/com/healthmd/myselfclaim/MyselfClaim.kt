package com.healthmd.myselfclaim

/** Purchase proof is read only after the owner chooses Verify purchase and continue. */
fun interface MyselfClaimPurchaseSource {
    suspend fun purchaseToken(): String
}

fun interface MyselfClaimVerifier {
    suspend fun verify(purchaseToken: String): String
}

enum class MyselfClaimFailure {
    NO_PURCHASE, STORE_UNAVAILABLE, VERIFICATION_FAILED, BROWSER_UNAVAILABLE,
}

class MyselfClaimException(val failure: MyselfClaimFailure) : Exception()

object MyselfClaimLinks {
    const val URL = "healthmd://myself/claim"

    fun accepts(action: String?, url: String?, purchasesAvailable: Boolean): Boolean =
        purchasesAvailable && action == "android.intent.action.VIEW" && url == URL
}
