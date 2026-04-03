package com.healthmd.data.billing

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import com.android.billingclient.api.*
import com.healthmd.BuildConfig
import com.healthmd.domain.repository.BillingRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import timber.log.Timber
import kotlin.coroutines.resume

/**
 * PurchaseManager implementation for Google Play Billing.
 * 
 * Architecture:
 * - Singleton (Hilt-injected)
 * - Uses BillingClient v7.1.1 with pending purchases enabled
 * - Caches unlock state in SharedPreferences (healthmd_purchase_prefs)
 * - Supports Auto Backup for purchase state persistence
 * 
 * Product: health_md_premium_lifetime (INAPP, one-time purchase, $4.99)
 */
class BillingRepositoryImpl(
    private val context: Context,
) : BillingRepository, PurchasesUpdatedListener {

    companion object {
        private const val PRODUCT_ID = "health_md_premium_lifetime"
        private const val PREFS_NAME = "healthmd_purchase_prefs"
        private const val KEY_IS_UNLOCKED = "is_unlocked"
        private const val KEY_DEBUG_OVERRIDE = "debug_unlock_override"
        private const val RECONNECT_DELAY_MS = 1000L
        private const val MAX_RECONNECT_ATTEMPTS = 3
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    
    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val billingClient: BillingClient = BillingClient.newBuilder(context)
        .setListener(this)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder()
                .enableOneTimeProducts()
                .build()
        )
        .build()

    // StateFlows
    private val _isUnlocked = MutableStateFlow(loadCachedUnlockState())
    override val isUnlocked: StateFlow<Boolean> = _isUnlocked.asStateFlow()

    private val _isPurchasing = MutableStateFlow(false)
    override val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _isRestoring = MutableStateFlow(false)
    override val isRestoring: StateFlow<Boolean> = _isRestoring.asStateFlow()

    private val _purchaseError = MutableStateFlow<String?>(null)
    override val purchaseError: StateFlow<String?> = _purchaseError.asStateFlow()

    private val _productDetails = MutableStateFlow<ProductDetails?>(null)
    override val productDetails: StateFlow<ProductDetails?> = _productDetails.asStateFlow()

    private var reconnectAttempts = 0
    private var isConnecting = false

    // Load cached unlock state (supports offline usage)
    private fun loadCachedUnlockState(): Boolean {
        // Check debug override first (debug builds only)
        if (BuildConfig.DEBUG && prefs.contains(KEY_DEBUG_OVERRIDE)) {
            return prefs.getBoolean(KEY_DEBUG_OVERRIDE, false)
        }
        return prefs.getBoolean(KEY_IS_UNLOCKED, false)
    }

    // Save unlock state to cache
    private fun saveUnlockState(unlocked: Boolean) {
        prefs.edit().putBoolean(KEY_IS_UNLOCKED, unlocked).apply()
        _isUnlocked.value = unlocked
        Timber.d("Unlock state saved: $unlocked")
    }

    override fun startConnection() {
        if (billingClient.isReady || isConnecting) {
            Timber.d("Billing client already ready or connecting")
            return
        }

        isConnecting = true
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                isConnecting = false
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    Timber.d("Billing client connected successfully")
                    reconnectAttempts = 0
                    
                    // Query product details and existing purchases
                    scope.launch {
                        queryProduct()
                        refreshPurchaseStatus()
                    }
                } else {
                    Timber.e("Billing setup failed: ${result.debugMessage}")
                    // Silent fallback - use cached state
                    handleConnectionFailure()
                }
            }

            override fun onBillingServiceDisconnected() {
                isConnecting = false
                Timber.d("Billing service disconnected")
                // Attempt to reconnect
                handleConnectionFailure()
            }
        })
    }

    private fun handleConnectionFailure() {
        // Use cached state for offline support
        _isUnlocked.value = loadCachedUnlockState()
        
        // Attempt reconnection with backoff
        if (reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
            reconnectAttempts++
            scope.launch {
                delay(RECONNECT_DELAY_MS * reconnectAttempts)
                startConnection()
            }
        }
    }

    override suspend fun queryProduct() {
        if (!billingClient.isReady) {
            Timber.w("Cannot query product - billing client not ready")
            return
        }

        val productList = listOf(
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(PRODUCT_ID)
                .setProductType(BillingClient.ProductType.INAPP)
                .build()
        )

        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(productList)
            .build()

        val result = billingClient.queryProductDetails(params)
        
        if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
            val details = result.productDetailsList?.firstOrNull()
            _productDetails.value = details
            if (details != null) {
                Timber.d("Product loaded: ${details.productId}, price: ${details.oneTimePurchaseOfferDetails?.formattedPrice}")
            } else {
                Timber.w("Product not found in Play Store: $PRODUCT_ID")
            }
        } else {
            Timber.e("Failed to query product: ${result.billingResult.debugMessage}")
        }
    }

    override suspend fun launchPurchase(activity: Activity): Boolean {
        if (_isPurchasing.value) {
            Timber.w("Purchase already in progress")
            return false
        }

        val details = _productDetails.value
        if (details == null) {
            // Try to query product first
            queryProduct()
            if (_productDetails.value == null) {
                _purchaseError.value = "Unable to load product information. Please try again."
                return false
            }
        }

        if (!billingClient.isReady) {
            _purchaseError.value = "Billing service unavailable. Please try again."
            return false
        }

        _isPurchasing.value = true
        _purchaseError.value = null

        val productDetailsParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(_productDetails.value!!)
            .build()

        val billingFlowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productDetailsParams))
            .build()

        val result = billingClient.launchBillingFlow(activity, billingFlowParams)
        
        if (result.responseCode != BillingClient.BillingResponseCode.OK) {
            _isPurchasing.value = false
            _purchaseError.value = "Failed to start purchase: ${result.debugMessage}"
            Timber.e("Launch billing flow failed: ${result.debugMessage}")
            return false
        }

        Timber.d("Purchase flow launched successfully")
        return true
    }

    override suspend fun refreshPurchaseStatus() {
        if (!billingClient.isReady) {
            Timber.w("Cannot refresh purchases - billing client not ready")
            return
        }

        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.INAPP)
            .build()

        val result = billingClient.queryPurchasesAsync(params)
        
        if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
            processPurchases(result.purchasesList)
        } else {
            Timber.e("Failed to query purchases: ${result.billingResult.debugMessage}")
        }
    }

    override suspend fun restorePurchase(): Boolean = suspendCancellableCoroutine { continuation ->
        if (_isRestoring.value) {
            continuation.resume(false)
            return@suspendCancellableCoroutine
        }

        if (!billingClient.isReady) {
            _purchaseError.value = "Billing service unavailable. Please try again."
            continuation.resume(false)
            return@suspendCancellableCoroutine
        }

        _isRestoring.value = true
        _purchaseError.value = null

        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.INAPP)
            .build()

        billingClient.queryPurchasesAsync(params) { billingResult, purchases ->
            _isRestoring.value = false
            
            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                val hasPremium = purchases.any { purchase ->
                    purchase.products.contains(PRODUCT_ID) &&
                    purchase.purchaseState == Purchase.PurchaseState.PURCHASED
                }
                
                if (hasPremium) {
                    saveUnlockState(true)
                    // Acknowledge any unacknowledged purchases
                    scope.launch {
                        purchases.filter { 
                            it.products.contains(PRODUCT_ID) && 
                            it.purchaseState == Purchase.PurchaseState.PURCHASED &&
                            !it.isAcknowledged 
                        }.forEach { purchase ->
                            acknowledgePurchase(purchase.purchaseToken)
                        }
                    }
                    Timber.d("Purchase restored successfully")
                    continuation.resume(true)
                } else {
                    _purchaseError.value = "No previous purchase found"
                    Timber.d("No purchases to restore")
                    continuation.resume(false)
                }
            } else {
                _purchaseError.value = "Failed to restore: ${billingResult.debugMessage}"
                Timber.e("Restore failed: ${billingResult.debugMessage}")
                continuation.resume(false)
            }
        }
    }

    override suspend fun acknowledgePurchase(purchaseToken: String) {
        val params = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchaseToken)
            .build()

        val result = billingClient.acknowledgePurchase(params)
        
        if (result.responseCode == BillingClient.BillingResponseCode.OK) {
            Timber.d("Purchase acknowledged successfully")
        } else {
            Timber.e("Failed to acknowledge purchase: ${result.debugMessage}")
        }
    }

    override fun clearError() {
        _purchaseError.value = null
    }

    override fun endConnection() {
        if (billingClient.isReady) {
            billingClient.endConnection()
            Timber.d("Billing connection ended")
        }
    }

    // PurchasesUpdatedListener implementation
    override fun onPurchasesUpdated(billingResult: BillingResult, purchases: List<Purchase>?) {
        _isPurchasing.value = false

        when (billingResult.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                Timber.d("Purchases updated: ${purchases?.size ?: 0} purchases")
                scope.launch {
                    processPurchases(purchases ?: emptyList())
                }
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> {
                // User cancelled - no-op, no error message
                Timber.d("User cancelled purchase")
            }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                // User already owns the item - unlock it
                Timber.d("Item already owned, unlocking")
                saveUnlockState(true)
            }
            else -> {
                _purchaseError.value = "Purchase failed: ${billingResult.debugMessage}"
                Timber.e("Purchase error: ${billingResult.responseCode} - ${billingResult.debugMessage}")
            }
        }
    }

    private suspend fun processPurchases(purchases: List<Purchase>) {
        var hasValidPurchase = false

        for (purchase in purchases) {
            if (!purchase.products.contains(PRODUCT_ID)) continue

            when (purchase.purchaseState) {
                Purchase.PurchaseState.PURCHASED -> {
                    hasValidPurchase = true
                    
                    // Acknowledge if not already acknowledged (required within 3 days)
                    if (!purchase.isAcknowledged) {
                        acknowledgePurchase(purchase.purchaseToken)
                    }
                }
                Purchase.PurchaseState.PENDING -> {
                    // Pending purchase - will be processed later
                    Timber.d("Purchase pending: ${purchase.orderId}")
                }
                Purchase.PurchaseState.UNSPECIFIED_STATE -> {
                    Timber.w("Purchase in unspecified state: ${purchase.orderId}")
                }
            }
        }

        if (hasValidPurchase) {
            saveUnlockState(true)
        }
    }

    // Debug methods (only functional in debug builds)
    override fun debugSetUnlocked(unlocked: Boolean) {
        if (!BuildConfig.DEBUG) {
            Timber.w("Debug methods only available in debug builds")
            return
        }
        prefs.edit().putBoolean(KEY_DEBUG_OVERRIDE, unlocked).apply()
        _isUnlocked.value = unlocked
        Timber.d("Debug: Set unlock state to $unlocked")
    }

    override fun debugResetPurchaseState() {
        if (!BuildConfig.DEBUG) {
            Timber.w("Debug methods only available in debug builds")
            return
        }
        prefs.edit()
            .remove(KEY_IS_UNLOCKED)
            .remove(KEY_DEBUG_OVERRIDE)
            .apply()
        _isUnlocked.value = false
        _productDetails.value = null
        _purchaseError.value = null
        Timber.d("Debug: Reset all purchase state")
    }
}
