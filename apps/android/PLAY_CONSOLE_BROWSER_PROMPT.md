# Google Play Console read-only audit prompt

Use this prompt only to inspect the Health.md Play Console state in a browser. Repository files are the source of truth for listing copy and release numbers.

This prompt is **read-only**. Do not click Save, upload an asset or AAB, create/edit a release, change a track, promote an artifact, submit review, change production availability, or otherwise mutate Play Console—even if the browser operator gives a general approval. Return a field-by-field change plan instead. Release and metadata mutation are owned exclusively by the protected phone workflows described in `PLAY_STORE_COMMANDS.md`. The Wear workflows are deferred and must not be run for the current release.

---

## Prompt

You are auditing the Google Play listing for Health.md. Work through one section at a time and report current values, discrepancies, and the exact repository source for each proposed correction. Do not save or submit any change.

### App identity

- Package: `com.healthmd.android`
- Store title: `Health.md – Health Data Export`
- Default language: English (United States), `en-US`
- Category: Health & Fitness
- Contains ads: No
- Privacy policy: <https://healthmd.app/privacy-policy.html>

Read the current phone `versionName` and `versionCode` from `app/build.gradle.kts` and verify them against `release-scope.json`. The Wear values are future-development inputs, not part of the current Play release.

### Listing metadata

The authored listing is under `play-console/listing/<locale>/`. Locale review state is in `play-console/locales.json`:

- Treat only locales marked `reviewed` as eligible proposed input.
- Treat every locale marked `draft` as awaiting native-speaker review.
- Keep the English title exactly `Health.md – Health Data Export`.
- Preserve the FHIR category list, privacy disclosures, permission explanation, and medical disclaimer in each full description.
- The offer is 10 free manual exports followed by a one-time lifetime unlock; there is no subscription.

Prepare and validate canonical files locally before comparing them with Console:

```bash
cd apps/android
./scripts/validate-play-listing.sh
```

Compare `build/play-metadata/reviewed/` with Console and report differences. Do not enter or save them in the browser.

### Store assets

- Phone screenshots: `play-console/screenshots/en-US/phone/` — eight reviewed 1080×1920 English images in filename order.
- Seven-inch tablet screenshots: `play-console/screenshots/en-US/sevenInch/` — four genuine 1200×1920 API 35 captures.
- Ten-inch tablet screenshots: `play-console/screenshots/en-US/tenInch/` — four genuine 2560×1600 API 35 captures.
- Icon: `play-console/graphics/en-US/icon.png`.
- Feature and promotional graphics remain user-owned work unless current files exist and pass validation.

Keep the phone screenshot order recorded in `docs/aso-screenshot-pairings.md`. Do not use old `60+`, `61/61`, or `99/99` claims; use `100+`.

Wear OS publication is deferred. Do not add Wear screenshots or run a Wear screenshot workflow for the current release. Any future Wear launch must resume its exact-build physical-watch capture and independent-review process first.

### Pricing and in-app product

Inspect and report; do not save:

- App price: Free with an in-app purchase
- Product ID: `health_md_premium_lifetime`
- Type: One-time product, not a subscription
- Name: `Unlock Health.md`
- Description: `Unlimited exports and automated scheduling — one-time payment, no subscription.`

Report current regional pricing instead of assuming an old USD amount.

### Content rating

Inspect the current answers against this intended state; do not submit a questionnaire:

- Violence, sexual content, profanity, and controlled substances: No
- User-generated content, social features, and location sharing: No
- Health or medical functionality: Yes; the app reads user-authorized Health Connect data
- Target audience: Adults using Health Connect exports and related health-data tools

### Data safety and privacy

Do not infer answers from the listing description. Compare Console with:

- `docs/campaign-attribution.md`
- `docs/onboarding-analytics.md`
- the hosted privacy policy
- the current Android manifest and implementation

Health records are never sent to campaign-attribution or onboarding-analytics systems. User-selected API endpoint and paired-CLI exports are separate intentional destinations and must not be described as first-party analytics. Report discrepancies; do not submit Data safety changes.

### Health Connect permissions

Use the current manifest and generated Health Connect declarations as the complete permission list. The rationale is:

> Health.md reads user-authorized Health Connect metrics only to create exports requested by the user. The user chooses the metrics and destination. Device-folder exports go to user-selected storage. If the user explicitly configures an API endpoint or pairs the desktop CLI, selected records are sent directly to that destination. Health.md does not proxy or store those requests in a Health.md health-data cloud.

Do not paste or save an old hand-maintained permission list if it differs from the manifest.

### Foreground service declaration

For `FOREGROUND_SERVICE_DATA_SYNC`, the task is local processing for importing/exporting. Scheduled exports read user-authorized records and write user-selected formats to a user-selected Android document-provider folder. On Android versions where expedited WorkManager jobs use a foreground service, this keeps a user-noticeable export running reliably.

Report whether the current evidence-video URL resolves. Do not submit the declaration.

### Release handling

Release pages are inspection-only here. Never upload an AAB, create/edit a release, change a testing or production track, promote an artifact, change rollout, or submit review from the browser.

The only supported AAB upload is `.github/workflows/android-release.yml`, which requires an exact annotated/main-reachable SHA and uploads the phone artifact to Internal Testing. The only supported production mutation is `.github/workflows/android-promote-production.yml`, which promotes the exact phone version code and submits it for review. Neither workflow uploads or promotes Wear. Report current release state and stop.

### Working order

1. Inspect Store presence → Main store listing.
2. Inspect Store presence → Store settings.
3. Inspect Monetize → In-app products.
4. Inspect Policy → App content.
5. Inspect Release → Testing and production state without opening or committing an edit.

After each section, state the observed value, the proposed repository-backed value, which locale or asset was compared, and whether a future approved action would affect users or trigger review. Do not save any section.
