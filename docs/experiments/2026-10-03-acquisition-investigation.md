# Acquisition investigation — October 3, 2026

This investigation follows the [October 3 pricing checkpoint](./2026-10-03-pricing-checkpoint.md). The question is whether lower observed iOS onboarding starts reflect less App Store discovery, fewer downloads, or a change between downloading and first use. No production prices, store assets, or acquisition campaigns were changed by this investigation.

The observed decline began before the September 17 price change. Recent first-time iPhone downloads softened modestly, with search downloads increasing and referrals decreasing. First-export completion among new recorded iOS installations held steady. The Health MD App YouTube public feed has no video newer than July 31, despite a saved posting plan through August 29. The subsequent video-traffic audit finds only 150 cumulative views across the latest 15 public videos and very little verifiable viewer traffic. Delivery is a gap to investigate, but YouTube is not established as a material cause of the acquisition decline.

## Comparison design

The existing D1 checkpoint reports 225 distinct onboarding starters during July 6–20, 133 during September 2–16, and 123 during September 17–October 1. These are app-install identifiers that emitted an event, not App Store downloads. Apple aggregates cannot be joined to those identifiers, and offline event delivery uses Worker receipt time. Compare equal dates and device scope, and treat their ratio as a reconciliation diagnostic rather than a customer-level conversion funnel. [Checkpoint evidence](./2026-10-03-pricing-checkpoint.md), [D1 event contract](../../apps/apple/worker/pricing-analytics/README.md).

Use **App Store Downloads Standard** to establish first-time downloads by source and device. Separate first-time downloads, redownloads, updates, and restores. Use **App Store Discovery and Engagement Standard** to establish the upstream changes in impressions, product-page views, and Get taps. Detailed reports can help identify large referring sources when available, but should not replace standard totals.

## Apple report semantics

| Report | Daily completeness | Weekly / monthly | Interpretation |
| --- | --- | --- | --- |
| Discovery and Engagement | Within 3 days | Both report types; complete by default | Counts of impressions, page views, and taps, with source, device, and territory |
| Downloads | Within 2 days | Detailed only; complete by default | First-time downloads, redownloads, updates, restores; first-time download uses the Apple Account and Get / Buy tap |
| Installations and Deletions | Within 5 days | Both report types; complete by default | Device installation / deletion events from users who opted into Apple's analytics |

Sources: [Discovery report](https://developer.apple.com/documentation/analytics-reports/app-store-discovery-and-engagement), [Downloads report](https://developer.apple.com/documentation/analytics-reports/app-download), [Installation / deletion report](https://developer.apple.com/documentation/analytics-reports/app-installs).

Discovery's API `Event = Impression` excludes page views; `Event = Page view` is separate. `Counts` counts events and `Unique Counts` counts unique users for the reported cell. Product-page views should filter both the page-view event and product-page page type. `Engagement Type = Get` represents taps on Get, Buy, or Pre-order; use the downloads and pre-order reports to distinguish the outcome. [Discovery field definitions](https://developer.apple.com/documentation/analytics-reports/app-store-discovery-and-engagement).

Standard reports include source type, device, and territory. Referring domain / app (`Source Info`), campaign token, and page title are detailed-only fields in discovery and downloads. Search includes Search Ads. Browse includes the Suggested section of the search landing page. A download can occur from a list with `Page Type = No Page`; first-time downloads divided by product-page views therefore does not measure a closed funnel. [Downloads field definitions](https://developer.apple.com/documentation/analytics-reports/app-download).

## Completeness, availability, and aggregation

Download every segment of an instance. Select events using the report's `Date` column, keeping the latest `processingDate` for each date and granularity; replace the entire older date batch rather than adding deliveries. Weekly dates name Monday; monthly dates name the first day of the month. Daily instances can contain multiple event dates. Rare later corrections remain possible. [Completeness and corrections](https://developer.apple.com/documentation/analytics-reports/data-completeness-corrections).

Instances remain downloadable for 35 days. Older historical reports require an available snapshot or separately retained exports; a missing July daily instance is not evidence of zero July traffic. Reports are generated only after a report request exists. The documented one-time snapshot retrieves available history and can be requested once a month. Parse columns by name. [Analytics Reports API overview](https://developer.apple.com/documentation/analytics-reports).

Detailed reports suppress cells with fewer than five users or devices and apply statistical noise. An empty detailed cell or missing referring site is not zero traffic; summing detailed rows need not reconcile to standard totals. Installation / deletion reports require at least five contributing users even in their standard form, and cover only people sharing Apple analytics. They cannot establish an all-user download-to-first-open conversion rate. [Privacy rules](https://developer.apple.com/documentation/analytics-reports/privacy).

## Conversion and attribution caveats

Apple's UI impressions include product-page views, unlike the API's impression event. The UI conversion rate uses total downloads plus pre-orders divided by unique-device impressions; total downloads means first-time downloads plus redownloads. Do not label first-time downloads / raw impressions or first-time downloads / page views as that metric. Summed daily or segmented unique counts are not a deduplicated multi-day audience; absent a correctly scoped unique denominator, report counts and descriptive event ratios explicitly. [Apple metric definitions](https://developer.apple.com/help/app-store-connect-analytics/reference/metrics-definitions/).

On iOS, links opened from websites in non-Safari browsers appear as app referrals; Safari redirect chains attribute to the last referring URL. Thus declining web referrals alone does not prove declining website acquisition. Acquisition source is recorded at download or redownload; manual redownload resets the source used for subsequent sales and usage. Source attribution is not proof that a campaign caused the acquisition. [Acquisition source rules](https://developer.apple.com/help/app-store-connect-analytics/acquisition/acquisition/).

## Live evidence

### Sources and coverage

Read on **October 3, approximately 14:50–15:05 UTC**, using `asc` 5.9.2 with `ASC_READ_ONLY=1` and aggregate D1 SELECTs. ASC app: `6757763969`; ongoing request: `601e9f5f-fbdc-499a-abc4-5348e254f915`. Reports:

- Downloads Standard: `r3-601e9f5f-fbdc-499a-abc4-5348e254f915`, processing through October 3; downloaded event dates August 31–October 2.
- Discovery and Engagement Standard: `r14-601e9f5f-fbdc-499a-abc4-5348e254f915`, processing through October 2; downloaded event dates August 30–October 1.

All segments of 63 daily instances were downloaded successfully, including multi-segment download instances. For each event date, the latest processing-date instance replaces the entire previous batch. Main download results use complete September 2–16 versus September 17–October 1. Discovery uses complete, equal 14-day windows September 2–15 versus September 17–30; October 1 is excluded under its three-day completeness rule. Counts below use the iPhone device field; separate iPhone+iPad results are noted explicitly.

The existing snapshot `c9cb405b-7888-4bf6-8091-60a3c1b55670` has no available download/discovery instances. July store-level daily acquisition data is therefore unavailable in these retained requests. No new report request was created. The July app-event comparison remains available in D1.

Temporary reproducibility files: `/private/tmp/healthmd-acquisition-reports/manifest.json`, `/private/tmp/healthmd-acquisition-reports/summary.json`, `/private/tmp/healthmd-acquisition-download.py`, `/private/tmp/healthmd-acquisition-analyze.py`, and `/private/tmp/healthmd-acquisition-query.py`. These files are local working data, not durable repository attachments. All pricing and campaign database query metadata reports zero rows written.

### Downloads: small recent decline, concentrated in referrals

| First-time iPhone downloads | September 2–16 | September 17–October 1 | Change |
| --- | ---: | ---: | ---: |
| Total | 95 | 87 | −8.4% |
| App Store search | 67 | 72 | +7.5% |
| App Store browse | 8 | 5 | −3 downloads |
| App referrer | 10 | 5 | −5 downloads |
| Web referrer | 10 | 4 | −6 downloads |
| Unavailable source | 0 | 1 | +1 download |

Referrals combined fall 20 → 9, while search adds five downloads. Samples are small; these are descriptive channel changes, not statistically established campaign effects. Search includes Search Ads and cannot be labeled wholly organic from this report.

First-time iPhone+iPad downloads are 101 → 91 (−9.9%). iPhone redownloads are 49 → 39; restores are 10 → 65. Updates are excluded from acquisition totals. First-time download counts identify Apple Accounts; new D1 installation identifiers can also follow redownloads/restores or other install paths, and the time windows are not customer-level joins.

US first-time iPhone downloads are essentially steady, 23 → 22. Germany falls 15 → 7 and the UK 7 → 3, while China rises 5 → 10 and Japan 6 → 8. No single territory is established as the cause. Device-installation reports were not used as an all-user denominator.

### Discovery: lower exposure, but search download demand holds

| iPhone discovery event counts | September 2–15 | September 17–30 | Change |
| --- | ---: | ---: | ---: |
| API impressions, excluding page views | 4,609 | 3,446 | −25.2% |
| Product-page views | 480 | 414 | −13.8% |
| Get taps | 102 | 114 | +11.8% |
| Search impressions | 2,965 | 2,419 | −18.4% |
| Browse impressions | 1,644 | 1,027 | −37.5% |
| Search product-page views | 248 | 260 | +4.8% |
| Browse product-page views | 161 | 113 | −29.8% |
| App-referrer product-page views | 31 | 24 | −22.6% |
| Web-referrer product-page views | 40 | 17 | −57.5% |

The decline is upstream exposure, particularly browse and referrals, rather than a demonstrated collapse in search downloads. China contributes 597 of the 1,163 lost impression events (999 → 402), even as its first-time downloads increase. Impressions are consequently a poor standalone target for this small app. Get taps, source-attributed downloads, and page views do not form a closed, individually joined funnel; no Apple UI conversion rate is calculated here.

### App starts and first use: decline predates the new price

The fresh D1 read assigns each iOS/legacy Apple installation to its first recorded onboarding start across all retained history and follows later iOS/legacy events across app upgrades. July includes 47 legacy starters without a platform/version field; that historical classification follows the checkpoint's Apple legacy treatment. Worker receipt times govern every boundary.

| First-start installation cohort | July 6–20 | September 2–16 | September 17–October 1 |
| --- | ---: | ---: | ---: |
| First recorded onboarding starts | 225 | 132 | 123 |
| Onboarding completed within 24 hours | 148 (65.8%) | 90 (68.2%) | 96 (78.0%) |
| Saved an export within 24 hours | 94 (41.8%) | 73 (55.3%) | 70 (56.9%) |
| Generated a preview or saved within 24 hours | 112 (49.8%) | 87 (65.9%) | 92 (74.8%) |

The checkpoint's 133 September-before starters includes one installation whose first start preceded that window; the new-cohort denominator is 132. Current 123 starts are all first recorded starts. Saved-export completion is stable in the recent comparison, while preview/activation improves descriptively. New onboarding starts decline 6.8%, first-time iPhone downloads 8.4%, and first-time iPhone+iPad downloads 9.9%; these similar directions do not indicate a large newly emerging download-to-onboarding failure. They do not establish an exact download-to-open rate.

Selected full Monday–Sunday weeks show the earlier decline:

| Week beginning | First recorded iOS/legacy onboarding starts |
| --- | ---: |
| July 6 | 119 |
| July 13 | 98 |
| July 27 | 72 |
| August 10 | 93 |
| August 24 | 71 |
| September 7 | 73 |
| September 14 | 69 |
| September 21 | 51 |

The welcome-start event remains protected by `pricing.analytics.onboarding.started.tracked.v1`; the September onboarding simplification changes later steps, not this start event. iOS minimum deployment target remains 17 with iPhone/iPad device family 1,2 in the compared repository states. Source evidence does not establish exact release availability or rule out every crash/telemetry issue. See [onboarding source](../../apps/apple/HealthMd/iOS/Views/OnboardingView.swift), event definitions (removed; see `b8ded3597:apps/apple/HealthMd/Shared/Analytics/PricingAnalyticsFunnel.swift`), and the [Worker measurement contract](../../apps/apple/worker/pricing-analytics/README.md).

### Campaign activity and delivery gap

Live `healthmd-campaigns` aggregates show redirect counts 137 during July 6–20, 20 during September 2–16, and 13 during September 17–October 1. Monthly counts are July 222, August 65, September 35. Current 13 requests comprise four `bot`, seven `youtube_or_google`, and two `android` signals. The classifier combines YouTube and Googlebot; there are no explicit iOS/mac signals in either September window. These counts cannot establish a human acquisition rate. The [attribution contract](../../apps/website/ATTRIBUTION.md) and [classifier](../../apps/website/cloudflare/attribution-worker/src/worker.js) define the scope.

Live HEAD checks verified the present redirect branches: iPhone → App Store with campaign/provider/custom-page parameters; Android → Google Play with Install Referrer; unknown desktop → homepage UTM. HEAD creates no click row. Provider-token absence in recent click rows therefore does not prove a broken provider secret. Source commit `723a1a39c` changed unknown-client routing on July 15, so provider-token totals across this boundary are especially unsuitable as human Apple traffic counts.

The July 10 [YouTube verification snapshot](../../apps/apple/fastlane/runs/2026-07-10-healthmd-app-youtube-shorts/verification.json) confirms one public Short and 21 future scheduled slots. The July 30 [cross-platform verification snapshot](../../apps/apple/fastlane/runs/2026-07-28-month-of-healthmd-cross-platform/verification.json) records 279 planned posts through August 29: six already posted and 273 still scheduled. Automation `COMPLETED` confirms schedule generation, not successful later delivery.

On October 3, a direct read of the [public YouTube channel feed](https://www.youtube.com/feeds/videos.xml?channel_id=UC-LsdCPDvzLhG5LyANgUDCg) returns 15 entries dated July 14–31. The newest public entry is **July 31 at 01:30:31 UTC**. No newer public video appears in that feed. This supports investigating whether the YouTube posting schedule stalled or failed; it does not audit TikTok/Instagram delivery, private/deleted posts, or prove a specific acquisition contribution. Feed results were retained locally in `/private/tmp/healthmd-acquisition-youtube-feed-2026-10-03.json`.

Website download buttons currently link directly to the App Store rather than the existing campaign route. The homepage and export SEO pages thus bypass campaign D1 measurement. No first-party website visitor/Search Console dataset was available in this read, and detailed Apple source fields would suppress sparse traffic. Campaign click decline is therefore incomplete evidence of website performance. See [homepage buttons](../../apps/website/index.html), [Apple Health export page](../../apps/website/apple-health-export/index.html), and [CSV export page](../../apps/website/apple-health-to-csv/index.html).

### YouTube traffic follow-up: small public reach, contaminated click totals

A further October 3 read of the same public feed retrieves each video's cumulative `media:statistics` views and description campaign links. The latest 15 public videos, dated July 14–31, total **150 views**. This is a subset of the channel, not its all-time view count or unique audience. The latest three total 70 views:

| Video | Public views | Campaign requests before public publication | Requests after publication |
| --- | ---: | ---: | ---: |
| Put your health data in Obsidian | 42 | 5 | 1, classified as bot |
| Export Apple Health data to CSV and JSON | 24 | 4 | 2: one unknown, one YouTube/Google |
| Your health data should be yours | 4 | 4 | 0 |

Their descriptions use `yt-obsidian-103`, `yt-csv-102`, and `yt-privacy-101`, respectively. The raw link totals are six, six, and four requests, but 13 of those 16 predate the public publication timestamps. The only recorded request after the latest video's publication is a bot. No verified human visit is established for the other two requests, and no download/sale count can be assigned to these videos. Do not calculate click-through rates from these incompatible totals. Source: [public feed](https://www.youtube.com/feeds/videos.xml?channel_id=UC-LsdCPDvzLhG5LyANgUDCg), read-only campaign SELECTs.

Across **all YouTube-labelled campaign links**, the database records:

| Month | Raw redirect requests | Explicit bot | Ambiguous YouTube/Google | Unknown client | OS identified |
| --- | ---: | ---: | ---: | ---: | ---: |
| June, from June 26 | 128 | 10 | 1 | 117 | 0 |
| July | 201 | 61 | 9 | 94 | 37 |
| August | 43 | 20 | 23 | 0 | 0 |
| September | 19 | 8 | 6 | 4 | 1 |
| Total | 391 | 99 | 39 | 215 | 38 |

`platform = yt` comes from the link slug, not a verified YouTube origin. All valid GETs are stored, including crawlers and repeated visits. No recorded YouTube referring hostname appears, although referrer omission also occurs for legitimate traffic. OS identification is not proof of a human user. Many June 30 links were visited sequentially about one second apart, suggesting automated checking; no exact live QA provenance was established. Unit tests use mocked storage, and current documented HEAD checks do not persist rows, so those specific checks must not be blamed for the historical requests.

YouTube-only matched windows contain 136 raw requests during July 6–20, 13 during September 2–16, and five during September 17–October 1. These differ from the earlier all-platform campaign counts 137, 20, and 13. They cannot explain how many people, first-time downloads, or purchases YouTube generated. The earlier suggestion to prioritize YouTube as an acquisition recovery mechanism put too much weight on this delivery gap; measured public reach is small and attribution is insufficient.

Reproduction files: `/private/tmp/healthmd-youtube-public-stats-2026-10-03.json`, `/private/tmp/healthmd-youtube-traffic-monthly-2026-10-03.json`, `/private/tmp/healthmd-youtube-traffic-campaigns-2026-10-03.json`, `/private/tmp/healthmd-youtube-traffic-publication-2026-10-03.json`, and `/private/tmp/healthmd-youtube-traffic-query.py`. All remote queries were aggregate SELECTs and reported zero writes.

### Sales during the July video runs

The retained ASC monthly purchase instance processed September 5 (`51cfe178-a84b-4511-8dd8-517c3d6e1b4e`) contains complete historical month batches, including June, July, and August. Both segments were combined, selecting `Date` for each month and filtering app `6757763969`, `Purchase Type = In-app purchase`, and `Device = iPhone`. This recovers monthly commerce even though July daily store instances are no longer retained. See the [commerce source and completeness rules](./2026-10-03-pricing-checkpoint.md).

| iPhone commerce | June, 30 days | July, 31 days | August, 31 days |
| --- | ---: | ---: | ---: |
| Gross paid purchases | 93 | 112 | 72 |
| Observed refunded units | 0 | 0 | 0 |
| Net consumer sales, estimated USD | $1,565.21 | $1,905.87 | $1,255.83 |
| Net developer proceeds, estimated USD | $1,227.43 | $1,518.91 | $978.79 |
| Paid purchases per day | 3.10 | 3.61 | 2.32 |

July increases 20.4% in total paid purchases and 23.7% in total proceeds over June. Adjusting for its extra calendar day, purchases/day increases 16.5% and proceeds/day 19.8%. iPad purchases add one unit/$12.62 proceeds in June and three units/$39.28 in July; the primary table preserves the iPhone scope. This is not a comparison with a randomized, unexposed control group.

July's growth is concentrated in **search-attributed purchases, 68 → 85**, accounting for 17 of the 19 extra iPhone units. Combined app/web-referral purchases are **18 → 18**: app referrals rise 7 → 12 while web referrals fall 11 → 6. Those source fields describe download/redownload attribution, not proof of the last marketing influence before buying. A video viewer could later search for the app; the standard report cannot resolve that pathway or identify YouTube buyers.

To check timing, read-only D1 queries count successful purchase responses from iOS plus legacy missing-platform Apple rows. These are app-reported responses, not complete store transactions, revenue, refunds, or unique customers. They use Worker receipt time and cannot substitute for unavailable July daily ASC commerce:

| Window in UTC | Days | Successful app purchase responses | Per day |
| --- | ---: | ---: | ---: |
| July 6–9, preceding the July 10 run | 4 | 14 | 3.50 |
| July 10–18, first publishing run | 9 | 31 | 3.44 |
| July 19–27, gap between public runs | 9 | 39 | 4.33 |
| July 28–30, lead-in including July 30 videos | 3 | 10 | 3.33 |
| July 31–August 8, following the latest upload | 9 | 18 | 2.00 |

July 1–5 is excluded because the unavailable subscription configuration generated failed attempts. Two unavailable-store responses still appear July 6–9, so even this short preceding baseline is imperfect. The July 30 videos began at 21:40 UTC; whole-day windows cannot identify exact-hour reactions or delayed effects.

Full Monday–Sunday purchase-response counts are 23, 26, 28, 21, and 21 for weeks starting July 6, 13, 20, 27, and August 3. These show gradual variation without an obvious immediate publishing spike. First-start seven-day purchase rates peak during the gap, potentially including delayed purchases, but remain small descriptive cohorts rather than causal attribution. The three-to-ten quota rollout around August 1 confounds the later decline, alongside acquisition/release/product/territory mix.

**Conclusion:** July sales improved overall. The daily proxy does not show a clear immediate jump during publication, referral-attributed paid units remain flat, and the measured public video reach is small. The evidence cannot assign the extra July sales to the videos or rule out a small/delayed contribution.

Local evidence: `/private/tmp/healthmd-video-sales-asc-months-2026-10-03.json` and `/private/tmp/healthmd-video-sales-d1-{windows,weeks,outcomes,daily,cohorts}-2026-10-03.json`. All queries report zero writes. Android commerce is not included.

### Listing history does not establish a recent metadata regression

Live ASC en-US App Info is **Health.md / Daily Health Journal & Export**, matching tracked App Info rather than Fastlane's differing subtitle. The current 3.4.2 and preceding 3.4.1 localizations return the same journal-oriented description and keyword set. The API also currently returns that set for versions 2.8, 2.9, 2.9.2, and 2.9.3; it is not a historical, immutable publication log.

Older repository snapshots indicate an earlier CSV/JSON/ownership emphasis, but neither those snapshots nor version-created timestamps prove the exact customer-facing change date. Current search downloads increase in the matched September comparison. There is no evidence here to attribute the recent decline to keywords or to justify immediately replacing the listing.

## Recommended next actions

1. Improve referral measurement: route website store-button clicks through platform-specific campaign links using the existing coarse attribution system, including homepage and export landing pages. Verify the click classifier separates bots from human-facing signals; source totals remain aggregate and should not be joined to pricing install IDs.
2. Audit the social publisher's actual delivery for the planned July 31–August 29 posts before relying on another schedule. Keep published, scheduled, and failed counts separate. Treat this as an operational repair, not a proven way to recover the lost acquisition volume.
3. Run a small, verified acquisition test around a concrete Apple Health → Obsidian or CSV export workflow. Choose the channel using measured reach and acquisition outcomes rather than assuming YouTube was previously successful. Judge incremental first-time downloads and downstream first-export completion, alongside proceeds. Preserve the current pricing observation window and test acquisition changes separately from quota/price changes.

This analysis covers Apple acquisition and the shared redirect service. The Android campaign-install table has no rows for July–October; that is an attribution coverage gap, not evidence of zero Android acquisition. Google Play store-level acquisition was not available in this read.
