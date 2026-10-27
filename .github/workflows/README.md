# GitHub Actions CI and release pipeline

## Required pull-request gates

Every pull request triggers the component CI workflows, and each reports one of eight stable final contexts suitable for branch protection:

- `Apple CI / Apple CI`
- `Android CI / Android CI`
- `CLI CI / CLI CI`
- `Core Rust CI / Core Rust CI`
- `Practice CI / Practice CI`
- `Wake CI / Wake CI`
- `Cloud CI / Cloud CI`
- `Website CI / Website CI`

Inside each workflow except Wake CI and Cloud CI (whose single job finishes in well under a minute and stays always-on), a small `changes` job evaluates the pull request's changed files. Most use `.github/actions/component-changes` against the same path map that gates that workflow's `main`-branch push trigger; Apple and Android use the job planners described below. When nothing matches, the heavy jobs are skipped and the final gate job still runs and succeeds, so every PR receives a conclusive required context without paying for unaffected components. Detection fails closed: if the `changes` job itself errors, the gate fails rather than silently skipping. Scheduled, manually dispatched, and `workflow_call` release-qualification runs always execute the full workflow.

For workflows using the composite detector, the path map lives in two places — the `on.push.paths` trigger filter and the `changes` job's `paths` input — and the two copies must stay in sync. Apple's and Android's push filters and component job planners jointly define their triggers. Shared contract paths (`packages/contracts/**`) and shared-core paths (`packages/healthmd-core-rust/**`) intentionally trigger every consuming component, including Apple CI.

The final gate jobs require every selected job to succeed and accept only explicitly unselected skips. Main-branch push triggers remain path-aware — Apple CI's `main`/`testing` pushes included — so unaffected components are not rebuilt after merge.

## Apple CI selection

`apps/apple/scripts/apple-ci-plan.py` selects existing jobs for pull requests.
Reviewed documentation paths retain macOS coverage and generated-document checks;
documents and resources read by shared XCTest assertions retain both unit suites.
Embedded Apple Swift CLI changes retain macOS, and UI-test changes retain the UI job.
Production sources, packages, project/build configuration, shared contracts/core,
and unclassified inputs retain the full suite. The planner also includes the
website resources and root workflows read by Apple tests.

The lightweight changes job runs planner/gate regression checks and validates
documentation links even when native jobs are unselected. PR file discovery
must prove a complete, revision-pinned change list and include rename sources;
uncertainty selects every job. The stable `Apple CI` gate requires all selected
jobs to pass and rejects missing selection outputs or selected skips. The Rust
artifact preparation job runs whenever an Xcode test job needs it. Main/testing
pushes, manual runs, and reusable/exact-SHA qualification retain every job.

### Apple critical-path execution

Preparation first checks the complete XCFramework cache against the exact native
inputs and active Xcode/SDK fingerprint. A hit still checks generated binding
drift, the source digest and the framework architecture/symbol inventory before
publishing the final current-run artifact directly. A lightweight Linux gate
requires exactly one complete producer path, avoiding a second SDK runner queue
on a hit. Consumers still check source, SDK provenance and framework contents;
only a validated hit skips native slice fanout.

A cache miss builds all five Rust targets (iOS device, both iOS Simulator
architectures, and both macOS architectures) in parallel with the unchanged
pinned release profile. Each archive has a source digest, commit, toolchain and
byte-hash receipt. The collector requires the complete five-slice inventory,
checks generated bindings and assembles the same three-platform XCFramework.
The Linux gate requires all five slices and successful assembly on this path.
Missing or failed prerequisites reject both paths. Prepared framework artifacts
remain available for three days to support bounded retries. Nightly uses the
same complete-artifact key and still validates source/bindings on cache hits.

The iOS unit job begins booting its selected compatible simulator before
compilation. Unit and UI products compile only the execution architecture and
disable the unused compiler index store. The native XCFramework still
contains all five previously qualified target architectures. Test results are
never restored from a cache.

Native unit tests compile once per platform. Xcode enumerates the complete
compiled XCTest and Swift Testing method inventory; four workers per platform
receive a balanced, exhaustive partition. Every worker restores the same
current-run archive and checks source/run/attempt, platform and SDK provenance.
macOS retains coverage and its 120/300-second method allowances; iOS retains its
original disabled per-test timeouts and validates its selected simulator UUID.
Test results are never cached. Runtime skips remain explicit in each inventory.

The stable `test-macos` and `test-ios` collectors require successful preparation
and every worker, verify actual xcresult methods against the compiled inventory,
and merge all four results. macOS coverage thresholds, both platforms' warning
and named automation receipts, and documentation/TDD checks remain downstream of
the complete result. Missing, duplicate, stale, failed or unexpected methods
reject qualification. Native-generated automation text is collected from its
executing Mac worker; conflicting copies fail. The unsigned iOS device candidate
build runs alongside unit shards after guarded preparation, and remains required
for the same PR/manual events as before. Its archive and source/checksum receipt
retain the existing name and lifetime.

The shared unit-test target scopes its Mac host with `platformFilters`.
Xcode ignored the singular `macos` filter during iOS preparation and also built
and packaged the desktop app and CLI helpers. Both host dependencies and native
suites remain; each producer now builds the host for its own platform.

Twenty phone UI cases run across three phone shards; a fourth shard runs four
App Review/history cases on iPad. The
same history method intentionally runs once per device family. Entire XCTest
classes remain together within a family to preserve shared fixture state.
One SDK27 preparation job builds fresh app/runner/test products and publishes a
qualified archive. Every shard verifies the producer archive SHA, exact source
and current restored binary fingerprints before execution. The selected actual
simulator must match its required device family. Setup and the single native
invocation share an owned deadline inside the existing 35-minute phone or
15-minute iPad step, with cleanup time reserved. Exact SDK27 compiler/signature
and producer/consumer provenance checks remain mandatory for core and app jobs.

Each shard checks the authoritative xcresult case tree and summary against its
exact selection. Missing, duplicate within a device family, failed, skipped or
unexpected cases fail qualification. The stable `iOS UI regressions` aggregate
requires successful preparation and all four current-run/source receipts for
24 device-attributed executions. Compile/runtime warning gates (including
premature StateObject access), raw logs, process ownership records and xcresults
remain mandatory. Fail-fast is disabled.

These changes trade additional simultaneous runners for a shorter critical
path; they do not remove test coverage or claim a fixed hosted-runner speedup.
Compare cold/warm execution separately from dependency wait, queue time and
summed runner work. F-Droid and Android Wear remain paused as described below.

## Android CI selection and accessibility coverage

Play JVM qualification retains debug, release and E2E variants. Each variant has
three fresh lanes: default Gradle discovery for all remaining classes, plus two
halves of the slow native configuration class. The halves come from the live
compiled JUnit annotations using the actual Test runtime classpath, rather than
a hand-maintained method list. Every variant's remaining lane excludes only that
native class. Debug's remaining lane also retains shared core, wearable-contract
and protocol tests, lint, packaging and phone APK policy checks.

The stable `test` collector requires all nine lanes, reconciles the two actual
native XML method sets with their compiled inventory and exact source/run/attempt,
and checks shared-module results. Missing, duplicate, stale, failed or unexpected
cases reject qualification. All original compiler and Test profiles remain; the
existing Gradle wrapper caches compilation while Test outputs always execute.
Lane reports include variant and lane in their artifact names. More simultaneous
runners trade extra preparation work for shorter wall time; full hosted results,
including queue time, determine whether the complete target is met.

The remaining-class lane uses two app-class forks within the existing two-worker
budget; each native lane contains one class and preserves its exact method half.
Gradle test graphs prepare all four ABIs for the actual library profile; the
binding check does not force an unused Debug build before Release.

On pull requests, `apps/android/scripts/android-ci-plan.py` selects the active Android
jobs that consume changed files. Phone sources keep Play JVM tests and phone
instrumentation; CLI changes keep instrumentation and live Rust/Kotlin interop.
Shared contracts, shared Rust core, build configuration, and CI infrastructure
retain every active consumer. Documentation and release tooling use the lightweight
policy job, with JVM tests retained for source/document contract assertions.

F-Droid and Wear builds are not currently distributed, so their CI jobs remain
paused for all events, including push, manual, and reusable/release qualification.
The planner emits `false` for those jobs and the final gate requires them to be
skipped. The main JVM job does not build or test Wear. Shared wearable-contract
JVM tests remain active because the phone consumes that module. Explicit build
and release tooling remains available for future qualification.

The planner paginates the PR files API, includes rename sources, and verifies the
event's head/base revisions and file count before and after pagination. Incomplete
or changing results run every active job. Selected jobs must succeed; a skipped
job is accepted only when its selection output explicitly says `false`. The policy
job's listing validator discovers every `scripts/tests/test_*.py`.

Phone instrumentation uses six hosted shards with the same complete Play test inventory. Shard zero also runs the core
suite and direct E2E; every shard runs the native-input readiness check using Play.
The stable instrumentation gate validates the combined Play/core/E2E XML inventory.
APK preparation reuses compilation outputs through the existing safe Gradle wrapper;
requested Test tasks still execute freshly. Six workers trade more runner minutes
for shorter device-test execution; hosted cache and queue evidence determine actual savings.
Local runs remain unsharded unless shard index/count are explicitly supplied.

Instrumentation runs every core and Play test method with the full ten-display
accessibility matrix. The local `run-ci-instrumentation.sh` runner has the same
Play-only scope. `make test-android` runs Play debug/release/E2E JVM tests plus
shared core, wearable-contract, and direct-protocol tests.

Main pushes, manual runs, and reusable/exact-SHA qualification run every active
job. Main pushes remain filtered at the workflow trigger. Reusable calls default
`full_qualification` to `true`; a nonempty `release_sha` forces full active
qualification. Phone release recovery requires only active CI jobs to succeed.

`.github/actions/android-native-cache` caches pinned cargo-ndk, Cargo downloads,
and the actual component build directories selected by each job. Keys include
OS/architecture, tool versions, lockfiles, and the checked-out source revision for
compiled targets. Only successful main pushes publish caches; PRs restore them.
Cargo still validates and builds the checked-out source. F-Droid clean builds
restore downloads and tools only, without compiled project targets. The action
selects Rust 1.88 for subsequent host commands as well as native preparation.

F-Droid debug tests, lint, and debug APK assembly run in parallel with release
APK assembly and the existing artifact/metadata/scanner checks on independent
clean runners. Both lanes build all four native ABIs from source; neither restores
compiled project outputs or uses the Gradle build/configuration cache. Fail-fast
is disabled so a failed lane cannot cancel the other lane’s coverage. The stable
`F-Droid clean build` gate requires both lanes, including for retained release
qualification. Per-lane test XML, task profiles, and runner CPU/memory diagnostics
are retained to separate build work from runner variation and queue time. This
uses an extra runner concurrently and may increase total runner work.

The JVM job also enables Gradle's task-output cache for compilation and lint via
`apps/android/scripts/run-ci-gradle.sh`. Its CI init script always executes every
`Test` task and prohibits restoring cached test results: contract tests can read
repository files outside Gradle's declared task inputs. An offline real-Gradle
fixture checks compilation reuse, fresh test execution, and failure after an
external contract file changes. Test XML, per-invocation task profiles, and hosted
runner CPU/memory details are retained on both successful and failed JVM jobs.

## CLI packaged-source cache

The packaged-crate smoke job retains verification targets under
`apps/cli/target/packaged-crates` through `HEALTHMD_PACKAGED_CACHE_DIR`. Rust 1.85
MSRV and Rust 1.88 targets are separated by compiler identity, and the workflow
cache key includes both compilers plus manifests, lockfiles, and build settings.
Archive generation, extraction, and MSRV dependency resolution remain fresh.
Every invocation cleans the five extracted project crates before compiling them;
only third-party compilation is reused. Full workspace tests, default-feature
binary builds, and version/help/MCP schema compatibility smoke checks still run.
Local use keeps temporary targets unless caching is explicitly enabled.

## Optional Apple local pilot

The Mac runner belongs exclusively to the private
[`CodyBontecou/health-md-local-ci`](https://github.com/CodyBontecou/health-md-local-ci)
controller repository. Public PRs cannot schedule this repository-scoped runner. Labels select
machines; they do not enforce workflow access. Do not register an everyday development Mac
against this public repository or use runner hooks as an access-control substitute.

`scripts/local-actions/apple-local-pilot.yml.template` is the reviewed controller workflow.
Copy it to `.github/workflows/apple-local-pilot.yml` in the private controller when updating it;
compare the deployed workflow with this template. This public repository's
`apple-local-pilot.yml` runs tooling safety tests on a hosted runner only.

The controller permits manual dispatch from its `main` branch. A hosted resolver checks out
public `health-md` main, validates an optional full 40-character `source_sha` against main
history, rejects commits predating the pilot script, and runs tooling safety tests before
scheduling the Mac. The default is the public main commit resolved at job start. The Mac then
checks out that exact public SHA. The controller does not accept public PR triggers, reusable
workflow calls, repository dispatches, or arbitrary source repositories.

Register with `scripts/setup-local-actions-runner.py`. It refuses a public controller or a
non-main default branch and uses **no default labels**, with only
`healthmd-local-pilot-macos-arm64`. Its ignored `.external/local-actions-runner/_work` checkout
is separate from development source. Registration does not install a background service.
Run the listener in a foreground terminal when the Mac is available; stop with Control-C:

```sh
python3 scripts/setup-local-actions-runner.py
cd .external/local-actions-runner
env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN ./run.sh
```

From another terminal, dispatch and inspect the private run:

```sh
gh workflow run apple-local-pilot.yml --repo CodyBontecou/health-md-local-ci --ref main
gh run list --repo CodyBontecou/health-md-local-ci --workflow apple-local-pilot.yml
```

To test an earlier eligible commit, add `-f source_sha=<full-main-commit-sha>` to the dispatch.
Only trusted people should have write/dispatch access to the private controller. Keep runner
registration credentials inside the ignored installation and never commit them. A custom-only
label prevents generic self-hosted jobs from claiming this runner; private registration provides
the public-PR access boundary. If the listener is offline, the optional Mac job waits for capacity.

The component entry point `apps/apple/scripts/run-local-actions-pilot.sh` requires a clean
committed checkout, native arm64 macOS, and installed Swift 6.3 or newer. It creates a fresh
compatible iPhone simulator, runs the unsigned iOS unit suite with isolated DerivedData, checks
for nonzero passing tests with no failures, and removes only its own simulator. Attempt-specific
logs, xcresult and a receipt with source/toolchain/controller identity are retained for seven days.
Cancellation preserves available diagnostics and records cleanup errors. It does not change
global Xcode or Git settings. Keep the Mac awake while a run is active.

This pilot is optional and is not the complete Apple CI matrix or release qualification.
Its checks/artifacts appear in the private controller and do not satisfy public PR status gates.
Existing required hosted CI, nightly, release, and exact-SHA qualification remain in place.

## Testing-tool feedback

[`testing-tools-ci.yml`](testing-tools-ci.yml) runs host-side command-routing, documentation build reuse, CI selection/final-gate, and website build orchestration regressions without compiling native apps or starting devices. Run `make test-testing-tools` locally after installing `scripts/testing-requirements.txt`; this is not a substitute for product or release gates. See the root [test selection guide](../../docs/testing-strategy.md) for iteration and qualification tiers.

Apple CI runs native documentation assertions within the complete coverage-enabled compiled inventory; local documentation commands retain incremental `xcodebuild test` source-change detection. The nightly macOS suite executes once with coverage, rather than once normally and again for coverage. Website CI uses `build:ci` after its locked install, building and checking documentation once.

## Android release trigger

Android `1.9.3` is a phone-only Google Play release. `apps/android/release-scope.json` records the active artifact and explicitly defers Wear OS publication. The phone build does not advertise a Wear capability, start Wear synchronization, or expose Wear settings.

`.github/workflows/android-release.yml` builds from an annotated `android/v<version>` tag. The tag must peel to a commit reachable from `origin/main`; its version must match `app/build.gradle.kts` and `release-scope.json`. The workflow re-runs the complete Android CI matrix against that exact SHA. A `google-play-qa` job reconstructs signing material only under `$RUNNER_TEMP`, requires the registered Play upload certificate, builds and inspects the phone AAB, removes the private key, and retains the signed artifact. A separate `google-play` job downloads that exact digest, re-verifies its signer and source identity, retains a SHA/tag/run-attempt/AAB-digest-bound intent, and only then requests a short-lived Play token and uploads to `internal`. A lost commit response is reconciled against the exact track instead of retrying the non-idempotent commit.

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

Dispatch from `main` with `release_tag=v<version>`. Apple versions use `v<major>.<minor>[.<patch>]`; the tag must exist on `origin`, its commit and the workflow commit must be reachable from `origin/main`, and the tag version must match every committed `MARKETING_VERSION` in `apps/apple/HealthMd.xcodeproj`. The resolver also requires an existing draft GitHub Release before qualification for a non-dry-run manual submission. It never creates a source ledger after an upload.

Before building, each workflow resolves the tag to an immutable SHA and runs the full Apple CI suite (`apple-ci.yml`) against it. The release job checks out **that same SHA**, not the dispatch branch head. Native tests, UI regressions, coverage, warnings, the connectivity package, and the workflow-policy job must all pass; a failed, cancelled, or skipped required job blocks the release. Release callers and reusable CI have distinct concurrency namespaces. Exact-SHA qualification groups are isolated by caller and run ID and cannot cancel their parent or another release; ordinary branch CI still cancels superseded runs.

Workflow-only recovery may dispatch newer `main` workflow code with the original `release_tag`. The release tag must be an ancestor of that workflow SHA, and the diff may change only `.github/workflows/`, `.github/actions/`, or `.github/scripts/`. Qualification and archives still use the original tag's product source, without an overlay from newer `main`. A product, dependency, build-script, version, or metadata fix needs a newly committed and tagged release; never move an existing release tag. Recovery can load the current workflow's source-policy script from Git into `$RUNNER_TEMP` even when the original tag predates that script.

Both release jobs recheck the clean, qualified checkout and pushed tag object at checkout, immediately before and after archiving, and before publication. Staged, unstaged, and non-ignored untracked files fail closed; ignored build products are allowed. The macOS workflow does not remove package references or otherwise edit the tagged project to avoid package networking. Any required project change must be committed, qualified, and released as new source. Summaries record the archived source SHA separately from the executing workflow SHA.

Keep the GitHub Release as a draft while App Store review is in progress. The ASC approval webhook and `apple-announce.yml` publish it. Human publication remains a legacy fallback, not the canonical submission path. Non-Apple tags (`healthmd-cli/v*`, `android/v*`) and bot-authored publications skip resolution, qualification, and release jobs, so they do not launch duplicate full Apple suites. Untagged branch dispatch is supported only with `dry_run=true`: it qualifies and archives the exact dispatch SHA and cannot upload or submit.

The lightweight policy regressions run on Ubuntu in Apple CI and are included in its final gate. Release-workflow and `.github/scripts/**` changes are in both Apple CI path maps. To run them locally without signing or a native build (Python with `PyYAML==6.0.3`, Git, Bash, and jq):

```sh
python3 -m unittest discover -s .github/scripts/tests -p 'test_apple_*.py' -v
actionlint .github/workflows/apple-ci.yml .github/workflows/release-ios.yml .github/workflows/release-macos.yml
```

The tests use local synthetic Git remotes and a stubbed release-record read; they never dispatch workflows, push, access signing credentials, or perform store operations.

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
qualified). The generated Homebrew formula is normalized in an isolated tap before the checksum
closure is signed. The remote draft assets are then compared byte-for-byte with the qualified
workflow artifacts before the separate protected `cli-release` environment can publish them.
After publication, the sealed formula clean-installs on every supported macOS/Linux architecture,
preserves the signed binaries byte-for-byte, and completes an installed MCP handshake before a
serialized, anti-rollback tap job pushes and remotely rechecks the exact formula blob.

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

## Opt-in cloud prototype CI (no deployment)

`.github/workflows/cloud-ci.yml` runs locked Node/type/unit checks, a synthetic local Wrangler D1/R2 test of account/session, Apple v1/v2 and Android v4 ingestion, encrypted downloads, tenant isolation, and token revocation, plus a Wrangler dry-run and dependency audit. It does not deploy or receive production credentials. Main pushes are path-scoped; pull requests always report `Cloud CI / Cloud CI`. This CI never handles real health data or deploys either profile. A separately authorized unbacked, owner-operated VM pilot accepts real exports, but no general production release is approved. See [`apps/cloud/README.md`](../../apps/cloud/README.md) and [ADR-0007](../../docs/architecture/adr-0007-healthmd-cloud.md).

## Release steps

1. Resolve a remote-safe build number with `asc builds next-build-number` for both platforms.
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`, update `apps/apple/CHANGELOG.md`, in-app notes, canonical metadata, and `apps/apple/fastlane/metadata/en-US/release_notes.txt`.
3. Test from a clean worktree, commit, and push the exact source to `origin/main`.
4. Create the `v<version>` tag and a **draft** GitHub Release targeting that exact commit. Its body is the canonical customer-facing release note.
5. Dispatch both workflows with `release_tag=v<version>`. Use `skip_asc_submit=true` when upload and validation/submission should be handled as separate phases.
6. Confirm `asc validate` passes for `IOS` and `MAC_OS`, then submit both versions for review.
7. Leave the GitHub Release as a draft. `apple-announce.yml` publishes it after ASC approval.

For a no-upload smoke test, run either workflow manually with `dry_run=true`.
