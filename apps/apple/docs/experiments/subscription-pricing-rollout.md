# Health.md paid-access rollout

> Source integration is authorized for main. App/website/Worker releases remain on hold. Keep current Lifetime prices unchanged; future price targets in historical proposals are not authorization to apply them. Physical-device and multi-account Family Sharing acceptance are deferred.

> Unpublished candidate update: custom in-app analytics and attribution have been removed. Historical analytics below describe earlier builds/services. Essential services remain. Prices are unchanged; nothing is deployed, submitted, or released.

## Status and scope

Owner-approved product policy, implemented in source. **Apple configuration and Google Play draft subscription/trial setup were applied and read back on October 29, 2026.** This is not review approval or an app release. The four new Apple subscriptions are now unsubmitted in `READY_TO_SUBMIT` state, with all four App Review screenshots delivered as `COMPLETE`. Exact-build restore/trial/expiry qualification and first-review preparation remain required before submitting or shipping the hard gate.

Apple readback confirmed all four subscriptions have prices, availability, and one-week free-trial offers in the app's 175 current storefronts. Family subscriptions use native Family Sharing at group level 1; Individual subscriptions use level 2 with Family Sharing disabled. All three approved lifetime IDs, types, family flags, and approval states were preserved. The temporary US Individual/Family Lifetime increase was rolled back on the owner's instruction: live prices are $19.99/$39.99, with all original regional manual price-point mappings restored exactly. Family Upgrade remains $19.99 US. Google Play Individual products `health_md_premium_weekly` and `health_md_premium_yearly` now have draft `weekly`/`yearly` base plans at $0.99/$29.99 US and draft `trial-7d` offers. All four plan/offer rows remain **Draft**, and both products have zero active base plans. The trials have one seven-day free phase and Play-managed eligibility restricted to users who never had any subscription in this app. Console lists 175 countries/regions per draft plan/offer. The existing Google Play Lifetime product remains $19.99 US; its complete rendered regional pricing/tax/availability table was identical before and after draft setup. No activation, review submission, publication, or release occurred.

Apple preparation also confirmed the existing group's historical review version remains `DEVELOPER_REJECTED` and still counts as inflight; Apple rejected creating a successor. Preserve group `22202004` and reconcile its supported resubmission path with the new app version rather than deleting/recreating the group or forcing a state transition. No new rollout app version, review-item attachment, or submission was created. Authorized Argent simulator checks verified the Apple hard gate and displayed subscription terms, plus Android's billing-unavailable gate/retry behavior. Apple purchase entry required Apple Account sign-in and was canceled without unlocking; successful purchases, renewals, expiry, restore, and Family Sharing remain unqualified. Both platforms may launch independently, while preparation continues on both.

The same outcome applies on iOS/iPadOS and Google Play Android: a store-backed trial, active subscription, or permanent unlock is required before tracking/setup and exports. No local free-export allowance remains. The macOS companion and F-Droid included-access channel remain free.

The owner selected **3.5.0** as the next iOS/iPadOS and Android phone release version. Source version names and draft release notes are aligned; store version creation, upload-safe build-number checks, exact-build qualification, and publication remain separate release gates. Android Wear remains deferred; this alignment does not publish it or synchronize CLI releases.

## Approved US launch targets (not current lifetime prices)

| Audience | Weekly | Yearly | Lifetime |
|---|---:|---:|---:|
| Individual (Apple and Google Play) | $0.99 | $29.99 | $49.99 |
| Apple Family Sharing | $1.99 | $49.99 | $89.99 |

The approved US Family Upgrade launch target is **$40.00**, the difference between Individual Lifetime ($49.99) and Family Lifetime ($89.99). Buying Individual Lifetime at the launch price and later upgrading therefore totals $89.99. This is a fixed-price upgrade, not a calculation based on an owner's historical receipt: older or discounted Individual purchases may have a different combined total. No new regional upgrade-pricing algorithm is approved. The existing live upgrade price remains $19.99 until the coordinated cutover is explicitly approved after the subscription-containing app is live.

Eligible subscriptions have a **seven-day free trial**, then auto-renew at the displayed localized price and cadence. Trial eligibility comes from the store; returning/ineligible users see the paid terms without a trial promise. Lifetime is charged immediately and has no trial. Monthly products are not offered.

These are US launch targets, not authorization to change existing live pricing before the subscription-containing app is live. Keep current Apple lifetime pricing ($19.99 Individual, $39.99 Family, $19.99 Upgrade) and all existing regional overrides unchanged until the owner-authorized subscription launch is live and the coordinated price cutover is explicitly approved. The same hold applies to Google Play's existing lifetime product. Draft/unsubmitted subscription product prices may be configured in advance; do not activate, submit, publish, release, or raise existing live prices as a side effect of setup.

These base-price decisions do not approve a new regional pricing algorithm. `docs/pricing-20261025.md` retains the original production schedules; a local StoreKit catalog describes launch/test targets and does not change live prices.

## Entitlement preservation

Keep every existing paid-app and lifetime entitlement, including restore/reinstall/device migration and family-shared lifetime transactions. Preserve the previously granted legacy cohort; do not expand the cutoff to all current free installs.

Never rename or replace these Apple non-consumables:

- `com.codybontecou.obsidianhealth.unlock`
- `com.codybontecou.obsidianhealth.unlock.family`
- `com.codybontecou.obsidianhealth.unlock.family.upgrade`

The existing Family Upgrade remains available only to eligible individual lifetime/legacy owners. Its approved US launch target is $40.00, but its existing live $19.99 price and regional overrides remain unchanged until the separately approved coordinated cutover. Preserve the product ID, eligibility, and all existing Family Upgrade entitlements. Subscription ownership alone does not qualify for that non-consumable upgrade.

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

The old Individual `pro.yearly` ID was absent from active subscriptions but Apple rejected its reuse as already used. The newly provisioned yearly products therefore use `.v2` IDs, and the app/StoreKit catalog and analytics allowlist must match them. Existing lifetime IDs are not versioned or replaced. Store subscription IDs are `6828524302` (Individual Weekly), `6828524286` (Individual Yearly), `6828524411` (Family Weekly), and `6828524202` (Family Yearly), all in the existing Health.md Pro group `22202004`.

Enable native Family Sharing only on Family products. No custom account/invite system or Apple-to-Android entitlement transfer is planned. Android is explicitly individual-only because Google Play Family Library does not share subscriptions or in-app purchases and the owner declined custom family infrastructure.

## Deployment and qualification gates

1. Configure draft Apple subscription products/group, seven-day introductory offers, localized descriptions/prices, and Family Sharing; preserve all lifetime IDs and current live price schedules. Do not apply the target lifetime prices until the subscription app changes are live and the owner explicitly approves the coordinated cutover.
2. Configure Play `health_md_premium_weekly` (auto-renewing `P1W` base plan), `health_md_premium_yearly` (`P1Y`), and existing lifetime INAPP. Configure eligible `P7D` free-trial offers on subscriptions. See the [Play billing guide](../../../android/GOOGLE_PLAY_BILLING_SETUP.md).
3. Deploy the pricing analytics allowlist before the app emits the new weekly and `.v2` yearly Apple IDs. No health payloads, paths, credentials, or request logging may be added.
4. Qualify fresh install, old free install, legacy paid app, all lifetime restores, eligible/ineligible trials, cancellation, pending purchase, purchase failure, expiry, renewal, refund/revocation, audience/cadence changes, and Family Sharing. Verify foreground and headless admission, including restart and offline behavior.
5. Verify localized store prices, renewal/trial disclosures, Terms/Privacy links, subscription management, accessibility, and hard-gate navigation on both native platforms. Simulator/device/store-sandbox QA requires explicit authorization.
6. Update store listings and customer-facing publications that still advertise free exports or lifetime-only access before release. Follow each component's release synchronization/qualification process; no release or store changes are implied by source edits.

Measure net proceeds per install, trial-to-paid conversion from mature trial cohorts, renewal retention, refunds, and support/review complaints. Starting a free trial is not paid conversion. The previous activation-before-paywall denominator no longer describes the new funnel; segment by app version and storefront rather than combining old/new journeys.

## Historical context

The earlier iOS 3.0 subscription proposal was canceled. It proposed individual monthly/yearly/lifetime at $4.99/$24.99/$59.99 and Family at $7.99/$39.99/$89.99; subscriptions never went live. The verified October 25 one-time US schedules were $19.99 Individual, $39.99 Family, and $19.99 Family Upgrade. Neither historical proposal nor these development files establish current deployed subscription availability.

## Current working-checkout qualification — October 30 UTC

The owner confirmed weekly/yearly subscriptions and deferred Vox Android. These checks qualify the local candidate, including its uncommitted changes; they do not certify committed main, an uploaded binary, Apple sandbox accounts, cross-account Family Sharing, or a physically paired Watch.

- Health.md: 24 purchase-policy/local StoreKit tests, five mandatory-root-wall UI tests and four onboarding/import/first-preview UI journeys passed. Twenty focused Android billing/offer/admission tests passed; queued Apple and Android compilation passed.
- Whereday: 17 purchase/StoreKit tests and eight Watch queue/reconnect regressions passed. Restore uses the actual restore path; separate fresh-user cases prove cancellation and network-failed restore cannot grant tracking. These are local StoreKit and synthetic Watch tests.
- Current-source and submitted-build provenance must be reconciled before release. Keep the first-paid Whereday cutoff at 51 and existing Lifetime price schedules unchanged.
