package com.healthmd.data.billing

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.*
import com.healthmd.domain.repository.BillingRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import kotlin.coroutines.resume

class BillingRepositoryImpl(
    context: Context,
) : BillingRepository {
    companion object {
        // IMPORTANT: Update these to match products in Google Play Console
        private const val PRODUCT_ID_PREMIUM = "health_md_premium_lifetime"
    }

    private val billingClient = BillingClient
        .newBuilder(context)
        .setListener(::onPurchasesUpdated)
        .enablePendingPurchases()
        .build()

    private val _isPurchased = MutableStateFlow(false)
    override val isPurchased: StateFlow<Boolean> = _isPurchased.asStateFlow()

    override fun connect() {
        if (billingClient.isReady) return

        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(billingResult: BillingResult) {
                if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                    Timber.d("Billing client ready")
                    // Query owned purchases
                    queryPurchases()
                } else {
                    Timber.e("Billing setup failed: ${billingResult.debugMessage}")
                }
            }

            override fun onBillingServiceDisconnected() {
                Timber.d("Billing service disconnected")
            }
        })
    }

    override fun disconnect() {
        if (billingClient.isReady) {
            billingClient.endConnection()
        }
    }

    override suspend fun launchPurchaseFlow(activityProvider: Any): Boolean =
        suspendCancellableCoroutine { continuation ->
            val activity = activityProvider as? Activity
                ?: return@suspendCancellableCoroutine continuation.resume(false)

            if (!billingClient.isReady) {
                Timber.e("Billing client not ready")
                continuation.resume(false)
                return@suspendCancellableCoroutine
            }

            // Query product details from Play Store
            queryProductDetailsAndLaunchFlow(activity)
        }

    private fun queryProductDetailsAndLaunchFlow(activity: Activity) {
        // Build the product to query
        val product = QueryProductDetailsParams.Product.newBuilder()
            .setProductId(PRODUCT_ID_PREMIUM)
            .setProductType(BillingClient.ProductType.INAPP)
            .build()

        // Build the params
        val paramsBuilder = QueryProductDetailsParams.newBuilder()

        // Use reflection to set products if direct methods don't exist
        try {
            val method = paramsBuilder.javaClass.getMethod("setProductsList", java.util.List::class.java)
            method.invoke(paramsBuilder, listOf(product))
        } catch (e: NoSuchMethodException) {
            try {
                val method = paramsBuilder.javaClass.getMethod("addProduct", QueryProductDetailsParams.Product::class.java)
                method.invoke(paramsBuilder, product)
            } catch (e2: NoSuchMethodException) {
                Timber.e("Could not find method to set products on QueryProductDetailsParams.Builder")
                return
            }
        }

        val params = paramsBuilder.build()

        billingClient.queryProductDetailsAsync(params) { billingResult, productDetailsList ->
            if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                Timber.e("Product details query failed: ${billingResult.debugMessage}")
                return@queryProductDetailsAsync
            }

            if (productDetailsList.isEmpty()) {
                Timber.e("Product not found in Play Store. Verify product ID matches Play Console.")
                return@queryProductDetailsAsync
            }

            val productDetails = productDetailsList.first()
            launchBillingFlow(activity, productDetails)
        }
    }

    private fun launchBillingFlow(activity: Activity, productDetails: ProductDetails) {
        val billingFlowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(productDetails)
                        .build()
                )
            )
            .build()

        val result = billingClient.launchBillingFlow(activity, billingFlowParams)
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            Timber.e("Purchase flow failed: ${result.debugMessage}")
        } else {
            Timber.d("Purchase flow launched")
        }
    }

    override suspend fun restorePurchases(): Boolean = suspendCancellableCoroutine { continuation ->
        queryPurchasesInternal(
            onSuccess = { continuation.resume(true) },
            onFailure = { continuation.resume(false) }
        )
    }

    private fun queryPurchases() {
        queryPurchasesInternal(
            onSuccess = { Timber.d("Purchases queried successfully") },
            onFailure = { Timber.e("Failed to query purchases") }
        )
    }

    private fun queryPurchasesInternal(onSuccess: () -> Unit, onFailure: () -> Unit) {
        if (!billingClient.isReady) {
            onFailure()
            return
        }

        billingClient.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder()
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        ) { billingResult, purchases ->
            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                // Check if user has the premium product
                val hasPremium = purchases.any { purchase ->
                    purchase.products.contains(PRODUCT_ID_PREMIUM) &&
                    purchase.purchaseState == Purchase.PurchaseState.PURCHASED
                }
                _isPurchased.value = hasPremium
                onSuccess()
            } else {
                Timber.e("Purchase query failed: ${billingResult.debugMessage}")
                onFailure()
            }
        }
    }

    private fun onPurchasesUpdated(billingResult: BillingResult, purchases: List<Purchase>?) {
        when (billingResult.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                purchases?.forEach { purchase ->
                    if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                        !purchase.isAcknowledged
                    ) {
                        // Acknowledge the purchase (REQUIRED by Google)
                        val params = AcknowledgePurchaseParams.newBuilder()
                            .setPurchaseToken(purchase.purchaseToken)
                            .build()

                        billingClient.acknowledgePurchase(params) { ackResult ->
                            if (ackResult.responseCode == BillingClient.BillingResponseCode.OK) {
                                Timber.d("Purchase acknowledged for product: ${purchase.products}")
                                _isPurchased.value = true
                            } else {
                                Timber.e("Failed to acknowledge purchase: ${ackResult.debugMessage}")
                            }
                        }
                    } else if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
                        purchase.isAcknowledged
                    ) {
                        // Already acknowledged
                        Timber.d("Purchase already acknowledged")
                        _isPurchased.value = true
                    }
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                Timber.d("User cancelled purchase")
            }
            else -> {
                Timber.e("Purchase flow error: ${billingResult.debugMessage}")
            }
        }
    }
}
