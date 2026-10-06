# Account-sync read-view wave 1 integration report

## Disposition

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
