# Google Play command reference

## Release ownership

Phone and Wear releases are a single versioned product pair. Gradle Play Publisher has been removed from both application modules; do not reintroduce it or upload, promote, or replace Play metadata with ad hoc Gradle/Fastlane commands. Module-level publishers cannot enforce the required `qa`/`wear:qa` and `production`/`wear:production` pairing, protected reviewer inputs, exact-SHA evidence, or one-edit production promotion.

The only supported mutation paths are:

- `.github/workflows/android-release.yml` — builds the exact annotated `android/v<version>` source and uploads the signed phone/Wear pair in one edit to `qa` and `wear:qa` using the protected `google-play-qa` environment.
- `.github/workflows/android-wear-screenshots.yml` — the only supported Wear screenshot mutation. From the exact annotated release tag it downloads an exact-attempt protected submission, verifies Play-generated APK and physical capture evidence, and invokes `scripts/sync-google-play-wear-screenshots.sh` with the reviewer-protected QA account. Never invoke the implementation script with a local mutation credential.
- `.github/workflows/android-promote-production.yml` — verifies sealed evidence before credentials, then promotes both exact codes and submits both tracks for review in one edit using `google-play-production`.
- `.github/workflows/android-promote-production-recover.yml` — non-committing recovery for a proven post-commit receipt-retention failure, bound to the exact original promotion run ID and attempt. It requires the protected production credential and temporarily creates, reads, and deletes an edit to inspect the committed screenshot set, but it never sends a track `PUT` or commits an edit.

Never use one account for both QA upload and production mutation. Never place the Wear artifact on a phone/default track.

## Safe local commands

Run from `apps/android`.

### Build and test

```bash
./gradlew :app:testDebugUnitTest :wearable-contract:test :wear:testDebugUnitTest :direct-protocol:test
./gradlew :app:lintDebug :wear:lintDebug
./gradlew :app:assembleDebug :wear:assembleDebug
./gradlew :app:bundleRelease :wear:bundleRelease
```

A release build requires externally supplied signing configuration. Local substitute signing proves only build/package behavior and is not production-signing evidence.

### Validate local release artifacts

```bash
WEAR_REQUIRE_SIGNING_ATTESTATION=true \
  ./scripts/validate-wear-artifact.sh \
  wear/build/outputs/bundle/release/wear-release.aab \
  app/build/outputs/bundle/release/app-release.aab

bundle exec fastlane android validate_wear_release
```

`validate_wear_release` builds and inspects both AABs without publication.

### Validate authored Play metadata

```bash
./scripts/validate-play-listing.sh
python3 ./scripts/validate-wear-play-assets.py
```

The Wear asset validator intentionally fails until the two exact-release physical-watch screenshots exist.

### Read-only Play readiness

Use a dedicated read-only Play service account, never a QA or production mutation credential:

```bash
PLAY_CONSOLE_KEY_PATH="$HOME/.config/play-console/health-md-read-only.json" \
  EXPECTED_PHONE_VERSION_CODE=30 EXPECTED_WEAR_VERSION_CODE=1000030 \
  ./scripts/inspect-google-play-wear-readiness.sh \
  .pi/evidence/google-play/readiness.json
```

This query creates no Play edit. Treat its output as time-bounded mutable-state evidence and re-run it immediately before an authorized release action.

### Local blocker report

```bash
./scripts/report-wear-release-blockers.sh
./scripts/verify-wear-audit-evidence.sh
```

Both commands are diagnostic. They cannot turn emulator, substitute-signed, or self-authored evidence into protected release proof.

## Authorized release sequence

1. Commit and independently review the complete source on a SHA reachable from `origin/main`.
2. Create the annotated `android/v<version>` tag at that exact SHA.
3. Require successful exact-SHA push CI and retain its independently re-queried receipt.
4. Authorize `android-release.yml` to upload the exact signed phone/Wear pair to `qa`/`wear:qa`.
5. Download and verify Play-generated base-master APKs and the Play App Signing identity.
6. Complete closed-track, Pixel/Samsung, accessibility, privacy, offline, screenshot, and battery protocols.
7. Submit the reviewed exact-release Wear screenshot evidence through `android-wear-evidence-submit.yml`, then dispatch `android-wear-screenshots.yml` from the exact release tag with that submission run ID and attempt. Retain its protected attempt-qualified receipt.
8. Submit the unsigned evidence archive, run protected ingest, and verify the checksum/HMAC-sealed artifact.
9. Authorize the one-edit paired production promotion.
10. Retain and independently verify the exact promotion receipt.

See `PLAY_STORE_SETUP.md`, `docs/features/wear-os-implementation.md`, and `docs/features/wear-os-completion-audit.md` for the complete evidence contract.
