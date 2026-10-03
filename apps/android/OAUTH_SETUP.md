# Interactive Play OAuth is unsupported for releases

The former interactive Gradle Play Publisher OAuth flow is retired, and the publisher plugin has been removed from both Android application modules.

An interactive developer token cannot provide the required separation between:

- QA-only `qa`/`wear:internal` upload authority,
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

The current phone-only release path uses GitHub OIDC with Google Workload Identity Federation in the tag-restricted `google-play` environment. `GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER` identifies a provider constrained to this repository, the `google-play` environment subject, and Android tags; `GOOGLE_PLAY_SERVICE_ACCOUNT` identifies the app-scoped Play publisher. A separate tag-restricted `google-play-qa` job signs the AAB with the registered upload certificate, deletes the temporary keystore, and transfers only the exact signed artifact to `google-play`. The mutation job requests a short-lived `androidpublisher` access token only after re-verifying that artifact and retaining pre-mutation intent evidence. No Google authentication private key is downloaded or written.

Keep other duties separated:

- Future Wear QA/production environments must use independently protected, least-privilege identities when that release path is reactivated.
- `google-play-announce` uses a dedicated app-level read-only account.
- Optional local readiness inspection uses a separate app-level read-only account passed through `PLAY_CONSOLE_KEY_PATH`.

Upload-signing material never enters the Play-mutation job and is removed before Play access is requested. Never copy an upload keystore or QA/production mutation key to a developer workstation.

## Safe local verification

Build and validate without Play authentication:

```bash
./gradlew :app:bundlePlayRelease :wear:bundleRelease
WEAR_REQUIRE_SIGNING_ATTESTATION=true \
  ./scripts/validate-wear-artifact.sh \
  wear/build/outputs/bundle/release/wear-release.aab \
  app/build/outputs/bundle/playRelease/app-play-release.aab
```

For a read-only Play query:

```bash
PLAY_CONSOLE_KEY_PATH="$HOME/.config/play-console/health-md-read-only.json" \
  EXPECTED_PHONE_VERSION_CODE=30 EXPECTED_WEAR_VERSION_CODE=1000030 \
  ./scripts/inspect-google-play-wear-readiness.sh \
  .pi/evidence/google-play/readiness.json
```

See `PLAY_STORE_COMMANDS.md` and `PLAY_STORE_SETUP.md` for the protected release flow.
