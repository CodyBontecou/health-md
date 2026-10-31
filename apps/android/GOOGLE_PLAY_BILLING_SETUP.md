# Google Play Billing Integration Guide

This guide covers the `play` Android variant. F-Droid does not compile Billing and retains included full access. Source implementation is not evidence of console setup, approval, or a qualified live transaction. Store mutations, device installation, sandbox purchases, and release workflows require explicit authorization.

## Product configuration

The approved US Individual prices are **$0.99 weekly**, **$29.99 yearly**, and **$49.99 Lifetime**. Eligible subscriptions include a **seven-day free trial**. Lifetime is charged immediately. Android offers no Family plans and no monthly subscription. The cross-platform decision and Apple setup are recorded in the [paid-access rollout](../apple/docs/experiments/subscription-pricing-rollout.md).

**Internal-testing release:** Android 3.5.0 build 44 is the follow-up candidate for trial-offer qualification; build 43 is already on Internal Testing. Upload through the protected `android-release.yml` workflow, then qualify real Play purchases with license-test accounts before production promotion. The Internal Testing upload does not activate subscription products or change any product price.

**Live-price hold:** these are launch targets. Leave the existing live lifetime product's price and regional pricing unchanged until the subscription-containing app is live and the owner explicitly approves the coordinated cutover. Draft subscription products, prices, and trials may be prepared in advance; do not activate, submit, publish, or release as a side effect of setup. Follow the rollout guide's live-price hold when resuming Console work.

Configure draft products in Google Play Console under Monetize → Products:

| Product ID | Type | Base-plan period | US launch target |
|---|---|---|---:|
| `health_md_premium_weekly` | Auto-renewing subscription | `P1W` | $0.99 |
| `health_md_premium_yearly` | Auto-renewing subscription | `P1Y` | $29.99 |
| `health_md_premium_lifetime` | Non-consumable INAPP | — | $49.99 |

On October 30, 2026 (October 31 UTC), the owner-authorized Android Internal Testing and Pixel 7 license-test preparation activated both subscription products: `health_md_premium_weekly` has active base plan `weekly` at US $0.99, and `health_md_premium_yearly` has active base plan `yearly` at US $29.99. Both `trial-7d` offers are **Active**. Fresh Console readback showed one active base plan and one offer per product. Each plan/offer retains its 175-country/region configuration. Trial eligibility remains **New customer acquisition → Never had any subscription** in this app, with one **Free trial → 7 days** phase before the recurring base price. Activation makes these products purchasable; it does not establish successful purchase qualification or publish a new app binary.

The existing `health_md_premium_lifetime` product remains **Active** at US **$19.99**. All 177 rendered pricing/tax/availability rows were byte-identical before and after subscription activation; its product ID, purchase option, regional prices and availability were not changed. The $49.99 Lifetime target remains on hold.

The annotated [`android/v3.5.0` tag](https://github.com/CodyBontecou/health-md/tree/android/v3.5.0) identifies phone version code 43 at `caa49a72326ed1b9b055f0e5090b781c210a411f`. The protected [Internal Testing workflow](https://github.com/CodyBontecou/health-md/actions/runs/41148643889) completed its second attempt and uploaded code 43 to `internal`. The retained intent and committed-upload receipts agree on source, code, track and AAB SHA-256 `e1be952bf4ff0b1828d648230e3b6debb145a307dc021d5b3d2fde8ce1f93307`; the upload certificate is the registered signer. Console confirmed **Available to internal testers**. No production promotion occurred. Real Play purchase, restore, renewal and expiry qualification remains pending.

Play Store delivery can lag a committed internal release. Console's code-43 bundle Downloads view provides the Play-signed universal APK for exact-build runtime checks; verify package, version/code and certificate before installation, and distinguish this artifact path from store-delivered split-APK qualification. Clearing app data does not remove Play-owned entitlements. Use a license-test account without permanent access for subscription and fresh-user gate checks; qualify existing permanent owners separately. Confirm the purchase sheet explicitly identifies a test purchase and a test payment method before completing a transaction.

A Play-signed release cannot update a debug-signed installation in place. Back up needed local state and obtain data-reset approval before replacement; Android Keystore credentials may require sign-in afterward.

Configure an eligible `P7D` free-trial offer on each subscription with one free cycle followed by the infinitely recurring paid phase. The app selects only an eligible seven-day trial or its paid base plan, and shows the localized price returned by Play. No fallback US price or fabricated trial is used. Product/base-plan/offer activation and regional availability must be verified in Console before shipping the hard gate.

**Never rename the existing lifetime ID.** Existing paid and previously grandfathered permanent owners retain access and restoration. No custom family accounts, invitations, or cross-store entitlement transfer are included.

## Architecture

`HealthMdNavigation` owns the root hard gate before tracking/setup. `PaywallScreen` displays typed `PurchaseOffer` values from `PaywallViewModel`; no Play SDK type crosses the channel-neutral `PurchaseRepository` and `EntitlementRepository` boundaries.

`BillingRepositoryImpl` and its BillingClient v8.3+ are application-scoped Hilt singletons. Screen ViewModels refresh them; they must never call `BillingClient.endConnection()`. A closed BillingClient is terminal. Billing-managed reconnection and bounded transient retries are preserved. Product details are reloaded before a purchase; changed displayed terms require another explicit tap. A purchase launch itself is never automatically retried.

The repository queries both INAPP and SUBS, accepts matching `PURCHASED` products, and asynchronously acknowledges unacknowledged purchases. Pending/canceled/unknown products do not unlock. Acknowledgment must complete within Google's window to avoid automatic refund.

Only permanent unlocks populate the old `isPurchased` flag and lifetime SharedPreferences cache. Subscription access is session-local, refreshed on foregrounding and periodically while the process is alive. Headless workers, automation, recovery, Direct CLI, and foreground export admission query current Play access. Empty successful snapshots remove subscription access; verification failures fail closed for subscription-only users. Existing lifetime/legacy caches remain usable offline. Subscription-only users need Play connectivity after process restart; there is no invented offline grace period.

Do not erase a saved schedule while subscription access is still resolving. Workers separately enforce access before execution. F-Droid uses its stable included-access repository and no simulated buy/restore flow.

## Security and privacy

This retains the existing client-side Billing trust boundary; accepting Play `PURCHASED` results is **not server-side signature verification**. A purchase-verification backend/RTDN lifecycle service is not introduced here. Do not persist subscription tokens as permanent access or expose them in telemetry. Health data never enters billing or pricing analytics.

The separate myself.md claim path continues to require fresh lifetime purchase evidence; an ordinary subscription does not establish that lifetime benefit.

## Focused local checks

From `apps/android`:

```bash
./gradlew :app:testPlayDebugUnitTest --tests 'com.healthmd.domain.billing.FreemiumPolicyTest' --tests 'com.healthmd.data.billing.*Test' --max-workers=2
```

Use root `make plan-native` / `make verify-native` for queued native integration compilation. Compilation does not verify purchases, navigation, or expiry behavior.

## Authorized store/device qualification

Use an internal testing track and Google Play license-test accounts. Product IDs, package/signature, product availability, store account, and region must match Console. Do not substitute legacy `android.test.*` product IDs for qualification of real subscription offers.

Verify on the exact release build:

- Fresh and old free installs hit the hard gate; Back/deep links cannot expose tracking.
- Existing lifetime owners and grandfathered users retain access after upgrade/restart/restore.
- Eligible and ineligible weekly/yearly offers show the correct trial, total renewal amount, cadence, and localized price.
- Successful, pending, canceled, failed, and already-owned purchases; acknowledgment retry and restore.
- Trial expiry, cancellation through the paid-through date, renewal, subscription expiry, refund/revocation, and process restart.
- Store disconnect, offline restart, missing products, and explicit retry without a false unlock.
- Foreground export, scheduled work, automation, recovery, and Direct CLI enforce access.
- Manage Subscriptions, Terms, Privacy, accessibility, and F-Droid's included-access behavior.

Retain exact-build evidence and use the canonical [Play release guide](PLAY_STORE_SETUP.md). This guide does not authorize publication.

## Troubleshooting

- **Product unavailable:** check exact IDs/types, active base plans/offers, test-track publication, account/territory eligibility, signature, and propagation delay.
- **Purchase does not open:** verify an Activity is supplied, Billing setup succeeds, and fresh offer details are available. Surface an explicit retry instead of retrying a charge automatically.
- **No previous purchase:** use the purchasing Google account and Restore Purchase; an expired subscription does not grant permanent access.
- **No controls on F-Droid:** expected; full access is included.

## References

- [Billing integration](https://developer.android.com/google/play/billing/integrate)
- [Subscription lifecycle](https://developer.android.com/google/play/billing/lifecycle/subscriptions)
- [Testing](https://developer.android.com/google/play/billing/test)
- [Security](https://developer.android.com/google/play/billing/security)

### Trial-offer qualification follow-up

On the authorized license-test Pixel, code 43 displayed the three correct US prices and preserved the mandatory gate after a canceled test purchase. Weekly's store sheet omitted the trial even after Billing Lab trial eligibility was enabled and the Play cache cleared. The billing account was confirmed in the payment-method sheet. A no-charge Weekly test payment subsequently succeeded; access, restore, renewal and expiry qualification are still pending.

The Android offer filter rejected equivalent `P1W` seven-day phases and non-recurring phases with zero cycles. Build 44 accepts `P1W` and `P7D` only when the free phase represents exactly one week, and uses the same predicate for trial disclosure and offer selection. Regression tests reproduce the rejection before the fix. This corrects the SDK representation handling; only a signed-build store-sheet check can establish whether it resolves the observed missing trial. The immutable code-43 tag and upload evidence remain unchanged. Lifetime's live price remains US $19.99.
