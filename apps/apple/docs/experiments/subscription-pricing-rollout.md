# Health.md paid-access rollout

> Source integration is authorized for main. Apple, Android production, website and Worker releases remain on hold. Android 3.5.0 Internal Testing preparation and Pixel 7 license-test QA are authorized. The owner applied the Apple Lifetime launch prices (readback November 3, 2026; see [Apple Lifetime cutover](#apple-lifetime-cutover--november-3-2026)). Keep Google Play's Lifetime price unchanged until its own cutover is approved; future price targets in historical proposals are not authorization to apply them. Apple physical-device and multi-account Family Sharing acceptance are deferred.

> Unpublished candidate update: custom in-app analytics and attribution have been removed. Historical analytics below describe earlier builds/services. Essential services remain. Apple Lifetime prices moved to the launch targets on the owner's instruction; Google Play Lifetime is unchanged. Android subscription activation and Internal Testing preparation are recorded below; no production app, website or Worker release is included.

## Status and scope

Owner-approved product policy, implemented in source. **Apple configuration and Google Play draft subscription/trial setup were applied and read back on October 29, 2026.** This is not review approval or an app release. The four new Apple subscriptions are now unsubmitted in `READY_TO_SUBMIT` state, with all four App Review screenshots delivered as `COMPLETE`. Exact-build restore/trial/expiry qualification and first-review preparation remain required before submitting or shipping the hard gate.

Apple readback confirmed all four subscriptions have prices, availability, and one-week free-trial offers in the app's 175 current storefronts. Family subscriptions use native Family Sharing at group level 1; Individual subscriptions use level 2 with Family Sharing disabled. All three approved lifetime IDs, types, family flags, and approval states were preserved. A temporary US Individual/Family Lifetime increase was then rolled back on the owner's instruction to $19.99/$39.99, with all original regional manual price-point mappings restored exactly, and Family Upgrade at $19.99 US. Those Apple Lifetime prices were superseded by the [November 3 cutover](#apple-lifetime-cutover--november-3-2026). Google Play Individual products `health_md_premium_weekly` and `health_md_premium_yearly` were activated on October 30, 2026 (October 31 UTC) for the authorized Android Internal Testing and Pixel 7 license-test work: `weekly`/`yearly` base plans remain $0.99/$29.99 US, and both `trial-7d` offers are **Active**. Each product has one active base plan and one offer across its existing 175-country/region configuration. Both trials retain one seven-day free phase and Play-managed eligibility restricted to users who never had any subscription in this app. Google Play Lifetime remains $19.99 US; all 177 rendered regional pricing/tax/availability rows were identical before and after activation. Android 3.5.0/code 43 is available on Internal Testing from the annotated `android/v3.5.0` source, with matching signed-artifact and committed-upload receipts. The [Android billing guide](../../../android/GOOGLE_PLAY_BILLING_SETUP.md) owns internal-build provenance and pending real-purchase qualification. No Android production promotion occurred.

The group's historical review version `d4f9e67b-02de-4adc-949b-0222c7ba029b` remains reusable: on October 30 Apple accepted it and all four subscription versions into the same unsubmitted draft review `8aaee0b4-a002-479f-a2ec-575446b0a228`. Apple earlier reported that version as `DEVELOPER_REJECTED` and still inflight, and rejected creating a successor. Preserve group `22202004`; no successor, deletion, or forced state transition is needed. The 3.5.0 iOS draft version `5f145ba0-c0b4-441f-9ce5-6e2685c4844d` is `PREPARE_FOR_SUBMISSION` with `MANUAL` release. Its ten existing listing locales now include plans, store-eligible trials, preserved purchase rights, analytics removal, and release notes. Review contact details and reviewer instructions are prepared. Apple requires a processed source-matched 3.5.0 build before the app version can join the draft; never attach an older binary just to satisfy validation. No review has been submitted. Authorized Argent simulator checks verified the Apple hard gate and displayed subscription terms, plus Android's billing-unavailable gate/retry behavior. Apple purchase entry required Apple Account sign-in and was canceled without unlocking; successful purchases, renewals, expiry, restore, and Family Sharing remain unqualified. Both platforms may launch independently, while preparation continues on both.

The same outcome applies on iOS/iPadOS and Google Play Android: a store-backed trial, active subscription, or permanent unlock is required before tracking/setup and exports. No local free-export allowance remains. The macOS companion and F-Droid included-access channel remain free.

The owner selected **3.5.0** as the next iOS/iPadOS and Android phone release version. Source version names and draft release notes are aligned, and the 3.5.0 iOS store draft is prepared; upload-safe build-number checks, exact-build qualification, app-version review attachment, and publication remain separate release gates. Android Wear remains deferred; this alignment does not publish it or synchronize CLI releases.

## Approved US launch targets (live on Apple; Google Play Lifetime pending)

| Audience | Weekly | Yearly | Lifetime |
|---|---:|---:|---:|
| Individual (Apple and Google Play) | $0.99 | $29.99 | $49.99 |
| Apple Family Sharing | $1.99 | $49.99 | $89.99 |

The approved US Family Upgrade launch target is **$40.00**, the difference between Individual Lifetime ($49.99) and Family Lifetime ($89.99). Buying Individual Lifetime at the launch price and later upgrading therefore totals $89.99. This is a fixed-price upgrade, not a calculation based on an owner's historical receipt: older or discounted Individual purchases may have a different combined total. No new regional upgrade-pricing algorithm is approved. Apple's live US upgrade price is $39.99, the nearest Apple price point, so Lifetime plus Upgrade at launch prices totals $89.98.

Eligible subscriptions have a **seven-day free trial**, then auto-renew at the displayed localized price and cadence. Trial eligibility comes from the store; returning/ineligible users see the paid terms without a trial promise. Lifetime is charged immediately and has no trial. Monthly products are not offered.

Apple's Lifetime products now use these launch prices; see [Apple Lifetime cutover](#apple-lifetime-cutover--november-3-2026). Google Play's existing lifetime product stays at $19.99 US, with its regional prices unchanged, until the subscription-containing Android app is in production and the owner explicitly approves that cutover. Until then Android Lifetime intentionally differs from Apple. Draft/unsubmitted subscription product prices may be configured in advance; do not activate, submit, publish, release, or raise existing live prices as a side effect of setup.

These base-price decisions do not approve a new regional pricing algorithm. `docs/pricing-20261025.md` retains the earlier production schedules; a local StoreKit catalog describes launch/test targets and does not change live prices.

### Apple Lifetime cutover — November 3, 2026

The owner updated the Apple Lifetime prices in App Store Connect. An `asc iap pricing summary` readback on November 3, 2026 returned these current US prices:

| Product | Previous US | Current US | US proceeds |
| --- | ---: | ---: | ---: |
| `com.codybontecou.obsidianhealth.unlock` | $19.99 | $49.99 | $42.49 |
| `com.codybontecou.obsidianhealth.unlock.family` | $39.99 | $89.99 | $76.49 |
| `com.codybontecou.obsidianhealth.unlock.family.upgrade` | $19.99 | $39.99 | $33.99 |

Each schedule lists 175 manual territory prices with no start or end date. The readback did not audit non-US price points against the October 25 regional schedule, and it does not record when the owner made the change; use the ASC price history for the effective date. Product IDs, types, Family Sharing flags and `APPROVED` states are unchanged. Google Play's `health_md_premium_lifetime` remains $19.99 US.

## Entitlement preservation

Keep every existing paid-app and lifetime entitlement, including restore/reinstall/device migration and family-shared lifetime transactions. Preserve the previously granted legacy cohort; do not expand the cutoff to all current free installs.

Never rename or replace these Apple non-consumables:

- `com.codybontecou.obsidianhealth.unlock`
- `com.codybontecou.obsidianhealth.unlock.family`
- `com.codybontecou.obsidianhealth.unlock.family.upgrade`

The existing Family Upgrade remains available only to eligible individual lifetime/legacy owners. Its approved US launch target was $40.00; the live US price is $39.99 after the November 3 cutover. Preserve the product ID, eligibility, and all existing Family Upgrade entitlements. Subscription ownership alone does not qualify for that non-consumable upgrade.

Apple restore history fallback is limited to non-consumables. Expired, revoked, and upgraded subscription transactions never create permanent access. Reconcile current entitlements on transaction updates and foregrounding; recheck expiration at export admission.

Android retains `health_md_premium_lifetime` and existing permanent/legacy caches. Only permanent access may populate the historical `isPurchased` flag. Active subscriptions are queried from Play, not cached as lifetime access. Headless exports/automation/recovery/Direct CLI re-query access; failed subscription verification fails closed while existing lifetime caches remain usable. Subscription-only users need Play connectivity after restart; no offline subscription grace is fabricated. The current client-side Billing trust boundary is unchanged; this rollout does not introduce a purchase-verification backend.

## Apple products and family scope

Use a single subscription group so cadence/audience changes do not create parallel subscriptions, with Family at the higher service level and equal levels for weekly/yearly within each audience:

| Plan | Product ID |
|---|---|
| Individual weekly | `com.codybontecou.obsidianhealth.pro.weekly` |
| Individual yearly | `com.codybontecou.obsidianhealth.pro.yearly.v2` |
| Family weekly | `com.codybontecou.obsidianhealth.pro.family.weekly` |
| Family yearly | `com.codybontecou.obsidianhealth.pro.family.yearly.v2` |

The old Individual `pro.yearly` ID was absent from active subscriptions but Apple rejected its reuse as already used. The newly provisioned yearly products therefore use `.v2` IDs, and the app/StoreKit catalog must match them. Existing lifetime IDs are not versioned or replaced. Store subscription IDs are `6828524302` (Individual Weekly), `6828524286` (Individual Yearly), `6828524411` (Family Weekly), and `6828524202` (Family Yearly), all in the existing Health.md Pro group `22202004`.

Enable native Family Sharing only on Family products. No custom account/invite system or Apple-to-Android entitlement transfer is planned. Android is explicitly individual-only because Google Play Family Library does not share subscriptions or in-app purchases and the owner declined custom family infrastructure.

## Deployment and qualification gates

1. Configure draft Apple subscription products/group, seven-day introductory offers, localized descriptions/prices, and Family Sharing; preserve all lifetime IDs and current live price schedules. Do not apply the target lifetime prices until the subscription app changes are live and the owner explicitly approves the coordinated cutover.
2. Configure Play `health_md_premium_weekly` (auto-renewing `P1W` base plan), `health_md_premium_yearly` (`P1Y`), and existing lifetime INAPP. Configure eligible `P7D` free-trial offers on subscriptions. See the [Play billing guide](../../../android/GOOGLE_PLAY_BILLING_SETUP.md).
3. Coordinate retirement of custom analytics with the app/privacy cutover using the [retirement runbook](../../worker/pricing-analytics/README.md). The candidate emits no pricing analytics. Do not restore the historical analytics allowlist as a subscription-launch prerequisite.
4. Qualify fresh install, old free install, legacy paid app, all lifetime restores, eligible/ineligible trials, cancellation, pending purchase, purchase failure, expiry, renewal, refund/revocation, audience/cadence changes, and Family Sharing. Verify foreground and headless admission, including restart and offline behavior.
5. Verify localized store prices, renewal/trial disclosures, Terms/Privacy links, subscription management, accessibility, and hard-gate navigation on both native platforms. Simulator/device/store-sandbox QA requires explicit authorization.
6. Update store listings and customer-facing publications that still advertise free exports or lifetime-only access before release. Follow each component's release synchronization/qualification process; no release or store changes are implied by source edits.

Measure net proceeds per install, trial-to-paid conversion from mature trial cohorts, renewal retention, refunds, and support/review complaints. Starting a free trial is not paid conversion. The previous activation-before-paywall denominator no longer describes the new funnel; segment by app version and storefront rather than combining old/new journeys.

## Local purchase qualification

For a physical sandbox tester on a phone that already has grandfathered access, a Debug build can launch with `-SandboxPurchasesQA`. This process-only switch skips legacy defaults, cached/server-verified legacy grants, and legacy receipt requests/retry accounting. Current verified StoreKit trial, subscription, and non-consumable entitlements still resolve normally. The switch does not erase Keychain rights or app data, and normal launch restores the legacy resolution path. It is excluded from Release builds. This is an Apple StoreKit QA harness, not a change to the shared paid-access policy or evidence of production-binary qualification.

`HealthMdTests/HardPaywallStoreKitTests` exercises the local catalog through the real PurchaseManager and StoreKit APIs; it does not establish Apple sandbox-account, cross-account Family Sharing, or uploaded-build qualification. Use the direct `xcodebuild test` path with the `HealthMd-Tests-iOS` scheme: XcodeBuildMCP's packaged `.xctestproducts` path omitted the scheme's StoreKit environment during qualification and opened a sandbox sign-in sheet instead. The test loader rejects subscription groups other than the local `healthmd-pro` fixture before purchasing.

After the current task's explicit simulator authorization, run from `apps/apple`, selecting an available simulator:

```bash
xcodebuild test -project HealthMd.xcodeproj -scheme HealthMd-Tests-iOS \
  -configuration Debug-iOS -destination 'platform=iOS Simulator,id=<UDID>' \
  -derivedDataPath build/native-verification -resultBundlePath build/purchase-tests.xcresult \
  -collect-test-diagnostics never -parallel-testing-enabled NO -jobs 2 \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  -only-testing:HealthMdTests/HardPaywallStoreKitTests \
  -only-testing:HealthMdTests/PurchaseManagerTests
```

Use a fresh result-bundle path on each run. The explicit arm64 selection matches the native queue's reduced Rust artifacts. Renewal/expiry uses StoreKit's accelerated renewal clock; forcing renewal and then force-expiring it left the old future expiry visible in `Transaction.currentEntitlements`, despite the test fixture reporting expiration. Do not treat that control sequence as an actual expired entitlement or weaken the app's expiry assertions.

## Historical context

The earlier iOS 3.0 subscription proposal was canceled. It proposed individual monthly/yearly/lifetime at $4.99/$24.99/$59.99 and Family at $7.99/$39.99/$89.99; subscriptions never went live. The verified October 25 one-time US schedules were $19.99 Individual, $39.99 Family, and $19.99 Family Upgrade. Neither historical proposal nor these development files establish current deployed subscription availability.

## Current working-checkout qualification — October 30 UTC

The owner confirmed weekly/yearly subscriptions and deferred Vox Android. These checks qualify the local candidate, including its uncommitted changes; they do not certify committed main, an uploaded binary, Apple sandbox accounts, cross-account Family Sharing, or a physically paired Watch.

- Health.md: 24 purchase-policy/local StoreKit tests, five mandatory-root-wall UI tests and four onboarding/import/first-preview UI journeys passed. Twenty focused Android billing/offer/admission tests passed; queued Apple and Android compilation passed.
- Whereday: 17 purchase/StoreKit tests and eight Watch queue/reconnect regressions passed. Restore uses the actual restore path; separate fresh-user cases prove cancellation and network-failed restore cannot grant tracking. These are local StoreKit and synthetic Watch tests.
- Current-source and submitted-build provenance must be reconciled before release. Keep the first-paid Whereday cutoff at 51. (At the time of these checks, Lifetime price schedules were held unchanged; Apple's later moved in the November 3 cutover.)
