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

The workflow requires the annotated tag's peeled commit to equal the triggering SHA, reconstructs the existing upload keystore and QA-only Play service-account key only under `$RUNNER_TEMP`, builds the signed phone/Wear AAB pair, and uploads both in one Play edit to `qa` (phone) and `wear:qa` (Wear). It does not commit either AAB or attach them to a GitHub Release. Before opening the Play edit, the workflow retains the exact signed AABs plus a SHA/tag/run-attempt/AAB-digest-bound QA upload intent receipt under attempt-specific artifact names. After Play generation and physical capture, `.github/workflows/android-wear-screenshots.yml` runs from the same exact annotated tag in `google-play-qa`, rechecks an exact-attempt protected evidence submission, and is the only supported mutation of the two Wear listing images. It cleans credentials and retains an attempt-qualified committed-edit receipt. Protected evidence ingest requires the successful release and screenshot run IDs/attempts, re-queries their workflow/repository/SHA and required step conclusions, downloads those protected artifacts directly, and includes them in the sealed evidence rather than trusting submitter-supplied upload claims. The non-idempotent Play commit POSTs are each issued once; lost success responses are reconciled against exact committed state instead of retried. No mandatory artifact write remains after Play consumes the version codes. `.github/workflows/android-promote-production.yml` uses a separate production-capable environment/account to promote the exact tagged codes atomically to `production` and `wear:production` without rebuilding either artifact. It fails if either exact code is already on production rather than bypassing the required paired edit, independently compares Play's committed Wear screenshot hashes with the sealed approved PNGs, verifies both form-factor track postconditions, and retains an exact-edit promotion receipt. A pre-mutation intent artifact makes post-commit receipt retention recoverable: if only the later receipt upload fails, `android-promote-production-recover.yml` requires the exact original run ID and attempt plus successful evidence/screenshot/precondition/paired-edit/cleanup steps, revalidates the sealed evidence and current Play pair/screenshots without track mutation, and retains recovery provenance. Recovery is non-committing, not API-read-only: Play screenshot inspection temporarily creates and deletes an edit with the production credential, while policy forbids any track `PUT` or edit `:commit`. Keep the QA account unable to mutate production tracks; repository workflow gates are defense in depth, not a substitute for Play-side least privilege.

Large physical evidence is never stored in a GitHub secret. An authorized operator places one unsigned/unsealed **USTAR** `wear-release-evidence.tar.gz` (GNU/PAX extension headers are forbidden) at a one-time HTTPS URL stored as the protected `WEAR_RELEASE_EVIDENCE_URL` environment secret, then dispatches `android-wear-evidence-submit.yml` with its exact SHA-256 and immutable release SHA. That submission workflow retains the digest-bound archive under a run-attempt-specific artifact name. A separately protected `android-wear-evidence.yml` run takes the full submission run ID/attempt, successful exact-SHA QA upload run ID, successful screenshot-publication run ID/attempt, and the merged source-review pull request number plus review ID; protected provenance also records the screenshot workflow's earlier source-submission run/attempt without conflating it with the complete submission. It validates their exact attempts, authenticates the independent GitHub source review through the pull-requests API into a workflow-owned namespace, safely extracts only bounded regular files, injects the exact-attempt QA AABs/receipt and protected screenshot committed-edit receipt from GitHub artifacts, independently re-queries the current exact `qa`/`wear:qa` pair and remote-CI run attempt, creates the protected checksum/HMAC seal, verifies every phase-6/7 artifact, and retains a SHA/version/run-attempt-named artifact. Production promotion requires that successful ingest run ID and independently revalidates its exact attempt before obtaining Play credentials.

Google Play does not expose an App Store Connect-style release webhook. `.github/workflows/android-announce.yml` therefore checks the read-only production release-summary endpoint hourly. When a version becomes `PUBLISHED`, it resolves the matching annotated `android/v<version>` tag by `versionCode`, requires its commit to be reachable from `origin/main`, uses that tag's English Play release notes, and posts the Android message to `#health-md-updates`. A successful `discord/android-production` commit status is the durable marker; an exact, bot-authored, bounded Discord history check reconciles a lost POST response before an immediate retry. The workflow also supports a dry-run manual dispatch and an optional `google-play-published` repository dispatch from a future external hook; every dispatch is revalidated against Google Play.

The release path uses separate protected environments and Play accounts. `google-play-qa` contains the upload key plus a Play service account restricted to `qa`/`wear:qa`. `google-play-production` contains the production-capable account, evidence HMAC key, protected attestor identity, and independently configured Play App Signing certificate. `wear-evidence-submission` protects the `WEAR_RELEASE_EVIDENCE_URL` secret used for one-time intake and must not contain Play mutation credentials. `google-play-qa` also contains only the non-secret `PLAY_APP_SIGNING_CERT_SHA256`, `WEAR_SCREENSHOT_REVIEWER`, and `WEAR_SCREENSHOT_REVIEW_TICKET` variables needed to bind protected screenshot publication. All three environments require human reviewers with deployment self-review disabled and an `android/v*` tag deployment policy before the first release; GitHub does not safely infer those controls from workflow YAML. Run `apps/android/scripts/check-github-wear-release-environments.sh` with an authenticated read-only `gh` session to verify the canonical repository identity, environment presence, reviewer rules, exact deployment-policy sets, complete paginated secret/variable-name allowlists, and absence of cross-environment credential shadowing without reading secret values. The legacy combined `google-play` environment does not satisfy this separation.

| Secret | Used for |
| --- | --- |
| `PLAY_CONSOLE_KEY_JSON` | Environment-specific Google Play authentication; QA and production use different least-privilege accounts |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | Existing Play upload keystore, encoded for secret storage (`google-play-qa` only) |
| `RELEASE_STORE_PASSWORD` | Upload-keystore password (`google-play-qa` only) |
| `RELEASE_KEY_ALIAS` | Upload-key alias (`google-play-qa` only) |
| `RELEASE_KEY_PASSWORD` | Upload-key password (`google-play-qa` only) |
| `WEAR_RELEASE_EVIDENCE_HMAC_KEY` | Protected post-ingest integrity seal (`google-play-production` only) |

The production environment variables `WEAR_RELEASE_EVIDENCE_ATTESTOR`, `PLAY_APP_SIGNING_CERT_SHA256`, `WEAR_BATTERY_REVIEWER`, `WEAR_BATTERY_REVIEW_TICKET`, `WEAR_BATTERY_CONTROL_PROFILE`, `WEAR_PAIRED_REVIEWER`, `WEAR_PAIRED_REVIEW_TICKET`, `WEAR_SCREENSHOT_REVIEWER`, `WEAR_SCREENSHOT_REVIEW_TICKET`, `WEAR_SOURCE_REVIEWER`, and `WEAR_SOURCE_REVIEW_TICKET` bind verification to independently controlled identities and approval records. The duplicated QA signer/reviewer/ticket values must equal their production-environment counterparts; the QA workflow uses them only for pre-production screenshot publication. The protected values must match the submitted receipts and manual attestation; reviewers must differ from the release attestor. Source review must explicitly approve the exact release SHA. The symmetric HMAC protects retained bytes after protected ingest; it does not by itself authenticate a human. Require environment reviewers and retain the review/audit record.

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
extracted signature. The generated Homebrew formula is normalized in an isolated tap before the
checksum closure is signed. The remote draft assets are then compared byte-for-byte with the
qualified workflow artifacts before the separate protected `cli-release` environment can publish
them. After publication, the sealed formula clean-installs on every supported macOS/Linux
architecture, preserves the signed binaries byte-for-byte, and completes an installed MCP handshake
before a serialized, anti-rollback tap job pushes and remotely rechecks the exact formula blob.

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
