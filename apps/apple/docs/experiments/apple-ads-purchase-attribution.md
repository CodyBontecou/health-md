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

## Deployment record — 2026-10-24

Production Worker `health-md-pricing-analytics` was deployed from merged main
`9b871af92aef1bd10b5e84cbee3f8f9f995402d6` as version
`5eace51b-51e1-401e-9137-6c2497552d94` at 100% traffic. The previous version was
`b0a65a3b-392f-4c53-838e-29dc3c4a91de`. No database migration was applied.

Verification passed: `/health`, attribution start/resolution ingestion,
installation-level replay deduplication, and rejection of a forbidden token
field. The temporary verification installation's two rows were deleted and a
follow-up query confirmed zero remaining rows. The campaign report ran with no
attribution rows yet; real campaign conversion still requires the new app.
The multilingual public privacy policy already contains the disclosure.

The next prepared iOS version is **3.4.4**, build **202610071219**, selected using
`asc builds next-build-number` across processed and in-flight iOS builds. Recheck
that number before building if another upload occurs. Version/build settings,
changelog, in-app notes, English fastlane notes and all ten canonical localized
store descriptions/release notes are prepared together.

Before submission:

- Merge the release preparation into `origin/main`, then create draft GitHub
  Release `v3.4.4` targeting the exact clean, pushed release source. Use the
  English canonical `whatsNew` text as the release body.
- Sign into an Apple web session and update App Privacy to include Advertising
  Data for Analytics, not linked to identity and not used for tracking, matching
  `PrivacyInfo.xcprivacy`. The CLI API key alone cannot update these answers;
  `asc web privacy pull` reported no cached Apple web session during preparation.
  Preserve the other current declarations.
- Apply the canonical 3.4.4 localized metadata, run `asc validate`, and use the
  existing `Apple Release iOS` workflow with the draft release tag. Keep the
  GitHub Release in draft while Apple reviews the app.
- After release, verify a real Apple Ads acquisition and purchase. Production
  backend smoke tests establish ingestion only, not Apple attribution accuracy.
