# Agent bridge parity audit and implementation backlog

- **Audit date:** 2026-10-04.
- **Source baseline:** `e9a1d8757b679ea49820893537873ef3002604fe` plus the working tree inspected in this session. Existing unrelated Cloud/website edits were not changed.
- **Status:** source-based findings and proposed implementation backlog; not an accepted wire specification, availability promotion, or release qualification.
- **Audit task:** `TODO-f721bd3c`.
- **Scope:** Android/iPhone direct CLI/MCP parity and agent-owned export/configuration workflows, plus verified adjacent native export/recovery gaps. This is not an exhaustive new watch, accessibility, billing, or cloud-service audit.

## Implementation progress (2026-10-04)

The dedicated `goal/agent-bridge/integration` branch includes five serial source waves through
`cccbb13de`: deferred B01/B05 contracts/codecs, B02/B03 repairs, partial B04 profile handling,
B09 native JSON/settings resolution, B16 authority/discard, Worker-only B15 FCM, scoped Apple
compiler/SDK repairs, private native/host stored planning, and exercised live consent/key/configuration/
publication/return fences. The audit findings below retain their original baseline context; consult the
[implementation ledger](../qa/agent-bridge-implementation.md) for commits, exact source/test evidence,
retained failures and remaining acceptance.

Frozen export/protocol/registry/Shared Setup bytes remain unchanged. Callable stored planning is not
native setup/routes or bound execution. Canonical catalog regeneration resolved prior drift; latest
host lane tests pass unfiltered256/3ignored/0filtered. Kotlin now truthfully represents31 fixed/default
output leaves without widening the preset. Actual Swift-complete discovery-to-host semantics pass;
Kotlin-after candidate/interoperability and fifth-wave merged compiler/native gates are not run.
Fresh coordinator disk is below6GiB; no post-merge compilation or admission bypass occurred.
V4 dispatch/capture/journals, typed queries/projection, permissioned controls, recipes/schedules and
ZIP/dictionaries remain unfinished. Capabilities stay planned; no four-way, physical, installed,
live-provider or release qualification is inferred.

Static B21 follow-up `417f2c11d` corrects CLI OS27 history promises, bounded query/wake examples and
platform-specific failure guidance without changing runtime bytes or pending alpha.7 counterpart rows.
Three new public-doc regressions, existing CI static24/contract60 and seven local links pass; these are
not native authorization or installed capability evidence. All469 fifth-wave evidence hashes remain
intact. Latest observed5,412,520KiB/no warning still admits neither compiler nor native-app gates.
Broader runtime/native/website/localization/consumer-skill reconciliation and B22 acceptance remain open.
Root inventory follow-up `bba3106b9` corrects portable23/bundledMac21/publicalpha.7 19/read-only13/frozen21
accounting and universal pairing3 versus legacy1/2, with two new public-doc regressions/static26+contract60.
Native4 remains unwired/unadvertised, with no bound execution; remaining parity/website/skill claims
are not corrected by this static slice. That checkpoint observed5,255,100KiB, below compiler/native gates.

Static parity follow-up `95d890094` corrects the root Share My Setup row to existing planned/deferred
status and distinguishes Android provider-native raw NDJSON from iPhone JSON and bounded host-side
JSONL extraction. Exactly three complete root rows/two docs and two new public-doc methods; unchanged
website English/nine locale rows already agree and are checked read-only, not fully qualified.
Current source static CI28/contract60, exact scope/two links and preservation pass; all609 earlier
indexed entries rehash intact. The82-file static index `e5a1507bc3371a7867aa538389ceba4877095c838d81ebabe78723716d2c3c95`
binds that source, not native import/permission/parser/transport or installed/release evidence.
Observed2026-10-05T13:11:51Z2,874,296KiB/no recorded warning still admits neither compiler nor native-app
gates; no compile/admission/cleanup/bypass or native/user action. Broader native lifecycle/MCP/support/
website/skills reconciliation remains eligible for bounded static work; the actual journey, merged
compiler gates and Kotlin-after remain incomplete. B21 in progress/B22 open; no capability/task/goal promotion.

Native direct-doc follow-up `ef33aba48` clarifies Apple pinned-SDK history/full-corpus dates and Android
active user-started FGS/first unlock/first-grant history/app-level quota, without changing runtime bytes.
Both pages separate development23/read-only13/publicalpha.7 19/frozen21 from installed/exact-build support;
native4 remains unwired/unadvertised, bound execution/recipes/full journey absent, Android queries planned.
Three new public-doc methods/static CI31+contract60 and eight local links pass; all other page/test bytes
are preserved. The85-file source index `33937b3d22479e64260fb8eac7f6622652b56335c9065c067eb75d8b1a292ae8`
binds this static increment, all691 previous entries intact; it is not native lifecycle/permission evidence.
Observed2026-10-05T13:33:39Z3,881,092KiB/no warning remains below compiler/native-app admission; no new
compiler/admission/cleanup/bypass or native/user action. Wider native portability/support/consumer/website
mirrors remain separately reviewable. Merged/native/Kotlin-after/full journey gates remain incomplete;
B21 in progress, B22 open, no task/capability/goal promotion.

## Product outcome

After initial native permission and pairing setup, a user can ask an authorized agent to select data, plan an export, choose formats and computer paths, execute it, inspect the receipt, change future output settings, and recover interrupted work without routinely navigating mobile settings.

The agent owns a declarative recipe. The host validates and binds its destination. The phone owns native permissions, protected-data checks, capture, entitlements, supported rendering, and lifecycle. Phone settings are optional presets, not hidden authority for an explicit agent request.

“Parity” means equivalent observable outcomes where APIs permit them, not matching picker counts or putting Health Connect records into HealthKit-shaped archives. The governing [unification policy](cross-platform-unification-policy.md) and [capability inventory](../../packages/contracts/product-capabilities.json) retain their authority. Proposed backlog states below do not silently modify that inventory.

## Existing parity: do not rebuild it

Android already implements daily Markdown/Bases/JSON/CSV, multi-format runs, metrics, date/folder/filename templates, frontmatter and Markdown customization, write modes, daily-note injection, individual entries, workout detail, native profiles and independent schedules, Today Refresh, history/retry, API delivery, widgets, and clinician reports. These capabilities have native feature pages in the [Android index](../../apps/android/docs/features/index.md) and are paired in the [root feature table](../features/feature-parity.md).

The direct path already shares the universal in-app selector-3 QR/20-digit pairing outcome, LAN/Tailscale connectivity, native secure trust, a bounded wake wait, and seven-day durable raw/generated export, status, resume, and acknowledged cancellation through the CLI. Current source also routes full-public-authorized raw MCP jobs and bounded job-bound artifact reads to either source. Implementation is not proof of the published build or complete physical qualification.

The [April Android exporter gap matrix](../../apps/android/docs/export-contract/android-ios-gap-matrix.md) contains historical P0/P1 fixes and superseded API assumptions. Its later status sections and the [migration/signature policy](../../apps/android/docs/export-contract/migration-plan.md) record the implemented migration. Do not turn its old rename lists into new tasks or rewrite shipped Android v4/v5 bytes. The [generated metric ledger](../../apps/android/docs/export-contract/android-ios-metric-parity-ledger.md) and [platform boundaries](../../apps/android/docs/export-contract/platform-native-export-boundaries.md) supersede unsupported equivalence assumptions.

## Verified agent-path gaps

| Finding | iPhone / current portable behavior | Android / missing behavior | Evidence | Tasks |
|---|---|---|---|---|
| Typed queries and factual evidence | Direct query v3 supports bounded metric series, sleep, workouts, coverage, comparisons, alignment and evidence | No Android typed-query capability, transport or native evaluator path | [Client query source check](../../apps/cli/crates/healthmd-client/src/direct.rs), [iPhone coordinator](../../apps/apple/HealthMd/iOS/IPhoneDirectQueryCoordinator.swift), [v3 contract](../../packages/contracts/direct-protocol/v3/protocol.md) | B05–B07 |
| Source-neutral query discovery | Fixed registry and source schemas are predominantly Apple-oriented | Health Connect/provider source IDs and operation/metric availability need reviewed semantics; global backend flags do not establish Android query support | [Operation registry](../../apps/cli/crates/healthmd-operations/src/registry.rs), [backend capabilities/readiness](../../apps/cli/crates/healthmd-cli/src/mcp/direct_backend.rs) | B02, B05, B07 |
| Scoped daily extraction | CLI `extract` supplies selected canonical iPhone data with completeness receipts | CLI rejects Android; `android_daily_records_v1` is reserved, not advertised, its native branch errors, and client acceptance does not enable it | [CLI extraction](../../apps/cli/crates/healthmd-cli/src/main.rs), [Android coordinator](../../apps/android/app/src/main/java/com/healthmd/direct/DirectCliCoordinator.kt), [v2 product contract](../../packages/contracts/direct-protocol/v2/protocol.md) | B08 |
| MCP generated-file execution | MCP `start_export` calls the iPhone/v1 `export_files` path | CLI has a v2 Android generated-file branch, but MCP start does not use it; status/resume/cancel infrastructure is already source-aware | [MCP adapter](../../apps/cli/crates/healthmd-cli/src/mcp/direct_backend.rs), [CLI Android branch](../../apps/cli/crates/healthmd-cli/src/main.rs), [client](../../apps/cli/crates/healthmd-client/src/direct.rs) | B02 |
| MCP pairing and host setup | First-device MCP onboarding is iPhone-scoped | MCP QR uses a universal code but the task calls `pair_first_ios`, rejecting/forgetting an Android peer; documented Android onboarding falls back to a shell command | [Pairing coordinator](../../apps/cli/crates/healthmd-cli/src/pairing.rs), [client pairing](../../apps/cli/crates/healthmd-client/src/direct.rs), [host onboarding](../../apps/cli/crates/healthmd-cli/src/onboarding.rs) | B03 |
| Profile selection discovery | CLI and native sources support profile references; MCP normalization accepts them | Advertised MCP file schema omits `profile` policy and `profile_reference`, so an agent cannot discover accepted inputs reliably | [Normalization](../../apps/cli/crates/healthmd-operations/src/normalize.rs), [export schema](../../apps/cli/crates/healthmd-operations/src/registry.rs) | B04 |
| Request-owned capture scope for generated files | iPhone accepts selected metrics/categories/detail, while preserving phone output preferences | Android generated files accept only saved settings or profile; `requested_scope` is reserved and selectors are rejected | [CLI grammar/dispatch](../../apps/cli/crates/healthmd-cli/src/main.rs), [Android resolver](../../apps/android/app/src/main/java/com/healthmd/direct/DirectCliCoordinator.kt), [v2 policies](../../packages/contracts/direct-protocol/v2/protocol.md) | B01, B09 |
| Request-owned output settings | CLI chooses computer root; generated formats, subfolder/folder/filenames, presentation and write behavior still come from mobile settings/profile | Missing on both sources, not solely Android | [v1 request model](../../packages/healthmd-core-rust/crates/healthmd-protocol/src/models.rs), [iPhone resolver](../../apps/apple/HealthMd/iOS/IPhoneDirectFileExportProducer.swift), [Android settings](../../apps/android/app/src/main/java/com/healthmd/domain/model/ExportSettings.kt) | B01, B09 |
| Configuration-only export plan | Offline command guidance explains required inputs; content preview is a different workflow | No agent operation resolves effective settings, predicted paths and required actions without health reads, then binds approval to execution | [Operations catalog](../../apps/cli/crates/healthmd-operations/src/registry.rs), [CLI command guidance](../../apps/cli/docs/command-guidance.md) | B01, B10 |
| Persistent agent configuration | Native profiles exist on both phones; CLI can refer to their IDs | No fixed CLI/MCP local recipe CRUD or mobile profile list/get/create/update/activate/delete surface | [CLI command enum](../../apps/cli/crates/healthmd-cli/src/main.rs), [operation definitions](../../apps/cli/crates/healthmd-operations/src/registry.rs), [native profile docs](../../apps/website/docs-src/src/content/docs/export-profiles.md) | B11, B12 |
| Agent-managed recurring work and destinations | Native schedules and API/folder targets exist; an external agent with shell authority can independently schedule a CLI command | No Health.md typed host scheduler or permissioned mobile schedule/destination control surface; native bindings cannot be created merely by supplying a path | [Operation definitions](../../apps/cli/crates/healthmd-operations/src/registry.rs), [CLI command enum](../../apps/cli/crates/healthmd-cli/src/main.rs), [Shared Setup destination rules](../../packages/contracts/shared-setup/v2/contract.md) | B13, B14 |
| Push wake when inactive | Enrolled iPhone APNs nudge is implemented; failures degrade to the shared wait | Android FCM is planned P3; current Worker delivery is APNs-only; F-Droid and force-stop need explicit limitations | [RFC-0005](rfc-0005-direct-cli-agent-wake.md), [wake sender](../../apps/wake/src/wake.ts), capability `direct.cli_agent_push_wake` | B15 |

### Lifecycle correction

Earlier discussion generalized the iPhone's foreground requirement too broadly. **Android can accept work in an already-active, user-started `DirectCliForegroundService`, including supported locked-screen sessions.** The Activity need not remain visibly foreground for every request. An absent service/process and before-first-unlock protection are different failure cases. See [RFC-0005 Android runtime analysis](rfc-0005-direct-cli-agent-wake.md) and [v2 lifecycle rules](../../packages/contracts/direct-protocol/v2/protocol.md).

On iPhone, new direct work requires the foreground app and available protected data. An already-active durable export has finite continuation and can pause. A notification only restores presence; it cannot unlock a phone, grant health permissions, or promise unattended HealthKit capture.

## Adjacent Android product gaps

| Finding | Classification of the actual gap | Evidence | Task |
|---|---|---|---|
| Scheduled API recovery lacks complete pre-capture original credential authority | Implementation/security gap: Apple available, Android planned. Endpoint freezing and prepared compatibility journals already exist; pre-journal/raw pending credential evidence remains missing | Capability `automation.api-recovery-authority`; [pending settings](../../apps/android/app/src/main/java/com/healthmd/domain/model/ExportSettings.kt), [API runner](../../apps/android/app/src/main/java/com/healthmd/data/export/APIEndpointExportRunner.kt) | B16, P0 |
| ZIP output | Android implementation gap, not an evidenced OS/API prohibition. Apple-only labeling currently reflects absence of a ZIP writer | [Feature parity](../features/feature-parity.md), [Android output settings](../../apps/android/app/src/main/java/com/healthmd/domain/model/ExportSettings.kt) | B17 |
| Generated data-dictionary companion | Android has mapping ledgers/shared registry, not the Apple-style optional generated companion. Define native/profile-correct metadata; do not copy HealthKit identifiers | [Feature inventory](../features/feature-inventory.md), [Apple dictionary](../../apps/apple/docs/features/data-dictionary.md), [Android feature index](../../apps/android/docs/features/index.md) | B18 |
| Requested-range summaries | Deliberately staged contract/profile gap. Existing capability target requires the first approved Android unified-v9 writer; historical v4/v5 cannot be extended | Capability `export.range-summary`; [rollup contract](../../packages/contracts/rollup-summary/v9/contract.md), [RFC-0004](rfc-0004-unified-health-data-v9.md) | B19, approval-gated |
| Typed WHOOP daily projection | Current Android-profile limitation, not proof that WHOOP cannot be read on Android. Play already retains native provider snapshots; a new reviewed profile/extension and consumer support are required | Capability `apple.typed-whoop-provider-section`; [provider sections](../../packages/contracts/proposals/provider-sections-v1/contract.md), [Android provider support](../../apps/android/docs/health-provider-support.md) | B20, approval-gated |

## Differences that must not become fake parity work

- HealthKit SDNN and Health Connect/WHOOP RMSSD retain distinct IDs/statistics. Historical key compatibility does not prove semantic equivalence.
- HealthKit source archives, medication dose events, State of Mind, hearing/symptom types, Apple activity/ring metrics and many running/mobility signals have no reviewed Health Connect equivalent. Omit/report unavailable; never fabricate zero or empty records.
- Apple wrist temperature and Health Connect skin temperature, Apple clinical data and Android PHR, menstrual flow and period intervals, and planned workout models are separate products/identities.
- Android exposes native intensity, meal/context, planned-session, PHR and provider-native records beyond Apple projections. Preserve them instead of deleting them to match Apple.
- Native permissions, folder grants, credentials, purchases and trust remain native authority. Agent configuration does not grant permissions or bypass Configuration Protection.
- Play/F-Droid provider and future wake capabilities differ intentionally. FCM absence and force-stop behavior require explicit degradation, not background-service workarounds.
- Mac loopback agent API/encrypted context, Apple Shortcuts, watchOS surfaces and Live Activity are not required dependencies of the portable agent bridge. Android has its own native automation/progress mechanisms. Wear OS and accessibility follow-ups remain separately tracked below.

These boundaries are maintained in the [capability inventory](../../packages/contracts/product-capabilities.json), [native boundary document](../../apps/android/docs/export-contract/platform-native-export-boundaries.md), and shared metric registry. Runtime SDK changes still require a fresh official-API review when implementing a task; this audit did not retrieve live vendor documentation.

## Backlog index

All implementation tasks are initially unassigned. B19 and B20 are explicitly blocked on profile/consumer approval; the other 20 are open, with execution dependencies listed below. Claim a task before work. Each todo contains scope, acceptance criteria, evidence and component test requirements. B-codes below are stable dependency labels resolving to the exact todo IDs in this table.

| Code | Priority | Todo | Deliverable | Dependencies / gates |
|---|---|---|---|---|
| B01 | P1 | `TODO-4cc35ad8` | Agent-owned export/configuration contracts and authority | None; specification before new wire behavior |
| B02 | P1 | `TODO-bb597b7e` | Android MCP generated-file dispatch and source capabilities | Existing v1/v2; no new wire prerequisite |
| B03 | P1 | `TODO-b350a7e6` | Android MCP pairing and host onboarding | Existing selector 3; coordinate existing pairing task |
| B04 | P1 | `TODO-141cfae7` | Advertised MCP profile policy matches normalization | Existing native profile support; B12 adds management later |
| B05 | P1 | `TODO-11a3bceb` | Android typed-query/evidence semantic and transport specification | None; coordinate B01 terminology/authority |
| B06 | P1 | `TODO-16f206de` | Android bounded native typed capture/evaluator | B05 |
| B07 | P1 | `TODO-c9fc8d1b` | Android CLI/MCP query/catalog/chart integration | B05, B06; align B02 capabilities |
| B08 | P1 | `TODO-f805316c` | Scoped Android source-shaped daily extraction | B01, B05; can run beside B06 |
| B09 | P1 | `TODO-30b3a9a0` | Request-owned generated-file settings on both sources | B01, B02; B04 for optional profile mode |
| B10 | P1 | `TODO-62c44c21` | Configuration-only plan and bound approval/execution | B01, B09; saved-mode increment may come earlier |
| B11 | P1 | `TODO-50b47d38` | Host recipe CRUD and run | B01, B09, B10 |
| B12 | P2 | `TODO-775852d0` | Permissioned native profile inspection/CRUD | B01, B04, B10 |
| B13 | P2 | `TODO-1f9994a7` | Host recipe scheduler and recovery | B11; B15 is optional nudge improvement |
| B14 | P2 | `TODO-3ff01744` | Native schedule and destination configuration | B01, B12; B16 before broader Android API recovery |
| B15 | P1 | `TODO-2fb08674` | Android Play FCM wake and explicit channel degradation | RFC-0005 security/runtime review; separate deployment authorization |
| B16 | P0 | `TODO-977e2632` | Android API recovery authority pin before capture | None; independent security slice |
| B17 | P2 | `TODO-7dbe03eb` | Android bounded ZIP packaging | Native work independent; B01/B09 for agent controls |
| B18 | P2 | `TODO-8e77baaf` | Android profile-aware dictionaries/catalog companions | B01/B09 for companions; B05 for query semantics |
| B19 | P2 | `TODO-0a295500` | Android requested-range summaries | Explicit unified-v9 reader/writer approval and consumer readiness |
| B20 | P2 | `TODO-69bfeffc` | Review/new-profile Android typed WHOOP output | New profile/extension approval and provider qualification |
| B21 | P1 | `TODO-a16aa320` | Reconcile capabilities, parity/support docs and schemas | Baseline now; incremental updates with each task; promote claims only after B22 |
| B22 | P1 | `TODO-f517ae13` | Retained cross-platform agent-bridge qualification | Qualify increments; core no-settings journey B09–B11; query claims B06/B07 |

### Suggested execution order

1. **Independent security and quick parity repairs:** B16 first; B02, B03 and B04 are small existing-protocol workstreams. B01 and B05 specifications can proceed independently. B21 can correct baseline documentation without advertising unimplemented features.
2. **No-settings desktop export:** B01 → B09 → B10 → B11, with B02 ensuring Android MCP actually uses v2. This solves the year-folder/daily-JSON user workflow on both sources without new mobile-profile mutation authority.
3. **Android typed data parity:** B05 → B06 → B07, plus B08. These are larger source/semantic workstreams, not a `SourceKind` conditional alone and not dependent on daily-v9 writer promotion.
4. **Convenience and advanced management:** B15, then B12–B14 where explicitly desired. ZIP/dictionaries B17/B18 are optional native-output parity, not prerequisites for ordinary daily JSON.
5. **Contract-gated future projections:** B19/B20 remain gated on explicit version/reader approval. Creating todos does not authorize enabling those writers.
6. **Qualification:** B22 runs per increment; B21 records exact tested availability. Do not make a single stable-release claim from basic connectivity.

## Existing work and non-duplication

The todo store contains older items whose open/blocked labels are not sufficient evidence that implementation is absent. This audit did not take ownership of or close them.

- `TODO-7d18fe24`: universal QR pairing work. Selector 3 is implemented; B03 addresses the separate MCP/host onboarding restriction.
- `TODO-1f168557`, `TODO-516c34b3`: prior wake production/deployment work. P2 is present/deployed; B15 is specifically Android P3 and does not recreate P2.
- `TODO-c93818fd`, `TODO-0ced5546`: Shared Setup implementation/validation. Current v2 transaction code exists, but its [contract](../../packages/contracts/shared-setup/v2/contract.md) and [QA record](../qa/shared-setup-v2.md) remain deferred/qualification-gated. B12 must not route remote authorization through import files.
- `TODO-e9043ac1`: existing range-summary review/repair. B19 tracks the distinct Android adoption gate.
- `TODO-81d22d48`: Wear OS phases audit (blocked); [completion audit](../../apps/android/docs/features/wear-os-completion-audit.md) governs the unreleased companion. Not cloned into an agent-bridge task.
- `TODO-2ecae73e`, `TODO-b1209c11`: Android/Apple accessibility work. Preserve their separate ownership and native QA gates.
- `TODO-8bd2a4bf`: CLI distribution hardening. B22 coordinates qualification; it does not overwrite this release/distribution work.

## Contract and release boundaries

- [Apple v8](../../apps/apple/docs/features/export-schema.md), [Android frozen v4/analytical v5](../../apps/android/docs/export-contract/migration-plan.md), raw snapshots, typed views, setup files and direct protocols version independently. Do not update a fixture just to make tests green.
- Both Android and Apple implementations are required for semantically shared controls. Register unavoidable/staged differences with evidence and concrete targets; unsupported data never becomes an approximation.
- Preserve desktop native destination/credential hardening and the Android opaque binding. Never retarget a durable job during resume or expose arbitrary shell/SQL/URL/file authority through MCP.
- Preserve local-read-only and remote-read-only profiles. Export/configuration/scheduling actions require separately scoped approval; adding controls must not silently widen those profiles.
- A full phone-owned configuration API is a later layer. Host recipes achieve desktop agent control without mutating the user's unrelated phone API-export setup.
- Public alpha.7 has 19 MCP tools; pre-fourth-wave source has21, current operation declarations23 including plan/exact-approval relay. The canonically regenerated packaged catalog is23 and passes unfiltered combined-source CLI verification; native setup/routes and bound execution remain incomplete. The [production readiness decision](../../apps/cli/docs/production-readiness.md) and [mobile ledger](../../apps/cli/docs/mobile-compatibility.md) say the public standalone release is unqualified. New Android queries/FCM/control APIs are not silently added to the frozen CLI 1.0 scope; an explicit scope/release decision is required.
- Wake Worker changes stay notification-only under [its component instructions](../../apps/wake/AGENTS.md). This plan authorizes no secrets, infrastructure deployment, live health reads or product releases. Cloud/Practice remain outside this backlog.

## Verification and completion criteria

For implementation, run each affected independently locked Rust workspace, contract validators and Swift/Kotlin conformance vectors; native Apple/Android focused tests and builds; CLI/MCP schema/generated-asset and fake-peer tests; website/localization consumers; and pinned external Obsidian tests whenever public output changes. Include Play/F-Droid and the Pixel 7 target. Never log real health values, owner dates, private paths, identities, tokens or QR secrets in qualification records.

Retain physical LAN/Tailscale evidence across exact mobile builds and macOS ARM/Intel, Linux ARM/x64 and Windows. Exercise credential denial/headless Secret Service, missing permissions/history, source limits, before-first-unlock and foreground-service differences, wake degradation, concurrent agents, cancellation, immutable resume and safe idempotent commits. Missing environments remain `not run`, not assumed passes.

The core acceptance journey is:

> After explicit native permission/pairing setup, the user asks an agent to export selected data as daily JSON into year folders. The agent plans, obtains approval, executes, verifies, saves a recipe and later changes future scope/layout/destination without opening mobile settings. Interrupted work resumes against its original scope and destination; unrelated phone API settings are unchanged.

This audit performed source/document review and backlog creation only. A local consistency check passed: all 63 documentation/source links resolve, all 22 workstream codes and todo IDs are unique, and all referenced new todo files exist. No application build, automated product test suite, physical-device run, live health-data access, wake notification or release qualification was performed.

## Implementation increments (qualification still incomplete)

The [implementation ledger](../qa/agent-bridge-implementation.md) records subsequent serial integrations, exact source/test evidence and retained failures. Existing-protocol CLI/MCP dispatch/onboarding, Android recovery authority and mocked Worker FCM increments are integrated. The second wave adds bounded pure Rust/Swift/Kotlin v4 codecs and one independently constructed common intent with matching bytes; committed source through `e61ef90ce` passes the affected core/CLI/package/JVM and Play/F-Droid source gates. Published-crate test isolation is repaired separately in `4a987f11f`.

The third wave through `770c74319` adds bounded both-platform request-settings/renderer resolution, authoritative Apple profile-ID lookup, Android exact-owned discard/reconciliation and strict private revocation parsing. Scoped Apple repairs preserve wire bytes and fail closed on unsupported history-boundary SDKs. Combined Play/F-Droid unit/lint/build/binding gates and generic iOS application/test-target build-for-testing now pass; app-host tests, full export-doc generation and installed/physical qualification are not run.

The fourth wave through `4df7cc180` adds real bounded native/host issuer-private stores, independent local decisions, actual request-settings-backed source planning services and shared CLI/MCP plan/approval adapters. Lane tests exercise actual stores/services and encrypted synthetic peers; they do not connect the production Swift/Kotlin counterparts. At that handoff the full Rust workspace was red on stale packaged catalog and first coordinator regeneration refused below6GiB. Those retained historical failures are superseded only by the admitted catalog follow-up below; native routes/execution were not completed.

These are **partial implementations**, not the four-way no-settings journey. Installed v4 advertising/native setup/routes, request-owned capture/journals, bound execution and recipes remain pending. Fourth-wave three-pointer Kotlin discovery and delayed consent/private-key/publication gaps were reproduced and receive bounded fifth-wave source fixes below; missing after-candidate and merged/native gates remain explicit. HMAC does not prevent valid historical-snapshot rollback, native fresh-open root protection is unqualified, Windows new issuer storage deliberately rejects, and host setup is currently single-root. Coverage is deliberately unequal across languages; canonical agreement and configuration equality do not prove runtime authorization. B21 follow-ups `aac010955`/`5a03fa7ea` correct unsupported native history-readiness and OS-only guidance while retaining legacy wire keys/types. Those committed macOS/iOS test-target build-for-testing gates pass; the actual-source metadata probe has retained red/green evidence, not app/service-host execution or fifth-wave app compilation.

After fresh disk admission returned, the coordinator regenerated the canonical MCP catalog (23 tools; all21 previous entries preserved) and ran unfiltered combined CLI tests:246 passed/two preexisting ignored/zero filtered. CLI fmt/clippy/runtime1.85 compilation and canonical asset freshness each pass; earlier red/filtered results remain historical evidence. Read-only stays13, alpha.7 stays19, and frozen CLI1.0 stays21; the bridge additions are not release-scope promotion. Actual counterpart/expiry follow-ups, combined native gates and the full journey remain pending.

The fifth wave serially integrates host `e03f49443`, Swift `9fe74f142` and Kotlin `4f9a9ec33` through `cccbb13de`. All lanes stopped/committed/clean before coordinator edits. Sixteen disjoint paths match lane bytes; all other tracked source/frozen contracts/dependencies/assets are preserved. Trusted live clocks/latest locked authority follow native consent/key/configuration/session callbacks and precede atomic metadata publication and return. Actual staged-file tests distinguish unchanged-byte prepublication rejection from retained stale metadata after postpublication rejection; no global atomicity, anti-rollback or native authority provisioning is claimed.

Final lane-source evidence: host unfiltered256 passed/3ignored/0filtered plus fmt/clippy/runtime1.85 compilation/assets0; Swift74 package and54 unique actual-source cases repeated in ordinary/MainActor modes; Kotlin62 unique focused methods per flavor (one normally no-op generation method),38 protocol pass/one live skip and binding equality0. Actual native complete Swift discovery passes the strict host31-leaf check and negative tamper checks. Kotlin-before is a retained actual3-pointer red; Kotlin-after is **not produced/not run**, not inferred from focused31-leaf tests. Native candidates are capability interoperability only, not permission or live transport.

After every merge static validator0/full60 contract tests0, exact union/provenance/diff audit0;420 retained lane-evidence hashes match. The469-file point-in-time index `fd74e0b1230f27e8caa239025e37c66496be4178eeec6588f523d106c773aa0b` binds this source increment and retained attempts. **No fifth-wave merged compiler gate ran:** observed4,721,440KiB free/no warning is below6,291,456KiB; native app/app-module gates additionally require10,485,760KiB. No cleanup/bypass/retry loop or cache reuse relabeled as new qualification. Resume missing gates only with fresh admission; actual Kotlin-after generation must be a separate gated invocation before ungated full variants and the exact host tracer.

Native setup/routes/send fences, bound execution/transfers/receipts/recipes/resume, the pinned-consumer failure, broad support/website/consumer reconciliation, physical/live/OS qualification and B19/B20 approval gates remain explicit. B10/B21 stay in progress and B22 open. No task is closed or planned capability promoted; goal remains incomplete and further compile-dependent work is stopped pending headroom.
