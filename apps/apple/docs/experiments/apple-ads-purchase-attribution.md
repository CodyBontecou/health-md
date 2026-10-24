# Apple Ads purchase attribution

Outcome: measure which acquisition campaigns produce purchasing installations,
without linking advertising to health data or sending purchases to advertisers.

## Scope and platform decision

Apple Ads AdServices attributes App Store acquisitions on iOS/iPadOS. This is
`apple_only` in the product capability inventory. Android Google Play Install
Referrer is a separate acquisition provider, with a separate campaign collector;
it cannot return Apple Ads campaign claims. macOS does not initiate this lookup.
Neither health exports, the public export schema, Rust core, CLI, direct protocol,
nor the external Obsidian consumer changes.

## Collection

The production analytics singleton enqueues an attribution-start event before
subsequent purchase events, then asynchronously resolves AdServices on physical
release iPhones/iPads. Debug and simulator builds never contact Apple. There is
no IDFA, ATT prompt, third-party MMP, or purchase postback to an ad network.

The token is sent directly to `https://api-adservices.apple.com/api/v1/` using
an ephemeral session. It never enters UserDefaults, analytics, logs, or Health.md
servers. A lookup makes at most three attempts, five seconds apart, with bounded
network timeouts. Failure remains unknown, with another attempt on a later
launch. An explicit successful `attribution=false` is **unmatched**, not proof of
organic acquisition. Developer Mode/foreign advertiser responses are rejected.
Only org 22465240 claims are accepted. Dimensions withheld by Apple remain absent.

The persisted local record contains only matched/unmatched status, numeric
campaign/ad-group/keyword IDs, Click/Impression/unknown claim, and
Download/Redownload/unknown conversion category. First resolution is sticky for
the installation. It is replayed on launch through the existing bounded offline
queue; the Worker deduplicates both start and resolution by install ID. Attribution
is joined server-side to the same random install UUID used by purchase analytics.
Attribution fields are accepted only on the dedicated iOS resolution event. Raw
responses, token, click time, geography and arbitrary strings are not accepted.
Rows inherit the existing daily 13-month retention cleanup.

## Campaign conversion report

From `apps/apple/worker/pricing-analytics`, run `npm run query:apple-ads` after the
backend is deployed. The checked-in `queries/apple-ads-conversion.sql` groups by
campaign, ad group, keyword, claim and download category. It counts distinct
resolved installations, distinct purchasing installations and their percentage.
Apple Ads reporting supplies campaign names for these numeric IDs.

Purchases must be `pricing_purchase_finished` with `succeeded` on iOS, received
at or after that installation's first attribution-start event. This excludes
historical purchases already queued before instrumentation started, restores,
failed/cancelled/pending purchases and duplicate purchase events. Purchases that
arrive before a delayed attribution response still join correctly. Events that
arrive from offline devices use server receipt order, not transaction dates.

This is a client-reported purchase-conversion report, not a financial ledger.
It does not verify StoreKit transactions on the server, count individual sales,
track refunds, currency or net revenue, or calculate monetary ROAS. Distinct
purchasers can include a family upgrade and do not establish incremental lift.
Keep click/view and download/redownload categories separate. Missing attribution
is excluded, not inferred organic. New resolutions have less purchase follow-up;
the report is all retained observations, not a mature acquisition cohort.

## Rollout

1. Deploy the backwards-compatible Worker allowlist before releasing the app.
   No D1 migration is required: campaign dimensions use the existing validated
   `payload_json` column. Existing clients and Android ingestion remain accepted.
2. Publish the updated multilingual privacy policy. Include Advertising Data for
   Analytics in App Store privacy answers, consistent with PrivacyInfo.xcprivacy.
   Review the next release's localized store descriptions; historical version
   metadata is preserved. The English fastlane draft includes the new disclosure.
3. Release a physical-device build with this implementation through the normal
   synchronized Apple release process. No deployment or store submission is part
   of this code change.
4. Verify an actual Apple Ads acquisition and a real verified StoreKit purchase
   after release. Developer Mode attribution is synthetic and is intentionally
   excluded; it cannot validate live campaign conversion. Historical ad-to-sale
   attribution cannot be reconstructed from the previous app analytics.

References: [Apple token and retry documentation](https://developer.apple.com/documentation/adservices/aaattribution/attributiontoken())
and [Apple Ads measurement](https://ads.apple.com/app-store/help/attribution/0028-measuring-ad-performance).
