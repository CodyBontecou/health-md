package com.healthmd.data.billing

import android.app.Activity
import android.content.Context
import android.content.SharedPreferences
import com.android.billingclient.api.*
import com.healthmd.myselfclaim.MyselfClaimException
import com.healthmd.myselfclaim.MyselfClaimFailure
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import com.healthmd.BuildConfig
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.billing.FreemiumPolicy
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchaseRepository
import com.healthmd.domain.repository.PurchasePlan
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber

/**
 * PurchaseManager implementation for Google Play Billing.
 *
 * Architecture:
 * - Application-scoped singleton (Hilt-injected)
 * - Owns one process-lifetime BillingClient; screen ViewModels must not close it
 * - Uses BillingClient v8.3.0 with pending purchases and automatic reconnection enabled
 * - Caches unlock state in SharedPreferences (healthmd_purchase_prefs)
 * - Supports Auto Backup for purchase state persistence
 *
 * Individual weekly/yearly subscriptions and the existing lifetime INAPP.
 * Play Console owns prices and seven-day trial eligibility. Subscription
 * access is re-queried, never persisted as a permanent lifetime grant.
 */
class BillingRepositoryImpl(
    private val context: Context,
) : EntitlementRepository, PurchaseRepository, PurchasesUpdatedListener {

    companion object {
        private const val PRODUCT_ID = "health_md_premium_lifetime"
        private const val PREFS_NAME = "healthmd_purchase_prefs"
        private const val KEY_IS_UNLOCKED = "is_unlocked"
        private const val KEY_DEBUG_OVERRIDE = "debug_unlock_override"
        private const val KEY_LEGACY_UNLOCK_GRANTED = "legacy_unlock_granted"
        private const val INITIAL_CONNECTION_RETRY_DELAY_MS = 1000L
        private const val MAX_INITIAL_CONNECTION_RETRY_ATTEMPTS = 3
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val prefs: SharedPreferences by lazy {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    private val billingClient: BillingClient = BillingClient.newBuilder(context)
        .setListener(this)
        .enableAutoServiceReconnection()
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder()
                .enableOneTimeProducts()
                .build()
        )
        .build()

    private val _isUnlocked = MutableStateFlow(loadCachedUnlockState())
    override val isUnlocked: StateFlow<Boolean> = _isUnlocked.asStateFlow()
    private val _isPermanentlyUnlocked = MutableStateFlow(loadCachedUnlockState())
    override val isPermanentlyUnlocked = _isPermanentlyUnlocked.asStateFlow()

    override val isAvailable: Boolean = true

    private val _isPurchasing = MutableStateFlow(false)
    override val isPurchasing: StateFlow<Boolean> = _isPurchasing.asStateFlow()

    private val _isRestoring = MutableStateFlow(false)
    override val isRestoring: StateFlow<Boolean> = _isRestoring.asStateFlow()

    private val _purchaseError = MutableStateFlow<BillingError?>(null)
    override val purchaseError: StateFlow<BillingError?> = _purchaseError.asStateFlow()

    private val _productDetails = MutableStateFlow<ProductDetails?>(null)
    private val _offer = MutableStateFlow<PurchaseOffer?>(null)
    override val offer: StateFlow<PurchaseOffer?> = _offer.asStateFlow()
    private val _offers = MutableStateFlow<List<PurchaseOffer>>(emptyList())
    override val offers = _offers.asStateFlow()
    private var detailsByID: Map<String, ProductDetails> = emptyMap()
    private var offerTokensByID: Map<String, String> = emptyMap()

    init {
        scope.launch {
            while (true) {
                delay(60_000)
                if (hasCompletedInitialSetup) refreshPurchaseStatus()
            }
        }
    }

    // Connection admission is confined to [scope], whose dispatcher is Main.
    private var hasCompletedInitialSetup = false
    private val claimBillingReady = MutableStateFlow(false)
    private var isConnecting = false
    private var initialConnectionRetryAttempts = 0
    private var initialConnectionRetryJob: Job? = null
    private var billingRefreshJob: Job? = null

    private fun loadCachedUnlockState(): Boolean {
        if (BuildConfig.DEBUG && prefs.contains(KEY_DEBUG_OVERRIDE)) {
            return prefs.getBoolean(KEY_DEBUG_OVERRIDE, false)
        }
        if (prefs.getBoolean(KEY_IS_UNLOCKED, false)) return true
        if (prefs.getBoolean(KEY_LEGACY_UNLOCK_GRANTED, false)) return true

        if (isLegacyInstall()) {
            prefs.edit()
                .putBoolean(KEY_IS_UNLOCKED, true)
                .putBoolean(KEY_LEGACY_UNLOCK_GRANTED, true)
                .apply()
            Timber.d("Legacy install grandfathered into lifetime unlock")
            return true
        }

        return false
    }

    private fun isLegacyInstall(): Boolean = runCatching {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        FreemiumPolicy.isLegacyUnlock(packageInfo.firstInstallTime)
    }.getOrDefault(false)

    private fun saveUnlockState(unlocked: Boolean) {
        prefs.edit().putBoolean(KEY_IS_UNLOCKED, unlocked).apply()
        _isPermanentlyUnlocked.value = unlocked
        if (BuildConfig.DEBUG && prefs.contains(KEY_DEBUG_OVERRIDE)) {
            _isUnlocked.value = prefs.getBoolean(KEY_DEBUG_OVERRIDE, false)
            Timber.d("Unlock state saved: $unlocked (debug override active, showing: ${_isUnlocked.value})")
        } else {
            _isUnlocked.value = unlocked
            Timber.d("Unlock state saved: $unlocked")
        }
    }

    override fun refresh() {
        scope.launch {
            if (hasCompletedInitialSetup) {
                requestBillingRefresh()
            } else {
                startInitialConnectionIfNeeded()
            }
        }
    }

    private fun startInitialConnectionIfNeeded() {
        if (hasCompletedInitialSetup) {
            requestBillingRefresh()
            return
        }
        if (isConnecting || initialConnectionRetryJob?.isActive == true) {
            Timber.d("Billing client already connecting or awaiting an initial setup retry")
            return
        }

        isConnecting = true
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                scope.launch { handleBillingSetupFinished(result) }
            }

            override fun onBillingServiceDisconnected() {
                scope.launch { handleBillingServiceDisconnected() }
            }
        })
    }

    private fun handleBillingSetupFinished(result: BillingResult) {
        isConnecting = false
        if (result.responseCode == BillingClient.BillingResponseCode.OK) {
            Timber.d("Billing client connected successfully")
            hasCompletedInitialSetup = true
            claimBillingReady.value = true
            initialConnectionRetryAttempts = 0
            initialConnectionRetryJob?.cancel()
            initialConnectionRetryJob = null
            requestBillingRefresh()
        } else {
            Timber.e("Billing setup failed: ${result.debugMessage}")
            scheduleInitialConnectionRetry()
        }
    }

    private fun handleBillingServiceDisconnected() {
        isConnecting = false
        _productDetails.value = null
        _offer.value = null
        _offers.value = emptyList()
        detailsByID = emptyMap()
        offerTokensByID = emptyMap()
        _isUnlocked.value = loadCachedUnlockState()
        Timber.d("Billing service disconnected; the next Billing API call will reconnect")
        if (!hasCompletedInitialSetup) {
            scheduleInitialConnectionRetry()
        }
    }

    private fun scheduleInitialConnectionRetry() {
        _isUnlocked.value = loadCachedUnlockState()
        if (
            hasCompletedInitialSetup ||
            initialConnectionRetryAttempts >= MAX_INITIAL_CONNECTION_RETRY_ATTEMPTS ||
            initialConnectionRetryJob?.isActive == true
        ) {
            return
        }

        initialConnectionRetryAttempts++
        val delayMillis = INITIAL_CONNECTION_RETRY_DELAY_MS * initialConnectionRetryAttempts
        initialConnectionRetryJob = scope.launch {
            delay(delayMillis)
            initialConnectionRetryJob = null
            startInitialConnectionIfNeeded()
        }
    }

    private fun requestBillingRefresh() {
        if (billingRefreshJob?.isActive == true) {
            Timber.d("Billing product and purchase refresh already in progress")
            return
        }

        billingRefreshJob = scope.launch {
            try {
                queryProduct()
                refreshPurchaseStatus()
            } finally {
                billingRefreshJob = null
            }
        }
    }

    private suspend fun queryProduct() {
        queryAndCacheProductDetails()
    }

    private suspend fun queryAndCacheProductDetails(): BillingResult {
        // ProductDetails objects can become stale across service or network changes.
        _productDetails.value = null
        _offer.value = null

        _offers.value = emptyList()
        val loaded = mutableMapOf<String, ProductDetails>()
        var lastResult = BillingResult.newBuilder()
            .setResponseCode(BillingClient.BillingResponseCode.OK).build()
        for (type in listOf(BillingClient.ProductType.INAPP, BillingClient.ProductType.SUBS)) {
            val plans = PurchasePlan.entries.filter {
                (it == PurchasePlan.LIFETIME) == (type == BillingClient.ProductType.INAPP)
            }
            val params = QueryProductDetailsParams.newBuilder().setProductList(plans.map {
                QueryProductDetailsParams.Product.newBuilder()
                    .setProductId(it.productId).setProductType(type).build()
            }).build()
            val result = executeWithBillingRetry(
                operationName = "query product details",
                maxAttempts = BillingRetryPolicy.FOREGROUND_MAX_ATTEMPTS,
                retryDelayMillis = BillingRetryPolicy::foregroundRetryDelayMillis,
                billingResult = { it.billingResult },
            ) { billingClient.queryProductDetails(params) }
            lastResult = result.billingResult
            if (lastResult.responseCode == BillingClient.BillingResponseCode.OK) {
                result.productDetailsList.orEmpty().forEach { loaded[it.productId] = it }
            }
        }
        val tokens = mutableMapOf<String, String>()
        val available = PurchasePlan.entries.mapNotNull { plan ->
            val details = loaded[plan.productId] ?: return@mapNotNull null
            if (plan == PurchasePlan.LIFETIME) {
                details.oneTimePurchaseOfferDetails?.formattedPrice?.let {
                    PurchaseOffer(plan.productId, it, plan)
                }
            } else {
                val selected = selectSubscriptionOffer(details, plan) ?: return@mapNotNull null
                tokens[plan.productId] = selected.offerToken
                val phases = selected.pricingPhases.pricingPhaseList
                PurchaseOffer(plan.productId, phases.last().formattedPrice, plan,
                    phases.first().isSevenDayFreeTrial())
            }
        }
        detailsByID = loaded
        offerTokensByID = tokens
        _productDetails.value = loaded[PRODUCT_ID]
        _offers.value = available
        _offer.value = available.firstOrNull { it.plan == PurchasePlan.LIFETIME }
        return lastResult
    }

    override suspend fun launchPurchase(activity: Activity, plan: PurchasePlan): Boolean {
        val result = withPurchaseLaunchAdmission(_isPurchasing) { markFlowLaunched ->
            _purchaseError.value = null

            // ProductDetails should be refreshed immediately before a purchase launch rather
            // than relying on the copy cached for paywall display.
            val displayedOffer = _offers.value.firstOrNull { it.plan == plan }
            val queryResult = queryAndCacheProductDetails()
            val details = detailsByID[plan.productId]
            val offer = _offers.value.firstOrNull { it.plan == plan }
            if (details == null || offer == null) {
                _purchaseError.value = errorForResponse(
                    responseCode = queryResult.responseCode,
                    fallback = BillingError.PRODUCT_UNAVAILABLE,
                )
                return@withPurchaseLaunchAdmission false
            }

            if (displayedOffer != null && displayedOffer != offer) {
                // Refresh the visible terms and require another explicit tap.
                _purchaseError.value = BillingError.SERVICE_UNAVAILABLE
                return@withPurchaseLaunchAdmission false
            }
            val builder = BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details)
            if (plan != PurchasePlan.LIFETIME) {
                val token = offerTokensByID[plan.productId] ?: return@withPurchaseLaunchAdmission false
                builder.setOfferToken(token)
            }
            val productDetailsParams = builder.build()
            val billingFlowParams = BillingFlowParams.newBuilder()
                .setProductDetailsParamsList(listOf(productDetailsParams))
                .build()

            // A purchase launch is side-effecting. Billing-managed reconnection still runs for
            // this call, but a residual transient failure is surfaced for an explicit user retry.
            val launchResult = billingClient.launchBillingFlow(activity, billingFlowParams)

            when (launchResult.responseCode) {
                BillingClient.BillingResponseCode.OK -> {
                    markFlowLaunched()
                    Timber.d("Purchase flow launched successfully")
                    true
                }
                BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                    Timber.d("Purchase launch reported item already owned; reconciling purchases")
                    reconcileAlreadyOwnedPurchase("purchase launch")
                    false
                }
                else -> {
                    _purchaseError.value = errorForResponse(
                        responseCode = launchResult.responseCode,
                        fallback = BillingError.PURCHASE_FAILED,
                    )
                    Timber.e(
                        "Launch billing flow failed: responseCode=%d, debugMessage=%s",
                        launchResult.responseCode,
                        launchResult.debugMessage,
                    )
                    false
                }
            }
        }

        if (result == null) {
            Timber.w("Purchase already in progress")
            return false
        }
        return result
    }

    /** Fresh Play evidence only: cached unlocks, debug overrides and legacy installs never qualify. */
    suspend fun myselfClaimPurchaseToken(): String = withContext(Dispatchers.Main) {
        if (!hasCompletedInitialSetup) {
            startInitialConnectionIfNeeded()
            if (withTimeoutOrNull(15_000) { claimBillingReady.first { it } } != true) {
                throw MyselfClaimException(MyselfClaimFailure.STORE_UNAVAILABLE)
            }
        }
        val result = queryPurchases("verify myself.md claim purchase", includeSubscriptions = false)
        if (result.billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
            throw MyselfClaimException(MyselfClaimFailure.STORE_UNAVAILABLE)
        }
        myselfClaimPurchaseToken(result.purchasesList)
            ?: throw MyselfClaimException(MyselfClaimFailure.NO_PURCHASE)
    }

    private suspend fun refreshPurchaseStatus() {
        val result = queryPurchases("refresh purchases")
        if (result.billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
            processPurchases(result.purchasesList, fullSnapshot = true)
        } else {
            // No offline permanent grant for a subscription. Lifetime caches remain valid.
            _isUnlocked.value = loadCachedUnlockState()
            logPurchaseQueryFailure("Failed to query purchases", result.billingResult)
        }
    }

    override suspend fun restorePurchase(): Boolean {
        if (_isRestoring.value) return false

        _isRestoring.value = true
        _purchaseError.value = null

        return try {
            val result = queryPurchases("restore purchases")
            val billingResult = result.billingResult

            if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                val hasPremium = processPurchases(result.purchasesList, fullSnapshot = true) || loadCachedUnlockState()

                if (hasPremium) {
                    Timber.d("Purchase restored successfully")
                    true
                } else {
                    _purchaseError.value = BillingError.NO_PREVIOUS_PURCHASE
                    Timber.d("No purchases to restore")
                    false
                }
            } else {
                _purchaseError.value = errorForResponse(
                    responseCode = billingResult.responseCode,
                    fallback = BillingError.RESTORE_FAILED,
                )
                logPurchaseQueryFailure("Restore failed", billingResult)
                false
            }
        } finally {
            _isRestoring.value = false
        }
    }

    private suspend fun queryPurchases(operationName: String, includeSubscriptions: Boolean = true): PurchasesResult {
        val purchases = mutableListOf<Purchase>()
        val types = if (includeSubscriptions) listOf(BillingClient.ProductType.INAPP, BillingClient.ProductType.SUBS)
            else listOf(BillingClient.ProductType.INAPP)
        for (type in types) {
            val result = executeWithBillingRetry(
                operationName = operationName,
                maxAttempts = BillingRetryPolicy.FOREGROUND_MAX_ATTEMPTS,
                retryDelayMillis = BillingRetryPolicy::foregroundRetryDelayMillis,
                billingResult = { it.billingResult },
            ) {
                billingClient.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(type).build())
            }
            if (result.billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
                // A successful lifetime query must remain restorable even when
                // subscriptions are unsupported or their query is unavailable.
                if (playEntitlementSnapshot(purchases).hasLifetime) break
                return result
            }
            purchases += result.purchasesList
        }
        return PurchasesResult(BillingResult.newBuilder().setResponseCode(BillingClient.BillingResponseCode.OK).build(), purchases)
    }

    override suspend fun verifyAccess(): Boolean = withContext(Dispatchers.Main) {
        if (loadCachedUnlockState()) return@withContext true
        if (!hasCompletedInitialSetup) {
            startInitialConnectionIfNeeded()
            if (withTimeoutOrNull(15_000) { claimBillingReady.first { it } } != true) return@withContext false
        }
        refreshPurchaseStatus()
        _isUnlocked.value
    }

    private suspend fun reconcileAlreadyOwnedPurchase(source: String): Boolean {
        val result = queryPurchases("reconcile already-owned purchase")
        val billingResult = result.billingResult
        if (billingResult.responseCode != BillingClient.BillingResponseCode.OK) {
            _purchaseError.value = errorForResponse(
                responseCode = billingResult.responseCode,
                fallback = BillingError.PURCHASE_FAILED,
            )
            logPurchaseQueryFailure("Could not reconcile already-owned purchase from $source", billingResult)
            return false
        }

        val reconciled = processPurchases(result.purchasesList)
        if (!reconciled) {
            _purchaseError.value = BillingError.PURCHASE_FAILED
            Timber.e("Already-owned purchase from %s had no completed matching entitlement", source)
        }
        return reconciled
    }

    private fun logPurchaseQueryFailure(message: String, result: BillingResult) {
        Timber.e(
            "%s: responseCode=%d, debugMessage=%s",
            message,
            result.responseCode,
            result.debugMessage,
        )
    }

    private suspend fun acknowledgePurchase(purchaseToken: String) {
        val params = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchaseToken)
            .build()

        val result = executeWithBillingRetry(
            operationName = "acknowledge purchase",
            maxAttempts = BillingRetryPolicy.BACKGROUND_MAX_ATTEMPTS,
            retryDelayMillis = BillingRetryPolicy::backgroundRetryDelayMillis,
            billingResult = { it },
        ) {
            billingClient.acknowledgePurchase(params)
        }

        if (result.responseCode == BillingClient.BillingResponseCode.OK) {
            Timber.d("Purchase acknowledged successfully")
        } else {
            Timber.e(
                "Failed to acknowledge purchase: responseCode=%d, debugMessage=%s",
                result.responseCode,
                result.debugMessage,
            )
        }
    }

    private suspend fun <T> executeWithBillingRetry(
        operationName: String,
        maxAttempts: Int,
        retryDelayMillis: (failedAttempt: Int) -> Long,
        billingResult: (T) -> BillingResult,
        operation: suspend () -> T,
    ): T = executeBoundedRetry(
        maxAttempts = maxAttempts,
        retryDelayMillis = retryDelayMillis,
        shouldRetry = { BillingRetryPolicy.isTransient(billingResult(it).responseCode) },
        sleep = { delay(it) },
        onRetry = { result, failedAttempt, delayMillis ->
            val response = billingResult(result)
            Timber.w(
                "Transient billing failure; retrying: operation=%s, responseCode=%d, attempt=%d/%d, delayMs=%d",
                operationName,
                response.responseCode,
                failedAttempt,
                maxAttempts,
                delayMillis,
            )
        },
        operation = operation,
    )

    private fun errorForResponse(responseCode: Int, fallback: BillingError): BillingError =
        if (BillingRetryPolicy.isTransient(responseCode)) BillingError.SERVICE_UNAVAILABLE else fallback

    override fun clearError() {
        _purchaseError.value = null
    }

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
                Timber.d("User cancelled purchase")
            }
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                _purchaseError.value = null
                Timber.d("Purchase callback reported item already owned; reconciling purchases")
                scope.launch {
                    reconcileAlreadyOwnedPurchase("purchase callback")
                }
            }
            else -> {
                _purchaseError.value = errorForResponse(
                    responseCode = billingResult.responseCode,
                    fallback = BillingError.PURCHASE_FAILED,
                )
                Timber.e(
                    "Purchase error: responseCode=%d, debugMessage=%s",
                    billingResult.responseCode,
                    billingResult.debugMessage,
                )
            }
        }
    }

    private fun processPurchases(purchases: List<Purchase>, fullSnapshot: Boolean = false): Boolean {
        val snapshot = playEntitlementSnapshot(purchases)
        if (snapshot.hasLifetime) saveUnlockState(true)
        if (fullSnapshot || snapshot.hasAccess) {
            _isUnlocked.value = loadCachedUnlockState() || snapshot.hasAccess
        }
        if (snapshot.unacknowledgedTokens.isNotEmpty()) {
            scope.launch {
                snapshot.unacknowledgedTokens.forEach { acknowledgePurchase(it) }
            }
        }
        return snapshot.hasAccess
    }

    override fun debugSetUnlocked(unlocked: Boolean) {
        if (!BuildConfig.DEBUG) {
            Timber.w("Debug methods only available in debug builds")
            return
        }
        prefs.edit().putBoolean(KEY_DEBUG_OVERRIDE, unlocked).apply()
        _isUnlocked.value = unlocked
        _isPermanentlyUnlocked.value = unlocked
        Timber.d("Debug: Set unlock state to $unlocked")
    }

    override fun debugReset() {
        if (!BuildConfig.DEBUG) {
            Timber.w("Debug methods only available in debug builds")
            return
        }
        prefs.edit()
            .remove(KEY_IS_UNLOCKED)
            .remove(KEY_DEBUG_OVERRIDE)
            .remove(KEY_LEGACY_UNLOCK_GRANTED)
            .apply()
        _isUnlocked.value = false
        _isPermanentlyUnlocked.value = false
        _offers.value = emptyList()
        _productDetails.value = null
        _offer.value = null
        _purchaseError.value = null
        Timber.d("Debug: Reset all purchase state")
    }
}
