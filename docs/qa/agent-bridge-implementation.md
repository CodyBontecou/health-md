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
| B01 contracts: precedence, scope, output, plan, approvals, revisions, authority, versions | New bounded contract/schema/fixtures; source resolvers; cross-language conformance | Deferred specification plus pure Rust/Swift/Kotlin codecs, merged through `e61ef90ce`; one common independently constructed intent agrees byte-for-byte. Native execution/authority and complete conformance remain missing |
| B02 source-aware generated MCP dispatch and durable receipts | CLI/client shared dispatcher; MCP adapter; both-source fake peers; filesystem/digest/cancel regressions | `14ac445a2`, merge `b9392ef74`: source-bound iOS-v1/Android-v2 dispatcher and validated host commit receipts; hermetic tests pass; four-way v4 journey remains pending |
| B03 mobile MCP/host pairing, approval, single credential identity | Pairing coordinator/client, onboarding, image/App privacy tests, transcript preservation | `14ac445a2`, merge `b9392ef74`: first-mobile pairing/onboarding and both-source fake peers; no transcript rewrite or physical pairing performed |
| B04 advertised profile grammar/policy matches parsing and negotiation | Operations registry/normalizer, CLI guidance, generated schemas, old-peer/profile conflict tests | `14ac445a2`: portable grammar agrees, Android gated. `9a55c696f` repairs authoritative Apple ID lookup; explicit iOS policy discovery/Apple MCP mirrors and enabled transport remain pending/fail-closed |
| B05 Android typed semantics, native evidence, bounded cursor contract | Versioned Android query spec/fixtures, reviewed IDs/units/statistics, SDK evidence | `d0ffb6542` + `a2832dc02`: exact native SDK identity/precision and bounded query/projection contracts; static SDK review and synthetic oracles only, not runtime conformance |
| B06 Android native typed capture/evaluation | Kotlin repository/evaluator/FGS boundaries; every fixed operation, DST/history/cursor/cancellation tests | Pending |
| B07 source-neutral CLI/MCP query/catalog/chart routing | Client/operations/MCP; old-peer/multiple-device/unit-safe PNG/App tests | Pending |
| B08 Android request-local daily extraction | New versioned native product/envelope and Rust validator; selectors/completeness/resume tests | Pending |
| B09 explicit generated settings on both sources | Protocol/client/Swift/Kotlin production resolvers and durable journals; unchanged-preferences/path/crash tests | `9a55c696f`, merge `8eac118b5`: bounded detached native JSON/selection/path resolvers and renderer adapters; source-slice preference tests pass. Stored authority, dispatch/capture/journals and runtime success/failure/cancel/resume invariance remain pending |
| B10 zero-health plan and bound execution | CLI/MCP plan API; read/write/quota counters; expired/stale/peer/scope/root/approval rejection tests | Pending |
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
