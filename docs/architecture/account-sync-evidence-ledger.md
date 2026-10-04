# Account-sync implementation and evidence ledger

## Status

**Active source implementation; not feature-complete, approved for real data, deployed, or enabled.** Epic AS00 / TODO-d8011329 remains in progress. This ledger distinguishes local source review from named owner/product/security/privacy/operations/mobile approval and actual physical evidence. A blocked acceptance or rollout gate is not completion.

Integration branch: `goal/account-sync/orchestrator` in the dedicated clean `/Users/codybontecou/dev/health-md-account-sync` worktree. Baseline: `e9a1d8757b679ea49820893537873ef3002604fe`. The original dirty checkout and unrelated fleets are not integration sources. No push, PR, deployment, live flag/signup, credential/resource provisioning, service restart, personal-health access, physical-device action or worktree/tab cleanup is authorized.

## Deliverables and completion standard

1. Optional separately scoped account sign-in on iOS/iPadOS/macOS and Android Play/F-Droid; native sessions never inherit browser health-read/upload/MCP authority.
2. Independently versioned portable profile synchronization, private revisioned storage, immutable revisions, deterministic offline/conflict behavior and explicit native/dashboard management.
3. Local binding/protection/activation gates: new profiles remain unbound; fetched revisions never overwrite accepted execution snapshots or frozen jobs.
4. Only after its product/authority prerequisites, foreground export requests pinned to immutable revisions, using existing exporters and separately authenticated upload with bounded verified receipts.
5. Task-by-task direct evidence, affected-component/consumer checks, authorization/environment/lifecycle/privacy preservation audit and retained integration/branch/worktree/tab/report map.

Passing a model test, fixture hash, manifest, build or simulator flow does not satisfy untested real parser/storage/authority/native/device behavior. Each requirement must map to actual artifacts and evidence; unverified requirements remain incomplete.

## Wave 1: source review and integration

- AS01 lane: commit `6d88534f96ec7f6e142168c86b0f095cc384b436`, integrated by merge `d5b152317cda1a174fb5578064a41b24066e7f22`.
- Seven new source-review artifacts only: [design](account-profile-sync-source-design.md) and [account-auth v1](../../packages/contracts/account-auth/v1/contract.md), policy, field inventory, capability proposals, synthetic security vectors and design tests. Existing runtime/contract bytes were untouched.
- Read-only portable audit completed independently at the baseline; no source commit or unrelated TODO mutation. Its full report identifies actual reusable validators, foreign-extension corruption hazards, import-only versus revision-bound execution gates, and still-unrun physical qualification.
- Coordinator read both full reports and the seven source files, verified committed/clean trees and disjoint ownership, and accepted only the reversible source interface choices below. **This is not the owner approval required by AS01.**

### Source-qualified interfaces for the next bounded slices

The locally reviewed account-auth v1 route/scope/token separation, strict S256/callback/issuer/environment binding, transactional issuance/rotation/revocation postconditions, independent profile-sync namespace and portable field inventory may be used for synthetic-first AS02/AS05 development. All actual registration, live adapter, configuration privacy and activation gates remain closed.

- Preserve existing password/email browser login. Native auth is an optional adjunct, not an identity-provider replacement or account-linking/recovery decision.
- Real environment registrations remain null. Synthetic reserved-domain callback shapes are fixtures, not universal/app-link registration or physical interoperability.
- Native scopes are only configuration read/write and own-session inventory/revoke. No request/device, ingest, retained-health, MCP, OS permission, purchase or activation authority.
- Sign-in transfers zero profiles; sync is separately selected and consented. Stable account IDs/revisions are new metadata, not bundle `profile-NNN`, native IDs or names.
- Fetched portable content is distinct from accepted local execution snapshots. New adoption is blocked before visibility; execution-sensitive changes require protected local review. Existing frozen jobs never reload latest remote content.
- A failed foreign-extension/sidecar read quarantines publication; an empty-on-read-failure map cannot authorize deleting foreign content.
- Real configuration privacy/key/retention/deletion/portability/region/operations policy remains unselected. A version marker, source flag, test or proposed ADR is not approval.
- AS18 remains undecided. Existing primary-only dashboard charts/aggregate MCP, exact envelopes and daily pointers are unchanged.

### Direct verification so far

Baseline coordinator checks, performed with Node 24 for Cloud:

| Check | Actual result | Coverage limit |
|---|---|---|
| `python3 packages/contracts/validate.py` | 16 contracts, 33 fixtures, 13 mirrors, 2 inventories, 3 output profiles, 40 capabilities; exit 0 | Existing governance/fixture consistency, not new account runtime |
| Shared Setup Python regression suite | 20 tests, exit 0 | Existing v2 host validation, not physical/native sync |
| Cloud `npm ci` / `npm run check` | locked install; both typechecks and 234 tests in 35 files pass | Existing synthetic Cloud baseline |
| Cloud `npm run dry-run` / dependency audit | packaging pass; zero moderate-or-higher vulnerabilities | No deployment/security approval |
| Cloud `npm run test:smoke` | isolated local synthetic account/ingest/round-trip/portability/isolation/revocation pass | Existing D1/R2 behavior only, no real accounts/health |
| AS01 `test_source_contract.py` | 11 tests, 116 scenarios, source allow/deny partitions and 329 pinned field rows | Symbolic/design predicates, not TS/Swift/Kotlin runtime/crypto/DB proof |
| AS01 frozen/unrelated diff audit | zero changes under existing app/runtime, Shared Setup, daily/API/direct, core and CI paths | Source preservation at this integration point |

Full logs and source reports are outside tracked source in the scratch root below. Subsequent waves must re-run shared authority/contract gates and inspect actual integration diffs.

## Task-by-task state (20 children)

This is an interim ledger, not a completion claim. TODO bodies are the detailed acceptance contracts. “Source-qualified dependency” permits only the specified disabled synthetic work; it does not close an approval-dependent task.

| Task / TODO | Actual source/evidence | Unmet acceptance / next gate |
|---|---|---|
| AS01 / TODO-9825212d | Partial: committed design/threat model/authority and field inventories/116 source vectors; locally reviewed interfaces | Named issuer/login/callback/linking/recovery/session/security choices; config privacy/key/retention/operations policy; mobile/physical/accessibility and pilot/cohort approval. TODO blocked, not complete. |
| AS02 / TODO-fd8dae80 | Next source-qualified slice: unavailable-by-default native configuration authorization/session module | Actual parser/crypto/transaction/fault/lifecycle and service isolation evidence; real browser/native adapters and registration remain unqualified |
| AS03 / TODO-02f3b1d0 | Not implemented | AS02 source interfaces; Apple Keychain/browser/callback/settings/lifecycle tests, supported iPad/macOS, UI/accessibility/physical evidence; real registration |
| AS04 / TODO-03effd7c | Not implemented | AS02; common Play/F-Droid browser/Keystore/intent/recreation tests, UI/accessibility and physical Pixel qualification; real registration |
| AS05 / TODO-541c5b8a | Next source-qualified slice: independent profile-sync v1 grammar/codecs/fixtures | Actual cross-language full content conformance, revisions/idempotency/tombstones/resync/conflicts/future/foreign/negative cases; review and integration registration |
| AS06 / TODO-f540313f | Not implemented | AS02/AS05 source interfaces; private purpose-encrypted durable revision/idempotency/tombstone/quota/lifecycle routes and ambiguous-commit tests; real config policy remains blocked |
| AS07 / TODO-cbfd8aa1 | Not implemented | AS05; deterministic TS/Swift/Kotlin offline/conflict/outbox/transaction/fencing/frozen-job scenarios |
| AS08 / TODO-e0f7ecbe | Not implemented | AS03/AS06/AS07 and coordinated AS10; Apple transactional mapping/sidecar/outbox/profile-management integration and actual UX/qualification |
| AS09 / TODO-370f24fa | Not implemented | AS04/AS06/AS07 and coordinated AS10; Android common-channel DataStore/mapping/outbox/UI integration and actual qualification |
| AS10 / TODO-3dedf371 | Existing import-only v2 gates inspected; no new sync revision gate | AS05/AS07; both-platform exact local binding/review/protection/manual/schedule/automation/direct admission and frozen-job tests/flows |
| AS11 / TODO-c441b03a | Not implemented; original shell snapshots are read-only context, not adopted source | AS02/AS05/AS06; bounded isolated profile/session CRUD/conflict/library UX; coordinate before overlapping original shell files |
| AS12 / TODO-795e178b | Baseline checks only, no account-sync qualification | AS03/04/08/09/10/11; full consumer/privacy/env/lifecycle tests, UI recordings, actual device/accessibility, documentation and separately gated rollout |
| AS18 / TODO-71b71ae4 | Explicitly undecided; primary precedence preserved | Owner must select additional retained evidence vs independently versioned provenance-labelled gap-fill, including consumer scope. Recommendation/test/draft is not consent. |
| AS13 / TODO-075d2c89 | Not finalized or implemented | AS01/AS05 and AS18 owner decision; independent immutable-profile request/confirmation/upload/typed-receipt contract and cross-language state/negative fixtures |
| AS14 / TODO-2db4e768 | Existing review-only repair/supplement substrate remains unchanged/non-launchable | AS02/AS06/AS13; separately bound confirmed request+write authority, durable nonreplacement race-safe storage/verified receipts and failure tests |
| AS15 / TODO-cbde636f | Not implemented; ordinary Apple exporter/client semantics unchanged | AS03/AS08/AS10/AS13/AS14, AS12 enablement; foreground review/existing exporter/no-redirect typed-receipt transport/restart/UI/physical tests |
| AS16 / TODO-97c8f97e | Not implemented; ordinary Android compatibility/raw semantics unchanged | AS04/AS09/AS10/AS13/AS14, AS12 enablement; equivalent common-channel review/export/receipt/recreation/UI/physical tests |
| AS20 / TODO-fd625ce1 | Not selected or implemented | AS18 explicit decision and AS14 verified retained outcomes; provenance UI/projection/zero/conflict/retention/consumer tests |
| AS17 / TODO-aa42a7cc | Existing draft-only planner remains unchanged | AS11/AS13/AS14/AS15/AS16/AS20; target/profile/date request UX/static links/verified status, source-version/lifecycle/DOM/browser/accessibility tests; live gates |
| AS19 / TODO-8a71976d | No physical request-to-receipt evidence | AS12/AS14/AS15/AS16/AS17/AS18/AS20; actual consented device-to-receiver safety matrix, privacy/consumer audit, truthful approved enablement gates |

## Preservation / affected-consumer audit

AS01 adds only a separate source-review surface; it changes no public daily/API/direct/Shared Setup bytes or native runtime. The Cloud/native/dashboard account consumers are the planned next implementation boundaries. Shared Rust/core, CLI/local MCP, website account proxy, external Obsidian and provider brokers receive no new account authority or changed export bytes. They are not implicitly rewritten or qualified by tests in another component.

Cross-platform local state to preserve at every later mutation: offline/local-only profiles, separately generated native IDs, active selection, concrete folder/Mac/API grants/bindings/credentials, OS health/background permissions, schedule activation/timezone/progress, runtime/pending jobs/history/engine pins, purchases, foreign unsupported portable meaning and existing accepted snapshots. Account switch/sign-out/revocation must fence old mappings/outbox/callbacks without republishing under another account.

Actual current impact and call-site tests must be added as boundaries change; this baseline matrix is not a waiver of native/API/automation/direct/external consumer checks.

## Fleet / evidence map

Scratch root: `/var/folders/vh/t562rzcx5dx1w0j01ky690rm0000gn/T/healthmd-account-sync.O0LAHV`.

| Agent / wave | Branch | Tab / pane | Checkout / report |
|---|---|---|---|
| account-sync-orch | goal/account-sync/orchestrator | w3R:t1 / w3R:p1 | `/Users/codybontecou/dev/health-md-account-sync`; scratch `fleet-state.md`, `acceptance-checklist.md`, `evidence/` |
| account-as01 / 1 | goal/account-sync/as01 | w3R:t2 / w3R:p2 | scratch `worktrees/as01`; `reports/as01.md`; committed clean standby |
| account-portable-audit / 1 | goal/account-sync/portable-audit | w3R:t3 / w3R:p3 | scratch `worktrees/portable-audit`; `reports/portable-audit.md`; unchanged clean baseline standby |

All `.pi/todos` paths are ignored symlinks to the same shared store. Exact provider/model/reasoning is `openai-codex` / `gpt-6.1-sol` / `max`. Tabs were created with `--no-focus`; other spaces and user focus were untouched. Full reports and trees are reviewed before serial integration. No tracked integration edits occur during active lanes.

Resource admission: initially two active lane agents (orchestrator excluded), never over three, one fleet-heavy command at a time, minimum 15 GiB free; no cache/artifact/tree duplication or unauthorized cleanup. Startup 30 GiB free, after wave 1 about 24 GiB with unrelated fleets active. Future heavy commands use the scratch fleet-local admission runner and actual disk/load rechecks.
