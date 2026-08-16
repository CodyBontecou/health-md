# Interactive Play OAuth is unsupported for releases

The former interactive Gradle Play Publisher OAuth flow is retired, and the publisher plugin has been removed from both Android application modules.

An interactive developer token cannot provide the required separation between:

- QA-only `qa`/`wear:qa` upload authority,
- production-only `production`/`wear:production` mutation authority,
- read-only release monitoring,
- protected environment review and independently bound release evidence.

Do not authenticate a local Gradle or Fastlane process with a personal Play developer account to upload, promote, submit for review, or replace metadata.

## Remove old local authorization

If Gradle Play Publisher was previously authorized interactively:

1. Revoke its access from the Google Account permissions page.
2. Remove its cached local OAuth token from the Gradle user home.
3. Confirm no token or service-account JSON exists in the repository or build artifacts.

Do not print token contents while checking cleanup.

## Supported authentication model

Use protected, least-privilege service accounts:

- `google-play-qa` environment: upload key plus a Play account restricted to `qa` and `wear:qa`.
- `google-play-production` environment: production-capable account used only after sealed evidence verification and environment approval.
- `google-play-announce` environment: dedicated app-level read-only account.
- Optional local readiness inspection: a separate app-level read-only account passed through `PLAY_CONSOLE_KEY_PATH`.

Credentials are written only under the protected runner's temporary directory and removed in unconditional cleanup. Signing material is removed before Play credentials are materialized.

## Safe local verification

Build and validate without Play authentication:

```bash
./gradlew :app:bundleRelease :wear:bundleRelease
WEAR_REQUIRE_SIGNING_ATTESTATION=true \
  ./scripts/validate-wear-artifact.sh \
  wear/build/outputs/bundle/release/wear-release.aab \
  app/build/outputs/bundle/release/app-release.aab
```

For a read-only Play query:

```bash
PLAY_CONSOLE_KEY_PATH="$HOME/.config/play-console/health-md-read-only.json" \
  EXPECTED_PHONE_VERSION_CODE=29 EXPECTED_WEAR_VERSION_CODE=1000029 \
  ./scripts/inspect-google-play-wear-readiness.sh \
  .pi/evidence/google-play/readiness.json
```

See `PLAY_STORE_COMMANDS.md` and `PLAY_STORE_SETUP.md` for the protected release flow.
