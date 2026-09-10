# Google Play command reference

## Current release ownership

The current Google Play release scope is **phone-only**. `release-scope.json` is the machine-readable source of truth: Android `1.9.1` publishes `:app` version code `39`, while the `:wear` artifact is deferred and is not uploaded, promoted, or advertised by the phone app.

Gradle Play Publisher remains removed. Do not upload, promote, submit review, or replace Play metadata with ad hoc Gradle, Fastlane, browser, or local API commands. The only supported mutation paths are:

- `.github/workflows/android-release.yml` — qualifies an exact annotated, main-reachable `android/v<version>` tag, builds the signed phone AAB, retains SHA/AAB-bound intent evidence, and uploads it to `internal`.
- `.github/workflows/android-promote-production.yml` — runs from that exact tag, promotes the same phone version code from `internal` to `production`, applies the reviewed listing in that same edit, submits it for review, and verifies the resulting lifecycle.

`.github/workflows/android-google-play-access-audit.yml` is the only supported credential diagnostic. From an allowed annotated Android tag, it retains intent, obtains a short-lived token, verifies an Internal-track read, inserts and immediately deletes one empty edit, and retains a receipt proving that no edit was committed. It cannot upload an artifact, change a track/listing, or submit review.

Both release workflows use the protected, tag-restricted `google-play` environment and short-lived Google Workload Identity Federation. The environment normally allows `android/v*`; a retained `android/recovery/*` tag is permitted only for a main-reachable workflow-infrastructure fix that still binds all artifact work to the original immutable release tag. The environment stores the upload-signing secrets plus `GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER` and `GOOGLE_PLAY_SERVICE_ACCOUNT` variables; it does not need a long-lived Play JSON key. Generated AABs remain workflow artifacts and are never committed.

The Wear workflows and evidence tools remain in the repository as dormant implementation material for the planned `1.10.0` qualification cycle. They are not part of the current release sequence and must not be dispatched for `1.9.1`.

## Safe local commands

Run from `apps/android`.

```bash
./gradlew :app:testPlayDebugUnitTest :app:testFdroidDebugUnitTest :direct-protocol:test
./gradlew :app:lintPlayDebug :app:lintFdroidDebug
./gradlew :app:assemblePlayDebug
./gradlew :app:bundlePlayRelease
./scripts/validate-play-listing.sh
```

A release build requires externally supplied signing configuration. Local substitute signing proves only build/package behavior and is not production-signing evidence.

The deferred Wear implementation may still be compiled and tested without publication:

```bash
./gradlew :wearable-contract:test :wear:testDebugUnitTest :wear:assembleDebug
bundle exec fastlane android validate_wear_release
```

## Authorized phone release sequence

1. Commit the complete source and push it to `origin/main`.
2. Require successful Android CI for that exact SHA.
3. Create an annotated `android/v<version>` tag at the exact main-reachable SHA.
4. Let `.github/workflows/android-release.yml` re-run exact-SHA qualification and upload the phone AAB to Internal Testing.
5. Verify that workflow's signed AAB, immutable intent, and committed-upload receipt artifacts.
6. Dispatch `.github/workflows/android-promote-production.yml` from the exact annotated release tag with the exact version name and phone version code. Use its `release_tag` recovery input only from an annotated, main-reachable `android/recovery/*` workflow tag after an infrastructure-only fix; the checked-out product source remains the original release tag. An Internal-upload recovery also requires the successful exact-SHA Android CI run ID and attempt so the workflow can reverify all retained qualification jobs without rebuilding unchanged test inputs.
7. Require the workflow to prove `IN_REVIEW`, `APPROVED_NOT_PUBLISHED`, or `PUBLISHED` before treating the submission as successful.
8. Monitor Play review and publish the Android announcement only after Google Play reports the production release as published.

See `PLAY_STORE_SETUP.md` for protected credential setup. See `docs/features/wear-os-completion-audit.md` for the deferred Wear qualification work; it is not a phone-release gate.
