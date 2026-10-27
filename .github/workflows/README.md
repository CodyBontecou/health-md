# GitHub Actions CI and release pipeline

## Required pull-request gate

Require **`CI / CI`** after this change lands. The previous seven component contexts
must be removed from branch protection in the same rollout; they no longer run as
separate PR workflows. Branch protection is external configuration and is not changed
by this patch. Keep the existing requirements until the replacement workflow is
available, then switch them together to avoid pending checks or an unprotected gap.

`.github/workflows/ci.yml` runs Rust, Apple, Android and Web concurrently on every PR
and every main/testing push, without a change-planning prerequisite or path skips.
The final gate requires all four jobs and exactly four passing, clean-tree receipts
for the current SHA. It rejects missing, stale, skipped, failed and over-budget results.
Each regression command has a 90-second process deadline. The final gate measures
120 seconds from workflow creation through setup, queueing, tests, cache post-actions,
artifact transfer and final reporting. Reruns use the new attempt start and fresh
attempt-specific artifacts. Slow infrastructure is a failed budget, never a pass.

See [the retained test strategy](../../docs/qa/two-minute-ci.md) for coverage, local
commands, measurements and limitations. Removed matrices are not relocated to nightly.
`apple-ci.yml`, `android-ci.yml`, `cli-ci.yml` and `practice-ci.yml` are reusable lanes
and manual diagnostics; release callers keep their exact-SHA inputs. The compatibility
`full_qualification` input does not revive the retired suite. CLI release qualification
now requires the unified CI run. Android recovery verifies the unified CI gate and
its Android job. Signing, packaging, publication and protected deployment boundaries
remain separate release work, outside the PR regression timing claim.

## Runner assumptions

Use GitHub-hosted `macos-26` arm64 for Apple and `ubuntu-24.04` for other lanes. Never
register an everyday development Mac as a public-PR runner. Toolchain and component
compilation caches save work; Cargo, Xcode and Gradle still validate current source.
Gradle Test tasks explicitly disable result caching and up-to-date skipping. Native
result directories are removed before execution, and required test identities must
appear exactly once with no skips or failures. Apple runs hosted macOS integration tests and compiles for iOS;
Android uses one emulator, one test-only ABI, and the isolated `.e2e` app.
Release builds retain their full native architecture sets.

A two-minute hosted run has **not** been demonstrated by local measurements. Cold
native compilation, cache restoration, emulator startup and runner capacity can exceed
the total budget. Validate clean-cache and warm-cache PR runs after rollout; the gate
will remain red until the infrastructure and workload actually fit. This deliberately
exposes the remaining capacity requirement instead of disguising a deadline as proof.
The private local-runner pilot remains a manually invoked tooling experiment and does
not satisfy the public PR gate.

## Android release trigger

Android `1.9.3` is a phone-only Google Play release. `apps/android/release-scope.json` records the active artifact and explicitly defers Wear OS publication. The phone build does not advertise a Wear capability, start Wear synchronization, or expose Wear settings.

`.github/workflows/android-release.yml` builds from an annotated `android/v<version>` tag. The tag must peel to a commit reachable from `origin/main`; its version must match `app/build.gradle.kts` and `release-scope.json`. The workflow runs the reduced Android lane against that exact SHA. A `google-play-qa` job reconstructs signing material only under `$RUNNER_TEMP`, requires the registered Play upload certificate, builds and inspects the phone AAB, removes the private key, and retains the signed artifact. A separate `google-play` job downloads that exact digest, re-verifies its signer and source identity, retains a SHA/tag/run-attempt/AAB-digest-bound intent, and only then requests a short-lived Play token and uploads to `internal`. A lost commit response is reconciled against the exact track instead of retrying the non-idempotent commit.

After Internal Testing succeeds, dispatch `.github/workflows/android-promote-production.yml` **from the exact annotated release tag** with the semantic version and phone version code. It requires the same tag/main/version bindings, retains a pre-mutation intent, verifies that the exact code is active on `internal` and that production has no newer code, applies the reviewed English listing while promoting that artifact to `production`, and submits the single edit for review. Success requires Google Play to report `IN_REVIEW`, `APPROVED_NOT_PUBLISHED`, or `PUBLISHED`. The workflow retains an attempt-qualified production receipt.

Both mutation workflows use the tag-restricted `google-play` environment and exchange GitHub's job-scoped OIDC assertion for a short-lived Google access token. No long-lived Google service-account key is materialized. Configure these protected `google-play` environment variables:

| Variable | Used for |
| --- | --- |
| `GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER` | Fully qualified Google Workload Identity provider resource |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | App-scoped Play publisher service account impersonated by the provider |

The separately tag-restricted `google-play-qa` environment contains the upload-signing secrets used only by the release build job. The Play-mutation job cannot read them:

| `google-play-qa` secret | Used for |
| --- | --- |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | Existing Play upload keystore |
| `RELEASE_STORE_PASSWORD` | Upload-keystore password |
| `RELEASE_KEY_ALIAS` | Upload-key alias |
| `RELEASE_KEY_PASSWORD` | Upload-key password |

The normal execution ref is the exact `android/v<version>` release tag. If an already-created immutable release needs a workflow-infrastructure-only recovery, an administrator may add and retain an annotated, main-reachable `android/recovery/*` tag for the fixed workflow revision and pass the original `release_tag` plus a successful exact-SHA Android CI run ID/attempt. The recovery verifies every required job in that retained CI attempt instead of spending a second run on unchanged product source. It still checks out and builds only the original release tag's source. Intent and result receipts bind the release SHA, qualification run, and recovery workflow SHA. Recovery tags must never contain product or artifact changes.

`.github/workflows/android-google-play-access-audit.yml` is a protected diagnostic for these boundaries. Its `google-play` job retains intent, records exact Internal/generated-artifact state, inserts and immediately deletes one empty Play edit without committing it, and retains a receipt. Its `google-play-qa` job exposes only public certificate digests and proves the protected keystore matches the registered upload certificate before deleting the temporary key file. It has no artifact upload, track/listing update, edit-commit, or review-submission operation.

Campaign-attribution build values remain repository secrets named `CAMPAIGN_ATTRIBUTION_ENDPOINT_URL` and `CAMPAIGN_ATTRIBUTION_INGEST_TOKEN`.

Gradle Play Publisher remains removed, and local/browser Play mutation remains unsupported. The Wear evidence, screenshot, recovery, and paired-track workflows stay in the repository as dormant implementation work for a future release; they are not invoked by, and do not gate, the phone-only release. Before any future Wear publication, restore separate QA/production environments and complete the physical Pixel Watch/Samsung, battery, lifecycle, screenshot, signer, and independent-review contract documented under `apps/android/docs/features/`.

Google Play does not expose an App Store Connect-style release webhook. `.github/workflows/android-announce.yml` checks the read-only production release-summary endpoint and announces only after the exact release is `PUBLISHED`.

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
per-architecture DMGs, tests signed Keychain upgrade continuity, publishes the committed signer
ledger, regenerates all post-signing checksums, and keyless-signs `sha256.sum` with the workflow's
GitHub OIDC identity. Windows Authenticode is ledger-gated: while
`apps/cli/release-identities.json` records `pending_external_certificate_provisioning`, the Windows
signing jobs skip and the archive/installer ship unsigned with Sigstore-checksum integrity only;
when the ledger records a `qualified` publisher, both Windows executables and the PowerShell
installer are Authenticode-signed and native jobs require an exact match with the protected
variable. Native runners verify every extracted macOS signature (and every Windows signature once
qualified). The remote draft assets are then compared byte-for-byte with the qualified
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

## Direct CLI wake Worker

`.github/workflows/wake-ci.yml` owns the `apps/wake` source gate. It installs the component's locked
Node dependencies, runs the cross-language-pinned HMAC and notification policy tests, type-checks
the Worker, and builds a Wrangler dry-run bundle without credentials or deployment. Main pushes are
path-scoped; pull requests always report the stable `Wake CI / Wake CI` context.

The live Worker remains an independently deployed, notification-only service with its own D1 and
APNs secrets. Deployment is not coupled to CLI artifact publication and must use committed, pushed
`origin/main` source under `apps/wake`; see its component README and AGENTS file. No workflow in this
repository routes health data through the Worker.

## Release steps

1. Resolve a remote-safe build number with `asc builds next-build-number` for both platforms.
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, update `apps/apple/CHANGELOG.md`, in-app notes, canonical metadata, and `apps/apple/fastlane/metadata/en-US/release_notes.txt`.
3. Test from a clean worktree, commit, and push the exact source to `origin/main`.
4. Create the `v<version>` tag and a **draft** GitHub Release targeting that exact commit. Its body is the canonical customer-facing release note.
5. Dispatch both workflows with `release_tag=v<version>`. Use `skip_asc_submit=true` when upload and validation/submission should be handled as separate phases.
6. Confirm `asc validate` passes for `IOS` and `MAC_OS`, then submit both versions for review.
7. Leave the GitHub Release as a draft. `apple-announce.yml` publishes it after ASC approval.

For a no-upload smoke test, run either workflow manually with `dry_run=true`.
