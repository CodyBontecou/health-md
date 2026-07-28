package com.healthmd.domain.repository

import android.app.Activity
import com.android.billingclient.api.ProductDetails
import kotlinx.coroutines.flow.StateFlow

/**
 * Repository interface for Google Play Billing operations.
 * 
 * Handles purchase state, product details, and billing operations for the
 * health_md_premium_lifetime one-time purchase product.
 */
interface BillingRepository {
    /** Whether the user has unlocked premium features */
    val isUnlocked: StateFlow<Boolean>
    
    /** Whether a purchase flow is currently in progress */
    val isPurchasing: StateFlow<Boolean>
    
    /** Whether a restore operation is currently in progress */
    val isRestoring: StateFlow<Boolean>
    
    /** Current purchase error message, if any */
    val purchaseError: StateFlow<String?>
    
    /** Product details from Play Store (contains pricing info) */
    val productDetails: StateFlow<ProductDetails?>
    
    /**
     * Establishes connection to Google Play Billing service.
     * Should be called when the app starts or when billing features are needed.
     * Handles reconnection automatically on connection loss.
     */
    fun startConnection()
    
    /**
     * Queries product details from Google Play Store.
     * Results are emitted to [productDetails] flow.
     */
    suspend fun queryProduct()
    
    /**
     * Launches the Google Play purchase flow for the premium product.
     * @param activity The activity to use for launching the purchase dialog
     * @return true if the flow was launched successfully
     */
    suspend fun launchPurchase(activity: Activity): Boolean
    
    /**
     * Refreshes the current purchase status from Google Play.
     * Updates [isUnlocked] based on current entitlements.
     */
    suspend fun refreshPurchaseStatus()
    
    /**
     * Restores previous purchases for users who reinstall or switch devices.
     * @return true if a valid purchase was restored
     */
    suspend fun restorePurchase(): Boolean
    
    /**
     * Acknowledges a pending purchase. Required by Google within 3 days of purchase.
     * Called automatically when purchases are detected.
     */
    suspend fun acknowledgePurchase(purchaseToken: String)
    
    /**
     * Clears any current error message.
     */
    fun clearError()
    
    /**
     * Disconnects from billing service.
     * Should be called when billing features are no longer needed.
     */
    fun endConnection()
    
    // Debug-only methods (only functional in debug builds)
    
    /** Debug: Force unlock state for testing */
    fun debugSetUnlocked(unlocked: Boolean)
    
    /** Debug: Reset all purchase state */
    fun debugResetPurchaseState()
}
