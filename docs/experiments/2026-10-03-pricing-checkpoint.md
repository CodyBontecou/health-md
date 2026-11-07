# $19.99 lifetime pricing checkpoint — October 3, 2026

This is an interim read of the [ongoing price experiment](./2026-09-17-19.99-lifetime-price.md). The first planned decision remains no earlier than October 8. No production price or experiment setting changed during this analysis.

## Commerce evidence and reporting window

App Store Connect reads retrieved on **2026-10-03, approximately 13:15 UTC** using `asc` 5.9.2 with `ASC_READ_ONLY=1`. Source app: `6757763969`; existing ongoing analytics request: `601e9f5f-fbdc-499a-abc4-5348e254f915`; selected report: **App Store Purchases Standard**, `r12-601e9f5f-fbdc-499a-abc4-5348e254f915`. Only standard aggregate reports were downloaded; customer review text and customer identifiers were not displayed or retained in this note.

The latest daily report processing date is **October 3**. Its sales dates are October 1 and October 2. October 1 is the latest complete sales day under Apple's two-day completeness rule; October 2 remains provisional. App Analytics dates use UTC. The principal comparison therefore uses **September 2–16 versus September 17–October 1**, two complete 15-day windows. [Purchase report definitions](https://developer.apple.com/documentation/analytics-reports/app-store-purchase), [reporting timezones](https://developer.apple.com/help/app-store-connect/measure-app-performance/differences-in-reporting-tools/).

Daily data was selected by the report's `Date` column, retaining the latest `processingDate` for each date and combining all segments within that instance. Later date batches replace earlier batches; they were not added together. Every daily processing instance from September 2 through October 3 was retrieved. Zero-sales dates have no purchase rows. August was selected by `Date = 2026-08-01` from the monthly instance processed September 5; that instance also contains other historical months, which were excluded. [Apple's completeness and correction rules](https://developer.apple.com/documentation/analytics-reports/data-completeness-corrections).

Amounts below use the report's **USD** columns across all territories, avoiding the addition of different local currencies. Proceeds are developer proceeds after Apple's commission and applicable taxes, estimated in USD; they are not final settled bank payments. Negative refund rows are already included in net totals and must not be subtracted twice. [Purchase report definitions](https://developer.apple.com/documentation/analytics-reports/app-store-purchase), [final financial reports](https://developer.apple.com/help/app-store-connect/getting-paid/download-financial-reports).

## Deployed US prices

Live `asc iap pricing summary --app 6757763969 --territory USA` and the individual price schedule confirm these current prices:

| Product | Content Apple ID | Customer price (USD) | Estimated US proceeds per unit |
| --- | --- | ---: | ---: |
| Individual lifetime | `6761057963` | $19.99 | $16.99 |
| Family lifetime | `6780235271` | $39.99 | $33.99 |
| Family upgrade | `6781658621` | $20.00 | $17.00 |

The September 17 ASC change date is documented in the [original experiment note](./2026-09-17-19.99-lifetime-price.md). The current schedule read exposes the current price, without reconstructing the creation time. Actual US individual sales include one $14.99 purchase on September 17; subsequent observed US individual purchases from September 18 onward are $19.99. Treat September 17 as a transition day rather than assuming every purchase that day used the new price.

## Complete commerce comparison

All purchase rows in these windows, including August, identify **iPhone** as the device. These totals therefore match the iOS consumer scope; no macOS or Android commerce is included.

| Metric | Sep 2–16, $14.99 period | Sep 17–Oct 1, $19.99 period | Change |
| --- | ---: | ---: | ---: |
| Gross purchases | 33 | 30 | −9.1% |
| Observed refunded units | 0 | 1 | +1 |
| Net units | 33 | 29 | −12.1% |
| Gross consumer sales, USD | $612.47 | $693.10 | +13.2% |
| Refund sales, USD | $0.00 | $22.08 | — |
| Net consumer sales, USD | $612.47 | $671.02 | +9.6% |
| Gross developer proceeds, USD | $465.89 | $550.84 | +18.2% |
| Refund proceeds, USD | $0.00 | $19.29 | — |
| **Net developer proceeds, USD** | **$465.89** | **$531.55** | **+14.1%** |

The observed refund belongs to the individual product. Reports do not establish that the refunded purchase originated in this experiment window, so this is an observed-period refund count rather than a new-customer cohort refund rate. No partial-refund rows were observed.

| Product | Sep 2–16 gross / refund units | Sep 2–16 net proceeds | Sep 17–Oct 1 gross / refund units | Sep 17–Oct 1 net proceeds |
| --- | ---: | ---: | ---: | ---: |
| Individual | 30 / 0 | $404.66 | 28 / 1 | $463.57 |
| Family | 3 / 0 | $61.23 | 2 / 0 | $67.98 |
| Family upgrade | 0 / 0 | $0.00 | 0 / 0 | $0.00 |

Territory mix also changed. US individual purchases rose from 5 to 12; the remaining individual purchases fell from 25 to 16. The sample covers 16 territories before and 13 afterward. Price, currency conversion, taxes, territory mix, product mix, and onboarding changes all affect proceeds per unit; this before/after read does not isolate the causal price effect.

## August baseline and provisional October 2

The August monthly report confirms **72 gross purchases**, no observed refunds, **$1,255.83 consumer sales** and **$978.79 developer proceeds**, all in estimated USD. Its product totals are 64 individual purchases / $832.22 proceeds, 6 family purchases / $131.00 proceeds, and 2 upgrades / $15.57 proceeds. This reproduces the approximately $979 baseline recorded at experiment launch.

Including provisional October 2 gives a 16-day current window of September 17–October 2: **34 gross purchases, 1 refund, 33 net units, $615.80 gross proceeds and $596.51 net proceeds**. October 2 adds 4 individual purchases and $64.96 proceeds so far. The equal-length September 1–16 window has **37 purchases, no refunds and $531.22 proceeds**. Do not substitute this provisional window for the complete comparison without labeling the reporting lag.

## Quality checks and limitations

The complete weekly purchase report processed October 2, covering September 21–27, exactly matches the corresponding reconstructed daily totals: 7 purchases, $167.62 sales and $128.00 proceeds. This provides an independent aggregation check.

Aggregate written App Store reviews: September 1–16 has 2 reviews (one 1-star and one 5-star); September 17–October 2 has no written reviews. All review pages were covered. The sample is too small to establish a satisfaction change. Support burden was not assessed.

Sales and Trends / settled financial reports were not retrieved because the local ASC vendor-number configuration is empty. This did not block the standard purchase analytics reports used here. Final payouts may differ from the estimated USD proceeds. September's monthly purchase report is not expected until October 5 under Apple's normal schedule. No Android store commerce was queried, so this checkpoint does not evaluate Android pricing.

## Pricing funnel and decision metric

Read-only aggregate queries against D1 `health-md-pricing-analytics` were retrieved on October 3 using Wrangler 4.120.1 and the configured pricing database. The main windows use Worker `received_at` in UTC: September 2 inclusive to September 17 exclusive, and September 17 inclusive to October 2 exclusive. Only coarse allowlisted pricing fields were queried; no health content or raw installation IDs were returned. Source definitions and service configuration: [pricing Worker runbook](../../apps/apple/worker/pricing-analytics/README.md), [schema](../../apps/apple/worker/pricing-analytics/migrations/0001_pricing_events.sql), and reviewed onboarding query (removed; see `b8ded3597:apps/apple/worker/pricing-analytics/queries/onboarding-funnel.sql`).

The reviewed onboarding query was run first for the general platform/build picture. Its exact-version join is useful for release segmentation but can omit later purchases following an app update. The custom mature-cohort comparison below instead follows an installation across versions.

| iOS metric | Sep 2–16 | Sep 17–Oct 1 | Change |
| --- | ---: | ---: | ---: |
| Activated installs: preview generated or export succeeded | 306 | 339 | +10.8% |
| Saved-export installs | 278 | 307 | +10.4% |
| Distinct paywall users | 135 | 132 | −2.2% |
| Paywall views (`pricing_paywall_shown`) | 205 | 184 | −10.2% |
| Successful purchase events / distinct purchasers | 29 / 29 | 28 / 28 | −3.4% |
| Purchasers / paywall views, historical decision ratio | 14.1% | 15.2% | +1.1 percentage points |
| Purchasers / paywall users, descriptive period ratio | 21.5% | 21.2% | −0.3 percentage points |
| **Reported net proceeds / activated install** | **$1.52** | **$1.57** | **+3.0%** |

The revenue calculation is `$465.89 / 306 = $1.5225` versus `$531.55 / 339 = $1.5680`. It is a calendar-period monetization measure, not new-user lifetime value or a causal estimate. The numerator includes purchases/refunds from earlier installs, while the denominator includes returning paid users and previews. Purchaser-to-paywall ratios are also period ratios; they do not establish that each purchaser saw a paywall in the same window. Lower repeated view frequency partly explains the improved per-view ratio.

D1 successful purchase responses differ from ASC gross paid units: 29 versus 33 before, and 28 versus 30 afterward. The event table deduplicates event delivery but contains neither transaction identifiers nor complete refund/revocation state. Use ASC for commerce; do not impute missing sales from D1 or subtract the refund again.

Legacy rows without a platform contribute one extra paywall view in each 15-day window and no additional activated install or purchaser. Deduplicating `ios` plus missing-platform records leaves the primary counts unchanged, with historical view ratios 29/206 = 14.1% and 28/185 = 15.1%. In August, this combined Apple activation count is 511 rather than iOS-only 510; `$978.79 / 511 = $1.92` rounded, consistent with the recorded target. Explicit macOS events do not contain activation/purchase outcomes in these windows. Android's zero outcome counts are missing instrumentation, not evidence of zero conversion.

All observed Apple build segments remain `baseline_lifetime_only`; this is a sequential store-price comparison, not a randomized A/B test. Version 3.4.2 contributes 26 of the 28 current in-app successful purchases. Its onboarding and soft prompts shipped alongside the price change, so their effects cannot be separated from price using this checkpoint. Distinct counts overlap across versions and must not be summed.

## Mature new-user cohort check

Each installation's first recorded `pricing_onboarding_started` across available history defines its cohort; only first-start rows explicitly labeled iOS are included. Follow-up joins use installation and platform, preserving events after app updates. Seven-day purchase rates include only starts at least seven full days before the October 2 cutoff. Windows use receipt time, so offline delivery can blur price/date boundaries. This is a known-instrumentation install cohort, not an account-level cohort.

| Cohort measure | Sep 2–16 starts | Sep 17–Oct 1 starts |
| --- | ---: | ---: |
| First recorded iOS starters | 132 | 123 |
| Saved an export within 24 hours | 73 (55.3%) | 70 (56.9%) |
| Seven-day-mature starters | 132 | 71 |
| Purchased within seven days | 24 / 132 (18.2%) | 10 / 71 (14.1%) |
| Approximate 95% Wilson interval for seven-day purchase rate | 12.5–25.6% | 7.8–24.0% |

The new-user purchase rate is lower descriptively, but these samples do not establish a decline. Do not divide 10 mature purchases by all 123 starters: 52 had not yet completed their observation window. Differences in acquisition, build, product experience, and reporting time still prevent a causal interpretation.

## Historical three-export comparison

A follow-up read on October 3 uses June 1–30 as a clean full month with the $14.99 lifetime price and three free exports. Aggregating iOS plus legacy missing-platform Apple events gives 457 activated installs, 405 paywall users, 601 paywall views, and 86 successful purchasers. All 601 paywall events carry a quota-state sum of three. Purchasers/views is **14.3%**; views/activated is **1.32**. The current explicit-iOS September 17–October 1 ratios are **15.2%** (28/184) and **0.54** (184/339), respectively. Legacy missing-platform current rows add one view and no purchaser/activation, giving 15.1% and 0.55 on the fully combined scope.

Current purchase responses per view are similar to June. The raw views/activated comparison is about 59% lower, but compares 30 June days with 15 current days. Repeated views accumulate while activated installations are deduplicated per window, so that percentage is not a matched-window estimate. Different prices, acquisition, builds, and onboarding also prevent attributing the exposure difference solely to free allowance. The earlier May 18–31 $9.99/three-export period has 35 purchasers / 146 views = 24.0%, but its launch cohort is a weaker comparison.

Equal 15-day windows confirm lower exposure at a smaller or similar scale. These rows consistently include explicit iOS and legacy missing-platform Apple records:

| Window | Activated installs | Paywall views | Views / activated |
| --- | ---: | ---: | ---: |
| June 1–15, three exports | 319 | 346 | 1.08 |
| June 16–30, three exports | 254 | 255 | 1.00 |
| July 6–20, three exports | 294 | 334 | 1.14 |
| September 17–October 1, current builds | 339 | 185 | 0.55 |

The matched historical comparisons imply roughly 46–52% lower views per activated installation. This remains an observational frequency comparison, not a causal quota result. In July 6–20 versus the current window, onboarding paywall views fall 174 → 96, Settings views 108 → 72, and export/Connected Mac/Shortcut gate views 52 → 8; nine new soft-prompt paywall views partially offset that decline. Recorded onboarding starters also fall 225 → 123 while activated installations rise 294 → 339. The latter count includes returning and paid users, so neither it nor the difference between these sets identifies the free-user population. Full-June onboarding-start cohorts are unavailable because that instrumentation was introduced June 18.

The broader June 1–July 26 period has 183 distinct purchasers, 185 successful purchase events, and 1,311 paywall views: 14.0% using distinct purchasers. July 1–5 includes the failed subscription configuration and should not be treated as a clean pricing experience. The historical 13.9% recorded for June 1–September 16 also mixes three- and ten-export periods. July 27 identifies the source quota change; deployed versions can retain the earlier allowance after that date. For quota attribution, use recorded quota/build evidence rather than assuming all users switched on one calendar day.

Source history identifies three pertinent product changes. Commit `b0d72b77d` raises the quota on July 27; tag `v3.0.2` still has three and `v3.0.3` has ten (tagged August 1; changelog dated July 31). In 3.4.2, the unlock screen with a Continue Free option moved out of onboarding and became a dismissible, once-per-install offer after the first real preview closes. Soft reminders after exports three and seven were added in the same release. See the [3.4.2 release notes](../../apps/apple/CHANGELOG.md), [current offer timing](../../apps/apple/docs/features/full-access-unlock.md), and [pricing rollout caveats](./2026-09-17-19.99-lifetime-price.md). Code/release preparation dates do not prove exact App Store availability.

## Free allowance and soft prompts

In the complete current window, **7 distinct iOS installations** recorded a quota-blocked export, versus 8 previously. This does not estimate the share of free users exhausting their allowance: the overall activated denominator includes paid and returning users. It also counts only attempted blocked exports, not every installation that reached its tenth success.

Current paywall views are 95 from onboarding, 72 from Settings, 8 from quota-triggered Export/Connected Mac contexts, and 9 from soft upgrade prompts. Successful purchase contexts are 10 onboarding, 12 Settings, 2 quota contexts, and 4 soft prompts. These are recorded attribution contexts, not causal purchase lift.

Soft prompts reached 44 distinct installs with 54 displays; 8 installs tapped Upgrade, and 4 recorded a successful purchase with the upgrade-prompt context. The third-export prompt was shown to 37 installs; the seventh-export prompt to 16. Those groups overlap, and an additional delayed display carried usage count 8. This supports investigating an earlier paid boundary, but does not show that reducing the allowance would increase net proceeds or preserve activation.

## Interim decision

**Continue the current $19.99 price and ten-export allowance through the planned review.** Complete-day net proceeds increased 14.1%, but proceeds per activated install improved only 3.0%. At $1.57, the primary metric remains below the $1.92 keep-price threshold and above the $1.50 revert threshold. The historical per-view purchase ratio exceeds the approximately 11% guardrail. Quality evidence is limited to one observed refund and very sparse written reviews; support burden remains unassessed.

This is an inconclusive checkpoint, not a keep/revert decision and not evidence to raise the price. Finish the current observation window before testing a five-versus-ten allowance. Re-read complete reporting days and mature cohorts on or after October 8; because purchase analytics complete with a two-day lag, 21 complete days from September 17 will be available no earlier than October 9 under the normal schedule.
