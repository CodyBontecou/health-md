# Google Play Console setup prompt

Use this prompt when working in the browser at <https://play.google.com/console>. Repository files, not this document, are the source of truth for listing copy and release numbers.

---

## Prompt

You are helping me prepare the Google Play listing for Health.md. Work through one section at a time, save drafts, and report what changed. Do not publish, submit for review, change production availability or upload a release without my explicit approval.

### App identity

- Package: `com.healthmd.android`
- Store title: `Health.md – Health Data Export`
- Default language: English (United States), `en-US`
- Category: Health & Fitness
- Contains ads: No
- Privacy policy: <https://healthmd.app/privacy-policy.html>

Read the current `versionName` and `versionCode` from `app/build.gradle.kts`. Do not copy an old release number from a document or screenshot.

### Listing metadata

The authored listing is under `play-console/listing/<locale>/`. The locale review state is in `play-console/locales.json`:

- Upload only locales marked `reviewed`.
- Treat every locale marked `draft` as awaiting native-speaker review.
- Keep the English title exactly `Health.md – Health Data Export`.
- Preserve the FHIR category list, privacy disclosures, permission explanation and medical disclaimer in each full description.
- The offer is 10 free manual exports followed by a one-time lifetime unlock; there is no subscription.

Before entering metadata, prepare and validate the canonical files:

```bash
cd apps/android
./scripts/validate-play-listing.sh
```

Use `build/play-metadata/reviewed/` as the reviewed Console input. Do not validate or upload directly from the custom authored directory structure.

### Store assets

- Phone screenshots: `play-console/screenshots/en-US/phone/` — eight reviewed 1080×1920 English images in filename order. Do not upload them without approval.
- Seven-inch tablet screenshots: `play-console/screenshots/en-US/sevenInch/` — four genuine 1200×1920 API 35 captures.
- Ten-inch tablet screenshots: `play-console/screenshots/en-US/tenInch/` — four genuine 2560×1600 API 35 captures.
- Icon: `play-console/graphics/en-US/icon.png`.
- Feature and promotional graphics remain user-owned work unless current files exist and pass validation.

Keep the screenshot order recorded in `docs/aso-screenshot-pairings.md`. Do not use old `60+`, `61/61` or `99/99` claims; use `100+`.

### Pricing and in-app product

- App price: Free with an in-app purchase
- Product ID: `health_md_premium_lifetime`
- Type: One-time product, not a subscription
- Name: `Unlock Health.md`
- Description: `Unlimited exports and automated scheduling — one-time payment, no subscription.`

Confirm the current price and regional pricing in Play Console rather than assuming an old USD amount from documentation.

### Content rating

- Violence, sexual content, profanity and controlled substances: No
- User-generated content, social features and location sharing: No
- Health or medical functionality: Yes; the app reads user-authorized Health Connect data
- Target audience: Adults using Health Connect exports and related health-data tools

### Data safety and privacy

Do not infer answers from the listing description. Keep Play Console answers synchronized with:

- `docs/campaign-attribution.md`
- `docs/onboarding-analytics.md`
- the hosted privacy policy
- the current Android manifest and implementation

Health records are never sent to campaign-attribution or onboarding-analytics systems. User-selected API endpoint and paired-CLI exports are separate, intentional destinations and must not be described as first-party analytics.

### Health Connect permissions

Use the current manifest and generated Health Connect declarations as the complete permission list. The rationale is:

> Health.md reads user-authorized Health Connect metrics only to create exports requested by the user. The user chooses the metrics and destination. Device-folder exports go to user-selected storage. If the user explicitly configures an API endpoint or pairs the desktop CLI, selected records are sent directly to that destination. Health.md does not proxy or store those requests in a Health.md health-data cloud.

Do not paste an old hand-maintained permission list if it differs from the manifest.

### Foreground service declaration

For `FOREGROUND_SERVICE_DATA_SYNC`, the task is local processing for importing/exporting. Scheduled exports read user-authorized records and write user-selected formats to a user-selected Android document-provider folder. On Android versions where expedited WorkManager jobs use a foreground service, this keeps a user-noticeable export running reliably.

Confirm that any evidence-video URL still resolves before submitting the declaration.

### Release handling

Read the current version, bundle and release notes from the repository and Play Console. Do not assume that an old internal-testing release is current. Do not upload an AAB, create a release, promote a track or submit anything for review without explicit approval.

### Working order

1. Store presence → Main store listing
2. Store presence → Store settings
3. Monetize → In-app products
4. Policy → App content
5. Release → Testing or production, only after explicit approval

After each section, state what was saved, what remains a draft, which locale or asset was used, and whether any action would affect users or trigger review.
