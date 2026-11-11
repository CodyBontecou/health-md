# Account-sync read-view wave 1 integration report

## Local Cloud parent integration (2026-11-11 UTC)

History-preserving local merge of exactly `c19a88a61cb3333add6a6b93511cb15769585480` into `c602c8827bbfa671584cadad57f549bb23667c1a`. Both histories remain parents of the merge; no later parent follow-up is included. The three conflicts were Apple/Android product-capability tests and the contract manifest. Resolutions retain both branches' capabilities and deferred contracts, preserve the parent's unpinned editable product-capability inventory, and retain immutable fixture/registry hashes. The read-view implementation/tests and inactive runtime boundaries from `c602c8827` are unchanged.

Host tests also exposed a previously nonconflicting ownership drift: current Shared Setup v2 gained `eu_dot`, while AS01/AS05 still pin and embed the earlier closed schema. The exact `c602c8827` schema bytes (unchanged SHA-256 `39e56dc54dfb56c556e2c71c734c00da4f02305a2a9b98ad795486c3e9c81f45`) now live alongside AS01's existing historical ledgers. Field scope and AS05 generation/reproducibility explicitly reference that historical path. Manifest fixture provenance pins the retained copy. The parent's current Shared Setup schema, existing sync schema/fixtures, all three embedded codecs and wire versions remain unchanged. This preserves reproducibility without silently adopting new portable content or weakening frozen validation.

Fresh merged-source host evidence, Node24 / one Vitest worker / 384 MiB heap: **277 Cloud tests in 11 files**, both strict Cloud typechecks, **15 AS01 + 8 AS05 + 38 Python reconciliation + 68 contract-validator regressions**, contract inventory validation (**32 contracts / 87 fixtures / 27 mirrors / 3 inventories / 6 output profiles / 62 capabilities / 122 documentation links**), product parity, and documentation navigation (**314 paths + 16 tests**) pass. The parent's scoped `@hono/node-server@2.1.6` lock update clears the earlier advisory: `npm audit --audit-level=moderate` reports **zero vulnerabilities**. Initial AS01 testing failed on the live-schema pin; historical ownership repair made the same check pass. The first expanded Cloud run had seven loopback-listen `EPERM` failures; the exact suite then passed with temporary synthetic loopback access. No deployed service or real health data was used. The full first-parent cached whitespace check flags inherited generated declarations and CRLF evidence CSVs; the parent-relative `git diff --cached --check c19a88a61` passes. Those inherited bytes were preserved rather than rewriting generated publications or evidence.

Portable session `pr190-parent-merge` retains all attempt receipts under ignored `.pi/verification/`. Final Cloud/typecheck receipt: `a2b9c6bb-aad6-4e33-b24e-ab3643fac4ff`; contract/regression/parity receipt: `92c8d6d9-a723-4cda-858a-9a53d1ed0834`; audit: `9121cda3-1b7b-4a39-bdb4-f794848e92be`; navigation: `41eaac03-f574-47df-a4d7-f388585fe3a8`.

**Qualification dependency / draft gates:** parent `c19a88a61` remains local and pending native/generated qualification. Its recorded native compilation attempts encountered the shared build queue; its automation generator manifest did not match the combined message-fields artifact. Owning native serializer regeneration, generated reference/agent publication checks and exact combined native compilation remain outstanding, not rerun or waived by these host passes. The resolved Swift/Kotlin capability tests have not been compiled/executed here. Later parent repair will be integrated separately. Full native/core/CLI/website/consumer/physical acceptance, the missing historical independent probe, real identity/privacy/private durability, AS18 decisions, all twenty child acceptances and AS00 remain incomplete. PR #190 stays draft; no push, deployment, activation, device QA or changes in another worktree.

## Draft PR #190 host-source milestone (2026-11-11 UTC)

The inactive TypeScript collector from `a0d52fde327290ce9a06adc7d554d0064a5522e4` is now locally integrated and subset-qualified against draft head `4c86df1e6`. Its real AS05 codec, RAM and account-auth dependencies match the candidate baseline. Only the collector, its public tests and documentation are added; no router, service binding, authority, storage, wire/schema/fixture, native capability, rollout flag or deployment changes. AS07 and all twenty full child acceptances remain incomplete; PR #190 stays draft. Parent #188 integration is outside this milestone.

Fresh Node **24.19.0** / Vitest **4.1.12** evidence, one worker and **384 MiB** heap: **246/246** tests pass across read-view (**47**), AS05 codec, AS06 RAM, account-auth and service-profile suites. Both unchanged strict Cloud configurations pass (`npm run typecheck` and `npm run typecheck:vm`). The real parser validates hashes/content independently of the timing hook. Tests cover complete-only publication, exact owned bytes, global pagination/coherence and item/page/byte bounds, full-observer preservation on refusal, reset/switch fences both before real parsing settles and after it settles, and retained original committed provenance. A dedicated observer test establishes that owned `parsing` diagnostics and their retention charge may appear while committed/tentative/control state remains unchanged. This resolves the documented expectation mismatch without hiding retained fields.

The original 44-test candidate reached 41 passes before heap exhaustion at the 4 MiB boundary; isolated reproduction also failed. Owned byte arrays now preallocate their exact length and diagnostic byte copies use `slice`. Allocation repair alone did not make the boundary test pass: generic matcher enumeration of large byte arrays was also replaced by a loop comparing **every byte**, with normal deep comparison of every other observer field. The subsequent 256-page test timed out at 5 seconds; it now captures the full pre-refusal observer at the actual boundary and uses the same exact comparison for refusal/retry, avoiding unnecessary copies at every successful intermediate page. Neither quotas, heap allowance, timeout, parser, fixtures nor acceptance assertions were relaxed. Final five-suite execution passed in 6.35 seconds.

The local `goal/account-sync/read-view-probe-1` ref resolves to `fa27a9a8`, with no probe committed. Its historical ignored artifact location is absent in this environment. No execution or independent authorship of that missing probe is claimed; the new observer/fencing coverage is authored here. Prior guards, failures, original refs and historical evidence below remain preserved, not retroactively qualified.

`npm audit --audit-level=moderate` exits 1 for existing transitive `@hono/node-server@2.1.1` via MCP SDK (`GHSA-rmxm-3fg6-px4f`). Lockfile/dependencies remain unchanged. Initial sandbox dependency installation failed DNS; authorized network retry succeeded. Broken Homebrew Node24 library resolution was avoided with the existing NVM Node24. Portable runner session `pr190-read-view` retains failure and final passing receipts in ignored `.pi/verification/`; final tests receipt `efa6d452-901f-4ec3-8334-c2a734aafaf9`, typechecks `cc42b106-53e2-4a95-82a5-30d8a48e653e`, audit `92bd7406-586f-4f2b-8426-e0c2a1876fdb`.

Unrun: missing independent probe, full Cloud/runtime bundling, shared/native/OS/device/physical/UI suites, real identity/health/private durability, rollout and deployment. The collector remains unimported by runtime entrypoints and unavailable by default. This finite synthetic host proof grants no account consent, authenticated completeness, accepted native revision, execution, persistence, activation or product acceptance.

## Historical wave disposition

**Blocked, partial, unmerged. AS00 and all twenty child acceptances remain incomplete.**

Integration SOURCE stays at `fa27a9a86c2e0cfa3a474d34160fa16771e6409d`, branch `goal/account-sync/orchestrator`. Closure changes documentation only. No merge, push, PR, deployment, real identity/health/device access, rollout or approval occurred.

New AS07 candidate: `a0d52fde327290ce9a06adc7d554d0064a5522e4`, direct child of fa27, branch `goal/account-sync/as07-read-view-1`. Three new Cloud files (collector, public tests, documentation), 839 lines / 62,642 bytes; **unqualified and unmerged**. Factory-local synthetic memory is not full reconciliation, authenticated completeness, private durability, native consent or execution authority. Existing AS06 remains 65,530 bytes; Python AS07 remains 131,061. Neither budget expanded.

## Actual evidence

Four admitted author commands used Node24/heap<=384MiB/one Vitest worker. All four Vitest runs exited1. The runnable stub produced pending-versus-unavailable RED. Next failures were incorrect input hash and omitted registry-review expectation, not implementation defects. Fourth WIP run: **7 passes / 37 failures / 44 tests**; two-page snapshot passed, continuation/reset/switch failed at missing public behavior. Negative cases failing setup do not prove their deeper fault branches.

The one strict Cloud typecheck exited2: the coordinator's sparse lane omitted `packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json`, breaking unchanged dashboard/MCP consumers. Setup debt, not a registry defect; no flags/imports/fixtures/aliases were weakened or restored.

After further repairs, the candidate was committed. Fifth guard attempt exited75 **before child launch**: final tests/typecheck did not run. Receipt: `Blocked: available disk  KiB below 15 GiB; no cleanup authorized.` The coordinator-authored guard omitted the printf argument: exact free space is unrecorded. Comparison/floor remains 15,728,640 KiB. Guard/receipt preserved unchanged; no fix/retry/poll/cleanup/waiver. Historical guard also unchanged.

Independent lane authored a public probe, inspected no implementation, and ran zero runtime commands. After settlement coordinator fully read both reports, three candidate files, probe/config and all five receipts. Coordinator Node/native/shared/contract/component runtime is **UNRUN** after terminal75. No historical pass substitutes for final RED-to-GREEN or exact/integrated qualification. All size/setup/test failures remain disclosed.

## Static findings, not executed proof

Source proposes exact request/reply ownership, actual AS05 parsing, tentative pages until completion, cross-page consistency, reset/switch epoch fencing and 100-item/256-event/256-page/4MiB SOURCE limits. Final behavior/bounds/temporal publication/default ports/compiler compatibility remain unexecuted.

Probe assumption to resolve: its byte-ownership case compares the whole PRE-receive observer to one while parsing is suspended. Candidate exposes an allowed `parsing` diagnostic then. This is a **static expectation mismatch**, not an executed failure or unauthorized publication. Do not hide retained fields or skip the case to silence it. Dynamic import/config/TS behavior is also unexecuted.

Changes are events, not merged inventory. General history/retired IDs/repeated selector rounds, native mappings/accepted revisions/outbox, account authorization, persistence/protection/frozen jobs remain separate missing work. Pending absence/sentinels confer no deletion/adoption/activation authority. AS18 decisions remain null; primary-only charts/MCP and daily/API/direct/job bytes unchanged.

## Twenty-child acceptance audit

Actual states: 7 blocked + 13 open; all child claims null after settlement; **zero complete**. Existing ledger evidence remains historical, not rerun.

| Child / TODO | State | Evidence and missing acceptance |
|---|---|---|
| AS01 / 9825212d | blocked | Design only; named issuer/login/linking/recovery/privacy/key/retention/mobile/rollout decisions missing. |
| AS02 / fd8dae80 | blocked | Synthetic authority; real browser consent/identity/durable adapters missing. |
| AS03 / 02f3b1d0 | blocked | Apple SOURCE/import subset; XCTest/app/browser/TLS/Keychain/OS/UI/device/privacy gates missing. |
| AS04 / 03effd7c | blocked | Provider-stopped14e unqualified/unmerged; exact-final/header/both-channel/OS/UI/device proof missing. No retry. |
| AS05 / 541c5b8a | blocked | Codec subset; actual native/core/consumer/app/privacy/physical acceptance missing. |
| AS06 / f540313f | blocked | Finite RAM subset; durability/lifecycle/feeds/general CAS/multitenancy/policy missing. |
| AS07 / cbfd8aa1 | blocked | Python memory proof; new TS candidate unmerged/unqualified; full reconciliation/native/private/protection acceptance missing. |
| AS08 / e0f7ecbe | open | Apple sync UX/persistence/outbox/mapping/adoption/protection and dependencies missing. |
| AS09 / 370f24fa | open | Android sync UX/persistence/outbox/adoption/protection and dependencies missing. |
| AS10 / 3dedf371 | open | Static feasibility; controls/candidate-accepted journal/binding/activation/protection/public pre-health/frozen-job proof missing. |
| AS11 / c441b03a | open | Dashboard CRUD/revisions/conflicts/session status/private authorization missing. |
| AS12 / 795e178b | open | P1 native/dashboard/consumer/device/security/privacy/release qualification missing. |
| AS13 / 075d2c89 | open | Immutable request/confirmation/upload/typed-receipt contract and P1/AS18 prerequisites missing. |
| AS14 / 2db4e768 | open | Same-authority execution/ingest persistence/verified receipt/provenance/nonreplacement missing. |
| AS15 / cbde636f | open | Apple revision-confirmed foreground export/upload/receipt/device acceptance missing. |
| AS16 / 97c8f97e | open | Android foreground export/receipt/recreation/device acceptance missing. |
| AS17 / aa42a7cc | open | Honest request/target/progress/verification dashboard and dependencies missing. |
| AS18 / 71b71ae4 | open | Owner A/B/MCP/provenance/missingness/conflict/completeness/retention/quota/invalidation choices null. |
| AS19 / 8a71976d | open | Physical request-confirm-export-bound-upload-verified-receipt/security/privacy/rollout qualification missing. |
| AS20 / fd625ce1 | open | Approved recovered-export presentation/provenance and AS18/14 dependencies missing. |

## Custody and next boundary

Both new lanes preserved `openai-codex / gpt-6.1-sol / max`. Actual stopped/ready/nonfocused/authored-STANDBY settlement: author1234/probe1233, clean exact trees/null child claims. ROOT frozen during work/finalization. Lane map:

- Author: `build/account-sync/waves/read-view-1/worktrees/author`, tab w3R:tA/pane pA, session 01a11043-6f32-7321-a803-351e544978dd, HEAD a0d52fde.
- Probe: `build/account-sync/waves/read-view-1/worktrees/probe`, tab w3R:tB/pane pB, session 01a11043-7b17-71a3-ab73-ef19a6c5cb2b, HEAD fa27a9a8.
- Reports/probe/config/failed receipts/briefs/metadata: `build/account-sync/waves/read-view-1/`. Git-ignored/local, not remote backups.

Dirty original SOURCE/unrelated registrations unused and unmutated; previously consolidated refs/history retained. No source integration or child completion. Epic remains in_progress. Documentation precommit initially rejected stopped `idle` instead of `done`; correct stopped classification retains identity/sequence/ready/nonfocus/standby/clean/claim checks. That metadata failure is not a SOURCE RED.

Future runtime needs a **new bounded admission**, verified capacity, correct dependency closure/probe expectation, then public RED/repair/GREEN and exact/integrated/shared checks before merging. This is not an extra human approval gate for source review. Closed allowances cannot be reused; no automatic retry/follow-on lane work. Product/privacy/identity/device/AS18 approvals remain separate and cannot be fabricated.
