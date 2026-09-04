# Gradle Play Publisher removal

Gradle Play Publisher has been removed from both Android application modules. Module-level publisher tasks could not enforce atomic phone/Wear track assignment, immutable source provenance, protected evidence, or separate QA and production credentials, so retaining them created an avoidable release-policy bypass.

Do not reintroduce `com.github.triplet.play`, a module `play {}` block, or Gradle Play mutation tasks. Use the protected workflows described in `PLAY_STORE_COMMANDS.md` and `PLAY_STORE_SETUP.md`.

## Supported local use

From `apps/android`, Gradle may be used to build and test both artifacts without Play credentials:

```bash
./gradlew :app:testPlayDebugUnitTest :wearable-contract:test :wear:testDebugUnitTest :direct-protocol:test
./gradlew :app:lintPlayDebug :wear:lintDebug
./gradlew :app:bundlePlayRelease :wear:bundleRelease
```

Release bundles require signing configuration from `local.properties` or protected workflow inputs. Never commit a keystore or `local.properties`. Substitute signing is acceptable only for local package/runtime validation and is never production-signing evidence.

Validate both outputs together:

```bash
WEAR_REQUIRE_SIGNING_ATTESTATION=true \
  ./scripts/validate-wear-artifact.sh \
  wear/build/outputs/bundle/release/wear-release.aab \
  app/build/outputs/bundle/playRelease/app-play-release.aab
```

## Play credentials

Use three separate trust domains:

- `google-play-qa`: existing upload key and a service account restricted to `qa` and `wear:qa2`.
- `google-play-production`: production-capable service account, protected release/evidence identities, Play App Signing certificate, and evidence HMAC key.
- `google-play-announce`: app-level read-only service account only.

The release workflows materialize credentials only under `$RUNNER_TEMP`, remove signing material before Play credentials exist, and unconditionally clean up. Do not cache an interactive OAuth token for release work; it bypasses environment review and least-privilege separation.

A local read-only readiness query may use a fourth read-only service account:

```bash
PLAY_CONSOLE_KEY_PATH="$HOME/.config/play-console/health-md-read-only.json" \
  EXPECTED_PHONE_VERSION_CODE=30 EXPECTED_WEAR_VERSION_CODE=1000030 \
  ./scripts/inspect-google-play-wear-readiness.sh \
  .pi/evidence/google-play/readiness.json
```

## Canonical publication flow

1. An annotated `android/v<version>` tag must peel to the exact requested SHA and be reachable from `origin/main`.
2. `.github/workflows/android-release.yml` builds/signs both AABs, retains an immutable pre-mutation intent, and uploads phone to `qa` plus Wear to `wear:qa2` in one Play edit.
3. Play-generated base-master APKs, signer identity, closed-track behavior, physical QA, screenshots, and battery evidence are captured and independently reviewed.
4. `.github/workflows/android-wear-screenshots.yml` verifies an exact-attempt protected submission and commits only the two approved Wear images with the QA-only account.
5. Protected ingest verifies the exact QA and screenshot workflow attempts, safe evidence archive, exact-SHA push CI, and protected reviewer identities before sealing the bundle.
6. `.github/workflows/android-promote-production.yml` verifies the seal before credentials and moves the exact pair to `production`/`wear:production` in one edit.

The initial AAB upload intentionally does not require Wear screenshots because exact Play-generated APKs do not exist until after that upload. Screenshot replacement is a later protected, evidence-bound workflow; never run its mutation implementation with local credentials.

## References

- `PLAY_STORE_COMMANDS.md` — safe commands and release sequence
- `PLAY_STORE_SETUP.md` — accounts, evidence ingest, and production promotion
- `fastlane/README.md` — non-publishing validation lane
- `docs/features/wear-os-completion-audit.md` — authoritative completion status
