# Google Play Billing Integration Guide

This document walks through the complete setup of Google Play Billing for the Health MD Android app.

## Architecture Overview

The billing implementation uses a clean architecture pattern:

```
UI Layer (PaywallScreen)
    ↓
ViewModel (PaywallViewModel)
    ↓
Repository (BillingRepository interface)
    ↓
Implementation (BillingRepositoryImpl)
    ↓
Google Play Billing Client
```

### Components

1. **BillingRepository** (`domain/repository/BillingRepository.kt`)
   - Interface defining the billing contract
   - `isPurchased`: StateFlow tracking purchase state
   - `launchPurchaseFlow()`: Initiates purchase flow
   - `restorePurchases()`: Queries existing purchases
   - `connect()/disconnect()`: Manages billing client lifecycle

2. **BillingRepositoryImpl** (`data/billing/BillingRepositoryImpl.kt`)
   - Concrete implementation using Google Play Billing Client v7.1+
   - Handles product queries, purchase flow, and acknowledgment
   - Automatically acknowledges purchases (required for security)

3. **PaywallViewModel** (`presentation/paywall/PaywallViewModel.kt`)
   - Manages paywall UI state
   - Handles coroutine lifecycle
   - Auto-dismisses paywall on successful purchase

4. **PaywallScreen** (`presentation/paywall/PaywallScreen.kt`)
   - Beautiful Compose UI with feature list
   - Purchase and restore buttons
   - Error messaging support

## Setup Instructions

### Step 1: Create Product in Google Play Console

1. Go to [Google Play Console](https://play.google.com/console)
2. Select your app → **Monetize** → **Products** → **In-app products**
3. Create a new product with:
   - **Product ID**: `health_md_premium_lifetime` (must match `PRODUCT_ID_PREMIUM` in code)
   - **Product type**: In-app product (one-time purchase)
   - **Title**: "Health MD Premium"
   - **Description**: "Unlimited exports and scheduled backups"
   - **Price**: Set your desired price

**Important**: The product ID in the code MUST exactly match the product ID in Google Play Console.

### Step 2: Update Product ID (if using different name)

If you use a different product ID, update:

**File**: `app/src/main/java/com/healthmd/data/billing/BillingRepositoryImpl.kt`

```kotlin
private const val PRODUCT_ID_PREMIUM = "health_md_premium_lifetime"  // ← Update this
```

### Step 3: Build and Test

The implementation is fully integrated. Build the app:

```bash
./gradlew assembleDebug
```

Or install on connected device:

```bash
./gradlew installDebug
```

### Step 4: Test Purchases (Development)

For testing without real transactions, use Google's test product IDs:

- `android.test.purchased` - Will pass purchase
- `android.test.canceled` - Will cancel purchase  
- `android.test.refunded` - Will refund purchase
- `android.test.item_unavailable` - Product unavailable

**Note**: Test product IDs only work with test accounts added to your Play Console.

To use test accounts:
1. Go to Play Console → **Settings** → **License testing**
2. Add test Gmail accounts
3. Sign in with test account on test device

### Step 5: Integration Points

#### In Navigation

The paywall is wired up in `HealthMdNavigation.kt`:

```kotlin
composable(SubRoutes.PAYWALL) {
    val paywallViewModel: PaywallViewModel = hiltViewModel()
    val isPurchased by paywallViewModel.isPurchased.collectAsStateWithLifecycle()
    val context = androidx.compose.ui.platform.LocalContext.current

    // Auto-dismiss on successful purchase
    LaunchedEffect(isPurchased) {
        if (isPurchased) {
            navController.popBackStack()
        }
    }

    PaywallScreen(
        onPurchase = {
            val activity = context as? android.app.Activity
            if (activity != null) {
                paywallViewModel.launchPurchaseFlow(activity)
            }
        },
        onRestore = { paywallViewModel.restorePurchases() },
        onDismiss = { navController.popBackStack() },
    )
}
```

#### To Check Purchase Status Anywhere

```kotlin
@Inject
lateinit var billingRepository: BillingRepository

val isPurchased = billingRepository.isPurchased.collectAsStateWithLifecycle()

// Show paywall if not purchased
if (!isPurchased.value) {
    navController.navigate(SubRoutes.PAYWALL)
}
```

### Current Status: Premium Features

Look for uses of `onNavigateToPaywall` in the codebase to see where paywalls are triggered:

```bash
grep -r "onNavigateToPaywall" app/src/main/java/
```

Update these screens to check `isPurchased` and show paywall for premium features.

## Purchase Flow Diagram

```
User taps "Unlock"
    ↓
PaywallViewModel.launchPurchaseFlow()
    ↓
Query product details from Play Store
    ↓
Launch billing UI (user completes payment)
    ↓
onPurchasesUpdated callback fires
    ↓
Acknowledge purchase (required!)
    ↓
Update isPurchased StateFlow
    ↓
PaywallScreen auto-dismisses
    ↓
Feature unlocked
```

## Important: Acknowledge Purchases

The code automatically acknowledges purchases after they're verified. This is **required** by Google:

```kotlin
private fun onPurchasesUpdated(billingResult: BillingResult, purchases: List<Purchase>?) {
    purchases?.forEach { purchase ->
        if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
            !purchase.isAcknowledged
        ) {
            // Acknowledge purchase (REQUIRED)
            val params = AcknowledgePurchaseParams.newBuilder()
                .setPurchaseToken(purchase.purchaseToken)
                .build()
            billingClient.acknowledgePurchase(params) { ... }
        }
    }
}
```

**Failure to acknowledge** results in automatic refunds after 3 days.

## Security Considerations

1. **Signature Verification**: For production, consider verifying purchase signatures server-side
2. **Fraud Detection**: Monitor unusual purchase patterns in Play Console
3. **Network Security**: Uses HTTPS to Google's servers (handled by BillingClient)
4. **Token Expiry**: Purchase tokens expire after 1 year

## Troubleshooting

### "Product not found"
- ✅ Product ID in code doesn't match Play Console
- ✅ App not published (use internal test track)
- ✅ Wait 15 minutes for Play Console changes to sync

### Purchase button does nothing
- ✅ Not signed in to Google Play Store account
- ✅ Billing library not initialized (`connect()` not called)
- ✅ Activity not passed to `launchPurchaseFlow()`

### Crashes on purchase
- ✅ Check Logcat: `BillingClient` or `BillingRepository` errors
- ✅ Make sure Activity is instanceof `android.app.Activity`

## Monitoring

Purchases are logged with Timber:

```
D/BillingRepository: Billing client ready
D/BillingRepository: Purchase acknowledged
D/BillingRepository: Purchases queried
```

Watch logs in Logcat: `adb logcat | grep BillingRepository`

## Next Steps

1. ✅ Create product in Play Console
2. ✅ Add test accounts for testing
3. ✅ Test purchase flow in app
4. ✅ Identify all premium features
5. ✅ Update ExportScreen and other screens to show paywall
6. ✅ Test restoration with test account
7. ✅ Submit to Play Store

## References

- [Google Play Billing Library Documentation](https://developer.android.com/google/play/billing)
- [Play Billing Integration Test Checklist](https://developer.android.com/google/play/billing/test)
- [Security Best Practices](https://developer.android.com/google/play/billing/security)
