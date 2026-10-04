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

## Wave 2: settled source slices and qualification frontier

- AS02 `f5d2ff52a549e5ce241874e3902fdcb05faf2f43` is integrated by `4f34aa6d6f5aa05068a595905b719cd72ee5cb18`. Eleven owned files: six isolated auth modules, source documentation/tests and three narrow default-unavailable hooks. No live identity/browser/durable adapter, migration, resource, config, native or public export change. Lane checks and independent coordinator integrated-tree checks pass both Cloud typechecks and **397 tests / 36 files**, zero dependency vulnerabilities and dry-run packaging. Metadata alignment also passes **12** AS01 design tests / 116 scenarios, the existing contract validator and 20 Shared Setup regressions. These are local source/synthetic results, not live/native/durable approval.
- Coordinator reviewed actual parser, WebCrypto, transaction/postcondition, SQLite fault, lifecycle and credential-isolation code/tests. SQLite tests prove that synthetic seam, not D1/VM/multi-region durability. The synthetic authorization GET requires explicit Origin+Cookie and returns JSON; it is not working system-browser consent. Existing pilot flags cannot enable native issuance.
- Stable server-owned `(issuer, environment, account_id)` and the additional client/installation/server-generation metadata received local source-interface review and are now aligned in the proposed AS01 contract/policy. These fields do not grant sync opt-in or qualify native wire/secure-storage/lifecycle adapters.
- Original AS05 `ae7d3ec9cc4ef9a575346ac8ad25a300e42ef5ed` had 40 new files and coordinator Swift/TS 10-fixture/152-case/30-test-only-scenario passes. The original Kotlin command failed before compilation due to omitted cached Trove, and original native reads returned mode only. A real NEL/BOM edge-name differential remained despite the passing corpus. These historical limitations/failures are retained, not treated as current successes.
- Repair `1b5d4c769094563bf98d3619a728eeb32107602c` adds immutable typed reads, bounded closed non-success errors, explicit finite byte-preserving name rejection and the cached compiler dependency/physical Swift module-cache path. Integrated by `6d8e0f17007dd12aeaa12d8610791fe6bb93db60`. Coordinator independently reran the actual combined Python/TS/Swift/Kotlin codecs: **10 content fixtures / 257 parser cases / 30 test-only scenarios / 6 field-asserted reads / 11 fixed errors**, all exit 0. Original pinned artifacts/positive bytes and all 152 prior parser rows are preserved. Kotlin registry injection is not the real core/Android adapter; no full native/OS/device build or execution proof resulted.
- Combined Cloud strict typecheck first failed on optional indexed `formats`. The helper now accepts that possible undefined input and rejects it via its existing array check, rather than asserting existence or weakening compiler settings; a missing/mistyped-format regression was added. Both actual Cloud typechecks and **400 tests / 37 files** pass after the fix, along with dependency audit and combined/split dry-run packaging. Earlier runtime-only TS success did not qualify tsc. Failure and corrected receipts remain retained.
- Central metadata review fixes server `session_generation` to nonnegative safe, initially **0**, independent from local account-switch generation. Current initial/refresh scope behavior is exact captured/unchanged, not implemented reduced-grant negotiation. Thirteen AS01 integrity/design tests now include a synthetic **73 response / 15 error / 3 PKCE** native-client corpus; actual native consumers/lifecycle and OS custody are still unqualified.
- Manifest records are centrally registered as **deferred**, three account capabilities as **planned** on both platforms, and Cloud CI now watches/runs the source contract checks. Registration/hashes are not canonicalization or approval. The read-only native audit recommends root-free parser/lifecycle slices next, not simulated live sign-in UI: actual browser consent, callbacks, secure storage and foreground attribution remain gated.
- Disk previously refused heavy work below 15 GiB (guard exit 75), then recovered without coordinator cleanup. The unchanged guard remains mandatory. Both follow-ups settled and released assignments before integration/central edits; no frozen source or compiler setting was changed to silence failures.

## Wave 3: native source held unqualified, not integrated

Both root-free native lanes settled in clean committed standby, with their assigned TODOs **partial/blocked and released without force**. The coordinator read both complete reports and reviewed the committed scope/receipts; no native source was merged. Integration remains at `1aa4d363a44178b405bba51dbf2462ba6daad834` before this documentation-only frontier update.

- **AS03:** isolated `1b8500facf49599e9f92b372cdc6adf62e3a2320`, eighteen new files / 2,436 lines. Foundation/CryptoKit parser/PKCE/callback/actor/fake-vault/transport source and tests only; no app factory, UI, browser, Keychain, URLSession, OS registration or root hook. Historical strict Swift 6 WIP execution passed the 73 response / 15 error / 3 PKCE / 32 callback corpus and 22 lifecycle seams, but its complete runner **exited 1** on the subsequent target-like MainActor compilation. Explicit protocol-isolation fixes and the temporal patch followed. The final commit, target-like repair, XCTest imports and 46 new temporal scenarios are **uncompiled/unexecuted**, not qualified by the earlier pass. All initial failures and outputs remain.
- **AS04:** isolated chain `379567bcbe509cc28689d92f062c54d461103e34` → `91d1dc17f217f18cf848185a832fb9d2c34bd61f` → `ecf4a2156f68e63b12374ec16a8f25d0538fd2f0`; seventeen new files relative to the integrated base. Pure common Kotlin/JVM source only, no Android/Google/OS/network/storage/UI/root/dependency change. Actual **41 tests / 22 seams** passed at historical `91d1dc17` with all positive response fields asserted. Coordinator verified all fifteen receipt hashes against that committed tree. The final eleven-file temporal follow-up is **uncompiled/unexecuted**; all 49 current test methods/shared vectors need a new exact committed run. Historical receipt integrity is not current qualification or an independent rerun.
- Bounded review found unavailable cleanup, lost remote-family knowledge, per-attempt installation labels, Cloud UTF-8 media-type compatibility and superseded erasure-proof issues. Native source/tests now model repairs; passing older tests does not qualify later changes. A further static defect rebased token lifetime on response arrival, allowing delayed TTL1 replies to extend a possibly exhausted lease. Both final branches contain proposed request-start lease/deadline/rollback checks at response, actual custody commit and visibility, but **no executed temporal reproduction or repair verification exists**. Do not report it resolved from code reading.
- **Resource blocker:** the unchanged guard refused the coordinator admission-only probe with **exit 75 / 14,711,208 KiB** and AS04's actual temporal command with **exit 75 / 15,248,020 KiB**, below the **15,728,640 KiB / 15 GiB** floor. AS03 deferred after the hold without issuing another command; it has no invented exit-75 receipt. Latest light observation was **12,650,580 KiB**, load 1.13/1.32/1.72. No cleanup/cache copy/install/guard modification or other-fleet control occurred. No new heavy work is admitted merely because disk later recovers; recheck and explicitly admit a bounded rerun first.
- Source-only defaults remain unavailable with zero ports; parsed namespace/headers/test consent/clock/fake readback are not real account or storage authority. Library no-call sentinels do not prove app-wide cold/foreground zero health calls. Named issuer/consent/privacy/key/retention, real durable/native transport/custody/callback, UI/accessibility/physical and rollout gates remain open. AS06/AS07 remain open/unclaimed; AS18 stays undecided and primary-only charts/MCP are unchanged.

**Resume boundary:** after resource recovery, review the complete final committed native source and admit only the exact source harnesses under the unchanged guard, retaining any failure/refusal. Repair owned source if justified, commit and rerun the final tree. Only then consider serial integration and actual shared/affected-component checks. Do not merge unqualified source or wire synthetic factories into app roots. AS00/current goal remains incomplete; no child task is declared feature-complete.

## Task-by-task state (20 children)

This is an interim ledger, not a completion claim. TODO bodies are the detailed acceptance contracts. “Source-qualified dependency” permits only the specified disabled synthetic work; it does not close an approval-dependent task.

| Task / TODO | Actual source/evidence | Unmet acceptance / next gate |
|---|---|---|
| AS01 / TODO-9825212d | Partial: committed design/threat model/authority and field inventories/116 source vectors; locally reviewed interfaces | Named issuer/login/callback/linking/recovery/session/security choices; config privacy/key/retention/operations policy; mobile/physical/accessibility and pilot/cohort approval. TODO blocked, not complete. |
| AS02 / TODO-fd8dae80 | Partial: integrated default-unavailable synthetic auth authority; actual parser/WebCrypto/SQLite transaction/fault/lifecycle/isolation tests; lane 397 Cloud tests | Live browser identity/consent/durable adapters, native secure storage/OS lifecycle, real registration/privacy/retention/rollout remain unqualified. TODO blocked, not complete. |
| AS03 / TODO-02f3b1d0 | Partial, **not integrated/unqualified**: clean isolated `1b8500facf49599e9f92b372cdc6adf62e3a2320`, 18 new source/test files; historical strict Swift WIP corpus/22 seams pass followed by target-like compilation failure | Exact final strict/MainActor/XCTest/46 temporal rerun after disk admission; real browser/Keychain/callback/settings/root/lifecycle, supported iPad/macOS, UI/accessibility/physical and registration/privacy approval. TODO blocked/released, not complete. |
| AS04 / TODO-03effd7c | Partial, **not integrated/unqualified**: clean isolated `ecf4a2156f68e63b12374ec16a8f25d0538fd2f0`, 17 new files; historical `91d1dc17` 41 actual tests/22 seams, receipt hashes verified | Final temporal source/all49-method rerun after guard75/disk admission; real common Play/F-Droid browser/Keystore/exact intents/backup/recreation/root, both native builds, UI/accessibility/physical and registration/privacy approval. TODO blocked/released, not complete. |
| AS05 / TODO-541c5b8a | Partial: integrated repaired proposed codecs; independent Python/TS/Swift/Kotlin 10-fixture/257-case/30-test-only-scenario/6-read/11-error passes, combined Cloud strict checks/400 tests; deferred integrity registration | Full native app/core/actual registry adapters, trusted native binding, approved content subset/privacy and consumer/physical qualification; durable/native scenarios remain separate. TODO blocked, not complete. |
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

AS01 adds a separate source-review surface; AS02 adds isolated default-unavailable native-auth reservations and synthetic authority without live adapters. Neither changes public daily/API/direct/Shared Setup bytes or native runtime. AS05's new proposed native/Cloud parsers are integrated as isolated source-only codecs; central source registration/CI/planned-capability metadata does not activate a runtime consumer. The Cloud/native/dashboard account consumers are the planned next implementation boundaries. Shared Rust/core, CLI/local MCP, website account proxy, external Obsidian and provider brokers receive no new account authority or changed export bytes. They are not implicitly rewritten or qualified by tests in another component.

Cross-platform local state to preserve at every later mutation: offline/local-only profiles, separately generated native IDs, active selection, concrete folder/Mac/API grants/bindings/credentials, OS health/background permissions, schedule activation/timezone/progress, runtime/pending jobs/history/engine pins, purchases, foreign unsupported portable meaning and existing accepted snapshots. Account switch/sign-out/revocation must fence old mappings/outbox/callbacks without republishing under another account.

Actual current impact and call-site tests must be added as boundaries change; this baseline matrix is not a waiver of native/API/automation/direct/external consumer checks.

## Fleet / evidence map

Scratch root: `/var/folders/vh/t562rzcx5dx1w0j01ky690rm0000gn/T/healthmd-account-sync.O0LAHV`.

| Agent / wave | Branch | Tab / pane | Checkout / report |
|---|---|---|---|
| account-sync-orch | goal/account-sync/orchestrator | w3R:t1 / w3R:p1 | `/Users/codybontecou/dev/health-md-account-sync`; scratch `fleet-state.md`, `acceptance-checklist.md`, `evidence/` |
| account-as01 / 1 | goal/account-sync/as01 | w3R:t2 / w3R:p2 | scratch `worktrees/as01`; `reports/as01.md`; committed clean standby |
| account-portable-audit / 1 | goal/account-sync/portable-audit | w3R:t3 / w3R:p3 | scratch `worktrees/portable-audit`; `reports/portable-audit.md` and `reports/native-auth-audit.md`; unchanged clean baseline standby |
| account-as02 / 2 | goal/account-sync/as02 | w3R:t5 / w3R:p5 | scratch `worktrees/as02`; `reports/as02.md`; clean committed standby, integrated, partial/blocked/released |
| account-as05 / 2 | goal/account-sync/as05 | w3R:t4 / w3R:p4 | scratch `worktrees/as05`; `reports/as05.md` including complete repair addendum; clean repaired source integrated, partial/blocked/released |
| account-as03 / 3 | goal/account-sync/as03 | w3R:t6 / w3R:p6 | scratch `worktrees/as03`; `reports/as03-source.md`; clean unqualified source, not integrated, blocked/released standby |
| account-as04 / 3 | goal/account-sync/as04 | w3R:t7 / w3R:p7 | scratch `worktrees/as04`; `reports/as04-source.md`; clean unqualified temporal source, not integrated, blocked/released standby |

Wave-3 review/receipts: scratch `evidence/wave3-wip-seam-review.md`, `as04-coordinator-pretemporal-source-review.md`, `as04-historical-committed-receipt-integrity.log`, `as04-temporal-unqualified.diff`, `wave3-unqualified-committed-source-inventory.json`, `wave3-resource-hold-1.log`; full lane reports retain every compiler/test failure and current unexecuted gate. Complete source reports were read before this frontier update, and both lanes were confirmed done with clean branches/released claims. No tracked coordinator edit occurred while either was active.

All `.pi/todos` paths are ignored symlinks to the same shared store. Exact provider/model/reasoning is `openai-codex` / `gpt-6.1-sol` / `max`. Tabs were created with `--no-focus`; other spaces and user focus were untouched. Full reports and trees are reviewed before serial integration. No tracked integration edits occur during active lanes.

Resource admission: initially two active lane agents (orchestrator excluded), never over three, one fleet-heavy command at a time, minimum 15 GiB free; no cache/artifact/tree duplication or unauthorized cleanup. Startup 30 GiB free, after wave 1 about 24 GiB with unrelated fleets active. Wave 2 crossed below the floor and heavy work stopped; later about 19 GiB permitted bounded standalone rechecks. Heavy commands use `bash <scratch>/with-heavy-slot.sh ...` unchanged, actual disk/load and the fleet-local slot. Full Xcode/Gradle/core builds require separate admission.
