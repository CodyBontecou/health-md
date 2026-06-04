# Health.md $14.99 Lifetime Price Experiment

## Status

- Results status: $14.99 price schedule active from 2026-06-02; results pending.
- Linear issue: ISO-294
- App Store Connect app ID: `6757763969`
- IAP ID: `6761057963`
- Product ID: `com.codybontecou.obsidianhealth.unlock`
- Baseline price: USD $9.99 (`USA` price point `10127`, estimated proceeds USD $8.49)
- $14.99 test price: USD $14.99 (`USA` price point `10152`, estimated proceeds USD $12.74)
- Variant ID: `test_lifetime_1499`
- Free-export limit remains 3 for the full baseline and test windows.
- App Store Connect price schedule created at 2026-06-01T15:50:09Z and verified at 2026-06-01T15:51:13Z.
- Scheduled equalized pricing spot-checked for `USA`, `GBR`, `CAN`, and `DEU`; all show effective date 2026-06-02.
- Because the shipped app still emits `baseline_lifetime_current`, analyze this sequential test by UTC price-window timestamps, not by `variant_id`.

The App Store Connect price change was scheduled only after the production
analytics baseline was verified and recorded through the
[pricing analytics worker](./pricing-analytics-worker.md). Analytics, remote
config, or transport failures must not block onboarding, HealthKit authorization,
preview, export, paywall display, purchase, restore, entitlement, or quota
behavior.

## Baseline window

Earliest calendar plan, if pricing analytics verification is complete before the
window opens:

- Baseline window: 2026-05-18 00:00 UTC through 2026-05-31 23:59 UTC.
- If analytics verification completes after 2026-05-18, shift the baseline to
  the next full UTC day and keep a 14-day baseline.
- Record the actual baseline start/end timestamps before any App Store Connect
  pricing edit.

Minimum sample:

- At least 100 activated users in the baseline window.
- At least 25 paywall views in the baseline window.
- If the 14-day window misses either event-count target, extend up to 28 total
  days and mark the read as underpowered if the target is still missed.

Activation definition:

- Activated user = a user/install counted by the analytics export after
  `pricing_export_preview_generated` or `pricing_export_succeeded`.
- Do not use raw HealthKit values, metric names, dates, file paths, vault names,
  peer device names, medication names, workout details, or exported text in any
  export or dashboard filter.

## $14.99 test window

Earliest calendar plan, only after the baseline is recorded:

- $14.99 test window: 2026-06-02 00:00 UTC through 2026-06-15 23:59 UTC.
- If the baseline shifts, start the $14.99 window on the next full UTC day after
  the recorded baseline closes and keep a 14-day test.
- Record the actual $14.99 start/end timestamps and App Store Connect change
  timestamp in this note before making the keep/revert/test-$19.99 decision.

Minimum sample:

- At least 100 activated users in the $14.99 window.
- At least 25 paywall views in the $14.99 window.
- If the 14-day window misses either event-count target, extend up to 28 total
  days and mark the read as underpowered if the target is still missed.

## Metrics and Query

Required event inputs:

- `pricing_export_preview_generated`
- `pricing_export_succeeded`
- `pricing_paywall_shown`
- `pricing_purchase_started`
- `pricing_purchase_finished`
- App Store Connect proceeds/refunds for `com.codybontecou.obsidianhealth.unlock`

Dashboard/export query requirements:

- Activated users per window = unique analytics users/installs with
  `pricing_export_preview_generated` or `pricing_export_succeeded`.
- Paywall views per activated user = `pricing_paywall_shown` count divided by
  activated users.
- Purchase conversion per paywall view = successful `pricing_purchase_finished`
  count divided by `pricing_paywall_shown` count.
- Net revenue per activated user = App Store Connect proceeds minus refunds for
  the product/window, divided by activated users in the same window.
- Decision uses `net revenue per activated user`, not raw conversion alone.

Minimum export columns:

```text
window_name
window_start_utc
window_end_utc
activated_users
paywall_views
successful_purchases
gross_proceeds_usd
refunds_usd
net_revenue_usd
paywall_views_per_activated_user
purchase_conversion_per_paywall_view
net_revenue_per_activated_user
support_message_count
refund_count
rating_average
review_count
paywall_complaint_count
```

Formula checks:

```text
net_revenue_usd = gross_proceeds_usd - refunds_usd
net_revenue_per_activated_user = net_revenue_usd / activated_users
paywall_views_per_activated_user = paywall_views / activated_users
purchase_conversion_per_paywall_view = successful_purchases / paywall_views
```

## Quality Gates

Check these before keeping $14.99:

- Support messages mentioning price, paywall, export quota, purchases, restore,
  refunds, or confusion.
- refunds and refund rate for the lifetime unlock.
- ratings/reviews during the baseline and $14.99 windows.
- paywall complaints in support, reviews, Discord, GitHub, and any feedback
  inbox used for Health.md.

Keep $14.99 only if:

- Net revenue per activated user improves materially versus baseline.
- Refund/support/review/paywall complaint signals do not degrade materially.
- Free-export behavior remains unchanged at 3 successful export actions.

Revert if:

- Net revenue per activated user falls versus baseline.
- Refund/support/review/paywall complaint signals degrade materially.
- StoreKit price propagation or purchase/restore behavior becomes ambiguous.

Only test $19.99 after:

- $14.99 is clearly healthy by net revenue per activated user.
- Quality signals remain healthy.
- A new follow-up ticket documents the next sequential test.

## App Store Connect change steps

Before changing price:

1. Confirm ISO-289 through ISO-293 are complete.
2. Confirm production/TestFlight analytics events are visible in D1 via Wrangler
   for the shipped event names listed above.
3. Export and attach the baseline metrics table.
4. Record the current App Store Connect price schedule for
   `com.codybontecou.obsidianhealth.unlock`.
5. Confirm `PurchaseManager.freeExportLimit` is still `3`.
6. Confirm the app paywall and onboarding use StoreKit `displayPrice` when
   available and a price-agnostic fallback when unavailable.

CLI-oriented price change outline:

```bash
asc iap pricing summary --iap-id "IAP_ID" --territory "USA"
asc iap pricing schedules create --iap-id "IAP_ID" --base-territory "USA" --price "14.99" --start-date "YYYY-MM-DD"
asc iap pricing summary --iap-id "IAP_ID" --territory "USA"
```

Manual App Store Connect outline:

1. Open the Health.md app in App Store Connect.
2. Open the non-consumable in-app purchase for
   `com.codybontecou.obsidianhealth.unlock`.
3. Record the existing price schedule and storefront status.
4. Set the next price schedule to USD $14.99 from the agreed test start date.
5. Verify the product still resolves through StoreKit and the app displays the
   live StoreKit price.

## Rollback steps

Rollback trigger:

- Revenue per activated user underperforms baseline.
- Refund/support/review/paywall complaint signals degrade.
- Purchase or restore behavior is unclear after the price change.

Rollback procedure:

1. Record the trigger and decision timestamp in this note.
2. Reopen App Store Connect or use `asc iap pricing`.
3. Restore the previous price schedule captured before the experiment.
4. Verify the StoreKit product loads and the app displays the live reverted
   price through `displayPrice`.
5. Keep the free-export limit at 3.
6. Export post-rollback metrics for the first 48 hours.

CLI-oriented rollback outline:

```bash
asc iap pricing summary --iap-id "IAP_ID" --territory "USA"
asc iap pricing schedules create --iap-id "IAP_ID" --base-territory "USA" --price "PREVIOUS_PRICE" --start-date "YYYY-MM-DD"
asc iap pricing summary --iap-id "IAP_ID" --territory "USA"
```

## Results Log

Fill this section when data is available.

```text
Baseline actual start: 2026-05-18T00:00:00Z
Baseline actual end: 2026-06-01T00:00:00Z
Baseline active installs: 314
Baseline new first-seen installs: 313
Baseline activated users: 203
Baseline paywall views: 146
Baseline paywall users: 97
Baseline D1 successful purchases: 35
Baseline App Store sales report paid IAP units: 47
Baseline App Store sales report refund units: 0
Baseline net revenue: pending FX-normalized App Store proceeds export
Baseline net revenue per activated user: pending FX-normalized App Store proceeds export

$14.99 App Store Connect schedule created: 2026-06-01T15:50:09Z
$14.99 App Store Connect schedule verified: 2026-06-01T15:51:13Z
$14.99 actual start: 2026-06-02T00:00:00Z
$14.99 actual end: 2026-06-16T00:00:00Z
$14.99 activated users:
$14.99 paywall views:
$14.99 successful purchases:
$14.99 net revenue:
$14.99 net revenue per activated user:

Support messages:
refunds: baseline sales report shows 0 refund units for 2026-05-18 through 2026-05-31.
ratings/reviews: App Store Connect ratings check on 2026-06-01 showed 5.0 average, 10 US ratings, 3 visible reviews, no price complaints in visible reviews.
paywall complaints:

Decision: $14.99 scheduled; keep/revert decision pending test-window read.
Follow-up Linear issue:
Project/wiki update link:
```
