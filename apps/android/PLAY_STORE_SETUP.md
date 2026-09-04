# Google Play Store deployment

Health.md publishes the phone and Wear artifacts as one evidence-bound pair through protected GitHub workflows. Gradle Play Publisher has been removed from both application modules so module-level tasks cannot bypass paired track assignment and protected evidence gates.

## Account setup

### Protected release accounts

Repository/environment administrators—not local release operators—create the Play service accounts and place their JSON keys directly in protected environment secrets:

1. Enable the Google Play Android Developer API without granting a Google Cloud project role such as Editor.
2. Create distinct service accounts for `google-play-qa`, `google-play-production`, and `google-play-announce`.
3. In Play Console, restrict the QA account to the `qa` and `wear:qa2` tracks; it must not mutate production. The Wear QA track identifier is `wear:qa2` because the exact `wear:qa` name is permanently occupied by an undeletable default-kind closed track created before form-factor tracks were understood (Google Play exposes no track deletion or rename); `wear:qa2` is a true Wear form-factor track (`formFactor: WEAR`, `type: CLOSED_TESTING`).
4. Grant production authority only to the account in the environment that verifies sealed evidence and requires human review.
5. Grant the announcement account only app-level **View app information (read-only)** (`CAN_VIEW_NON_FINANCIAL_DATA`) for `com.healthmd.android`.
6. Store each JSON key only as that environment's `PLAY_CONSOLE_KEY_JSON` secret. Do not place a QA or production mutation key on a developer workstation or point local Gradle/Fastlane at it.

Avoid account-wide Admin permission. The Android Publisher OAuth scope is broad; actual least privilege comes from Play Console app/track grants and protected environment separation.

### Optional local read-only inspection

A separate app-level read-only service account may be stored outside the repository and passed through `PLAY_CONSOLE_KEY_PATH` only to `inspect-google-play-wear-readiness.sh`. It must not have upload, track, review, metadata, pricing, or production permissions. Never use it with a Gradle publisher task.

## Prepare app metadata

Create the `play-console` directory structure:

```
play-console/
├── listing/
│   ├── en-US/
│   │   ├── title.txt          # App title (max 50 chars)
│   │   ├── short-description.txt  # 80 chars
│   │   ├── full-description.txt   # Full description
│   │   └── video.txt          # YouTube video URL (optional)
│   │
│   └── release-notes/
│       ├── en-US/
│       │   └── default.txt    # What's new in this version
│
├── screenshots/
│   ├── en-US/
│   │   ├── phone/
│   │   │   ├── 1.png         # 1080x1920px (5+ recommended)
│   │   │   ├── 2.png
│   │   │   └── ...
│   │   ├── sevenInch/         # 7" tablet (optional)
│   │   ├── tenInch/           # 10" tablet (optional)
│   │   └── wear/              # Wear OS (optional)
│   │
│   └── ...other languages...
│
├── graphics/
│   ├── en-US/
│   │   ├── featureGraphic.png    # 1024x500px (required)
│   │   ├── icon.png             # 512x512px (required)
│   │   ├── promoGraphic.png      # 180x120px (optional)
│   │   └── tvBanner.png          # 1280x720px (optional)
│   │
│   └── ...other languages...
```

## Build and release ownership

Build both Play release bundles without Play credentials:

```bash
./gradlew :app:bundlePlayRelease :wear:bundleRelease
```

Outputs:

- `app/build/outputs/bundle/playRelease/app-play-release.aab`
- `wear/build/outputs/bundle/release/wear-release.aab`

Do not upload either module, move a track, submit review, or replace Play metadata from an ad hoc Gradle/Fastlane command. The protected annotated-tag workflow is the only supported AAB upload path and atomically assigns phone to `qa` plus Wear to `wear:qa2`. Production mutation is exclusively the protected, evidence-gated `.github/workflows/android-promote-production.yml` path, using a production-only Play service account that the QA workflow cannot access. It atomically updates `production` and `wear:production` for the exact tagged pair.

Exact-release Wear screenshot replacement is a separate confirmed metadata edit after Play-generated APK verification, physical capture, and independent review. It is never part of the initial upload and cannot be replaced by generic listing publication.

## Version Management

Every Play upload requires a `versionCode` higher than every previously uploaded build. Update `versionCode` and `versionName` in `app/build.gradle.kts` before creating the release commit; do not rely on an uncommitted CI-time increment.

Track version history:
```bash
git log --oneline app/build.gradle.kts | grep -i version
```

## CI/CD Integration

The canonical upload workflow is [`.github/workflows/android-release.yml`](../../.github/workflows/android-release.yml). An annotated `android/v<version>` tag whose peeled commit exactly equals the triggering `main`-reachable SHA builds the signed phone/Wear AAB pair and uploads it in one Google Play edit to `qa` and `wear:qa2`. The AABs are never committed or attached to a GitHub Release. Before opening the Play edit, the workflow retains those exact bytes and a SHA/tag/run-attempt/AAB-digest-bound QA upload intent receipt under attempt-specific artifact names; protected ingest later proves the intent-artifact, paired-upload, and credential-cleanup steps all succeeded, leaving no mandatory artifact operation after Play consumes the codes. Production promotion uses [`.github/workflows/android-promote-production.yml`](../../.github/workflows/android-promote-production.yml) to promote the exact tagged codes atomically to `production` and `wear:production` without rebuilding or re-uploading either binary. The promotion workflow verifies the sealed approved screenshots against current Play hashes, rejects an already-partial/full production pair instead of bypassing the required edit, issues the non-idempotent commit POST once and reconciles both exact tracks if its response is lost, verifies both form-factor postconditions, and retains an exact-edit receipt before reporting success. It first retains a pre-mutation intent artifact. If only post-commit receipt retention fails, the protected non-committing `android-promote-production-recover.yml` flow requires the original run ID and attempt and proves its evidence/screenshot/precondition/paired-edit/cleanup steps succeeded, revalidates the sealed evidence and current Play pair/screenshots, and creates recovery provenance without writing either track. It still requires the production credential because Play screenshot inspection temporarily creates and deletes an uncommitted edit; recovery never sends a track `PUT` or calls edit `:commit`.

After production publication, [`.github/workflows/android-announce.yml`](../../.github/workflows/android-announce.yml) detects the `PUBLISHED` release through Google Play's read-only release-summary endpoint and posts the tagged release notes to the Health.md Discord updates channel. Google Play has no equivalent of the App Store Connect approval webhook, so the workflow checks hourly and can also accept a `google-play-published` repository dispatch from a future external hook. Manual runs default to a no-post dry run.

Use separate protected environments and Play accounts. `google-play-qa` stores the existing upload keystore/signing values, a Play account restricted to `qa` and `wear:qa2` plus listing-image mutation, and exact variables `PLAY_APP_SIGNING_CERT_SHA256`, `WEAR_SCREENSHOT_REVIEWER`, and `WEAR_SCREENSHOT_REVIEW_TICKET`; it must not be able to mutate production. `google-play-production` stores the production-capable Play account, evidence HMAC key, protected attestor identity, independently sourced Play App Signing certificate, and independently controlled `WEAR_BATTERY_REVIEWER`, `WEAR_BATTERY_REVIEW_TICKET`, `WEAR_BATTERY_CONTROL_PROFILE`, `WEAR_PAIRED_REVIEWER`, `WEAR_PAIRED_REVIEW_TICKET`, `WEAR_SCREENSHOT_REVIEWER`, `WEAR_SCREENSHOT_REVIEW_TICKET`, `WEAR_SOURCE_REVIEWER`, and `WEAR_SOURCE_REVIEW_TICKET` values. Those protected values must match the submitted evidence and prevent an archive submitter from inventing reviewer identities or approval records. `wear-evidence-submission` contains only `WEAR_RELEASE_EVIDENCE_URL`. Require human reviewers, disable deployment self-review, and require an `android/v*` tag deployment policy on all three environments; the legacy combined `google-play` environment is not an acceptable substitute. Before dispatching any release workflow, run `scripts/check-github-wear-release-environments.sh` with a read-only authenticated `gh` session. It verifies the canonical repository identity, environment presence, required-reviewer rules, exact deployment-policy sets, and complete paginated secret/variable-name allowlists without exposing secret values; unexpected names fail because environment-level values could shadow repository inputs or cross credential boundaries. The workflow writes credentials and keystore only under `$RUNNER_TEMP`; a workspace-local `local.properties` points both Gradle application modules at that temporary keystore, and `always()` cleanup removes it. Never commit or regenerate the existing Play upload key. The separate, `main`-restricted `google-play-announce` environment stores only a dedicated read-only `PLAY_CONSOLE_KEY_JSON`, so the scheduled monitor cannot publish Play changes or access signing credentials. The Android Publisher OAuth scope is broad; least privilege comes from distinct app-level Play Console grants.

## Troubleshooting

### "Service account not found"
- For local readiness inspection, verify `PLAY_CONSOLE_KEY_PATH` points to the dedicated read-only service-account JSON supplied to `inspect-google-play-wear-readiness.sh`
- For protected workflows, verify the environment-specific `PLAY_CONSOLE_KEY_JSON` secret and least-privilege Play Console invitation; do not copy that credential to a workstation

### "Invalid version code"
- Ensure the committed `versionCode` is higher than every previous Play upload

### "Upload failed: Invalid localization"
- Screenshot dimensions must be exact
- Ensure all required files exist in listing structure

### "Health Connect permissions warning"
- App already declares Health Connect opt-in
- Make sure privacy policy is set in Play Console

## Documentation Links

- [Google Play Upload Guide](https://support.google.com/googleplay/android-developer/answer/9859152)
- [Health Connect Policies](https://developer.android.com/health-and-fitness/guides/health-connect)

## Release validation

Before a Wear-bearing upload, run the read-only Play preflight (it never creates an edit):

```bash
PLAY_CONSOLE_KEY_PATH="$HOME/.config/play-console/play-publisher-<project-id>.json" \
  EXPECTED_PHONE_VERSION_CODE=30 EXPECTED_WEAR_VERSION_CODE=1000030 \
  ./scripts/inspect-google-play-wear-readiness.sh .pi/evidence/google-play/readiness.json
```

Confirm the observed version history is compatible with committed phone/Wear codes and retain the redacted track-state artifact. The report exposes both `expectedPairAlreadyInternal` and `expectedPairAlreadyProduction`. Before promotion, the internal flag must be true while production may still be false; after promotion, the production flag is the required postcondition. `expectedPairAlreadyInternal: false` is normal before the first authorized upload; `anyWearArtifact: false` and zero `expectedWearGeneratedSigningKeys`/`expectedWearGeneratedDownloads` mean Wear form-factor recognition still requires post-upload evidence and must not be inferred locally. After upload, require the exact phone code on `qa`, exact Wear code on `wear:qa2`, plus a generated signing-key group and at least one split, standalone, or universal Wear APK download before closed-track install claims.

After the exact pair is active on `qa`/`wear:qa2`, create `.pi/evidence/wear-play/play-app-signing.json` with the read-only `capture-google-play-generated-apk-evidence.sh` collector. Supply `PLAY_CONSOLE_KEY_PATH`, exact `EXPECTED_PHONE_VERSION_CODE`/`EXPECTED_WEAR_VERSION_CODE`/`EXPECTED_VERSION_NAME`, and an independently authorized `EXPECTED_PLAY_APP_SIGNING_CERT_SHA256`; the collector lists Play-generated APKs, chooses the base-master split APK from the matching signing-key group so its digest matches the physical installed `base.apk`, downloads it through the official Generated APKs API, verifies package/version and the actual APK certificate with `apksigner`, retains the exact APK bytes and raw inventory with checksums, records both APK digests, refuses overwrite, and runs `verify-google-play-generated-apk-evidence.sh` before returning. The release preflight reruns that byte-level verifier with a separately supplied protected signer value rather than trusting receipt fields. Physical checkpoint capture requires that receipt identity and rejects either installed base APK or signer mismatch.

Before production, construct the complete unsigned/unsealed manual evidence root: `release-attestation.json` (including `versionName`, exact SHA/codes, protected release attestor, independent paired-QA reviewer/ticket, independent screenshot reviewer/ticket, exact-SHA `sourceReview.approved`/reviewer/ticket/`pullRequestNumber`/`reviewId`/time fields, and independent `manualQa.batteryReviewer`, `manualQa.batteryReviewTicket`, and `manualQa.batteryControlProfile` fields), generated APK bytes/inventories, screenshots and capture receipts, paired QA, battery controls, and successful push-CI receipt. The committed screenshot-upload receipt is not submitter-owned; protected ingest downloads it from the exact successful screenshot workflow attempt. The attestation must explicitly approve phone-first and watch-first closed-track installs, upgrade from current production, version skew, and delete/uninstall/reinstall—not just generic paired QA. Every reviewer/ticket/profile value must equal its independently configured `google-play-production` environment variable, and every reviewer must differ from the release attestor. For local blocker diagnostics, retain the independently approved source record as `.pi/evidence/wear-source-review/review.json` with schema version 1, exact `releaseSha`/`versionName`, `approved: true`, reviewer, ticket, and UTC review time, then supply matching `EXPECTED_SOURCE_REVIEWER`/`EXPECTED_SOURCE_REVIEW_TICKET`; this diagnostic live-queries remote main plus the annotated/peeled release tag and cannot create or infer review approval. The same diagnostic requires the protected `EXPECTED_BATTERY_REVIEWER`, `EXPECTED_BATTERY_REVIEW_TICKET`, `EXPECTED_BATTERY_CONTROL_PROFILE`, `EXPECTED_PAIRED_REVIEWER`, `EXPECTED_PAIRED_REVIEW_TICKET`, `EXPECTED_SCREENSHOT_REVIEWER`, and `EXPECTED_SCREENSHOT_REVIEW_TICKET` values before accepting their evidence. Current ADB phone/watch presence and unbound generated-APK counts are informational only; retained protected paired-QA evidence, the live exact `qa`/`wear:qa2` pair, and signer-bound base-master APK evidence are the corresponding completion gates. The required scenario keys are `manualQa.closedTrackPhoneFirstInstallApproved`, `manualQa.closedTrackWatchFirstInstallApproved`, `manualQa.closedTrackUpgradeFromProductionApproved`, `manualQa.closedTrackVersionSkewApproved`, and `manualQa.closedTrackDeleteUninstallReinstallApproved`; each must be JSON `true`. `sourceReview` must contain `approved: true`, the exact `releaseSha`, protected `reviewer`/`reviewTicket`, `pullRequestNumber`, `reviewId`, and `reviewedAtUtc`; `reviewTicket` must be the authoritative GitHub review URL (`https://github.com/CodyBontecou/health-md/pull/<n>#pullrequestreview-<id>`), and the pull request must be merged to canonical `main` with its head commit equal to the exact release SHA. The named independent review is authenticated, not merely asserted: with `pull-requests: read`, protected ingest fetches the pull request and the exact review from the GitHub API into the workflow-owned `source-review/` namespace, and `verify-github-source-review-evidence.py` requires a current `APPROVED` review of that exact commit by the protected reviewer (an OWNER/MEMBER/COLLABORATOR distinct from the pull-request author) with review/merge/verification timestamps in order. Before packaging, run `scripts/validate-wear-release-attestation.py --help` and validate the manifest with every exact release identity and protected reviewer/ticket/profile argument, including `--source-pull-request-number`/`--source-review-id`. The validator enforces the complete key inventory, every scenario boolean, code ranges, reviewer independence, exact source SHA, and UTC ordering; protected ingest invokes the same validator. Do **not** include `qa-upload/`, `source-review/`, `wear-play-screenshot-upload/`, `SHA256SUMS`, or `SHA256SUMS.hmac-sha256`; protected ingest downloads the exact QA AABs/receipt and screenshot committed-edit receipt from their successful protected workflow attempts, authenticates the GitHub source review itself, and creates the seal so a submitter cannot impersonate those trust boundaries.

Create a deterministic **USTAR** `wear-release-evidence.tar.gz` (for example, GNU tar `--format=ustar`; GNU/PAX extension headers are intentionally rejected), place it at a short-lived access-controlled HTTPS URL, calculate its lowercase SHA-256, and store the URL as the protected `WEAR_RELEASE_EVIDENCE_URL` secret in the `wear-evidence-submission` environment so credentials never appear in workflow inputs/run metadata. Dispatch `android-wear-evidence-submit.yml` with version, exact immutable release SHA, and archive digest. The submission workflow retains the digest-bound large archive as a GitHub artifact—never a GitHub secret. Then dispatch protected `android-wear-evidence.yml` with that successful full submission run ID **and exact attempt**, the successful `android-release.yml` QA upload run ID, the successful `android-wear-screenshots.yml` run ID plus exact attempt, and the merged source-review pull request number plus review ID. The protected provenance separately records the earlier screenshot-source submission run/attempt, which may differ from the later complete evidence submission. It queries the Actions API to prove all exact run-attempt workflow/repository/SHA/success identities, downloads and digest-verifies the attempt-specific signed AABs, pre-mutation SHA-bound QA intent, and protected screenshot committed-edit receipt, independently re-queries and retains the current exact `qa`/`wear:qa2` pair, then verifies the required exact-attempt steps, safely extracts only bounded regular files (rejecting traversal, links, devices, duplicate paths, protected namespaces, extension-header chains, and oversized content), independently re-queries the retained push-CI run attempt/jobs, records protected ingest provenance, creates the protected checksum/HMAC seal, verifies all evidence against protected attestor and Play signer inputs, and retains `wear-release-evidence-<version>-<sha>-attempt-<n>`. Supply the successful ingest run ID to production promotion; promotion independently rechecks the ingest workflow's exact attempt and complete sealed artifact before obtaining Play credentials or creating any mutation edit. A successful promotion uploads `android-production-promotion-<version>-<sha>-attempt-<n>` containing the exact new paired edit ID, source/payload/before/after/review track responses, pre-mutation screenshot set, and checksums. Download it to `.pi/evidence/google-play/production-promotion/`; `verify-android-production-promotion-evidence.sh` and the blocker preflight reject pre-existing production codes, a one-sided or mismatched payload, incorrect screenshots, or missing accepted review lifecycles. If that post-commit artifact upload alone failed, dispatch `android-promote-production-recover.yml` from the exact `android/v<version>` tag with the original promotion run ID, exact original run attempt, and evidence-ingest run ID; download its attempt-qualified recovery artifact to the same location. The recovery verifier requires the original paired-edit and cleanup step conclusions plus freshly queried exact production/screenshot state and performs no track PUT/commit. The HMAC protects retained bytes after ingest; protected environment reviewers—not the symmetric key alone—authenticate the human approval.

The initial paired AAB upload intentionally does **not** replace Wear screenshots: an exact Play-generated, Play-signed Wear APK does not exist until after that upload, so requiring its screenshots first would be circular. After Play form-factor recognition, generated-APK signer verification, closed-track installation, physical capture, and protected human visual approval, build a USTAR evidence submission containing `wear-play/`, `wear-screenshots/`, and `wear-play-screenshots/` (but not `wear-play-screenshot-upload/`). Submit it through `android-wear-evidence-submit.yml`, then dispatch `.github/workflows/android-wear-screenshots.yml` from the exact annotated `android/v<version>` tag with the semantic version, exact SHA/codes, and the submission run ID and attempt. The reviewer-protected `google-play-qa` workflow independently rechecks the exact submission attempt, APK bytes/signer, physical captures, reviewer/ticket, and source tag before materializing its QA-only Play credential. It invokes `sync-google-play-wear-screenshots.sh`, replaces exactly the two `en-US` Wear screenshots, verifies committed remote SHA-256 values, cleans credentials, and retains `wear-screenshot-upload-<version>-<sha>-attempt-<n>`. Do not invoke that implementation script with a local mutation credential. Supply the successful screenshot workflow run ID and exact attempt to later `android-wear-evidence.yml`; protected ingest downloads and injects the committed-edit receipt, while submitted archives are forbidden from supplying that namespace. Production promotion independently opens a non-committing verification edit and refuses to mutate tracks unless Play's committed screenshot hashes exactly match the sealed PNGs. This path is never a substitute for exact-installed-build capture and visual review.

From `apps/android`, validate both signed Play bundles without Play API credentials:

```bash
./gradlew :app:bundlePlayRelease :wear:bundleRelease
WEAR_REQUIRE_SIGNING_ATTESTATION=true \
  ./scripts/validate-wear-artifact.sh \
  wear/build/outputs/bundle/release/wear-release.aab \
  app/build/outputs/bundle/playRelease/app-play-release.aab
```

Verify Play access only with `inspect-google-play-wear-readiness.sh` and a dedicated read-only service account. Do not use a publisher task as a credential check: even a task described as a dry run is not release evidence and encourages bypass of the paired protected workflow.
