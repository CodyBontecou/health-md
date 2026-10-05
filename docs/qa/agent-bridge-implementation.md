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
| B01 contracts: precedence, scope, output, plan, approvals, revisions, authority, versions | New bounded contract/schema/fixtures; source resolvers; cross-language conformance | Deferred specification/codecs, private issuer stores and callable planning through `cccbb13de`, including exercised live consent/publication/return fences. Native setup/dispatch, execution and complete conformance remain missing; merged compiler gates and Kotlin-after interop not run; no installed promotion |
| B02 source-aware generated MCP dispatch and durable receipts | CLI/client shared dispatcher; MCP adapter; both-source fake peers; filesystem/digest/cancel regressions | `14ac445a2`, merge `b9392ef74`: source-bound iOS-v1/Android-v2 dispatcher and validated host commit receipts; hermetic tests pass; four-way v4 journey remains pending |
| B03 mobile MCP/host pairing, approval, single credential identity | Pairing coordinator/client, onboarding, image/App privacy tests, transcript preservation | `14ac445a2`, merge `b9392ef74`: first-mobile pairing/onboarding and both-source fake peers; no transcript rewrite or physical pairing performed |
| B04 advertised profile grammar/policy matches parsing and negotiation | Operations registry/normalizer, CLI guidance, generated schemas, old-peer/profile conflict tests | `14ac445a2`: portable grammar agrees, Android gated. `9a55c696f` repairs authoritative Apple ID lookup; explicit iOS policy discovery/Apple MCP mirrors and enabled transport remain pending/fail-closed |
| B05 Android typed semantics, native evidence, bounded cursor contract | Versioned Android query spec/fixtures, reviewed IDs/units/statistics, SDK evidence | `d0ffb6542` + `a2832dc02`: exact native SDK identity/precision and bounded query/projection contracts; static SDK review and synthetic oracles only, not runtime conformance |
| B06 Android native typed capture/evaluation | Kotlin repository/evaluator/FGS boundaries; every fixed operation, DST/history/cursor/cancellation tests | Pending |
| B07 source-neutral CLI/MCP query/catalog/chart routing | Client/operations/MCP; old-peer/multiple-device/unit-safe PNG/App tests | Pending |
| B08 Android request-local daily extraction | New versioned native product/envelope and Rust validator; selectors/completeness/resume tests | Pending |
| B09 explicit generated settings on both sources | Protocol/client/Swift/Kotlin production resolvers and durable journals; unchanged-preferences/path/crash tests | `9a55c696f` detached resolvers feed real bounded native stored planning through `cccbb13de`; reviewed summary/JSON subset only. Kotlin31-leaf discovery remains fixed/default support, not wider customization. Dispatch/capture/journals and runtime success/failure/cancel/resume preference invariance remain pending |
| B10 zero-health plan and bound execution | CLI/MCP plan API; read/write/quota counters; expired/stale/peer/scope/root/approval rejection tests | In progress: callable source services, host shared CLI/MCP relay and exercised consent/key/configuration/publication/return live fences. Actual Swift-complete discovery-to-host tracer passes; Kotlin-after absent. No native route, bound execution or four-way acceptance. Catalog/host lane gates pass; fifth-wave merged compiler/native gates not run |
| B11 host recipe CRUD/run | Private atomic bounded store, CAS/idempotency, CLI/MCP parity, corruption/concurrent/stale/run-freeze tests | Pending |
| B12 native profile CRUD/activation with separate approval | Both native stores and shared controls; protection/import/last-profile/revision/rollback/schedule tests | Pending |
| B13 bounded host scheduler and exact-job recovery | Typed portable scheduler and private state; DST/catch-up/concurrency/unknown-outcome/headless tests | Pending |
| B14 native schedules/destination workflows | Both native profile-bound controls, human grant actions, exact-endpoint approval, recovery/late-worker tests | Pending; B16 prerequisite |
| B15 Android Play wake, F-Droid/force-stop degradation | Mocked notification-only Worker FCM/HMAC and native enrollment/tap/revoke/fallback; no live delivery | `a9f87df02`, merge `19c759c67`: additive Worker v2 FCM with mocked delivery; 114 tests/typecheck pass. Native/CLI adoption and production security review pending; deployment unauthorized |
| B16 before-read API recovery authority | Pending admission/settings/credential proof; compatibility/raw runners; no-read rotation/legacy/race tests | Initial authority `54e4a24c9`; exact-owned revocation/cleanup `a09d06ba5` + `9b334a570`, strict private parsing `bd13e0192`, merge `770c74319`. Combined full Play/F-Droid tests/lint/builds pass; default control/UI wiring and physical Pixel/storage/transport qualification remain pending |
| B17 bounded ZIP packaging, explicit settings/manifest | Native/direct streaming production artifacts, path/digest/budget/cleanup/cancel tests | Pending |
| B18 profile-aware dictionaries and catalog | Registry/native evidence, separately versioned companion, coverage/alias/unit/manifest tests | Pending |
| B19 range summaries | Approved unified-v9/consumer evidence required | Blocked; no approval granted |
| B20 typed WHOOP profile | Approved new profile/provider/consumer evidence required | Blocked; no approval granted |
| B21 truthful capability/docs/schema reconciliation | Capability JSON, feature tables, native/CLI/support/website/locales/skills; source ≠ installed ≠ qualified | All new bridge capabilities remain planned. SDK/CLI history/lifecycle and root catalog/pairing/Shared Setup/raw-product rows corrected through `95d890094`; seven static public-doc methods/static28+contract60 pass. Ten unchanged website pages checked read-only for the two latest claims, not whole-site qualification. Native/runtime mirrors, other parity rows, website/locales/skills and broader support reconciliation pending; no native qualification from docs |
| B22 four-way no-settings journey and physical qualification | CLI+MCP × iOS+Android synthetic peers; explicit negative matrix; exact candidate/mobile/desktop records | Host encrypted synthetic-peer plan/approval tests and Swift-complete capability interop pass at lane-source level; Kotlin-after not run. Native transport and execution/receipt/recipe/resume acceptance absent. Fifth-wave post-merge compiler/native gates blocked by admission; physical authorization/environments absent |

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

### Second serial integration: bounded native v4 foundations

All three workers were confirmed **done**, with committed clean worktrees and complete handoffs, before coordinator repository edits resumed. Their base was `fb7b9815c9a2c585874d4e16d7ea1a24a6704e0a`. The scope audit records 13 Rust paths (only existing `src/lib.rs` gains a module), 12 new Swift files, and seven Kotlin paths (only the existing module build file registers read-only fixture resources). No dependencies, lockfiles, installed hello lists, legacy dispatch, crypto, frames, public export schemas, credentials, native settings or capability availability changed.

| Lane source commits | Integration merge | Implemented boundary / deliberate limits |
|---|---|---|
| Rust `1c9d5382696d2b97a3d58786d013c202cd8e0500`, `5dbcf31b159f56acea436be86283f6171bf436ef` | `82a91d78c19b6c23e5d259ff2bc35d2bee3a3528` | Closed generated-export/discovery DTOs, strict canonical codec, pure integrity/context comparisons and exact source identity/time. No query/projection/control execution, native persistence, journal transaction or filesystem authority. Non-ASCII path collision scope fails closed. |
| Swift `697b0f89a796215b27c7a90e76a3daee3159e0d3`, `f6b7f3de74f9f5e437f0c079225761bfcbcf3d4b` | `4503f84015673b9d62090b7b00e47ccdc16c148e` | Closed generated-export/discovery documents, strict raw boundary, pure binding/path/source checks. Categories/all-metric expansion and query/projection/control branches remain unsupported; no stored native authorization. Foundation Codable alone is not the raw boundary. |
| Kotlin `d9473da42114820f6406bddbdfb08be7f241d414` | `e61ef90ce078e5f8ce9fc53858462f88aee7ea23` | Closed export and source-query/projection DTOs plus pure supplied-catalog/binding checks. Controls, projection jobs, dictionaries and runtime capture/authorization/cursors remain unsupported. Successful Unicode filesystem collision validation is restricted to ASCII NFC spellings. |

All strict raw boundaries reject duplicate decoded keys, unknown domain members/enums, forbidden nulls, malformed UTF-8/scalars and noninteger lexical JSON. Shared default bounds are 2 MiB, depth 24, 262144 nodes, 512 object members, 4096 array entries and 65536 string scalars. Compact canonical UTF-8 recursively sorts Unicode codepoints, without normalization, slash/Unicode escaping or trailing LF. Domain integers retain their declared widths; Swift's generic tree additionally retains arbitrary bounded integer text, which is **not** an expanded common domain guarantee. Source binary64 time is checked with exact rational rounding rather than floating multiplication. Correct bytes, hashes or DTOs do not issue permissions.

#### Independent candidates and unequal coverage

The native constructor source was inspected: the shared standalone `intent-request-owned-summary` is assembled from literal primitives and closed DTO constructors before expected-fixture comparison, never constructed by decoding that fixture. All three emit the same 1782 bytes, SHA-256 **`b9bf00875dbc4178491f5b3f8debd412e31c24d02e837e6bd4ada3d84a2e5217`**. This is one constructor-agreement result, not stored approval, native capture, or a full v4 conformance verdict.

| Evidence level | Rust | Swift | Kotlin |
|---|---:|---:|---:|
| Generic codec specification vectors exercised | 58 | 58 (not exported as candidates) | 58 |
| Exported independent constructor rows | 6 | 8 | 15 (14 unique values) |
| Typed round-trip evidence | 25 vector indices | 13 envelope vectors | 90 positive case IDs |
| Fixture-specific evidence | 96/481 intrinsic/lexical/synthetic context cases | 65/481 IDs at expressly narrower pure/round-trip levels | Overlapping lists: 58 standalone-document cases, 92 supplied query binding cases, 18 lexical path cases |
| Explicit remaining limits | 346 unsupported targets, 39 pending assertions | 416 IDs unexercised; no query/control/cursor/projection-transfer fixture verdicts | 93 unexercised IDs; conservative 388 runtime-context-not-proven IDs; unsupported rejection is not a normative authority outcome |

Counts across rows/languages are not additive. Complete IDs and qualifications remain in the handoffs and candidate/coverage artifacts under `evidence/{rust-v4,swift-v4,kotlin-v4}/`. The coordinator's independent comparator checks canonical bytes/base64/digests and identifies the one common constructor; it does not manufacture native semantic or authorization verdicts. Initial comparison had **zero** common constructor values, so all lanes added the common-input assertion without deleting their original candidates.

Candidate file SHA-256 values: Rust `949edf6998c55a8aa83bc8b719517c484f4d320ab9515052d5a82753b3804a87`; Swift `18540568bec20b46c6fa171dd486d6a12951d9cce3e95a34042f501540d1de06`; Kotlin `fb34bcf02d8e655eb4f0d241814569f979be4e431382f82d1902a52413043f5f`. Native generation requires both `HEALTHMD_GENERATE_AGENT_BRIDGE_V4=1` and explicit scratch `HEALTHMD_AGENT_BRIDGE_CANDIDATES`; missing-output probes fail as intended and remain recorded. No native test invokes Python to obtain its verdict.

#### Post-merge gates and published-crate repair

The main consumer gates below tested committed source through `e61ef90ce078e5f8ce9fc53858462f88aee7ea23`. Additional registry/binding and packaging checks include the subsequent test-only repair `4a987f11feec6c7ca3edb8b5d345dbec1b946954`. Scratch logs retain command output and failures; no mobile build was installed or launched.

| Command / directory | Exit / result / retained log prefix |
|---|---|
| `cargo test -p healthmd-protocol --all-features --locked`, core | 0; 70 passed. `integrated-v4-rust-protocol-tests.log`; old v1/v2/v3/pairing/frame vectors included |
| `cargo test --workspace --all-features --locked`; workspace fmt/clippy `-D warnings`, core | All 0; 169 passed. `integrated-v4-core-workspace-*` |
| Runtime-only `rustup run 1.85.0 cargo check -p healthmd-core -p healthmd-protocol -p healthmd-core-uniffi --all-features --locked`, core | 0; `integrated-v4-core-runtime-msrv.log`; tooling still independently pinned to Rust 1.88 |
| CLI locked workspace tests/fmt/clippy/MSRV; generated MCP asset check | All 0; 227 passed, 2 ignored. `integrated-v4-cli-*`; no CLI v4 dispatch was added |
| `swift test --package-path apps/apple/Packages/HealthMdConnectivity --scratch-path <scratch>/build-swift-connectivity --jobs 2` | 0; 73 passed. `integrated-v4-swift-package-tests.log`; application/XCFramework qualification is separate |
| `:direct-protocol:test --rerun-tasks --max-workers=2` with isolated JVM flags, Android | 0; 31 passed, one live-listener gate skipped. `integrated-v4-kotlin-protocol-tests.log` |
| Full Play/F-Droid unit tests, both lints/assembles and Kotlin binding check, Android | 0; Play 1362 tests / 0 failures / 1 skipped; F-Droid 1201 / 0 / 1. `integrated-v4-android-full-gates.log`; max workers 2; Java 21.0.12 explicitly selected |
| Contract validator and `test_validate*.py` discovery | 0; initially 59 tests, then 60 after packaging mirror regression; 15 registered mirrors. `integrated-v4-{contracts,mirrors-contracts}-*` |
| Native importer and registry adapter checks; two independently generated Swift/Kotlin binding sets and byte diff | All 0. `integrated-v4-core-{import,adapters}.log`, `integrated-v4-bindings-*`; existing check artifacts were preserved |
| `cargo package -p healthmd-protocol --no-verify --offline --locked`, then standalone `cargo test --manifest-path <extracted crate>/Cargo.toml --offline --locked` | Archive build 0; initial standalone test **101** because external monorepo includes were absent. After repair, standalone tests **0 / 70 passed**. `integrated-v4-protocol-package-*` |

The packaging repair adds byte-identical test mirrors of the unchanged conformance fixture, reviewed projection catalog and entire frozen registry; it does not regenerate or promote their provenance. Two contract mirrors are registered in the manifest, and an independent Python regression checks all three source/mirror byte identities. The generator now locates the actual enclosing Git root (or the standalone crate root) instead of assuming monorepo depth. The first missing-mirror regression exited 1; corrected source tests/fmt/clippy and all 60 contract tests exited 0. The retained fixed `.crate` has SHA-256 **`0128d516088db9cecd58420a23fde342c07c701bb7a741cc3f264b9350af51b0`**. Subsequent default `cargo package -p healthmd-protocol --offline --locked` verification also exited 0 (`integrated-v4-protocol-package-default-verify.log`). This is local packaging/test evidence, not publishing or release qualification.

The frozen fixture digest remains `a94e2bc8a7c9a3bcf40b149e857f8d514f7eee9b0fea53319a57fbe04189f076`; registry remains `56def644baa3d81e0c6c2eda3733bfdd7ceee6554ca9ec609da80356c6578c99`. Preservation audit `integrated-v4-frozen-preservation.json` records no second-wave changes to frozen source paths. Packaging subsequently changes only new test assets, their include paths, manifest packaging metadata and a regression; historical fixture/inventory/public bytes stay unchanged.

The sanitized log/digest index `integrated-v4-evidence-index.json` has SHA-256 `386d17e97ec36789d18bba54ee981487cc3c84992f543129d60805a89d3387b3` and binds these retained source/codec/packaging observations, not runtime qualification.

No v4 runtime is advertised. B01/B05/B08 remain incomplete; native consent/authority persistence, zero-read planning/execution, request-local captures, artifact transfer and immutable journal recovery still require implementation. Apple application compilation blockers, the pinned external consumer failure, live/physical qualification and B19/B20 approvals remain open. No todo closes and no capability is promoted from this wave.

### Third serial integration: native settings, SDK fidelity and private discard

All three lanes stopped before coordinator source edits or integration resumed. Apple and settings handoffs were committed/clean. The Android strict-boundary continuation stopped on a provider error with a reviewed uncommitted repair; the coordinator did **not** mistake that idle state for completion. After all lanes stopped, its existing patch/tests were preserved, five hardening tests added and the bounded two-file repair committed. No bypass of the provider error, sibling worker edits, discarded work or uncommitted-source merge was used.

| Slice / source commits | Serial merge | Actual behavior / limits |
|---|---|---|
| Apple `45c60a0b7`, `c6ee0a19b`, `c57cf5fde`, `4ec05bc41` | `de4c7f751cafdf71fdb27bf6aeae1092911ff394` | Local health-free Mac result summary without wire fields; pinned-SDK history boundary fails closed; three live metric accessors repaired; two ContentView compiler expressions preserve deferred dismissal and actual journal partial-success mapping. UI/layout/authority unchanged; app-host tests/visual journeys not run |
| Both-platform native settings `9a55c696f262aa4436c27df588279f2965c9e8f4` | `8eac118b52a2d036cdbab55772cc0dab4f615fea` | Actual detached exporter settings, pinned native selectors/units/reducers, revision/profile/path resolution. Loose summary/no-archive JSON preset only; unsupported axes reject. No stored authority, v4 dispatch, capture or journal acceptance |
| Android discard `a09d06ba5`, `9b334a570`; coordinator strict parsing `bd13e019250564a493012960d4d1dcb1e133950b` | `770c74319675fa4afeb0ed261fcea11ec4984ce1` | Durable private revocation before unlink/admission clear, exact-owned raw/compatibility staging, default/profile reconciliation and late callback/retry fences. Strict raw ledger/binding validation; no external retraction or native authority issuance. Default API is not yet wired to new UI/agent controls |

The 34 changed paths are disjoint; contracts, the entire frozen registry, shared-core/CLI/Worker/website source, public schemas/fixtures, pairing/hello/crypto/frames, model descriptors and committed bindings remain byte-identical to `05fda127a`. No v4 producer advertises support. Private resolution and discard storage are independently version1 and never portable; the seven-field private recovery supplement/historical Shared Setup ledger remain unchanged. The original checkout remains at `e9a1d8757`, with its independently owned Cloud/website work preserved: 11/19 initially inventoried files retain their bytes; eight differ without coordinator restoration or attribution from hashes alone.

#### Resolver and recovery evidence boundaries

The native settings preset resolves nonempty exact IDs for steps and four heart-rate statistics, plus distinct Apple SDNN `hrv` and Android `android.hrv_rmssd`. It retains native types/selectors/reducers, exact Gregorian civil dates/timezone, opaque destination and frozen output snapshots; no API/schedule plumbing or active-profile fallback is inherited. Unsupported categories/all-metrics, provider data, series/archive, nondefault presentation, companions/ZIP and other formats reject rather than approximate. `all_available` stays logical with unresolved days/paths and no history read. Configuration equality on reuse is not grant, approval, expiry or authenticated-journal validation.

Actual detached `AdvancedExportSettings` preferences are instrumented through the supplied isolated UserDefaults dependency, including deferred nested mutations; native value snapshots remain unchanged. Source-slice cancellation-like reconstruction is **not** runtime cancellation/resume. Unused health/quota/grant/wake mocks were removed, not offered as zero-effect proof. Full planning/execution still needs production-path runtime counters and issuer-owned native/host records.

Discard tests exercise actual journal creation, storage, upload/retry and generation/admission dependencies. Tombstones precede cleanup; missing raw journals cannot recapture; signed canonical Long temporary suffixes (including negative values) are matched exactly. In-flight admitted delivery may finish externally; discard stops later private acknowledgement/frontier/retry, not receiver retention. Durable raw sort/capture staging is operation-owned. Corrupt/full ledgers and unverifiable ownership fail closed; revocations are never evicted.

Two plain/escaped duplicate-ledger red tests demonstrated actual journal resurrection, and two duplicate-binding red tests demonstrated ambiguous deletion eligibility. The new raw-byte boundary rejects those before typed decoding. A 1MiB streaming limit plus generic strict bounds apply; legacy binding metadata above 65,536 decoded string scalars, 4,096 array entries or other generic limits is left untouched and reported unavailable—not clipped, repaired or universally supported. Nine boundary tests verify actual filesystem effects, valid noncanonical reads without rewrites and exact/over-limit snapshots. Five later hardening cases are successful assertions, not separately retained red attempts.

#### Integrated gates and retained artifacts

These gates test committed source through **`770c74319675fa4afeb0ed261fcea11ec4984ce1`**. Every substantial native compile used `native-followup-build.sh`, disk/thermal admission, at most two workers (Android one), explicit JDK21 and the external Rust-cache Gradle init. No retained caches/artifacts were deleted. Free space remained above 6 GiB and no thermal warnings were recorded.

| Command / owning directory | Exit / evidence |
|---|---|
| Contract validator + full `test_validate*.py` discovery, root, after every merge | All 0; 60 tests. `third-wave-{apple,settings,final}-contract-*` |
| Swift Connectivity package, isolated scratch/jobs2 | 0; 73 tests. `third-wave-apple-connectivity.log`; source unchanged by later merges |
| Retargeted actual-source resolver host harness and MainActor variant | Both 0; same 12 unique tests, not 24. `third-wave-settings-swift-{harness,mainactor-harness}.log`; 14 actual source links plus qualified scratch dependencies/extractions; not app-host execution |
| Focused native settings/direct/exporter Android tests, both variants | Both 0; 116 tests each. `third-wave-settings-android-{Play,Fdroid}.log` |
| Committed strict-discard scoped Play/F-Droid reruns | Both 0; 625 tests/63 classes each. `android-recovery-discard/strict-boundary/committed-scoped-*`; forced execution, no up-to-date pass claim |
| Full Android unit/lint/debug assembly + Kotlin binding checks, each variant separately | All 0; Play 1407 / 0 failures / 1 skipped; F-Droid 1246 / 0 / 1. `third-wave-full-android-{Play,Fdroid}.log`; skipped dense clinician-report benchmark remains unrun |
| JVM direct-protocol test task rerun | 0; 32 tests / 0 failures / 1 skipped live Rust-listener case. `third-wave-direct-protocol.log` |
| Generic iOS `build-for-testing`, documented platform scheme, signing off | **0 / TEST BUILD SUCCEEDED**. `third-wave-combined-ios-build.log` + xcresult; current resolver/SDK/source/test target compiled, no app/simulator/test-host launched |
| CLI generated MCP assets `--check` | 0; `third-wave-cli-assets.log`. Core/CLI/contracts/Worker/website source byte-identical to the previous tested increment; prior locked/MSRV/packaging/consumer gates remain separately recorded, not rerun or rebranded |

The iOS command ran from `apps/apple`: `xcodebuild build-for-testing -project HealthMd.xcodeproj -scheme HealthMd-Tests-iOS -configuration Debug-iOS -destination 'generic/platform=iOS Simulator' -derivedDataPath <scratch>/build-apple-ios-followup -resultBundlePath <scratch>/evidence/third-wave-combined-ios-build.xcresult -jobs 2 -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile` with all signing/team/profile fields disabled. It compiled current application/test source for both simulator architectures using retained incremental intermediates. The source-built **c6ee** Rust framework was reused only after Git verified identical Rust/package inputs; no new framework build is claimed. New harness copies point to integration source; their first preparation failed on an intentional MainActor scratch-directory symlink, then was corrected without changing product code. That failure is retained, not a resolver failure.

Toolchain: Xcode 26.6/17F113, Swift 6.3.3, SDK 26.5, JDK 21.0.12, Gradle 8.11.1. Unlaunched Apple source build remains 3.4.2/202609171600; Android debug metadata remains 1.9.1/code 39. Exact artifact hashes:

- Combined Play APK: `beeb0c960124d985cc51d297a38929a2acc9d593caaf884bfda75013b4a5eb4b`.
- Combined F-Droid APK: `8aaab4aa918ba4726e041dc785149bb960a47cc7aecd321063a393db7336d294`.
- Unlaunched iOS debug dylib: `1ebc2587760ed506ad79141e7f4848c211b03bc8f2046478f656029e26c5d5ad`.
- Unrun iOS test executable: `9a361fb1c237ea9dbaa4d9821ec7578eb87d0eb119e7fa7b7886e39532a495ce`.

The sanitized 914-file `third-wave-evidence-index.json` SHA256 is **`4b0add99aac39f37b8059670e4cf4160d23987a308f1f21708b2e719cfd1bc69`**; it binds tested source, retained failures, logs, XML/provenance and artifacts, not runtime authority or physical qualification. Earlier 9b334 APKs do not contain the later strict repair and remain separately labeled. Original heap-thrashing, misleading green-log filename, SDK/compiler failures and the settings lane's duplicate-module invocation failures remain retained. That duplicate-output failure is attributed only to its command; no untested baseline-project defect is claimed.

**Remaining:** B01/B05/B08/B09 runtime authority/capture/journals, B10 bound zero-read plan/execute, B11 recipes, queries and permissioned configuration/scheduling/wake/ZIP/dictionaries. Actual native history-boundary support is false on the pinned SDK; stale OS27 guidance/static AgentAPI metadata need B21 reconciliation. App-host tests, literal export-doc generator/drift validation, native/physical/LAN/Tailscale/wake/live delivery and installed/release qualification are not run. The pinned Obsidian failure and B19/B20 approvals remain blocked. All capabilities stay planned and all unmet tasks stay open/in progress; this is not the four-way no-settings journey.

### B21 follow-up: unavailable history support, not OS-version promises

Committed source `aac0109553d33814d71502cabaf567638ea8f573` and `5a03fa7ea14030db9129e832bb9c10b587045470` correct the Mac readiness boolean/message, six iPhone rejection/Intent explanations, Export-tab warning and Apple permission/Shortcuts docs. Current pinned SDK/native adapter support is **false**, independent of a future OS version. Explicit date ranges remain available with unverified completeness. Mac cache/metadata never infer native permissions, no data or a full-history assessment. Android's actual Health Connect historical-read grant path was inspected and remains distinct/unchanged.

Existing API/export/protocol schema versions, fields/types and historical fixtures are unchanged. Legacy integer OS hint and `full_history_claim_requires_os_27_boundary_check` key remain for compatibility; documentation explicitly says they are not availability or upgrade instructions. No SDK API/permission bypass, registry/capability promotion or old-peer reinterpretation is introduced.

An actual-source Swift metadata-initializer/JSON-serialization probe reproduced the wrong advertised boolean (**exit1**), then passed (**exit0**) after the repair. It does not execute the entire service route; Python only extracts the production expression and supplies no verdict. The existing public readiness-route XCTest adds false/unknown/bounded-action assertions, **compiled but not executed**. Both committed-source `HealthMd-Tests-macOS` and generic `HealthMd-Tests-iOS` build-for-testing pass, through the serialized runner with signing disabled/jobs2. Same c6ee shared-core framework is reused after identical input verification; native intermediates are incremental, not clean-room/release qualification. Contract validator and 60 tests pass; affected non-Apple sources remain unchanged.

Evidence/provenance/logs/xcresults are in `evidence/b21-history-metadata/`; its 36-file index SHA256 is **`596dba1153c04173e4336a3aedd8ca246fcbcc6b1ed291c6a60901537fd4a6ad`**. Four unlaunched/unrun binaries are now separately copied under `artifacts/b21-history-source-5a03fa7/`, not just referenced in derived caches: iOS dylib `7d4c93dec529cd53d0bff85ebad88587c884debf85e44ccf326aa1a862275b24`; iOS tests `9a361fb1c237ea9dbaa4d9821ec7578eb87d0eb119e7fa7b7886e39532a495ce`; macOS dylib `27087c0457006ea12de2eb8f1fc50a3153dced37766d143254638573fb439da7`; macOS tests `a9039f29540c4775150d2afe496c10ee7661f7c8af5a5e3b229afe0085c724b5`. Prior derived products can be superseded by incremental builds; older recorded digests remain historical source observations, not retained installed candidates. One artifact-copy preparation failed on an incorrectly guessed Mac bundle name; observed `Health.md.app` paths fixed it, without a product/build/source change.

App/service-host execution, visual/localization review, full export-doc generation, current binary/provider/native lifecycle/physical/desktop matrices and broad B21 website/consumer-skill reconciliation remain unrun. Initial goal and all unmet tasks remain incomplete; no release, deployment, user settings/grant enrollment, real data read or device action occurred.

### Fourth serial integration: stored issuers and callable planning services

All lanes stopped with scoped clean commits before coordinator edits. Exact base `38ae7a1aa171d5638063c236230f6a74e92fbc5f`; 45 disjoint source/test paths (Rust28, Swift8, Kotlin9), no public schema/fixture/registry/dependency/lock/project/binding changes. Scope audit verifies integration bytes equal lane source. Serial merges and contract validator after each merge pass; combined Python suite **60 tests / exit0**. No combined-source native/Rust compilation has yet run.

| Source commits | Merge | Implemented source boundary |
|---|---|---|
| Rust client `295831cf4f3f0eea351a10d0378f4eb02fa23020`, shared adapters `ba973c9fbf099c75b5210963a30f4af2b5afd130` | `0075a6e2e35e8baea0d95bfdbb9803816c7d2a2f` | Real private host grant/root/issued-plan/decision storage; independent v4 connection and current backing-trust fences; fixed `healthmd_export_plan` / `healthmd_export_approval` through shared CLI/MCP service. Execute rejects locally; no old export fallback |
| Swift `69d50e2ba685150579792149bb6f5206c49415b6` | `e053785a22ad47b4a30298fc06c5182dfffef9a0` | Real bounded issuer-private store, strict discovery/plan/exact native-decision relay, actual native resolver/effective-output seam, explicit MainActor serialization and revocable native context |
| Kotlin `ff5919a3a472907bd33de84a0670218e4bd40338` | `4df7cc180d82f481d70eebf2b3204d34c3594173` | Existing no-backup factory, bounded private store/CAS/locks and strict source service using actual resolver, independent non-wire native decisions and current-peer checks |

These are working **callable source services**, not installed native routes or completed B10. Native app/TCP hello/dispatch/UI, protected-key provisioning/configuration/session adapters and final transport-send coordination remain unwired. Only reviewed nonempty exact metrics, summary/no archive, loose daily JSON/overwrite/default presentation/ASCII layout are supported. Logical history stays unresolved without reads. Native issuers verify their own stored parent only; supplied host descriptions/destination cannot issue host rights. Host independently loads its grant/root and clamps expiry. Remote discovery/plan/approval cannot initialize keys, grants, roots or decisions. Read-only MCP excludes/denies the two operations.

#### Lane-source gates (not combined-build or installed evidence)

Every substantial lane compile used the serialized `native-followup-build.sh`, fresh disk/thermal checks, jobs≤2; native app builds required10GiB. Java21/one worker/in-process1.5GiB and external lane outputs were used. No cache/artifact removal, sibling process control, native credentials, installs/launches, health/provider reads or live delivery occurred.

| Lane / exact command surface | Exit / result |
|---|---|
| Rust CLI `cargo test --workspace --all-features --locked` | **101**:232 passed, one unchanged stale packaged-catalog assertion failed, two preexisting ignored; stops before operations suite. `27-final-full-workspace.log` |
| Rust same command with explicit `-- --skip catalog::tests::packaged_catalog_is_generated_from_the_shared_registry` | 0:245 passed, two ignored, one explicitly filtered. This bounded gate is not a full-workspace pass. `24-final-bounded-tests.log` |
| Rust CLI all-target/all-feature clippy `-D warnings`; runtime1.85 locked check; both fmt checks | 0; MSRV is compilation, not1.85 execution. Protocol unchanged:70 tests/clippy pass. `20-cli-msrv.log`, `21-protocol-tests.log`, `22-protocol-clippy.log`, `25-final-clippy.log` |
| Rust canonical generated assets `--check` | **1**, only `mcp-tools-v1.json` stale after two declarations. Catalog source23; packaged asset still21. Coordinator regeneration pending; no assertion or old asset weakened |
| Swift Connectivity `swift test`, jobs2 | 0:74 tests. `connectivity-verified.log` |
| Swift actual-source ordinary/default-MainActor harnesses | Both0; same36 unique tests (17 service,7 store,12 resolver), not72. `harness-verified.log`, `harness-mainactor-verified.log` |
| Swift generic iOS `build-for-testing`, signing off/jobs2 | 0 / TEST BUILD SUCCEEDED; app/test target compiled, zero app-host tests executed. Verified-identical c6ee framework reused only as aid; no new framework rebuild |
| Kotlin focused Play/F-Droid tests | 0:46 passed each (factory5/store11/planner19/resolver11). `native-qualified-source-final.log` denotes source-only tests |
| Kotlin direct-protocol tests | 0:38 passed, one live listener skipped; seven new pure delegation cases. Native device/Keystore/SELinux/lifecycle not run |

Complete commands/exits/source/dependency/artifact hashes and red attempts remain in the three reports/indexes under `reports/` and `evidence/{swift-native-planning,kotlin-native-planning,rust-host-planning}/`. Misleading green filenames, compile/import mistakes, corruption normalization, Android creating-getter failures, exact replay-ID rejection, revoked-response and final-authentication-fence expiry reds are retained. An earlier Kotlin command unintentionally ran the full Play1436 suite and only focused F-Droid29; it precedes final fences and is not final-source full Android qualification.

#### Security and cross-source acceptance limits

- **HMAC is integrity, not privileged historical-snapshot anti-rollback.** Limitation tests demonstrate signed rollback acceptance; no native-protected monotonic witness exists. Native same-instance inode fencing does not prove protected root identity on fresh open. Windows new issuer storage deliberately rejects; Linux/native credentials unrun. Host setup currently supports one initial peer/grant/root, not multi-root/update/rotation/renewal.
- Android's real no-backup parent is inspected as existing `dataDir/no_backup`, never through the creating getter. Tagged AOSP Android16 evidence shows0771; trusted native UID/GID-owned0700/0771 parents differ from arbitrary strict0700 temp injection. Leaf/files stay0700/0600. Real filesystem/provider/Context-alias/SELinux behavior remains unqualified.
- Exercised key/preference/configuration/transport/filesystem dependencies are distinct from all eight public zero counts. Health/earliest/preview/provider/quota/output/settings/enrollment/wake absence is **structural source-service qualification**, not unused counters or installed-path proof. Private issued metadata writes are intentional.
- **Observed structural interoperability gap:** Kotlin discovery advertises only three layout setting pointers; the host demands every effective-settings leaf, including fixed/disabled outputs. Host fake peers advertise more, so their passing both-platform parity tests do not prove the actual Kotlin counterpart. An actual-source red tracer and truthful capability-pointer correction are required; no unsupported settings/authority widening.
- **Delayed-boundary qualification remains:** Swift uses one trusted `now` snapshot per synchronous request; Kotlin final transaction fences check trust but not necessarily expiry after every callback. Host local decision checks time before awaited native consent; private-key publication can be delayed after a clock check. Final-authentication expiry tests do not cover every consent/persistence delay. Add exercised clock-advance regressions and final expiry/current-authority checks; do not treat persisted stale metadata as permission.
- Capture/execute/journal/transfer/receipt/resume/cancel/recipe support remains absent. Apple366/Android128 advertised planning artifact limits are distinct. No bound-execution feature or installed availability is promoted.

#### Combined admission stop and preservation

After merges, available disk fell below6GiB. Canonical coordinator `CARGO_TARGET_DIR=<scratch>/build-cli CARGO_NET_OFFLINE=true python3 scripts/update-mcp-shared-assets.py` through the runner exited **70 before compilation/generation** (`fourth-wave-mcp-regeneration-first.log/.exit`). No asset mutation or substitute filtered-green gate occurred. Native app gates additionally require10GiB. Combined native/Rust/MSRV/assets/full Android/app gates remain pending until fresh admission returns. No retained cache/artifact deletion or space-recovery attribution is made.

Point-in-time138-file `fourth-wave-evidence-index.json` SHA256 **`dc8d41315468215be8677d1ec12aca58af3a2939fac0923bc01b9beb161fcb34`** binds lane hashes, merge/contract checks, failures and scope/preservation observations, not future files or runtime qualification. Original checkout independently advanced to `19f6b41b05d0edafa0adbf4c1ff59baa80648c39`;10/19 initial hashes now match. Changed original paths are neither restored nor attributed from hashes; original work is not staged/imported. Integration remains separate.

B01/B09/B10/B21/B22 remain incomplete; B11 has not started. Next acceptance work is real counterpart capability/clock boundary tests, combined native gates, native setup/dispatch and bound execution/journals, then recipes. Broader query/configuration/scheduling/wake/ZIP/dictionary and physical/live/installed gates remain. No task closure, capability promotion, deployment/release or goal completion.

### Admitted canonical catalog and unfiltered combined CLI follow-up

A fresh observation returned17519960KiB free/no thermal warning after an earlier5047068KiB stop. No cleanup, cache deletion or recovery attribution is made. With all prior lanes stopped/clean, canonical `CARGO_TARGET_DIR=<scratch>/build-cli CARGO_NET_OFFLINE=true python3 scripts/update-mcp-shared-assets.py` ran through the mandatory serialized runner and exited0. Only `mcp-tools-v1.json` changed:23 source/generated declarations, all21 prior entries preserved and two fixed plan/exact-approval-relay entries added. HTML/registry assets, frozen protocol/export contracts, independent lockfiles and unrelated components remain unchanged. No retained-generator substitution or manual asset construction was used.

On integration base `8c95e19d56ad6b2e5fe76fc7b463cd08b3cc9c9a` plus this canonical catalog diff, the **unfiltered** locked/all-feature CLI workspace exits0:246 passed, two preexisting live-listener tests ignored, zero filtered/failed. Owning fmt, all-target/all-feature clippy `-D warnings`, runtime Rust1.85 locked check and canonical asset `--check` each exit0. Each substantial invocation used the runner, jobs2 and fresh disk/thermal admission; final observed16882408KiB/no warning. Logs/commands/exits `fourth-wave-mcp-regeneration-admitted.*` and `fourth-wave-combined-cli-{fmt,full-tests,clippy,msrv,assets}.*` are retained separately from earlier stale-catalog red/filtered lane results. MSRV is compilation, not1.85 execution; incremental external caches were reused, not clean-room qualification.

The 23-tool development catalog does not enlarge frozen CLI1.0's21-tool scope or public alpha.7's19-tool release. Read-only remains13. CLI readiness/QA count guidance is corrected without availability/release promotion. These passes resolve catalog drift only, not actual Swift/Kotlin counterpart compatibility, delayed expiry boundaries, combined native compilation, native setup/routes, bound execution/receipts/recipes/resume or installed/physical qualification. B10/B21 remain in progress; B22 remains open.

### Fifth serial integration: live planning boundaries and actual-native discovery

All three lanes explicitly stopped/standing by, committed and clean, and were observed `done` before coordinator repository edits. Exact base `3bc392c823193ab04aeea4bb71e7cbcb5747b403`. Sixteen disjoint paths (host7/Swift4/Kotlin5); merge bytes equal the tested lane hashes. No source conflict repair, frozen contract/core/registry/capability/fixture/dependency/lock/project/binding/old transport change or manual catalog edit. The host CLI test migration changes exactly one existing argument to pass the live clock, not a timestamp; production CLI behavior is unchanged.

| Source commit | Serial merge | Actual increment |
|---|---|---|
| Host `e03f4944324b5389dda23143c435645fde8f95d9` | `1e37c2b16021056d39f29917c1984758029e8998` | Trusted live-clock/latest locked host authority after awaited consent/key/current-source callbacks, staged/fsynced prepublication fence, independently refreshed final return and cached approval. Advisory CLI snapshot preflights remain non-authorizing |
| Swift `9fe74f142544241efe37154ad2763dc9fed54634` | `da81768214d52e7bd7504efac3ff511eab832635` | Service-owned live clock, post-consent exact decision from real locked CAS state, refreshed configuration/session/parent and state-aware pre-rename/return fences; exact retries retain identity/timestamps/expiry |
| Kotlin `4f9a9ec334a3921eeaf5755c606edbfdccda8620` | `cccbb13de93a689b5b4a20cf576b5914fabbc0e7` | Locked candidate/parent/configuration/live-time fences after signing/pending-file fsync and at typed/envelope returns; actual preset derives31 fixed/default leaves rather than only3 layout pointers |

#### Exercised publication semantics, not global atomicity

Retained actual-source reds reproduced stale consent and publication, not merely hypothetical races. Host consent persisted a decision after expiry; delayed publication keys advanced plan/approval revisions despite final rejection. Swift consent/key/configuration/session, serialized/fsynced plan/decision and final discovery-parent checks failed before fixes. Kotlin actual discovery required31 leaves but returned3; delayed consent/signing/pending/cached/return regressions failed. Each native/runtime verdict comes from actual service/store/resolver or host store/transport execution; Python supplies only hash/scope/provenance checks.

Prepublication rejection checks byte-identical state/generation and only the original published files. A rejected fence cleans only its own unpublished temporary, never repairs interrupted/corrupt state or evicts revocations. Current-trust callbacks precede final live-time checks after bounded serialization/signing/staging work. Consent/decision timestamps are sampled after consent; binding/expiry never renews.

Postpublication rejection is separately exercised: a later callback/key load can suppress return while stale private plan/decision/approval metadata remains. It is not rollback or proof publication never occurred. Fresh subsequent authority/expiry checks reject that metadata; execution still rejects as unsupported. No atomic transaction spans external trust/configuration, wall time, filesystem scheduling and response delivery. Future native routes must qualify their actual send boundary. HMAC valid-snapshot rollback and native fresh-open identity limits remain; no protected monotonic witness, Windows issuer implementation or multi-root setup was added.

Kotlin support names include fixed/disabled DTO leaves, not arbitrary settings. Twenty-one nondefault output candidates still reject; the real native resolvers and host full-leaf check are unchanged. Summary/no archive, default presentation, loose JSON/overwrite and safe ASCII layout remain the reviewed subset. Health/earliest/preview/provider/quota/output/settings/enrollment/wake absence remains structural source-service evidence; exercised isolated preferences/configuration/key/filesystem/trust dependencies do not become installed-route counters.

#### Final lane-source gates — not post-merge compilation

| Owning command surface | Exit / result |
|---|---|
| Host CLI `cargo test --workspace --all-features --locked` | 0:256 passed, 3 ignored, 0 filtered. Two preexisting live-listener ignores plus one opt-in native-artifact tracer, separately executed below; host integration suite22 unique cases |
| Host fmt/all-target all-feature clippy `-D warnings`/runtime1.85 check/canonical assets `--check` | All0. Runtime1.85 is compilation, not execution; all final gates16–22 bind unchanged source/locks aggregate `62c06e08fc3c45ce14a85fdec56a8edb130c9b584e9c279c4cab988fcb580741` |
| Unchanged host protocol suite | 0:70 passed |
| Swift Connectivity / actual-source ordinary/default-MainActor harnesses | All0:74 package cases plus the same54 unique harness cases (planning34/store8/resolver12), not108. Both generation methods exercise service assertions before output gates; explicit generation runs write candidates |
| Kotlin focused actual native service/store/resolver/factory, both variants | 0:62 per flavor,124 executions/62 unique methods. One normally no-op generation method is included; its native path executed separately for the baseline only |
| Kotlin unchanged direct-protocol/binding equality | 0:38 pass/one preexisting live skip; fresh binding equality0 |
| Swift-complete actual-native-to-host tracer | 0:one explicit case/99 filtered in this scoped tracer, not a replacement for unfiltered workspace tests;31 pointers, baseline/digest/revision/missing-leaf/nondefault negative checks |
| Kotlin before-fix actual-native-to-host tracer | Retained101:3 pointers cause actual `unsupported_capability`, not parsing/preparation failure |
| Kotlin after-fix actual-native-to-host tracer | **NOT RUN: native after-candidate absent** |

Each substantial lane compile used `native-followup-build.sh`, fresh disk/thermal admission and jobs≤2; native app/app-module gates require10GiB. Host/Swift warm shared intermediates remain incremental evidence, not clean-room/release qualification. Earlier native/compiler/preparation/format failures are retained; Kotlin's precisely reverted optional uncompiled test is not counted as final coverage. No retained caches/evidence were removed or space movement attributed to cleanup.

Reports `reports/{host,swift,kotlin}-planning-boundaries.md` and their `evidence/<lane>/evidence-index.json` retain full commands/exits/source/test/dependency/artifact hashes, distinct reds/greens, unique versus repeated counts and missing gates. Final lane index SHA256 values: host `d8da1af0ac93a1e6d2184023836e21680b1327a3a5f72436beb31de01e01db28`; Swift `a6265c561208a6aceb219348edf5321e0ff4afe69722494a000d47721d4b9607`; Kotlin `5e3e4febdcfe131928c3458644513e33ec255c7c3c700af882306638d98ef093`. Shared cache executable hashes are point-in-time observations, not immutable installed artifacts; Swift separately retained harness executables remain synthetic-source tests.

#### Actual native candidate provenance and remaining interoperability

Both native producers require `HEALTHMD_GENERATE_AGENT_BRIDGE_V4=1` and an explicit scratch output. Native typed constructors and the production private store/service/resolver execute before native source hashing/output; no Python candidate/authority verdict or richer fake substitute.

- Retained Kotlin-before six-field wrapper: `evidence/kotlin-planning-boundaries/native-discovery-before.json`, SHA256 `7cde5bd9f04be53e44c03e8b92f1d75333d929f096b87708de2b22220016e2c8`, nine native source-input hashes,3 advertised pointers. The host red is semantic, not parser failure.
- Swift current complete wrapper: `evidence/swift-planning-boundaries/native-discovery-candidates-complete.json`, SHA256 `f4fb1610b6a1bcddb49dbff38c6def76bba8ab693a8f43eecfb10ad18c7f80af`,15 native source/registry hashes,31 pointers. Strict actual host tracer accepts it. Earlier standalone discovery and intermediate discovery-only host probe remain separately qualified, not relabeled as complete-wrapper acceptance.
- Kotlin-after remains absent after app-module admission70 before Gradle. Passing native31-leaf focused tests do not manufacture an after-candidate or host verdict. Both-source after-fix interoperability remains incomplete.

Candidate bytes/references prove capability interoperability only, never native/host permission, live TCP/app routing or the full journey. Production mobile4 routes remain unwired/unadvertised, and encrypted fake peers are not actual native counterparts.

#### Post-merge static checks and blocked stop

Contract validator after each serial merge exits0; full static `test_*.py` discovery exits0/60 cases. Exact sixteen-path union/lane-source equality, all420 retained lane-evidence hashes, native producer provenance and source diff-check pass; no tracked paths outside the allowed union changed before central documentation. Coordinator review is bounded, not an exhaustive independent security audit.

Point-in-time469-file `fifth-wave-evidence-index.json` SHA256 **`fd74e0b1230f27e8caa239025e37c66496be4178eeec6588f523d106c773aa0b`** binds source head `cccbb13de`, stopped receipts, lane reports/indices, exact static commands/exits, retained failures and preservation/resource observations. It does not cover later documentation as compiled source or mutable cache binaries as immutable candidates.

**No fifth-wave post-merge compiler gate ran.** Coordinator observed4,721,440KiB free at2026-10-05T11:26:04Z, below6,291,456KiB, with no thermal/performance/CPU-power warning. This is a resource observation, not a new failed compiler or admission invocation. All Rust/Swift package/harness post-merge gates remain not run;10,485,760KiB is additionally required for Kotlin after-generation/full variants/lint/APK and native app/test-target builds. Earlier lane admission70 evidence remains distinct. No cleanup, retry loop or gate bypass.

Original checkout remains separately owned at observed `19f6b41b05d0edafa0adbf4c1ff59baa80648c39`;10/19 initial hashes match, without attributing/restoring changed files or staging/importing original work.

B10/B21 stay in progress and B22 stays open. Native consent/setup/key/configuration/session adapters, negotiated4 routes/send coordination, bound capture/execution/journals/transfers/receipts/recipes/immutable resume and four-way acceptance remain absent. Android typed-query/extraction, permissioned configuration/scheduling/native wake/ZIP/dictionaries, broad docs/consumer/physical/OS qualification and B19/B20 approvals remain incomplete. Resume missing compiler gates only under fresh admission; generate actual Kotlin-after once in a separate gated test before ungated full variants and the exact host tracer. Do not invoke the application-launching export-doc generator in this slice. No task closure, capability promotion, deployment/release, live user action or goal completion; further compile-dependent work is stopped pending headroom.

### B21 static CLI history and lifecycle guidance

Commit **`417f2c11dc38484c982a1111da06b280bd5208ed`**, base `dcdbde4f7c55fc3a69bebc836af339616e6b9fea`, changes only four CLI support docs and the existing CI-discovered release-policy test module. Read-only native/doctor source inspection found stale OS27 support promises, despite the pinned SDK's unavailable boundary assessment. No native/runtime/contracts/assets/locks/workflow/project/binding byte changes or new builds. All fifth-wave lanes remain done/standing by; no original or sibling edits.

Readiness now requires actual peer metadata and exact native build/SDK assessment, not OS upgrades. Compatibility explains `api_unavailable`, absent/`unknown` and denied-versus-empty ambiguity, preserves legacy hint names/types, and distinguishes Android's historical-read/first-grant-date model. Typed execution and wake-window examples use bounded exact dates, explicitly illustrative rather than silent user-scope substitution. Failure guidance distinguishes iPhone foreground/protected data from Android's active user-started service/first unlock. Logical configuration-only planning remains distinct from capture/native routes/approved execution. Alpha.7 mobile table rows are byte-identical and pending; development23/read-only13/publicalpha.7 19/frozenCLI1.0 21 are unchanged.

Three vertical public-document assertion reds/greens are retained. At committed417f2c11, Python3.14.7 executes the four existing CI static policy modules: **24tests/exit0**, including three new methods. The single release-policy module has9 (6existing+3new), not a wrapper's initial incorrect10 label. Contract validator0/full60tests0, exact five-path audit0, seven local file/anchor links0 and diff checks0. JSON example checks validate public shape/bounded illustrative dates, not native protocol execution or permissions. Initial Python3.9 `tomllib` import and wrong Herdr wrapper-field parsing are retained preparation failures, not product/native defects; no toolchain/dependency installation.

Report `reports/b21-cli-history.md`, commands/exits/inputs/reds and the **87-file** static index `evidence/b21-cli-history/evidence-index.json`, SHA256 **`115a4e1087f5160258d265a967e8b94e307900893d8f28d3ed75050fc9b124df`**, bind this source increment. All469 earlier fifth-wave evidence hashes recheck without mismatch. This index does not turn later central docs/todos into compiled native evidence.

Observed2026-10-05T12:12:00Z available5,412,520KiB/no recorded warning remains below6,291,456KiB compilation and10,485,760KiB native-app admission; space movement is unattributed. No compiler/admission attempt, cache cleanup/substitute, native operations or application-launching export-doc generator. Fifth-wave post-merge compiler/native gates and Kotlin-after candidate/tracer remain not run. Runtime/native instruction mirrors, broader B21 website/localization/consumer skills and B22 full journey/physical qualification remain incomplete; native setup/routes, bound execution/receipts/recipes/resume and other backlog work remain absent. B21 stays in progress, B22 open; no capability/release/todo/goal promotion.

### B21 static root inventory: source catalog and universal pairing

Commit **`bba3106b913d209ef1df28692609cab7b07eb837`**, base `38c544aad945a592ac189ee3b6610293278b1098`, corrects exactly three root feature-inventory rows and adds two static public-doc regressions to the existing CLI CI module. Portable development23/read-only13/publicalpha.7 19/frozenCLI1.0 21 are separated from independently versioned bundledMac21. Plan/exact-approval relay names do not promote native4: routes remain unwired/unadvertised, no bound execution. Pairing describes universal selector3/20-digit iPhone+Android QR, preserves legacyApple1/6 and Android2/20, distinguishes query3 and forbids permission escalation. Other inventory bytes/classifications and all runtime/assets/contracts/fixtures/locks/workflow/project/binding bytes remain unchanged.

At committedbba3106b9, Python3.14.7 four existing CI static modules exit0/**26tests** (two new unique methods; single release-policy module11). Contract validator0/full60tests0; exact two-path/three-row source preservation0 and diff/staged checks0. Actual canonical catalog bytes remain equal to prescribed-generator3bc392; no generation/check compilation or native negotiation verdict is inferred. Two vertical assertion reds/greens are retained. Pairing red has four failed assertions/subcases in one method, not an initially mislabeled five; absent guessed native docs paths and that console-verifier failure remain preparation/source-review evidence.

Report `reports/b21-root-inventory.md` and **53-file** index `evidence/b21-root-inventory/evidence-index.json`, SHA256 **`dcfa00fe8bfd7c60c7aaec6b693262d9792205100b13e1a09679ecc66df9177f`**, bind this committed static source. All556 earlier indexed entries rehash without mismatch. Later central records/todos are not compiled evidence. Fifth-wave agents remain done/standing by; no sibling/original or website edit.

Earlier blanket statements that no safe work remained were too broad: B21's root-inventory seam was executable without a compiler. Native/Rust build-dependent work remains blocked: observed2026-10-05T12:43:03Z5,255,100KiB/no recorded warning is below6,291,456/10,485,760KiB. No compiler/admission, cache deletion/substitute, credentials, real health reads, device/app/user mutation, notification, deployment or release. Remaining shared-setup/NDJSON/website/locales/consumer-skill claims require separate revalidation, not inferred fixes. Native post-merge gates/Kotlin-after/routes/execution/recipes/full journey and physical acceptance remain incomplete. B21 stays in progress, B22 open; no task/capability/goal completion.

### B21 static parity: Shared Setup availability and source-specific raw output

Commit **`95d890094bc7afa6c4341aa03b79d1a8384082ed`**, base `91500df5469b24de54ae564cc430c2fad12650f7`, changes exactly three complete public rows across root parity/inventory plus a two-method class in the existing CLI CI release-policy module. Share My Setup now matches the unchanged capability `planned` and v2 contract/manifest `deferred` state. ADR-0006's v2-only default-writer decision and host-side transaction tests do not satisfy physical-device interoperability/accessibility or promote availability; the existing v2 QA matrix remains not run. Separately assigned Shared Setup tasks were read, not edited/claimed/closed.

Raw rows now identify Android provider-native JSON/NDJSON snapshots and their CLI `--raw-format ndjson` option. Reviewed iPhone source constructs `ResponseMode::RawJson`; MCP rejects iPhone raw NDJSON. Bounded host-side `extract --format jsonl` remains a distinct canonical projection, not an Android snapshot or a new native format. This is source review/public-copy correction, not freshly executed parsing or transport. All10 unchanged website platform-feature pages already gate Shared Setup with QA/planned markers and keep raw snapshots Android-only; checks are read-only and cover these rows, not translation quality, rendering, every website claim or whole-site qualification. No website/localization or product classification/contract/default-writer change.

Two vertical public-doc reds/greens are retained: setup red1 has one assertion failure; raw red1 has two document subcases in one unique method. At committed95d890, installed Python3.14.7 four-module static CI suite **28tests/exit0**, single policy module13 (six preexisting plus seven cumulative public-doc methods), contract validator0/full60tests0. Exact three-path/three-row preservation, two local file/anchor links, prior policy-test bytes and diff/staged checks0. Canonical catalog remains byte-identical to prescribed-generator3bc392; runtime/native/core/routes/crypto/hello/contracts/fixtures/registry/classification/locks/workflows/projects/bindings/assets and alpha.7 pending qualification rows unchanged. No compiler/generator/native permission or installed verdict.

Report `reports/b21-parity-setup-raw.md` and **82-file** index `evidence/b21-parity-setup-raw/evidence-index.json`, SHA256 **`e5a1507bc3371a7867aa538389ceba4877095c838d81ebabe78723716d2c3c95`**, bind that clean source and its static gates; all609 earlier indexed entries rehash without mismatch. Later central records/todos/checkpoints are separate, not retroactive compiled evidence. Fresh Herdr receipts are idle at unchanged912/911/913 sequences with matching final commits/clean worktrees; retained handoffs establish the already-resolved barrier, not idle alone. Unsupported get flag, bare help exit2 in set-e preflight, no-match scratch search and out-of-range read offset are preparation observations, not product/compiler reds. No lane restart or original/sibling source write.

Observed2026-10-05T13:11:51Z2,874,296KiB (~2.74GiB)/no recorded thermal/performance/CPU-power warning is below6,291,456/10,485,760KiB. Disk movement is unattributed. No compiler/admission attempt, cleanup/bypass/substitute, app-host/device/service/credential/settings/schedule/health-read/wake/deployment/release action or application-launching export-doc generator. Whole website/npm/i18n/Astro/visual/human-translation and native/installed/physical gates are not run in this slice. Fifth-wave merged compiler gates/Kotlin-after/routes/execution/receipts/recipes/resume/full journey and wider backlog remain incomplete. Further concrete static B21 native-lifecycle/MCP/support/website/skill reconciliation is available; B21 in progress, B22 open, no task/capability/goal promotion or confirmed pause.
