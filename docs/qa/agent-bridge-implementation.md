# Agent bridge implementation evidence

## Decision and boundaries

**INCOMPLETE.** This is a source implementation ledger, not release or physical qualification.
Acceptance is the [roadmap](../architecture/agent-bridge-parity-roadmap.md) and its canonical linked todos. The deliverable is a working CLI **and** MCP journey for both mobile sources: discovery → explicit scope/settings → configuration-only plan → bound approval → daily JSON in year folders → validated receipt → host recipe → future changes, with immutable resume and unchanged phone API preferences. Additional deliverables are typed Android queries/extraction, onboarding, permissioned native configuration, scheduling, wake degradation, ZIP and dictionaries.

No push, release, deployment, Cloud/Practice work, real health reads, native credential provisioning, user settings/schedule mutations, device notifications or physical-device actions are authorized. B19/B20 remain approval-blocked. Missing evidence is not a pass. Unit tests cannot qualify a physical matrix.

## Execution provenance

- Original HEAD: `e9a1d8757b679ea49820893537873ef3002604fe`, branch `feat/cloud-mcp-pilot`.
- Dedicated integration: `goal/agent-bridge/integration`; roadmap-only commit `77f57256c`.
- Original Cloud/website modifications and untracked Cloud test were inventoried, not staged or copied into integration.
- Original `.pi/todos` remains canonical; worktrees reference that same store. Coordinator claims tasks; workers must not create/claim/update independent task databases.
- `HERDR_ENV=1`; Herdr 0.8.0 syntax discovered via help/group help. Initial agents/worktrees inventoried; existing unrelated agents are not controlled.
- Exact lane model: `openai-codex` / `gpt-6.1-sol` / `max`.
- Four first-wave scopes: B16 Android API/scheduler security; B02/B03/B04 CLI-only repairs; B01/B05 contracts-only specifications; B15 Worker-only mocked FCM. No overlapping writable files. Coordinator does not edit repository files while workers run. All lanes committed and stopped before serial integration and central repairs.
- Retained scratch receipt hashes: original HEAD `894f13c962a42822187703762f3282e4170e2d6587ab1b3afb3faa08d3243a6d`; original status `64c5d177132cecb1e76be0dbf5f46c741c487008e54f6c9f8277c5e7e7e151d5`; original file inventory `eea3035cc16dfab8376fa06f2346adfe93cd3facb4b20bf19a85cfbefd3ecc0c`; preservation diff `f8cf5a8a6c75c4ab1992ddd2b5b25d4d8d6f08469b976a0c3deec5f81b0e7749`. These prove initial preservation only, not feature implementation.

## Prompt-to-artifact implementation checklist

Every row requires the linked todo's individual acceptance items, implementation commits, tests, and the relevant gates below. A planned artifact is not evidence of implementation.

| Requirement | Artifact/test surface to inspect | Integrated evidence / remaining work |
|---|---|---|
| B01 contracts: precedence, scope, output, plan, approvals, revisions, authority, versions | New bounded contract/schema/fixtures; source resolvers; cross-language conformance | `d0ffb6542` + `a2832dc02`, merged through `f55a71a08`: deferred foundation; native implementations/conformance remain missing |
| B02 source-aware generated MCP dispatch and durable receipts | CLI/client shared dispatcher; MCP adapter; both-source fake peers; filesystem/digest/cancel regressions | `14ac445a2`, merge `b9392ef74`: source-bound iOS-v1/Android-v2 dispatcher and validated host commit receipts; hermetic tests pass; four-way v4 journey remains pending |
| B03 mobile MCP/host pairing, approval, single credential identity | Pairing coordinator/client, onboarding, image/App privacy tests, transcript preservation | `14ac445a2`, merge `b9392ef74`: first-mobile pairing/onboarding and both-source fake peers; no transcript rewrite or physical pairing performed |
| B04 advertised profile grammar/policy matches parsing and negotiation | Operations registry/normalizer, CLI guidance, generated schemas, old-peer/profile conflict tests | `14ac445a2`: portable registry/parser/assets agree, Android policy gated; iOS remains fail-closed pending authoritative-ID resolution and explicit policy discovery; Apple MCP projection pending |
| B05 Android typed semantics, native evidence, bounded cursor contract | Versioned Android query spec/fixtures, reviewed IDs/units/statistics, SDK evidence | `d0ffb6542` + `a2832dc02`: exact native SDK identity/precision and bounded query/projection contracts; static SDK review and synthetic oracles only, not runtime conformance |
| B06 Android native typed capture/evaluation | Kotlin repository/evaluator/FGS boundaries; every fixed operation, DST/history/cursor/cancellation tests | Pending |
| B07 source-neutral CLI/MCP query/catalog/chart routing | Client/operations/MCP; old-peer/multiple-device/unit-safe PNG/App tests | Pending |
| B08 Android request-local daily extraction | New versioned native product/envelope and Rust validator; selectors/completeness/resume tests | Pending |
| B09 explicit generated settings on both sources | Protocol/client/Swift/Kotlin production resolvers and durable journals; unchanged-preferences/path/crash tests | Pending |
| B10 zero-health plan and bound execution | CLI/MCP plan API; read/write/quota counters; expired/stale/peer/scope/root/approval rejection tests | Pending |
| B11 host recipe CRUD/run | Private atomic bounded store, CAS/idempotency, CLI/MCP parity, corruption/concurrent/stale/run-freeze tests | Pending |
| B12 native profile CRUD/activation with separate approval | Both native stores and shared controls; protection/import/last-profile/revision/rollback/schedule tests | Pending |
| B13 bounded host scheduler and exact-job recovery | Typed portable scheduler and private state; DST/catch-up/concurrency/unknown-outcome/headless tests | Pending |
| B14 native schedules/destination workflows | Both native profile-bound controls, human grant actions, exact-endpoint approval, recovery/late-worker tests | Pending; B16 prerequisite |
| B15 Android Play wake, F-Droid/force-stop degradation | Mocked notification-only Worker FCM/HMAC and native enrollment/tap/revoke/fallback; no live delivery | `a9f87df02`, merge `19c759c67`: additive Worker v2 FCM with mocked delivery; 114 tests/typecheck pass. Native/CLI adoption and production security review pending; deployment unauthorized |
| B16 before-read API recovery authority | Pending admission/settings/credential proof; compatibility/raw runners; no-read rotation/legacy/race tests | `54e4a24c9`, merge `363d8693e`: installation-bound admission, frozen compatibility/raw artifacts and generation fences. Full Play/F-Droid tests/lint/builds pass after central inventory/localization/readiness repairs; Pixel not run; explicit-discard artifact cleanup follow-up |
| B17 bounded ZIP packaging, explicit settings/manifest | Native/direct streaming production artifacts, path/digest/budget/cleanup/cancel tests | Pending |
| B18 profile-aware dictionaries and catalog | Registry/native evidence, separately versioned companion, coverage/alias/unit/manifest tests | Pending |
| B19 range summaries | Approved unified-v9/consumer evidence required | Blocked; no approval granted |
| B20 typed WHOOP profile | Approved new profile/provider/consumer evidence required | Blocked; no approval granted |
| B21 truthful capability/docs/schema reconciliation | Capability JSON, feature tables, native/CLI/support/website/locales/skills; source ≠ installed ≠ qualified | All new bridge capabilities remain planned. Central capability index is independent of frozen metric bytes; native exact accounting tests repaired. Broader docs/website/support reconciliation pending |
| B22 four-way no-settings journey and physical qualification | CLI+MCP × iOS+Android synthetic peers; explicit negative matrix; exact candidate/mobile/desktop records | Pending; physical authorization/environments absent |

## Cross-cutting audit checklist

- [ ] Shipped Apple-v8, Android frozen-v4/analytical-v5, raw-v1 and historical fixtures unchanged; pairing/transcript/frame/cryptographic bytes unchanged.
- [ ] New products explicitly versioned and negotiated; old peers reject before capture, no fallback/peer switch.
- [ ] Distinct HRV, temperatures, sleep aliases, clinical and native archive identities retained; absent values never fabricated.
- [ ] Effective settings, selected peer, scope, revisions, capability context and native destination identity bind approval/execution; resume cannot retarget.
- [ ] Receipts validate every digest/manifest/frontier; overwrite/append/merge restart idempotence and duplicate prevention evidenced.
- [ ] Pairing never grants arbitrary configuration; Configuration Protection, native grants, entitlements and separate mutation consent preserved; read-only/remote MCP remain read-only.
- [ ] Fixed bounded operations only; no arbitrary shell, SQL, URL, or file-read authority.
- [ ] Android active user-started FGS and before-first-unlock limitations differ truthfully from iPhone foreground/protected-data new-work gates.
- [ ] Wake remains notification-only and cannot unlock/grant/capture; Play/F-Droid/force-stop fallback and mocked delivery evidenced.
- [ ] Reports contain no health payloads, owner dates, private destination paths, identities, tokens or pairing secrets.
- [ ] Serial integrations inspected and checked; shared artifacts centrally regenerated; unrelated original modifications rehashed.

## Verification command inventory

Run from the documented owning directory; retain sanitized commands, exit codes, exact tested commit and artifact digests. All product gates below are **not run** at initial survey.

| Working directory | Required commands/gates | Initial state |
|---|---|---|
| `packages/healthmd-core-rust` | `cargo fmt --all --check`; `cargo test --workspace --all-features --locked`; `cargo clippy --workspace --all-targets --all-features --locked -- -D warnings`; `rustup run 1.85.0 cargo check --workspace --all-features --locked`; Swift v1/v3 and Kotlin v2 vector tests | Not run |
| root | `make check-core-bindings`; `python3 packages/contracts/validate.py`; new negative/conformance validators; frozen fixture diff | Not run |
| `apps/cli` | Independently locked fmt/tests/clippy/MSRV; `python3 scripts/update-mcp-shared-assets.py --check`; `dist plan --allow-dirty`; package verification; offline help/guidance/MCP/schema/compatibility launcher | Not run |
| `apps/apple` | `swift test --package-path Packages/HealthMdConnectivity`; focused direct-service/query/exporter tests; generic iOS `xcodebuild` with signing disabled; required exporter signature preservation | Not run |
| `apps/android` | Focused Kotlin/protocol/scheduler tests; Play/F-Droid unit tests and assembles; exporter signatures and Android bindings | Not run; no install/device work authorized |
| `apps/wake` | HMAC/replay/rate/no-health/FCM/fallback tests, type check and local dry-run with delivery mocked | Not run; no secrets/deploy/delivery authorized |
| `apps/website` | Affected generated docs, tests/build/i18n/localization/link gates | Not run; unrelated changes preserved |
| pinned external Obsidian | Exact pinned consumer fixtures/tests for affected public outputs | Not run |
| physical desktop/mobile matrix | macOS ARM/Intel, Linux ARM/x64, Windows; exact iPhone/Pixel 7 Play/F-Droid; LAN/Tailscale, denied/history/credentials/headless, lifecycle/cancel/wake | Not run; needs separate live authorization and environments |

## Exact local toolchain (survey)

macOS 26.5.1 (25F80), arm64; Xcode 26.6 (17F113); Rust/Cargo 1.98.0; MSRV 1.85.0 installed; OpenJDK 21.0.12; Python 3.9.6; Node v26.8.1; Herdr 0.8.0. Original survey/help/status/version commands exited 0, except optional filesystem discovery of absent artifact directories (exit 1) and absent `apps/cli/AGENTS.md` (no component-local file; root instructions apply). No build/test result is inferred from installed tools.

## Slice evidence

### First serial integration and central repairs

Integration order and local merge heads: contract foundation `a0bd0154e`, refinement `f55a71a08`, CLI `b9392ef74`, Worker `19c759c67`, Android security `363d8693e`. Central frozen-digest/private-coverage/native-test/localization repairs committed as `ac69cc6286f87a733d1bb62c77230e142d5f8e11`. Both contract commits validated after their respective merges; CLI and Worker gates passed before the next merge. Android scoped exporter/scheduler/settings/raw/engine tests, both assembles and binding checks passed after security integration. Original worktree was not merged, reset, staged or restored.

Sanitized gate evidence is retained under the isolated scratch `evidence/` directory. Initial merged gates tested the exact merge heads above. Central repairs were tested on the integration tree based on `363d8693e` plus the explicit repair diff; these results are not committed-source binary qualification.

| Command / owning directory | Exit / result |
|---|---|
| `python3 packages/contracts/validate.py`; full `test_validate*.py` discovery, root | 0 after each contract merge; central final discovery 59 tests, 0 failures |
| Independent `jsonschema==4.25.1` Draft-2020-12 schema checks in scratch venv | 0; 3 schemas and 139 positive document cases (72 agent, 43 query, 24 wire). Semantic negative oracles remain separate |
| CLI locked all-features workspace tests / fmt / clippy `-D warnings` / Rust 1.85 check / asset check | All 0; 227 passed, 2 ignored; `integrated-cli-*.log` |
| Wake `npm test`; `npm run check`, `apps/wake` | Both 0; 114 tests; `integrated-wake-*.log`; providers mocked, no live notifications |
| Core locked all-features workspace tests / fmt / clippy / runtime-only Rust 1.85 / native import / registry-adapter checks | All 0 after error-documentation and independent capability-index repair; `integrated-core-*.log`. Tooling uses pinned Rust 1.88; whole tooling workspace is not Rust-1.85 compatible |
| Android full Play/F-Droid unit tests, both lints/assembles, Kotlin binding check, workers ≤2 | 0, `integrated-android-full-gates.log`; Play 1362 tests, 0 failures, 1 skipped; F-Droid 1201 tests, 0 failures, 1 skipped. Source-built JNI; no runtime/device qualification |

Central repairs deliberately preserve historical fixtures:

- Original whole-registry SHA-256 remains `56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99`. A first regeneration changed only capability arrays but broke frozen semantic/render digest gates (`central-contract-validate.log` and `central-android-inventory-tests.log`). The current capability index is now independently versioned and source-inventory-bound; native importer refuses any frozen registry digest change. No historical fixture was rewritten.
- Independent Android private recovery coverage v1 pins the original Shared Setup v2 ledger SHA-256 `4a539e7e22006bd0f06e63c3dda7a82f41c6fac0d536249573a37eccec8ae789`. Seven new/inherited private runtime rows are prohibited, never portable; strict descriptor union coverage and rejection tests pass. The old ledger is untouched.
- Five missing recovery-discard strings are translated for all 15 supported Android locales. Token/plural/localization checks and lint pass; native-language human review and visual qualification are not run.
- The QR-readiness test now validates a closed static custom-scheme allowlist, preserving the existing Cloud handoff without treating it as pairing authority. No Cloud code or routing was changed.

### Baseline and remaining gates

Baseline core tests/fmt/runtime-MSRV/bindings, Swift connectivity (55 tests), website tests/i18n/docs checks, and mocked Wake tests/typecheck passed before implementation. Baseline core clippy failed for optional timestamp helper error documentation; central documentation-only repair now passes. Initial native importer drift was capability metadata only; independently versioned repair preserves metric/profile bytes.

Apple `check-export-docs` initially failed (make 2/xcodebuild 74): local `HealthmdCoreFFI` binary target had no framework. A baseline source-built XCFramework was retained in scratch. At committed `ac69cc6286f87a733d1bb62c77230e142d5f8e11`, `prepare-apple-xcframework.sh` rebuilt the framework from source into the Apple package artifact directory (exit 0, `apple-core-framework-integrated.log`), with no tracked artifact diff. `make -C apps/apple check-export-docs` was rerun (exit 2/xcodebuild 65, `apple-export-docs-integrated.log`): the missing-binary blocker is resolved, but macOS compilation now exposes `RefreshMacContextIntent.swift` references to unavailable `ExportIntentRunner` and nonexistent `MetricSelectionState.enabledMetricIDs`. These application compile failures remain unfixed; focused Apple capability/accounting tests have not run. Swift connectivity rerun passed (exit 0, `swift-connectivity-integrated.log`). Copied prebuilt artifacts are not qualification.

Pinned external Obsidian consumer `c33dcbe935d681216faca78c5dae251344cb4014`: install/typecheck/build 0; tests and rerun nonzero, 105 passed / 1 failed due missing generated range-rollup file. External checkout untouched. This failure is not fixed or declared green.

New contracts comprise 481 synthetic cases (183 positive/298 negative), 58 canonical vectors and 31 focused bridge unit tests. They do not establish Rust/Swift/Kotlin native conformance, zero-read source behavior, authority persistence, actual source projection capture, or the four-way no-settings journey. These remain mandatory follow-up work.

B19/B20 approval gates, physical mobile/desktop LAN/Tailscale matrices, installed-build support, live provider delivery, production ownership/abuse review, secrets, deployment and releases remain blocked/not run. No capability is promoted and no todo closes from these tests alone.

### Narrow Apple compilation repair before native-contract lanes

On base `31828abd172fc23b523ede4920272ee4d822a53a`, the iPhone-only refresh intent now uses an `os(iOS)` guard and the actual `MetricSelectionState.enabledMetrics` property, sorted deterministically. Its existing profile/rebind checks and wire models are unchanged. A new isolated-suite request-builder regression asserts the exact selected IDs and unchanged preferences; that test is **not run** because the application build remains blocked.

- `DERIVED_DATA_PATH=<isolated scratch>/build-apple-docs make -C apps/apple check-export-docs`: make 2/xcodebuild 65. The previous intent diagnostics are gone; macOS compilation next fails at `HealthMdApp+macOS.swift:1037,1071` because `MacExportResultPayload` has no `message` member. Log `apple-export-docs-intent-repair.log`, SHA-256 `ebb7a8d9705729d4dd72064e8a16dfb3ce272e4a4f33085c9d48c0fba77bcdb8`.
- From `apps/apple`, `xcodebuild build-for-testing -project HealthMd.xcodeproj -scheme HealthMd-Tests-iOS -configuration Debug-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath <isolated scratch>/build-apple-ios -jobs 2` with signing disabled: 65. Compilation fails at `SystemHealthStoreAdapter.swift:388` because the pinned SDK's `HKHealthStore` has no `earliestAuthorizedSampleDate` member. Log `apple-ios-intent-repair-build.log`, SHA-256 `c7dfe8fcc3a5ea9ed20cb8338e8604519459bb428539d8df71b2cb584f44a26c`. Build-only: no simulator launch, health read or device action occurred.

These are repair-diff compiler observations, not passing application/accounting tests or installed-build qualification. Neither additional blocker is repaired here. Other agents' PR/Cloud/website work remains untouched. The next disjoint wave targets pure Rust/Swift/Kotlin v4 models and independent synthetic conformance; it must not advertise v4 or substitute DTO conformance for native execution/authority acceptance.
