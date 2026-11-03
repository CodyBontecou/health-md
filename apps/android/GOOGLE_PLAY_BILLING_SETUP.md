# Google Play Billing Integration Guide

This guide covers the `play` Android variant. F-Droid does not compile Billing and retains included full access. Source implementation is not evidence of console setup, approval, or a qualified live transaction. Store mutations, device installation, sandbox purchases, and release workflows require explicit authorization.

## Product configuration

The approved US Individual prices are **$0.99 weekly**, **$29.99 yearly**, and **$49.99 Lifetime**. Eligible subscriptions include a **seven-day free trial**. Lifetime is charged immediately. Android offers no Family plans and no monthly subscription. The cross-platform decision and Apple setup are recorded in the [paid-access rollout](../apple/docs/experiments/subscription-pricing-rollout.md).

**Live-price hold:** these are launch targets. Leave the existing live lifetime product's price and regional pricing unchanged until the subscription-containing app is live and the owner explicitly approves the coordinated cutover. Draft subscription products, prices, and trials may be prepared in advance; do not activate, submit, publish, or release as a side effect of setup. Follow the rollout guide's live-price hold when resuming Console work.

Configure draft products in Google Play Console under Monetize → Products:

| Product ID | Type | Base-plan period | US launch target |
|---|---|---|---:|
| `health_md_premium_weekly` | Auto-renewing subscription | `P1W` | $0.99 |
| `health_md_premium_yearly` | Auto-renewing subscription | `P1Y` | $29.99 |
| `health_md_premium_lifetime` | Non-consumable INAPP | — | $49.99 |

As of October 29, 2026, both subscription products are configured in Console but remain unavailable for purchase: `health_md_premium_weekly` has base plan `weekly`, and `health_md_premium_yearly` has base plan `yearly`. Each base plan and its `trial-7d` offer is **Draft**, and both products show **zero active base plans**. Console lists 175 countries/regions for each plan and offer, with converted prices on these new drafts only. The saved US prices are $0.99 weekly and $29.99 yearly. Trial eligibility is **New customer acquisition → Never had any subscription** in this app; each offer has one **Free trial → 7 days** phase before the recurring base price.

The existing `health_md_premium_lifetime` product was inspected read-only: US $19.99, with its entire rendered country/price/tax/availability table identical before and after draft setup. Its price, regional overrides, active state, and product ID were not changed. No products were activated and no review, publication, or release action was taken. Later activation and exact-build sandbox qualification remain separately authorized release gates.

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
