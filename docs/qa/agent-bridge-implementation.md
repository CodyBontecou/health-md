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
- Three first-wave scopes: B16 Android API/scheduler security; B02/B03/B04 CLI-only repairs; B01/B05 contracts-only specifications. No overlapping writable files. Coordinator does not edit repository files while workers run.
- Retained scratch receipt hashes: original HEAD `894f13c962a42822187703762f3282e4170e2d6587ab1b3afb3faa08d3243a6d`; original status `64c5d177132cecb1e76be0dbf5f46c741c487008e54f6c9f8277c5e7e7e151d5`; original file inventory `eea3035cc16dfab8376fa06f2346adfe93cd3facb4b20bf19a85cfbefd3ecc0c`; preservation diff `f8cf5a8a6c75c4ab1992ddd2b5b25d4d8d6f08469b976a0c3deec5f81b0e7749`. These prove initial preservation only, not feature implementation.

## Prompt-to-artifact implementation checklist

Every row requires the linked todo's individual acceptance items, implementation commits, tests, and the relevant gates below. A planned artifact is not evidence of implementation.

| Requirement | Artifact/test surface to inspect | Integrated evidence / remaining work |
|---|---|---|
| B01 contracts: precedence, scope, output, plan, approvals, revisions, authority, versions | New bounded contract/schema/fixtures; source resolvers; cross-language conformance | Pending |
| B02 source-aware generated MCP dispatch and durable receipts | CLI/client shared dispatcher; MCP adapter; both-source fake peers; filesystem/digest/cancel regressions | Pending |
| B03 mobile MCP/host pairing, approval, single credential identity | Pairing coordinator/client, onboarding, image/App privacy tests, transcript preservation | Pending |
| B04 advertised profile grammar/policy matches parsing and negotiation | Operations registry/normalizer, CLI guidance, generated schemas, old-peer/profile conflict tests | Pending |
| B05 Android typed semantics, native evidence, bounded cursor contract | Versioned Android query spec/fixtures, reviewed IDs/units/statistics, SDK evidence | Pending |
| B06 Android native typed capture/evaluation | Kotlin repository/evaluator/FGS boundaries; every fixed operation, DST/history/cursor/cancellation tests | Pending |
| B07 source-neutral CLI/MCP query/catalog/chart routing | Client/operations/MCP; old-peer/multiple-device/unit-safe PNG/App tests | Pending |
| B08 Android request-local daily extraction | New versioned native product/envelope and Rust validator; selectors/completeness/resume tests | Pending |
| B09 explicit generated settings on both sources | Protocol/client/Swift/Kotlin production resolvers and durable journals; unchanged-preferences/path/crash tests | Pending |
| B10 zero-health plan and bound execution | CLI/MCP plan API; read/write/quota counters; expired/stale/peer/scope/root/approval rejection tests | Pending |
| B11 host recipe CRUD/run | Private atomic bounded store, CAS/idempotency, CLI/MCP parity, corruption/concurrent/stale/run-freeze tests | Pending |
| B12 native profile CRUD/activation with separate approval | Both native stores and shared controls; protection/import/last-profile/revision/rollback/schedule tests | Pending |
| B13 bounded host scheduler and exact-job recovery | Typed portable scheduler and private state; DST/catch-up/concurrency/unknown-outcome/headless tests | Pending |
| B14 native schedules/destination workflows | Both native profile-bound controls, human grant actions, exact-endpoint approval, recovery/late-worker tests | Pending; B16 prerequisite |
| B15 Android Play wake, F-Droid/force-stop degradation | Mocked notification-only Worker FCM/HMAC and native enrollment/tap/revoke/fallback; no live delivery | Pending; deployment separately unauthorized |
| B16 before-read API recovery authority | Pending admission/settings/credential proof; compatibility/raw runners; no-read rotation/legacy/race tests | Pending |
| B17 bounded ZIP packaging, explicit settings/manifest | Native/direct streaming production artifacts, path/digest/budget/cleanup/cancel tests | Pending |
| B18 profile-aware dictionaries and catalog | Registry/native evidence, separately versioned companion, coverage/alias/unit/manifest tests | Pending |
| B19 range summaries | Approved unified-v9/consumer evidence required | Blocked; no approval granted |
| B20 typed WHOOP profile | Approved new profile/provider/consumer evidence required | Blocked; no approval granted |
| B21 truthful capability/docs/schema reconciliation | Capability JSON, feature tables, native/CLI/support/website/locales/skills; source ≠ installed ≠ qualified | Pending; incremental only |
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

No product implementation integrated yet. Future entries must include commit/test mappings, sanitized commands and exit codes, failures, hashes and not-run/blocked items; no todo closes on intent alone.
