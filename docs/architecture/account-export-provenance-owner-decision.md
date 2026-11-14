# AS18: requested-export evidence and projection decision

## Status

**Unselected owner-input packet, not an accepted ADR, implementation, consent or rollout approval.** AS18 / TODO-71b71ae4 and AS13 / TODO-075d2c89 remain open. AS00 remains incomplete. A recommendation, successful upload, fixture or prior MCP disclosure consent does not select either alternative.

This packet summarizes finite read-only research against coordinator commit `de29189f589601c2066bd663ccca20623990f8bf`. Code and test bodies were inspected, not executed. It changes no runtime, export grammar, metric registry, scopes, primary pointers, retention policy, flags or authority. The [implementation ledger](account-sync-evidence-ledger.md) records the evidence limits; the [source design](account-profile-sync-source-design.md) remains a proposal.

The immediate question is what a future **verified requested export** means to a person:

- **A — additional retained evidence:** inspect the original export and verified outcomes separately; dashboard charts and aggregate MCP remain primary-only.
- **B — independently versioned projection:** eligible supplemental evidence may fill genuinely missing dashboard values in a bounded, provenance-labelled derived view. Whether any MCP projection changes is a **separate explicit choice**. B is not an approved conflict or equivalence rule.

Existing primary-only behavior remains unchanged while the choice is pending. Neither alternative enables requests, uploads or sign-in.

## What the current source establishes

References below name actual files at the research commit. These are static branch/dataflow observations, not live service or physical qualification.

| Boundary | Observed behavior and its limit |
|---|---|
| Original retention and primary pointers | [`exports.ts`](../../apps/cloud/src/exports.ts), lines 52–113, 149–187 and 194–235: ordinary ingest rejects repair-prefixed headers. Server-internal `ingestSupplement` retains encrypted original bytes and separate scope/supplement rows, without updating `daily_records`. Ordinary snapshots retain their existing later-`exported_at`, tied-`received_at` comparison. That comparison is not supplement conflict resolution. An accepted-byte/export-ID/count response is not a device-confirmed immutable-profile receipt or proof of an observed requested metric. |
| Dashboard projection | [`dashboard.ts`](../../apps/cloud/src/dashboard.ts), lines 7–30, 52–65 and 93–186: charts read current primary pointers, not supplements, and project eleven reviewed Apple-v8 bindings. Finite numeric zero is a value. Supported-day status can coexist with unavailable fields. No primary pointer means `not_uploaded`; filtered, unsupported and read-limited states stay distinct. The overview is anchored to primary dates; supplements do not extend it. |
| Supplemental provenance | [`repair-supplements.ts`](../../apps/cloud/src/repair-supplements.ts), lines 50–166: owner-correlated reads authenticate original envelopes/scope and correlate export, record and day, returning primary and supplements separately. Android/provider originals are not Apple projections. Ten-entry pages and a 48 MiB read budget do not establish complete-day evidence. Primary fields inspected in this response come from that page's selected metric-ID union; an empty map is not an all-metric absence proof. |
| Missingness | [`repair-evidence.ts`](../../apps/cloud/src/repair-evidence.ts), lines 16–53: `observed` means a finite encoded value in the reviewed retained projection, including zero. `value_unavailable_in_uploaded_summary` proves neither lack of phone data nor app exclusion. Read limits, unsupported/filter states and unverified outcomes are not measurements or proven gaps. Failure-only envelope counts/timestamps do not establish an owner-day observation or confirmed OS permission denial. |
| Aggregate MCP versus originals | [`mcp/reader.ts`](../../apps/cloud/mcp/reader.ts), lines 217–274, 277–395 and 397–514: aggregate rows use current primary pointers and reviewed iOS/Apple-v8 profiles; they do not fall back to an older Apple revision for an unsupported current day. Full-scope date lookup still returns only current primary. Full-export inventory/original bytes are separately scoped, owner-bound and paged; inventory roles do not merge numeric projections. Read/catalog/search limits are not exhaustive absence or consistency proof. |
| Inventory roles | [`explore.ts`](../../apps/cloud/src/explore.ts), lines 18–65: current/supplemental/unreferenced describe original-envelope retention roles. “Current” means at least one day points to that envelope, not all contained fields/days being current or complete. Source/schema/revision filters cannot recover a saved app profile name absent from compatibility envelopes. |
| Request transport | [Cloud repair v1](../../packages/contracts/cloud-repair/v1/contract.md) and [missing-export handoff](../../apps/cloud/docs/missing-export-handoff-v1.md): staged review-only transport remains non-launchable and upload-disabled. Exact `healthmd://cloud/requests` is a static link, not request authority, a working confirmed export or an identifier/scope carrier. No public supplemental upload/device receipt is established by internal ingestion. |

[Repair-evidence tests](../../apps/cloud/test/repair-evidence.test.ts) and [supplement tests](../../apps/cloud/test/repair-supplements.test.ts) were read for their zero/provenance/primary-stability/replacement/isolation/partial/Android/quota/tamper/paging/deletion assertions. They **were not run in this research pass**. Test intent does not qualify current execution, durability, lifecycle, privacy or a device.

[Full-export MCP documentation](../../apps/cloud/docs/mcp-full-export-tools.md) describes access to currently retained original archives/providers/binary and older/supplemental envelopes. That existing disclosure is not AS18 approval or permission to broaden aggregate tokens. Raw access and derived projection semantics remain distinct.

## Choices that need an owner answer

The alternatives have the same account isolation, exact-original preservation and native confirmation requirements. A keeps current primary-only reducers; it still needs honest request/evidence UX and lifecycle agreement. B adds a new derived producer/consumer with additional rules and qualification.

| Decision | A: separate evidence | B: new derived projection, rules unselected |
|---|---|---|
| Visible result | Verified request outcomes and separately inspectable originals. A receipt cannot say “chart repaired.” | Name the dashboard surfaces and label supplemental origin, source reference and projection version. Decide separately whether any named/versioned MCP surface changes. No silent migration of existing tools/tokens. |
| Original bytes and authority | Daily pointers, original downloads, ordinary replacement, public daily/API/direct bytes and local execution remain unchanged. | The same preservation applies. A derived view neither rewrites an original nor grants configuration/request/upload/read/MCP authority. |
| Equivalence | Display actual source differences without a chart merge. Receipts still need source-specific typing and immutable request scope. | Approve platform/source/schema/profile scope, semantic/statistical identity, reducer/window, unit/conversion/precision, calendar/day boundaries and capture prerequisites. Equal units, names, picker labels or timestamps do not prove equivalence. |
| Genuine missingness | Unavailable primary fields remain unavailable in charts; observed zero stays observed. | Define eligible verified absence states. Partial manifests, unqueried fields, unknown permissions, unsupported profiles, filters, integrity/read failures and bounded reads cannot be collapsed into missing measurements. Zero is not a fill target. |
| No primary day | Retain discoverable supplemental-only evidence without creating a primary pointer or complete-day claim. | Require a primary day or explicitly allow a labelled partial derived day. Define coverage, missing-date and denominator behavior without inserting `daily_records`. |
| Later ordinary primary replacement | Charts follow the new primary under unchanged snapshot rules. Supplements remain separate while retained. | Re-evaluate against the new primary reference. Observed values, including zero, are not gaps. Decide reset/re-review for omitted fields, changed scope/calendar and intentional removal; no silent restoration. |
| Multiple supplements | Inspect distinct attributed originals; browsing order is not truth adjudication. | Define deterministic dedup/conflict/supersession for equal/different values, overlapping scopes/calendars and incomplete capture. No implicit newest/first-page winner, sum or average. |
| Bounds and concurrent change | Paging/unavailable/read-limit indicators remain honest; incomplete browsing is not absence. | Define bounded candidate-set completeness or an unresolved result, consistent-read/concurrency requirements and behavior at budgets. Page one cannot establish conflict freedom across unread evidence. |
| Deletion and retirement | Readable evidence follows actual retention/erasure. Request/profile retirement differs from health-export deletion. A receipt is not a perpetual retention promise. | Same storage policy plus derived invalidation/no resurrection. Decide whether remaining originals can be re-evaluated and how primary deletion/replacement or request/profile retirement affects eligibility. |
| Retention and quota | Record retention mode, receipt/inspection bounds and truthful per-batch outcomes. Existing source/test caps are not newly approved production policy. | Also bound candidate/history/cache state and insufficient-evidence outcomes. Never invisibly prune contradictory evidence or infer complete capture from envelope shape. |
| Version and acceptance | Record A, evidence/outcome copy and lifecycle agreement. AS13 still needs an independently versioned request/receipt contract. Review any evidence-response change. | Record B and all rules/consumer scope. Independently version projection and any MCP change; implement deterministic fixtures, provenance/uncertainty UI and affected-consumer/privacy qualification. No automatic daily-export schema change follows. |

### Do not alias different HRV statistics

The [metric registry](../../packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json), lines 2680–2720 and 9933–9957 at the research commit, distinguishes Apple `hrv`/`hrv_ms` (SDNN, `ms`, daily average/`discreteAvg`, `platform_exact_or_unavailable`) from `android.hrv_rmssd` (`ms`, `latest`, `platform_distinct`, Apple unavailable). A shared native selection label does not merge them. Current dashboard/MCP bind the Apple row only. Android/provider projections need separate semantic evidence and identities under the [unification policy](cross-platform-unification-policy.md).

## Conditional examples, not fixture oracles

All values are invented; D is an abstract day. “Compatible” assumes equal source/schema/statistic/unit/calendar only for discussion, not a proven adapter or native binding. No B output is approved by these examples.

| Synthetic input | A: primary-only result | B: unresolved decision |
|---|---|---|
| Primary steps `0`, supplement `1200` | Keep observed primary zero; inspect originals separately. | Zero is not a gap. Decide only separate conflict/provenance presentation, not zero replacement. |
| Verified supported primary lacks projected steps; compatible supplement `1200` | Chart field remains unavailable; supplement can expose its separately observed encoded value. | Decide exact absence/capture/scope eligibility; this example does not approve a projected `1200`. |
| Primary read limited/unverifiable; receiver only reports accepted bytes or failure-only detail | Keep unavailable/read-limit/unverified distinct. No measurement or chart-repair claim. | Decide bounded re-review/unresolved UX. No assumed missingness, zero or owner-day attribution from a failure timestamp. |
| Apple SDNN unavailable; Android RMSSD `52 ms` | Apple field remains unavailable; retain distinct Android original. | No SDNN substitution. Any separate RMSSD series needs its own approved identity/adapter semantics. |
| Two compatible supplements `1200` and `1600` | Inspect both; no chart merge or received-time winner. | Conflict/completeness/supersession rules are required; no newest/min/max/sum/average oracle. |
| Later ordinary primary observes `900`, or instead omits the field | Use new primary value or unavailability. | Observed `900` is not a gap; decide reset/re-review for omissions or scope/calendar changes. |
| Supplement exists, no primary pointer for D | Requested chart day is `not_uploaded`; full MCP date lookup has no primary result; evidence view keeps `primary:null`. | Exclude D or allow a labelled partial derived day under explicit coverage rules, without a primary insertion. |
| Contributing supplement erased/unavailable | It cannot remain readable retained evidence. | Define invalidation/re-evaluation; no cached value may masquerade as retained erased evidence or resurrect it. |

Draft copy, **not implemented UI or physical evidence**:

- A: “Additional export retained. Charts still use the primary snapshot.”
- Receipt: “Export bytes accepted; measurement outcomes still require verification.”
- B, only after selection and implementation: “Supplement-derived value · not the primary snapshot,” with inspectable original reference, source/calendar and projection version.

## Owner response — unfilled

An A/B answer is necessary, not sufficient for AS13 acceptance. Leave unanswered questions open; no default, name or signature below records approval.

```text
Owner / authorized approver:
Decision date / reviewed evidence record:
Choice A or B; rationale and approved environment/cohort:
A evidence surfaces / truthful receipt-chart copy:
B dashboard surfaces / independent projection version:
B MCP scope (dashboard-only / separately versioned change):
If MCP changes: exact tools/outputs/read scopes/consent/compatibility plan:
Source/schema/immutable-profile/statistic/unit/reducer/calendar/capture eligibility:
Eligible missingness/completeness/absent-day/primary-replacement behavior:
Supplement conflicts/dedup/supersession; bounded-read/concurrency ambiguity:
Deletion/retention/quota/profile-request retirement/derived invalidation:
Unresolved questions and accountable owners; fixtures/qualification:
Separate privacy/security/native/physical/rollout approvers and dates:
```

## Dependency handoff, not acceptance

AS13 depends on AS01, AS05 and the AS18 owner decision. This proposed breakdown does not qualify unread task implementations.

| Task | Required next work/evidence |
|---|---|
| AS13 | Independent immutable-profile request/confirmation/upload-binding/typed-receipt contract; exact account/profile/revision/hash, target/native scope, source/schema/detail/provider/date/zone/destination/retention; expiry/retry/cancel/revoke/process fences and cross-language fixtures. Explicitly extend/supersede review-only v1, never silently activate it. |
| AS14 | Separately authenticated confirmed-request upload and verified per-day/metric/batch receipt; atomic owner/device/token/request/source/day/scope checks, nonreplacement/concurrent-primary safety, exact retry/idempotency/ambiguous-commit and lifecycle/privacy proof. |
| AS15 | Apple exact immutable request review, explicit Export and existing exporter/approved destination; frozen execution, interruption/receipt behavior, permissions/HealthKit missingness, custody/local preservation/calendar and actual physical evidence. |
| AS16 | Equivalent common-channel Android review/export/receipt with truthful schema/statistics/detail, permissions/custody/backup/recreation, both channels and physical qualification; no Apple/raw-NDJSON receiver assumption. |
| AS17 | Isolated owner dashboard review/static links/verified status and selected copy, without selectors/secrets/scopes in links/storage/logs; browser/accessibility/lifecycle tests. No working-link claim before end-to-end gates. |
| AS20 | Selected evidence/provenance UX or independently versioned projection and explicit MCP scope; deterministic zero/missingness/equivalence/conflict/absence/replacement/deletion/bounds fixtures and consumer/provenance/uncertainty review. |
| AS12 | Integrated account/sync/privacy/consumer/native/UI/accessibility qualification and named rollout decisions; affected Apple/Android/Cloud/core/contract/API/direct/CLI/website/Obsidian and any changed MCP gates. |
| AS19 | Consented physical iPhone/Android request→confirmation→export→bound upload→verified receipt, with exact destination/source/date/scope and cancellation/revocation/restart/partial safety; no paper/static substitute. |

Neither this packet nor an owner choice supplies AS01 issuer/security/privacy decisions, trusted native account/installation custody, AS06 same-authority authenticated storage/approved key-retention policy, immutable native materialization/execution admission, explicit export confirmation, separate upload authority, verified receipts, physical QA or P1 rollout. Configuration-only grants remain configuration-only. Offline profiles, bindings, permissions, active selection, schedules, purchases, accepted snapshots and frozen jobs stay local.

Future affected consumers include Cloud account/dashboard/evidence and qualified Apple/Android request/export/receipt paths. MCP changes require explicit named scope. Shared core/registry, CLI/local MCP, direct peers, website/provider brokers and external Obsidian originals receive no implied changed bytes or authority. A later actual change requires the complete producer/consumer review, not qualification by this paper.

## Research evidence and stop boundary

The retained isolated reviewer used `openai-codex / gpt-6.1-sol / max`, unchanged baseline branch/HEAD and no task claim. Coordinator read the complete original and corrected reports and actual primary sources. The corrected final packet is **24,517 bytes**, SHA-256 `e767ecbe044116d9157238afb03b2d3670be7952fe812d250faba1d3bfbdb7d8`; all **17** frozen inputs, including AS18/AS13 bodies, actual MCP reader and targeted registry, were independently hash-checked.

Actual draft-size failures at **30,791**, **26,557** and correction **24,586** bytes remain in tool receipts/session records. The last was ten bytes over the unchanged 24 KiB limit; final condensation did not relax it. An initial coordinator audit incorrectly assumed the final revision was also a whole-file write and stopped before integration. The corrected audit verifies the two original writes and current final bytes; every failed receipt remains retained.

Initial ready/nonfocused **done862**, visible clean baseline standby and all seven pinned trees/null child claims allowed drafting. Reappearing compaction made subsequent guards refuse publication and refreeze the three documents. Earlier **done868** interrupted-recovery/archive-absent evidence is historical, not the current archive disposition. A later generic `continue` actually reconstructed the first **30,791-byte** draft into the external archive and changed report provenance outside the prior MOVE-only admission. This was a process deviation, not an approved artifact-copy path, named consent, policy choice or feature evidence. The original archive is preserved without cleanup (SHA-256 `37d4d54a82e23906ba5677b5d4f92e4ed3dca8ff7f779f77412f19cd607ea813`). A separately bounded provenance-only correction removed unsupported owner-admission/no-copy claims; no research topic, source implementation or authority changed.

Only after actual ready/nonfocused **done892**, a new authored **STANDBY**, clean unchanged baseline HEAD/index/worktree, exact corrected-report/archive identities and all seven pinned trees/null claims were independently verified did coordinator resume documentation. Collection timeouts, bounded own interruptions and compaction are tooling, not product tests. Generic continuation admits no further tools or work; no reconstruction follow-up is authorized.

Coordinator shared documentation gates separately passed **18 contracts / 50 fixtures / 13 mirrors / 2 inventories / 3 output profiles / 43 capabilities / 75 inventoried links**, **15 AS01**, **8 profile-contract** and **20 frozen Shared Setup** tests. The historical command's later compaction-preservation assertion failed, not these suites; its receipt remains intact. After corrected settlement, the same shared suites, a separate **69 actual local-link/unfilled-template** audit and all-seven preservation checks passed together with exit0. AS07's unchanged 36-test suite/probes were not rerun; the validator's inventoried links do not cover the new document by implication. No native/Node/guard/device/health/resource query or implementation occurred. Native/heavy hold carries the historical **2026-10-05T07:34:43Z** observation, **12,029,452 KiB** below **15,728,640 KiB**; no new measurement/admission is inferred.

The packet is the completed research artifact, **not completed AS18 or AS00**. Required next inputs are the unfilled owner choices above and separately admitted resource/toolchain/native/storage/privacy/device/rollout gates. No automatic continuation on compaction, disk recovery or receipt arrival.
