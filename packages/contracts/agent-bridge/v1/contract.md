# Agent bridge foundation v1 (B01 / B05)

Status: **deferred specification**, not implemented, advertised, approved for production, or
CLI 1.0 scope. Synthetic vectors are Python specification candidates, not native-generated
conformance evidence. All new product-capability entries remain planned.

Outcome: an authorized host describes selected capture and output independently of mobile
preferences, previews configuration without health reads, approves one immutable plan, and commits
or resumes that exact job. Source-aware fixed factual queries retain native meanings and uncertainty.

Normative grammar: [agent schema](agent.schema.json), [query schema](query.schema.json),
[direct v4](../../direct-protocol/v4/protocol.md). Cross-field rules below and the
[synthetic oracle](validation.py) supplement JSON Schema. [Vectors](fixtures/conformance.json),
[source review](source-review.md), [bounded reviewed catalog](reviewed-query-catalog.json), and
[conformance/integration gates](conformance.md) are part of this foundation.

## Version decisions and boundaries

| Boundary | New identity | Decision |
|---|---|---|
| Declarative intent, plan, discovery, authority, approval, receipts, control | `healthmd.agent_*` / 1 | Closed independent configuration DTOs; never Shared Setup RPC |
| Source-aware typed request / response / catalog | `healthmd.source_query_request`, `healthmd.source_query_response`, `healthmd.source_query_catalog` / 1 | Separate from existing Apple `healthmd.query_request/1` and `query_response/1` |
| Cursor claims and cancellation | `healthmd.source_query_cursor_claims`, `source_query_cancel`, `source_query_cancelled` / 1 | Native-authenticated, transient, dataset/peer/scope-bound |
| Android selected extraction | `healthmd.source_projection_request`, `healthmd.source_data_projection` / 1 | B08 new source-shaped product `android_source_projection_v1`; not reserved v2 `android_daily_records_v1` |
| Manifest / profile dictionary | `healthmd.agent_artifact_manifest`, `healthmd.profile_dictionary` / 1 | ZIP/dictionary companions and generated artifacts version independently |
| Encrypted control extension | Direct v4 | Independently negotiated on Apple base v1 and Android base v2; not pairing selector 4 |

No shipped daily schema, archive, raw snapshot, setup, semantic/render fixture, pairing transcript,
secure-channel or binary-frame byte changes. No Apple schema bump/signature generation. No unified-v9
writer or B19/B20 authorization. Existing commands, stored jobs and iPhone query v3 continue on
existing contracts. No shared Rust query engine is claimed: the current evaluator is Swift.

## Complete explicit intent and precedence

Every `agent_export_intent/1` contains a selected source/host installation pair, an opaque destination
binding, explicit dates and IANA timezone, timestamp timezone `UTC`, capture scope and settings policy.
No destination path, basename, SAF URI, bookmark, credential, endpoint secret, trust or purchase object
crosses the wire. The host owns the mapping from binding ID to its private native root and identity.

Settings policy is exactly one of:

1. `explicit`: all fields of the output settings DTO are required. No live/mobile/profile/API-target
   default is inherited, even for an apparently optional output. False, empty and `none` are values.
2. `saved_device_settings`: snapshot the device output settings at the requested revision. No profile
   fallback; no output overrides in this version.
3. `profile`: resolve the exact native profile ID at the requested revision. No display-name fallback,
   deleted-ID fallback, imported-blocked-profile activation, or inheritance of live destination grants.

For **every** policy, request dates/timezone and `capture_scope` override saved selections/detail/archive.
The policy selects output settings only. It cannot expand the requested capture. Clone/freeze, never
persist; byte-identical native preferences must survive success, failure, cancellation and resume.
Unsupported saved fields or unsupported explicit choices fail with a stable code; never approximate.
Profiles' engine authority can be frozen internally without exporting portable authority tokens.

Capture scope:

- sorted unique **registry semantic** metric IDs and source/category/provider selections;
- categories are lowercase native registry category IDs normalized to the query catalog; resolve the
  union once against the selected platform's registry. Unknown/unavailable IDs reject before reads;
- `all_metrics` resolves the installed, authorized-supported catalog, not future APIs or another source;
- `compatibility_detail` is `summary` or `selected_time_series`;
- `native_archive` is an independent explicit `none`, Apple canonical HealthKit v1 archive, or Android
  provider-native raw-snapshot v1 product. The Android scope/format/route preference is separately
  disclosed. A selected archive cannot quietly become all-authorized scope. Route consent stays native.

Summary+none has no hidden time series, archive, entry files or companions. Archive-only and selected
series without archive remain valid independent combinations. Native artifacts never become fake
`healthmd.healthkit_records`, HealthKit UUIDs or complete daily documents.

Output settings enumerate:

- unique sorted formats `csv`, `json`, `markdown`, `obsidian_bases` and an exact shipped output profile;
- relative `subfolder`, date-based `folder_template`, single-segment `filename_template`;
- explicit `overwrite`, `append`, `merge_markdown`, `merge_markdown_preserving_preamble`;
- display units `metric`/`imperial`, locale, machine units **always canonical**, metadata/category grouping;
- frontmatter field order, bounded custom fields, unit/diagnostic preferences; Markdown style, bounded
  custom template and ordered placeholder IDs (data only, no execution);
- individual-entry master/metric selection, folders, filename and category-folder preference;
- Daily Notes enabled/only/folder/filename/create-if-missing/section selections;
- loose files or explicit ZIP, optional loose-file retention, archive name and bounded staging;
- no dictionary or explicit profile-correct JSON/Markdown dictionary companion.

This is a closed bounded **portable dialect**, not a promise that every native customization maps.
Custom frontmatter cannot override reserved schema/unit/time/capture meanings. Native-only or dialect
features unsupported by an installed peer reject; a producer must publish supported fields/tokens in
its configuration catalog before acceptance. This edition has no range-summary setting (B19) or typed
Android WHOOP daily section (B20). Existing saved runs requiring those features stay on existing contracts.

The complete machine settings are schema-defined; broad arbitrary key/value settings, shell, SQL,
URL execution, arbitrary file reads and arbitrary JSON pointers are forbidden.

## Dates, owner time and configuration-only planning

Civil date bounds are inclusive in the frozen IANA Gregorian calendar; native reads use half-open
instants `[start-day midnight, day-after-end midnight)`, not fixed 24-hour arithmetic. Source timestamps
retain seconds, nanoseconds and nullable original offsets. Owner timezone and source offset are distinct.

`past_complete_days` uses an explicit configuration anchor date, excludes that date, and resolves to
exact bounds before approval. A host recipe/schedule must compute a fresh anchor in its explicit zone
and create a fresh plan; it cannot reuse a prior approval to widen dates. DST gap/fold policy is explicit.

**`all_available` earliest-date discovery reads health data and is forbidden during planning.** A plan
preserves logical `all_available`, returns no concrete predicted paths and uses
`template_only_all_available` plus `history_bounds_unresolved`. It cannot promise exact first/last days,
record counts, completeness, archive sizes or specific output existence. A consumer wanting exact target
paths must provide an explicit configuration-only range. Capture may resolve actual authorized bounds
only **after** bound execution; its immutable capture manifest/journal pins that resolution. Planning
never clips uncertain history to a silently narrower range or reports full history from SDK version.

Planning may read authenticated runtime capability/settings/profile revisions and native readiness
without side effects. It **must not** invoke earliest-date discovery, content preview, a health query,
provider login/probe, quota accounting, output writes, native settings mutation, credential enrollment,
wake enrollment or notification. Counts in `side_effects` are all integer zero. Required native actions
are descriptions, not actions that the plan performs.

The plan discloses effective settings, resolved selections/dates, origin of every effective setting,
revision pins, source limits, unresolved history, unsupported choices and exact configuration-derived
relative paths (or an explicitly unresolved pattern). Discovery enumerates formats/write modes, capture
detail/native products, supported setting pointers/path tokens and smaller installed artifact/path limits.
Capability SHA-256 covers the entire discovery object except `capability_sha256`, `request_id`,
`issued_at`, `expires_at`; timestamps/expiry are checked separately. An absent source-query feature uses
an all-zero query-catalog digest and no query operations, never permission to probe an old peer. Ordered arrays are one setting origin each;
origins cover all DTO leaf fields and request capture axes, including disabled outputs. Data-dependent
entry/attachment paths are disclosed as `deferred_native_entries`; they cannot be predicted by reading
health data. General path planning does not guarantee that a selected day contains data.

## Paths and packaging

All paths are POSIX destination-relative, at most 4,096 UTF-8 bytes, 16 components, 255 UTF-8 bytes per
component. Empty folder means the bound host root; filenames are nonempty single segments. Reject
absolute/drive/URI paths, backslash, percent escapes, control characters, empty/`.`/`..` components,
leading tilde, Windows reserved device names, trailing dot/space and unsafe Windows characters.

Daily templates accept only `{year}`, `{month}`, `{day}`, `{date}`. `{date}` is ISO civil date;
`{year}` is four-digit Gregorian year. Filename templates are **basenames**: producers append `.json`,
`.csv` or `.md`; Bases gets `-bases` when Markdown is also selected. Thus folder `{year}`, filename
`{date}`, JSON yields `{year}/{date}.json`. No double interpretation of extensions or date dialects.
Individual entries additionally allow `{metric}`, `{category}`, `{record_id}` from catalog IDs and
privacy-preserving path-safe digests, never raw source identity/title/notes. Unknown tokens reject.

Validate templates and every expanded artifact independently. Reject case-fold/NFC aliases, all same-run
collisions, symlinks, junctions, hard-link escapes and root-identity mutation. Never normalize an unsafe
path into a different approved target. Host-native handle-relative resolution and private root binding
are mandatory; the Python oracle tests lexical/collision rules only, not filesystem race safety.

ZIP B17 uses exact production inner bytes, relative paths and profile IDs from the same manifest.
Deterministic ordering, fixed synthetic ZIP metadata for conformance, no symlink entries or traversal,
no credential/path comments, at most 4,096 entries and 1 GiB uncompressed per staging container. Larger
jobs require separately approved bounded containers, not unbounded memory. Every inner digest and
container digest is validated before commit; cancel/crash cleanup cannot delete an already committed
output. ZIP is an output container, **not** a HealthKit/source archive. Dictionary inclusion/loose-file
retention is explicit; neither implies capture scope. Run-level archive/dictionary filename tokens use
the final **requested** configuration date (never the latest captured health date). ZIP-only plans list
the container path, not loose inner-file targets; exact inner paths remain in the manifest. Entry paths
stay unresolved until approved native capture, and entry generation cannot secretly enable an archive. Android ZIP remains planned B17.

Dictionary B18 records exact profile/source-schema version, registry digest, source-native selector/type,
unit/statistic, aliases, registry equivalence and static mapping support. It contains no health values,
permission assertions, grants or secrets; query-runtime availability is a different catalog. It must
not copy HealthKit mappings into Android or use the frozen `hrv` key to equate RMSSD with SDNN.

## Authority, approval and immutable execution

Pairing proves installation identity only. `agent_authority/1` is a **sanitized description of a
native/host-issued stored grant**, not a bearer token or a client-authored grant. Receiving a JSON object
or Shared Setup file never creates rights. Servers check the authenticated peer against their private
issued-grant/approval records; unknown IDs and replay from another host/source fail closed. Do not derive
new authority from an MCP annotation or a valid digest alone.

Separate rights:

| Domain | Inspect | Mutate / run |
|---|---|---|
| Capabilities / configuration-only planning | `discover`, `plan` | None |
| Factual queries | `query_summary` | `query_evidence` additionally for explicit native evidence values |
| Generated export | None implied by planning | `export_execute` and bound approval |
| Host recipes | `recipe_read` | `recipe_mutate`; `recipe_run` creates a fresh export plan and needs export approval |
| Host schedules | `host_schedule_read` | `host_schedule_mutate`, `host_schedule_run`; run still needs export authority |
| Mobile profiles/destinations | `native_configuration_read` | `native_configuration_mutate` |
| Mobile schedules/recovery | `native_configuration_read` | `native_schedule_mutate` |

Remote/read-only profiles get no export, mutation, schedule-run, configuration-unlock or destination
rights. All grants are scoped, peer-bound and expiring. Native initial HealthKit/Health Connect/history/
route/PHR grants and entitlements remain mandatory. Configuration Protection cannot be remotely
unlocked; native mutation requires an existing native unlock/consent decision. Export authority never
implies phone profile mutation, native destination rebinding or scheduling authority.

Plan lifetime is at most ten minutes. Approval is bound to **all** of source+host peer, opaque destination
identity+revision, scope/settings/plan digests, native/profile/recipe revisions, capability digest and
expiry. Canonical digest is sorted compact UTF-8 JSON (unescaped `/`, no Unicode normalization, no
floats in metadata). The plan digest excludes only its own `plan_sha256` field. Scope digest includes
resolved/logical dates, zone, capture axes and resolved metric IDs. Any change requires a new plan and
approval, never silent replanning. Approval cannot outlive the plan or stored authority. Human approval
is stored before execution; client-supplied approval IDs are insufficient.

Execution checks revisions, required native actions, consent/entitlements and capability/peer/destination
bindings immediately before reads. Persist the accepted exact request and fingerprint before capture.
Atomic idempotency index is `(authenticated peer, job_id, idempotency_key)`; same key+same request returns
only the stored job/receipt even after planning approval expiry, never recaptures or replaces it. Resume
is a separate exact-journal operation subject to native grant/revocation/job-expiry checks. Different
bytes under the same index reject. Concurrent agents use compare-and-swap, never last-writer-wins.
Capability receipt and installed app/provider evidence are prerequisites, not availability claims here.

Durable jobs expire seven days after acceptance. Resume reuses immutable request, source/host, settings,
destination/root identity, resolved scope, artifact manifests, transfer/session IDs, digest chain and
committed frontier. Resume does **not** resolve saved preferences again, reapprove widened settings,
regenerate a missing nontransactional snapshot, renew expiry, or require old configuration revisions to
still be current. Current revoked trust/native grants/protection are rechecked; revocation can stop work,
not migrate it. Missing preserved spool returns `spool_missing_restart_required` with a fresh approved
job required. Local timeouts/disconnects do not mean source cancellation.

Manifest and commit receipt pin every artifact path/profile/write mode/byte count/digest. Before
append/merge, host persists a commit plan with destination identity, before/input/after digests and
`commit_key` (SHA-256 of the schema-defined commit identity fields). Commit and receipt are journaled
restart-safely. Replay only recognizes the same already-applied after digest; a new before/input/destination
fails. Overwrite is atomic. No duplicate append or merge after ambiguous outcomes. Only source
confirmation makes completion/cancellation terminal; local intent is `cancellation_pending`.

## B11-B14 typed control boundary

`agent_control_request/1` enumerates fixed verbs only: host recipe create/list/get/update/delete/run;
native profile create/list/get/update/activate/delete; host schedule create/list/get/update/pause/delete/
run-now; native schedule inspect/plan/update/enable/disable/inspect-pending/discard-pending; native
destination inspect/plan/update. Each mutation has a separate stored approval and idempotency key.
Object references are stable IDs and expected revisions. No display-name fallback or arbitrary files.
Sanitized `agent_control_receipt` returns bounded typed items/revision/digest/actions, never native secrets.

Recipe values contain name and declarative intent, not health data, pairing rights or approvals.
Destination/device references are host-local; recipe import/export is separate from Shared Setup and
requires rebind. Run produces a new plan, not a replay of an old approval. Private store, atomic CAS,
name bounds/collisions, rollback and last-profile invariant belong in B11/B12 native tests.

Native profile definitions contain name, selected capture, output settings and native destination
intent/reference. A desktop binding never becomes a native destination. Native binding ID must name
an existing granted device-owned folder/SAF/bookmark/endpoint; `requires_native_rebind` yields a human
native action. HTTPS endpoint disclosure is component-based, exact-target digest approved, queries/
userinfo/escapes forbidden, private credential **reference** only (never value). Mutation never probes
an arbitrary URL. Unbound imported profiles remain blocked; activation does not clear the block or
retarget schedules/durable work. Deleting the last profile is rejected.

Host and native schedules are different stores/authorities. Host schedule contains a recipe revision,
opaque host destination, explicit calendar/timezone, cadence, wall time, lookback and catch-up policy.
Native schedule uses a native destination reference instead. Unsupported native cadence rejects without
approximation; enabled imported intent is never automatic. DST gap = skip; fold = first occurrence.
Catch-up = skip or one latest complete window. Run identity is hash of schedule ID/revision, recipe
revision and exact scheduled civil occurrence (including offset); persist it before any request. Unknown
outcomes resume that existing job before replacement. No arbitrary cron/systemd/shell MCP interface.

Native pending recovery retains original credential/destination/scope authority. `discard_pending` names
its exact pending-binding digest and needs separate approval; update governs future work only. B16's
pre-capture Android credential pin remains a gate before expanding native API recovery. Scheduling
never grants unattended HealthKit access: iPhone new work needs foreground/protected data; Android
needs an already-active user-started service after first unlock, not hidden health readers.

## Source-aware query and projection rules (B05 / B08)

Fixed operations: metric catalog, metric series/charts, sleep-session listing, workout listing, coverage,
period comparison, workout/sleep alignment, source-record evidence listing, factual packets. No arbitrary
query language, causal/diagnostic/therapeutic interpretation. Use [reviewed source semantics](source-review.md).

This edition resolves explicit metric IDs before health reads; broad categories/all-metrics require
catalog resolution by the client and are rejected by the fixed query decoder. `source_id`, `provider_id`,
source+host installation, catalog digest, exact/logical dates, zone, detail, operation and resource/page
bounds are all part of scope. Sources never silently fall back. Provider-native queries not in the
reviewed installed catalog are unavailable; multi-provider merged queries are not in this edition.
`all_available` means logical full authorized scope, not proof that all history is authorized.

Only explicit `native_evidence` plus `include_evidence_values` and `query_evidence` may return source
values. Summary is not permission to disclose raw records. Native record identity is provider-qualified:
Health Connect record ID/data origin/client ID/version/last-modified, HealthKit original UUID, provider
native ID, or documented external identity. Nested SDK children without native IDs are `derived_child`
with a parent identity; no fabricated native UUIDs. Exact timestamps retain nanoseconds, nullable offsets
and zero client record versions. Source strings never become paths or URLs to execute.

Values retain statistic and canonical unit. SDK aggregates are explicit native aggregate facts; do not
resum raw steps to emulate provider priority. Decimal values are strings to preserve exact decimal
meaning; integer scalars in this view are exact JSON safe integers, with checked overflow failure.
No missing, unavailable, failed, history-limited, skipped or denied value may contain a numeric zero
substitute. Available explicit zero is allowed. Comparisons require unique descriptors inside selected
metric/date scope with exact expected units; checked delta arithmetic, no saturation. Factual packets
contain scoped typed facts only, `medical_interpretation: false`.

Coverage distinguishes complete, complete-empty, partial, unavailable, failed, cancelled. History state
is full-granted/bounded/unverified/not-applicable; unknown first grant/provider capability never becomes
complete-empty. A failed sibling retains valid facts and an explicit missing reason. HealthKit read denial
may be indistinguishable from empty: retain that limitation, never assert permission-granted based on values.
Missing/source metadata arrays cap at 64, limitations at 64, with counts and truncation flags; page items
at 1,000 and 1 MiB, whole encrypted outer packet at 2 MiB. Truncation is reported, not hidden. A single
oversized item fails `query_budget_exceeded`, never silently sliced into a fabricated complete record.

Query capture is transient and produces no export files or saved-setting mutations. One active query/export
per source. Negotiated capture budgets max 120 seconds, 64 MiB compact context, 366,000 civil days;
exceeding any budget rejects with partition-scope guidance rather than exposing partial unauthorized data.
Client total traversal is bounded, cancellable, cursor-cycle protected; pages never recapture live data.

Cursor token = unpadded base64url(canonical claims) + `.` + unpadded base64url(HMAC-SHA256(native 32-byte
cursor key, `HealthMd.AgentBridge.SourceQueryCursor.v1` + NUL + canonical claims)). Claims bind source+host,
query fingerprint (request without request ID and cursor, retaining **all** other controls), dataset/catalog
digests, authority revision, position, issuance/expiry and random nonce. Keys are native-protected and
independent of pairing/channel keys. Claims reveal no health values or dates and tokens never enter logs.
Verify MAC constant-time before decoding claims; reject noncanonical/padded token forms. Snapshot max
lifetime one hour, inactivity max ten minutes (both clamped); absolute expiry never slides. Cancellation,
revocation, restart/snapshot eviction or expiry destroys continuation; no silent recapture. Phone background
clears iPhone transient snapshots; Android service stop clears Android snapshots. Supported locked-screen
service sessions may continue after first unlock; no boot/force-stop bypass. Cancellation acknowledgement
is bound to request/scope/dataset and clears the snapshot.

B08 projection requests use explicit source-native objects/field **IDs**, not arbitrary JSON pointers.
Summary/selected-series/native-record detail is orthogonal to daily formatting and native archives.
`source_data_projection/1` is always `is_complete_daily_document: false`; it never relabels Android records
as Apple daily/HealthKit records or frozen Android v4/v5. Strict partial acceptance defaults false; receipts
cover every requested day/branch before exposure. B08 must use the durable v4 job/manifest/commit boundary
for artifacts and exact-resume, not this transient query paging cache. The schema enables a bounded
projection envelope; production capture/selector/profile evidence and Kotlin/Rust artifact validation
remain B08 gates.

## Verification and promotion

Run `python3 packages/contracts/validate.py` and
`python3 -m unittest discover -s packages/contracts -p 'test_validate_agent_bridge.py'`.
The oracle is executable reference validation for synthetic proposals, not installed producer behavior,
filesystem race proof, native permission proof or shared evaluator implementation. Native generation and
all consumers must satisfy [the conformance plan](conformance.md) before any implementation/availability
claim. Coordinator-owned registry capability-index regeneration is still required after integration;
no frozen setup/semantic fixtures or metric rows are changed here.
