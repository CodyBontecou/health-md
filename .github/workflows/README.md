# GitHub Actions CI and release pipeline

## Required pull-request gates

Every pull request runs the component CI workflows and reports five stable final contexts suitable for branch protection:

- `Apple CI / Apple CI`
- `Android CI / Android CI`
- `CLI CI / CLI CI`
- `Practice CI / Practice CI`
- `Website CI / Website CI`

The final jobs fail unless every job in their component workflow succeeds. Main-branch push triggers remain path-aware, so unaffected components are not rebuilt after merge.

## Android release trigger

Android releases are built from committed `android/v<version>` tags by `.github/workflows/android-release.yml`. The tag version must match `versionName`, and `versionCode` must already be higher than every build previously uploaded to Play.

The workflow reconstructs the existing upload keystore and Play service-account key only under `$RUNNER_TEMP`, builds a signed AAB, and uploads it directly to Google Play's `internal` track. It does not commit the AAB or attach it to a GitHub Release. Production promotion remains a manual Play Console decision.

Google Play does not expose an App Store Connect-style release webhook. `.github/workflows/android-announce.yml` therefore checks the read-only production release-summary endpoint hourly. When a version becomes `PUBLISHED`, it resolves the matching annotated `android/v<version>` tag by `versionCode`, requires its commit to be reachable from `origin/main`, uses that tag's English Play release notes, and posts the Android message to `#health-md-updates`. A successful `discord/android-production` commit status is the durable marker; an exact, bot-authored, bounded Discord history check reconciles a lost POST response before an immediate retry. The workflow also supports a dry-run manual dispatch and an optional `google-play-published` repository dispatch from a future external hook; every dispatch is revalidated against Google Play.

The tag-restricted `google-play` environment contains:

| Secret | Used for |
| --- | --- |
| `PLAY_CONSOLE_KEY_JSON` | Google Play Android Developer API authentication |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | Existing Play upload keystore, encoded for secret storage |
| `RELEASE_STORE_PASSWORD` | Upload-keystore password |
| `RELEASE_KEY_ALIAS` | Upload-key alias |
| `RELEASE_KEY_PASSWORD` | Upload-key password |

Campaign-attribution build values are repository secrets named `CAMPAIGN_ATTRIBUTION_ENDPOINT_URL` and `CAMPAIGN_ATTRIBUTION_INGEST_TOKEN`. They match the deployed first-party Worker; the prior internal-testing token remains a temporary Worker-only overlap value during rotation.

The `google-play-announce` environment is restricted to `main` and contains only `PLAY_CONSOLE_KEY_JSON`. Use a dedicated service account whose only Play Console permission is app-level **View app information (read-only)** (`CAN_VIEW_NON_FINANCIAL_DATA`) for `com.healthmd.android`; the Android Publisher OAuth scope itself is broad, so reusing the publishing service account would not make the credential read-only. Keeping the environment separate prevents the monitor from receiving the upload keystore or signing passwords. Apple and Android announcements suppress Discord mentions because the retired per-app roles no longer exist.

## Apple release trigger

Health.md ships iOS and macOS builds to App Store Connect from GitHub Actions.

The canonical release path starts from a draft GitHub Release whose tag starts with `v` (for example `v3.0`). After creating the draft against the exact committed and pushed `origin/main` SHA, dispatch both workflows with that tag through `workflow_dispatch`:

- `.github/workflows/release-ios.yml`
- `.github/workflows/release-macos.yml`

Use `release_tag=v<version>`. The tag version must match `MARKETING_VERSION` in `apps/apple/HealthMd.xcodeproj`; each workflow fails early if it does not. Keep the GitHub Release as a draft while App Store review is in progress. The ASC approval webhook and `apple-announce.yml` publish it.

Publishing a release still triggers both workflows as a legacy fallback, but it is not the canonical path because publication must wait for ASC approval.

## What the workflows do

1. Build and sign the iOS `.ipa` and macOS App Store `.pkg`.
2. Upload each build to App Store Connect with `asc builds upload`.
3. Discover the processed ASC build through the builds API rather than treating an upload operation ID as a build ID.
4. Create or reuse the matching ASC version, apply locale-specific `metadata/version/<version>/*.json` release notes, validate it, and submit it for review.
5. Attach the notarized macOS Developer ID zip to the draft GitHub Release.
6. Wait for the ASC approval webhook (`apple-announce.yml`) to publish the release, publish the macOS zip to isolated.tech, record the release and note history in the internal registry, and post Discord announcements.

Bot-authored release publishes are skipped so legacy draft releases promoted by `apple-announce.yml` do not redeploy the same build.

## Required repository secrets

These are configured under Settings → Secrets and variables → Actions:

| Secret | Used for |
| --- | --- |
| `APPLE_CERTIFICATE_P12` | Combined signing identities for iOS, Mac App Store, Developer ID, and installer signing |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` bundle |
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `IOS_APP_STORE_PROVISIONING_PROFILE` | Base64-encoded iOS App Store provisioning profile |
| `MAC_APP_STORE_PROVISIONING_PROFILE` | Base64-encoded Mac App Store provisioning profile |
| `APPLE_ID` | Apple ID for notarization |
| `APPLE_ID_PASSWORD` | App-specific password for notarization |
| `ASC_KEY_ID` | App Store Connect API key id |
| `ASC_ISSUER_ID` | App Store Connect issuer id |
| `ASC_API_KEY_P8` | Base64-encoded ASC `.p8` private key |
| `HEALTHMD_ASC_APP_ID` | App Store Connect app id |
| `ISOLATED_API_KEY` | isolated.tech publish from `apple-announce.yml` |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle signing for isolated.tech publish |
| `DISCORD_BOT_TOKEN` | Apple and Android Discord release announcements |
| `INTERNAL_RELEASE_API_TOKEN` | Authenticated release-registry ingestion |

Optional repository secret:

| Secret | Used for |
| --- | --- |
| `LLM_WIKI_DISPATCH_TOKEN` | Launch-checklist dispatch from `apple-announce.yml` |

Required repository variable:

| Variable | Used for |
| --- | --- |
| `ISOLATED_APP_SLUG` | isolated.tech app slug |
| `INTERNAL_RELEASE_API_URL` | Release-registry ingestion endpoint |

## Standalone CLI release signing

`healthmd-cli/v<version>` tags run `.github/workflows/cli-release.yml`. The workflow rebuilds and
qualifies the exact tag SHA, then pauses at the protected `cli-signing` environment before it can
use external signing identities. It Developer ID-signs both macOS executables, notarizes and staples
per-architecture DMGs, Authenticode-signs both Windows executables and the generated PowerShell
installer, tests signed Keychain upgrade continuity, publishes the committed qualified signer
ledger, regenerates all post-signing checksums, and keyless-signs `sha256.sum` with the workflow's
GitHub OIDC identity. The tag preflight fails while `apps/cli/release-identities.json` has no
qualified Windows publisher, and native jobs require an exact match with the protected variable. Native runners verify every
extracted signature. The remote draft assets are then compared byte-for-byte with the qualified
workflow artifacts before the separate protected `cli-release` environment can publish them.

The repository variables, `cli-signing` environment secrets, rollback/key-compromise/crates-yank/
Homebrew runbooks, and mobile compatibility requirements are documented in
[`releasing.md`](../../apps/cli/docs/releasing.md) and
[`architecture.md`](../../apps/cli/docs/architecture.md). Complete one health-free
[`release-evidence-template.md`](../../apps/cli/docs/release-evidence-template.md) per candidate.
Azure uses an environment-scoped federated credential and the minimum Artifact Signing Certificate
Profile Signer role; it does not use a client secret. Pull requests
never receive signing credentials and produce unsigned smoke candidates only. A missing signing
input, rejected notarization, absent timestamp, checksum mismatch, stale/extra draft asset, or
credential-upgrade failure leaves the release in draft state.

## Release steps

1. Resolve a remote-safe build number with `asc builds next-build-number` for both platforms.
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, update `apps/apple/CHANGELOG.md`, in-app notes, canonical metadata, and `apps/apple/fastlane/metadata/en-US/release_notes.txt`.
3. Test from a clean worktree, commit, and push the exact source to `origin/main`.
4. Create the `v<version>` tag and a **draft** GitHub Release targeting that exact commit. Its body is the canonical customer-facing release note.
5. Dispatch both workflows with `release_tag=v<version>`. Use `skip_asc_submit=true` when upload and validation/submission should be handled as separate phases.
6. Confirm `asc validate` passes for `IOS` and `MAC_OS`, then submit both versions for review.
7. Leave the GitHub Release as a draft. `apple-announce.yml` publishes it after ASC approval.

For a no-upload smoke test, run either workflow manually with `dry_run=true`.
