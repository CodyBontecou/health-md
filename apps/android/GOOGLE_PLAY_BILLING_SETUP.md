# Google Play Billing Integration Guide

This guide covers the `play` Android variant. F-Droid does not compile Billing and retains included full access. Source implementation is not evidence of console setup, approval, or a qualified live transaction. Store mutations, device installation, sandbox purchases, and release workflows require explicit authorization.

## Product configuration

The approved future US Individual launch targets are **$0.99 weekly**, **$29.99 yearly**, and **$49.99 Lifetime**. Live Lifetime remains **$19.99 US** under the hold below. Eligible subscriptions include a **seven-day free trial**. Lifetime is charged immediately. Android offers no Family plans and no monthly subscription. The cross-platform decision and Apple setup are recorded in the [paid-access rollout](../apple/docs/experiments/subscription-pricing-rollout.md).

**Internal-testing release:** Android 3.5.0 build 45 is available on Internal Testing. It retains build 44's seven-day trial phase fix and corrects refunded-Lifetime revocation and asynchronous automation results. Upload through the protected `android-release.yml` workflow, then qualify real Play purchases with license-test accounts before production promotion. The Internal Testing upload does not activate subscription products or change any product price. Production promotion remains on hold.

**Live-price hold:** these are launch targets. Leave the existing live lifetime product's price and regional pricing unchanged until the subscription-containing app is live and the owner explicitly approves the coordinated cutover. Draft subscription products, prices, and trials may be prepared in advance; do not activate, submit, publish, or release as a side effect of setup. Follow the rollout guide's live-price hold when resuming Console work.

Configure draft products in Google Play Console under Monetize → Products:

| Product ID | Type | Base-plan period | US launch target |
|---|---|---|---:|
| `health_md_premium_weekly` | Auto-renewing subscription | `P1W` | $0.99 |
| `health_md_premium_yearly` | Auto-renewing subscription | `P1Y` | $29.99 |
| `health_md_premium_lifetime` | Non-consumable INAPP | — | $49.99 |

On October 30, 2026 (October 31 UTC), the owner-authorized Android Internal Testing and Pixel 7 license-test preparation activated both subscription products: `health_md_premium_weekly` has active base plan `weekly` at US $0.99, and `health_md_premium_yearly` has active base plan `yearly` at US $29.99. Both `trial-7d` offers are **Active**. Fresh Console readback showed one active base plan and one offer per product. Each plan/offer retains its 175-country/region configuration. Trial eligibility remains **New customer acquisition → Never had any subscription** in this app, with one **Free trial → 7 days** phase before the recurring base price. Activation makes these products purchasable; it does not establish successful purchase qualification or publish a new app binary.

The existing `health_md_premium_lifetime` product remains **Active** at US **$19.99**. All 177 rendered pricing/tax/availability rows were byte-identical before and after subscription activation; its product ID, purchase option, regional prices and availability were not changed. The $49.99 Lifetime target remains on hold.

The annotated [`android/v3.5.0` tag](https://github.com/CodyBontecou/health-md/tree/android/v3.5.0) identifies phone version code 43 at `caa49a72326ed1b9b055f0e5090b781c210a411f`. The protected [Internal Testing workflow](https://github.com/CodyBontecou/health-md/actions/runs/41148643889) completed its second attempt and uploaded code 43 to `internal`. The retained intent and committed-upload receipts agree on source, code, track and AAB SHA-256 `e1be952bf4ff0b1828d648230e3b6debb145a307dc021d5b3d2fde8ce1f93307`; the upload certificate is the registered signer. Console confirmed **Available to internal testers**. No production promotion occurred. The code-43 runtime results and follow-up qualification gaps are recorded below.

The follow-up annotated [`android/v3.5.0+44` tag](https://github.com/CodyBontecou/health-md/tree/android/v3.5.0%2B44) identifies code 44 at `f32b00988da87da7a7ab7e46a9850f42f82697d2`. Its protected [Internal Testing workflow](https://github.com/CodyBontecou/health-md/actions/runs/41154938163) passed on attempt 2 and retained matching intent/committed-upload receipts for AAB SHA-256 `2ee5a4655af0a1c54436271ecd7fb21d6b528a59d7fddb37fb706a88331089ae`, using the same registered upload signer. Console confirmed code 44 **Available to internal testers**. The Pixel then updated normally through Google Play to 3.5.0/code 44, with Play as installer/initiator and base plus arm64, English and xxhdpi splits. The installed base APK's app-signing certificate SHA-256 matched `48441e648ea657cc2b215965ff8ce372ec4b4935cc99def8a5addc76759e154a`. No fallback APK installation was used for code 44. Production remains unchanged.

Play Store delivery can lag a committed internal release. Console's code-43 bundle Downloads view provides the Play-signed universal APK for exact-build runtime checks; verify package, version/code and certificate before installation, and distinguish this artifact path from store-delivered split-APK qualification. Clearing app data does not remove Play-owned entitlements. Use a license-test account without permanent access for subscription and fresh-user gate checks; qualify existing permanent owners separately. Confirm the purchase sheet explicitly identifies a test purchase and a test payment method before completing a transaction.

A Play-signed release cannot update a debug-signed installation in place. Back up needed local state and obtain data-reset approval before replacement; Android Keystore credentials may require sign-in afterward.

Configure an eligible seven-day free-trial offer on each subscription, followed by the infinitely recurring paid phase. The Billing SDK may represent the week as `P7D` or `P1W`; finite free phases have one cycle, while non-recurring phases have zero cycles. The app selects only an eligible seven-day trial or its paid base plan, and shows the localized price returned by Play. No fallback US price or fabricated trial is used. Product/base-plan/offer activation and regional availability must be verified in Console before shipping the hard gate.

**Never rename the existing lifetime ID.** Existing paid and previously grandfathered permanent owners retain access and restoration. No custom family accounts, invitations, or cross-store entitlement transfer are included.

## Architecture

`HealthMdNavigation` owns the root hard gate before tracking/setup. `PaywallScreen` displays typed `PurchaseOffer` values from `PaywallViewModel`; no Play SDK type crosses the channel-neutral `PurchaseRepository` and `EntitlementRepository` boundaries.

`BillingRepositoryImpl` and its BillingClient v8.3+ are application-scoped Hilt singletons. Screen ViewModels refresh them; they must never call `BillingClient.endConnection()`. A closed BillingClient is terminal. Billing-managed reconnection and bounded transient retries are preserved. Product details are reloaded before a purchase; changed displayed terms require another explicit tap. A purchase launch itself is never automatically retried.

The repository queries both INAPP and SUBS, accepts matching `PURCHASED` products, and asynchronously acknowledges unacknowledged purchases. Pending/canceled/unknown products do not unlock. Acknowledgment must complete within Google's window to avoid automatic refund.

Only permanent unlocks populate the old `isPurchased` flag and lifetime SharedPreferences cache. Subscription access is session-local, refreshed on foregrounding and periodically while the process is alive. Headless workers, automation, recovery, Direct CLI, and foreground export admission query current Play access. Successful complete ownership snapshots remove expired subscription access and clear both persisted Lifetime flags when Play no longer reports Lifetime ownership. Previously grandfathered grants remain independent of store product ownership. Failed queries and partial purchase callbacks do not revoke a cached Lifetime grant; verification failures fail closed for subscription-only users. Existing lifetime/legacy caches remain usable offline. Subscription-only users need Play connectivity after process restart; there is no invented offline grace period.

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

On the authorized license-test Pixel, code 43 displayed the three correct US prices and preserved the mandatory gate after a canceled test purchase. Weekly's store sheet omitted the trial even after Billing Lab trial eligibility was enabled and the Play cache cleared. The billing account was confirmed in the payment-method sheet. A completed no-charge Weekly purchase unlocked onboarding, survived process restart, and automatically restored after clearing only the unconfigured QA app state. Play advanced the next payment by five minutes, confirming a test renewal. Cancellation preserved access through the paid period; after Play no longer reported the subscription, resuming Health.md restored the mandatory gate. Restore then reported no previous purchase and stayed locked (six-step replay passed). These checks used the Play-generated signed universal code-43 APK, not ordinary store-delivered splits. The saved foreground screenshot also shows the mandatory paywall before leaving the app or reading back Play state, verifying automatic foreground relock. A live accessibility wait returned a stale onboarding hierarchy despite that screenshot, so its failed wait is an automation false negative; use the runner full hierarchy and screenshots to corroborate subsequent state transitions.

The Android offer filter rejected equivalent `P1W` seven-day phases and non-recurring phases with zero cycles. Build 44 accepts `P1W` and `P7D` only when the free phase represents exactly one week, and uses the same predicate for trial disclosure and offer selection. Regression tests reproduce the rejection before the fix. On the normally Play-delivered code 44, both subscription buttons showed seven days free. The actual Weekly sheet included the three-minute sandbox trial and US $0.99/five-minute test renewal, with an explicit no-charge test instrument. Its trial-entry/cancellation replay passed (15 steps), the Weekly trial purchase unlocked access (12 steps), and access restored after clearing the unconfigured QA app state (three-step replay). These runtime results confirm the fix resolves the missing-trial symptom. The immutable code-43 tag and upload evidence remain unchanged. Lifetime's live price remains US $19.99.

### Code-44 device qualification

These checks used the normally Play-delivered 3.5.0/code 44 on the authorized Pixel 7 and no-charge license-test instruments. No health permissions were granted and no health data was read or exported.

| Surface | Result |
| --- | --- |
| Delivery and identity | Normal internal-track Play update; version/code, split delivery and Play app-signing certificate verified |
| Eligible offers | Both seven-day trial labels and their localized prices verified; actual Weekly/Yearly sheets showed the three-minute sandbox trial and $0.99/five-minute or $29.99/30-minute renewal terms |
| Weekly lifecycle | Trial purchase, reset-state restore, trial-to-paid conversion, cancellation through the paid period and automatic foreground expiry verified |
| Expired access | Back/relaunch stayed gated; expired Restore returned no previous purchase after scrolling the control fully into view |
| Yearly lifecycle | Trial purchase, cancellation while in trial and automatic foreground expiry verified; paid Yearly renewal remains unrun |
| Pending Lifetime | Slow-decline test instrument did not grant access across QA data reset/restart; product became purchasable again afterward |
| Declined Lifetime | Google displayed its explicit always-denied test-instrument error; dismissal/restart preserved the gate |
| Successful Lifetime | US $19.99 test purchase unlocked access; after a five-minute wait, clearing the unconfigured QA state restored access from Play and restart retained it (six-step run) |

Automation caveats are retained with the exact-build evidence: the live trimmed accessibility projection sometimes returned stale nodes, and `scroll-to` considered a partly visible Restore button reachable. Full runner hierarchy checks and screenshots corroborated transitions; the initial combined expiry/restore run failed at the missed Restore tap, and the recovered Restore fragment passed. Do not describe that combined run as a clean full replay.

Production remains on hold for the unrun qualification matrix, including paid Yearly renewal, refund/revocation, offline/store-loss behavior, existing permanent-owner upgrade cases and device-level headless/export/automation admission. Passing portable billing/admission regressions and native compilation do not replace those runtime checks. No production promotion or Lifetime price cutover is included.

Both sandbox subscriptions were canceled during qualification. The QA account now owns a test Lifetime purchase, so future unentitled-user checks require a tester without permanent access or deliberate revocation of that exact test order followed by clearing only disposable QA state. Preserve legitimate existing purchases. The Pixel retains normally Play-installed code 44; the original debug app's private backup remains outside the temporary release worktree.

### Revocation and automation qualification follow-up

On October 31, 2026, cached Lifetime access on Play-delivered code 44 survived an offline process restart (three-step replay); Wi-Fi was restored afterward. The owner then refunded the exact no-charge Lifetime QA order with **Remove entitlement** selected. Console confirmed the order refunded. Code 44 still admitted the same installation past the root gate after repeated restarts. A no-data explicit automation export reached `NO_FOLDER_SELECTED` instead of rejecting revoked access; no Health Connect read permissions were granted and no health data was read or exported. These are release blockers, not passing revocation qualification.

The repository regression reproduced a successful empty Play ownership query returning Restore success from the old Lifetime cache. The follow-up candidate uses version code **45**, retaining marketing version **3.5.0**, and reconciles both permanent-access flags on a successful complete query while preserving grandfathered and offline grants. Foreground export, automation, scheduled work, recovery and Direct CLI ask the entitlement repository before admitting work instead of bypassing it with the historical Settings flag. Existing permanent owners must still qualify on the replacement signed build.

The same device automation probe returned default result code `0` to its ordered-broadcast caller. `goAsync()` detaches the receiver's result; asynchronous responses must be written through that invocation's retained `PendingResult` before finishing it. The candidate carries that result explicitly through each automation path, without changing action names, extras or result-code meanings.

Source changes and host tests alone do not qualify code 45. The signed-build results below supersede the corresponding outstanding code-44 cases; retain the code-44 failure evidence. Lifetime's live price and regional mappings remain unchanged; production promotion remains on hold.

### Code-45 device qualification

The annotated [`android/v3.5.0+45` tag](https://github.com/CodyBontecou/health-md/tree/android/v3.5.0%2B45) identifies `a296ffeae821b6f94291ac8fed605d3f32153c5a`. The protected [Internal Testing workflow](https://github.com/CodyBontecou/health-md/actions/runs/41232644269) passed on attempt 2 and committed the internal upload. Its matching intent/upload receipts identify AAB SHA-256 `f2af6bd0fcee02663ca315d259086d72378cb8c9e372f076d31184d751253e47` and the registered upload signer. Attempt 1 exceeded the unchanged portable CI time budget; no gate was relaxed. The exact-source main CI and queued Android native compilation passed. The affected Play host batch passed 109 tests, and seven F-Droid boundary tests passed separately.

The authorized Pixel normally updated from code 44 through Google Play to 3.5.0/code 45, preserving app data and its original installation time. The base plus arm64/English/xxhdpi split delivery and Play app-signing certificate were verified. The checks below used no-charge license-test instruments. During this initial billing-only pass, no Health Connect read permissions were granted and no health data was read or exported; the separately authorized Steps-only follow-up is recorded below.

| Surface | Result |
| --- | --- |
| Refunded Lifetime | The same installation that incorrectly retained access on code 44 returned to the mandatory gate on code 45; the two-step restart regression passed |
| Ordered automation | Revoked access returned result `2`, “Unlock Health.md to run automation exports”; an active Yearly subscription advanced to “No export folder selected,” before health access |
| Returning subscriber offers | $0.99 weekly and $29.99 yearly displayed without trial badges for the ineligible tester; Lifetime remained $19.99 |
| Paid Yearly renewal | The purchase sheet showed the paid $29.99/30-minute test cycle, the intended tester, and a no-charge test instrument. Billing Lab accelerated renewal; Console confirmed a processed recurring test order. Post-renewal restart passed |
| Subscription-only offline restart | With Wi-Fi off and airplane mode on, Play still supplied valid ownership: restart and explicit automation retained access. Wi-Fi was restored. This does not test failed ownership queries or establish an app-defined offline grace period |
| Cancellation before expiry | Canceling the renewed Yearly test preserved access through the displayed paid-through time; restart passed |
| Paid Yearly expiry | The foreground app returned to the mandatory gate after the paid-through time without reset/restart. Restart stayed gated; expired Restore reported no previous purchase, Back/relaunch stayed gated (nine-step replay passed), and automation returned result `2`, “Unlock Health.md to run automation exports” |

The foreground-expiry accessibility wait timed out on a stale hierarchy while the saved visible screen showed the mandatory gate. Retain that failed wait as an automation diagnostic, not a passing replay. The first expired-Restore replay missed its tap; adding a destination wait and post-scroll idle check produced the passing nine-step replay.

Billing Lab's product-response simulator is distinct from ownership verification. Its `queryProductDetailsAsync` error control does not establish a failed `queryPurchasesAsync` result. The attempted product-error override did not affect code 45: the build has no billing-overrides manifest opt-in, which [Google requires for the Response Simulator](https://developer.android.com/google/play/billing/test-response-codes). Product-query failure/explicit retry and failed ownership-query device qualification remain **unrun**; host regressions do not replace them. Adding that test-only opt-in would require a separate non-production build; it must not be added to the production candidate. The simulator was returned to **off**, with **zero** response-code rules, after inspection.

The owner confirmed no device retaining an eligible pre-April-26 installation and no account with an older genuine paid Lifetime purchase are available. True grandfathered-user and existing paid-owner upgrade qualification remain **unrun**; passing cutoff, grandfathered-grant and purchase-restoration host tests do not replace those cases. The initial billing admission probes did not qualify scheduled/recovery/Direct CLI execution or end-to-end exports. The Steps-only scheduled follow-up below narrows that gap; full recovery and Direct CLI workflows remain unrun. Preserve those gaps before any production decision. The original debug installation's private backup remains retained outside the release worktree.


### Code-45 billing-failure and scheduled-export follow-up

The same Play-installed code 45 was tested with no-charge instruments. Actual offline Yearly checkout displayed Google Play's connection error; dismissal and process restart retained the mandatory gate (12-step replay passed). After restoring the original network configuration, an explicit retry with the always-declines test instrument displayed the decline and retained the gate (18-step replay passed). These test real checkout errors, not injected ownership-query failures.

Fourteen focused `BillingRevocationTest` host tests passed with zero failures or errors using `:app:testPlayDebugUnitTest --tests com.healthmd.data.billing.BillingRevocationTest --max-workers=2 --offline --console=plain`. New cases verify that a failed ownership query removes subscription-session access while preserving an independent grandfathered grant, and that product-query failure prevents checkout; explicit catalog recovery restores the returned localized price without unlocking or launching a purchase. These are test-only changes; the signed candidate and release tag remain unchanged.

The owner separately authorized temporary Steps-only and background Health Connect reads, a new local device folder, and one earlier date within the existing access window. All other health permissions stayed denied; notifications and exact-alarm access were not granted. Real WorkManager fallback occurrences verified:

| Scheduled surface | Result |
| --- | --- |
| Background permission missing | The scheduled worker recorded background-access denial before reading health data; history assertion replay passed |
| Empty completed day | The Steps-only local run recorded `NO_HEALTH_CONNECT_DATA` and wrote no file; history assertion replay passed |
| Local file creation | A seven-day completed-day backfill wrote exactly one approved date file; six dates independently confirmed empty were skipped. History reported **1/7 partial**, not a complete seven-day success. Only the Steps metric was enabled, and output stayed on the device |

Health values, file contents and private integrity receipts are excluded from public release evidence. The private backup and diagnostic recordings remain retained.

A separate natural no-charge renewal was forced to decline by changing only that test subscription's primary test instrument. Google Play reported payment declined; a cold launch retained access during grace. After the five-minute sandbox grace interval, a cold launch returned to the mandatory gate and `EXPORT_DATE` for the approved known-empty date returned result `2`, “Unlock Health.md to run automation exports,” with Steps/background permissions still present. The attempted grace-period scheduled rerun produced no separate history entry and is not a passing qualification.

Restore during the post-grace locked state reported no previous purchase; Back and relaunch stayed gated (the existing nine-step Restore regression passed). Billing Lab still labeled the overdue subscription “Active” after refresh, so that label is retained as a tooling limitation rather than used to establish the precise server-side hold state.

A fresh profile's real 17:02 background occurrence recorded `PAYWALL_REQUIRED` / “Unlock required” before health access, despite Steps/background permissions remaining granted; the history assertion replay passed. The approved local file remained the sole output, with unchanged private integrity receipt. Updating only the sandbox primary method to always-approves recovered access on cold launch; Google Play returned to a normal next-renewal display. All QA profile schedules and the legacy automatic schedule were disabled, and the temporary Steps/background grants were revoked. Package/job inspection confirmed zero health grants and zero queued release-app jobs.

The recovered test subscription was canceled; Play confirmed access ends at the displayed paid-through time with no further renewal. The approved device-local output and private debug backup are retained. Full scheduled recovery and Direct CLI workflows, a distinct grace-period scheduled execution, injected device query failures, and unavailable genuine-owner/grandfathered upgrades remain explicitly unqualified. Live Lifetime pricing is unchanged and production promotion remains on hold.
