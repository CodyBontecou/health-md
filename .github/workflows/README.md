# GitHub Actions CI and release pipeline

## Required pull-request gates

Every pull request triggers the component CI workflows, and each reports one of seven stable final contexts suitable for branch protection:

- `Apple CI / Apple CI`
- `Android CI / Android CI`
- `CLI CI / CLI CI`
- `Core Rust CI / Core Rust CI`
- `Practice CI / Practice CI`
- `Wake CI / Wake CI`
- `Website CI / Website CI`

Inside each workflow except Wake CI (whose single job finishes in well under a minute and stays always-on), a small `changes` job evaluates the pull request's changed files through `.github/actions/component-changes` against the same path map that gates that workflow's `main`-branch push trigger. When nothing matches, the heavy jobs are skipped and the final gate job still runs and succeeds, so every PR receives a conclusive required context without paying for unaffected components. Detection fails closed: if the `changes` job itself errors, the gate fails rather than silently skipping. Scheduled, manually dispatched, and `workflow_call` release-qualification runs always execute the full workflow.

Each workflow's path map lives in two places — the `on.push.paths` trigger filter and the `changes` job's `paths` input — and the two copies must stay in sync. Shared contract paths (`packages/contracts/**`) and shared-core paths (`packages/healthmd-core-rust/**`) intentionally trigger every consuming component, including Apple CI.

The final gate jobs fail unless every job in their component workflow succeeds (or path filtering skipped the whole component). Main-branch push triggers remain path-aware — Apple CI's `main`/`testing` pushes included — so unaffected components are not rebuilt after merge.

## Android release trigger

Android `1.9.1` is a phone-only Google Play release. `apps/android/release-scope.json` records the active artifact and explicitly defers Wear OS publication. The phone build does not advertise a Wear capability, start Wear synchronization, or expose Wear settings.

`.github/workflows/android-release.yml` builds from an annotated `android/v<version>` tag. The tag must peel to a commit reachable from `origin/main`; its version must match `app/build.gradle.kts` and `release-scope.json`. The workflow re-runs the complete Android CI matrix against that exact SHA, reconstructs signing material only under `$RUNNER_TEMP`, builds and inspects the signed phone AAB, and retains both the AAB and a SHA/tag/run-attempt/AAB-digest-bound intent before opening a Play edit. It uploads the phone artifact to `internal`. A lost commit response is reconciled against the exact track instead of retrying the non-idempotent commit.

After Internal Testing succeeds, dispatch `.github/workflows/android-promote-production.yml` **from the exact annotated release tag** with the semantic version and phone version code. It requires the same tag/main/version bindings, retains a pre-mutation intent, verifies that the exact code is active on `internal` and that production has no newer code, applies the reviewed English listing while promoting that artifact to `production`, and submits the single edit for review. Success requires Google Play to report `IN_REVIEW`, `APPROVED_NOT_PUBLISHED`, or `PUBLISHED`. The workflow retains an attempt-qualified production receipt.

Both mutation workflows use the tag-restricted `google-play` environment and exchange GitHub's job-scoped OIDC assertion for a short-lived Google access token. No long-lived Google service-account key is materialized. Configure these protected environment variables:

| Variable | Used for |
| --- | --- |
| `GOOGLE_PLAY_WORKLOAD_IDENTITY_PROVIDER` | Fully qualified Google Workload Identity provider resource |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | App-scoped Play publisher service account impersonated by the provider |

The environment contains only the upload-signing secrets needed by the release build:

| Secret | Used for |
| --- | --- |
| `ANDROID_RELEASE_KEYSTORE_BASE64` | Existing Play upload keystore |
| `RELEASE_STORE_PASSWORD` | Upload-keystore password |
| `RELEASE_KEY_ALIAS` | Upload-key alias |
| `RELEASE_KEY_PASSWORD` | Upload-key password |

The normal execution ref is the exact `android/v<version>` release tag. If an already-created immutable release needs a workflow-infrastructure-only recovery, an administrator may add and retain an annotated, main-reachable `android/recovery/*` tag for the fixed workflow revision and pass the original `release_tag` input. The workflow still checks out, qualifies, builds, and promotes only the original release tag's source. Intent and result receipts bind both the release SHA and recovery workflow SHA. Recovery tags must never contain product or artifact changes.

`.github/workflows/android-google-play-access-audit.yml` is a protected diagnostic for this boundary. It retains intent, verifies an Internal-track read, inserts and immediately deletes one empty Play edit without committing it, and retains a receipt. It has no artifact upload, track/listing update, edit-commit, or review-submission operation.

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
