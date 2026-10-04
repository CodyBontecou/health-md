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
| Declarative intent, plan, discovery, stored delegation references, authority, approval, receipts, control | `healthmd.agent_*` / 1 | Closed independent configuration DTOs; never Shared Setup RPC |
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
binding, explicit dates and IANA timezone, timestamp timezone `UTC`, capture scope and a closed `product`.
`generated_files` requires the daily settings policy below. `source_projection` requires its explicit
product ID, selector request and projection output; daily `settings_policy` is forbidden in that branch.
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
instants `[start-day midnight, day-after-end midnight)`, not fixed 24-hour arithmetic. Source timestamps retain a checked seconds/nanoseconds view, declared **source representation precision**
and nullable original offsets; HealthKit Date additionally preserves exact returned binary64 bits.
Nanosecond formatting is not proof of nanosecond storage or sensor accuracy. Owner timezone and source
offset are distinct.

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
wake enrollment or notification. `side_effects` explicitly counts health reads, earliest-date reads, content-preview reads, quota,
output writes, settings mutations, credential enrollments and wake enrollments; all are integer zero.
Required native actions are descriptions, not actions that the plan performs.

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

## Stored authority bootstrap (no plan-time grant creation)

The first export is expressible without a caller inventing an exact-scope grant. Two **previously
approved private stores** are prerequisites, independent of mobile export preferences:

1. On the source, a native human decision has stored a bounded `agent_export_delegation/1` for the
   authenticated source+host pair. Pairing alone is insufficient. Its closed bounds specify semantic
   metrics, calendar zones, exact date limits or authorized-history/max-day policy, formats, profiles,
   write modes, capture detail and native archive products; allowed products and projection detail/object/
   field IDs are explicit additional bounds. A generated-files grant cannot implicitly grant projection. It can grant `discover`, `plan` and
   `export_execute` only, never configuration/schedule mutation, queries or destination credentials.
2. On the host, its human/native output authorization has already stored a separate export delegation
   and registered private destination roots. The source-approved destination policy is
   `authenticated_host_bindings`; the host policy is `registered_host_bindings` with an explicit bounded
   ID list. The source does not learn roots and the host cannot manufacture source consent. Registering
   a new root is a separate host authorization step **before** planning, not a planner side effect.

`discovery.authority_references` returns only source-owned, peer-filtered stored references:
`authority_id`, `issuer: native_source`, `grant_revision`, `grant_sha256`. It may be empty; that means
native authorization is required before the first plan. No secret, credential, bearer capability,
bookmark, root or portable grant is returned. Host-owned references (`issuer: authorized_host`) come
from the host's authenticated private-store catalog, **not** source discovery. `grant_sha256` is the
canonical digest of the stored sanitized grant/delegation description at that immutable revision.
Changing any bound, revoking or replacing a grant invalidates its reference; JSON cannot register it.
A sanitized delegation description is a grammar for review, not a grant-creation request or v4 RPC.

The concrete journey is:

- Discover with the authenticated pair; select an existing native reference and a locally obtained host
  reference. `plan_request` names the native `authority_id`/`authority_revision`, host reference,
  capability digest and complete intent. Look up both references in their **issuing** private stores.
- Resolve configuration-only scope/settings and check both stored delegation bounds. This does **not**
  demand a pre-existing exact scope hash or allocate a fresh authority ID. For saved/profile policies,
  resolve only the requested configuration revision. Refuse out-of-bounds choices; do not narrow them.
- Return `agent_export_plan/1` with both `authority_references`. Pure derivation of each scoped
  `agent_authority/1` reuses its parent ID/issuer/revision, pins the new scope and the single approved
  destination binding, and clamps expiry to the plan and parent expiry. The native adapter independently
  derives it from its own stored record; the host independently derives/checks its own output grant.
  Derived JSON is **not** new stored authority and cannot widen parent bounds. Current native consent,
  entitlement, trust/revocation and host output readiness remain independent runtime checks.
- `approval_request` names the issued plan and full binding. This is a request to check/relay a separately
  stored human/policy decision, not `approve: true` authorization. Source and host verify their respective
  delegation/reference and exact issued plan; the stored decision must match the binding. The issuer
  stores/returns `agent_approval/1` via `approval_response`; caller-supplied IDs/digests do not issue it.
- Execute the exact plan/approval. Check the two derived scoped authorities, both parent references,
  installed capabilities, peer/root identity, revisions, consent and entitlement before capture/commit.

A future metric/date scope or another **already host-approved** destination inside both delegations
uses a fresh request, plan, derived scope, approval and job. Neither edits phone settings nor requests
new phone destination grants. The old exact approval/derived scope cannot authorize it. Outside a
parent's bounds, a separate human delegation change is required; planning cannot do that. Unknown
IDs, copied references from another peer/issuer, expired/revoked parents and substituted root identity
fail closed. For logical `all_available`, max-day bounds are enforced only after approved execution
resolves history; overflow rejects, never silently clips. No earliest-date read is needed for delegation
checking during planning.

Native configuration is deliberately different. A bounded export delegation **never** derives
configuration authority. Native configuration-read authority has a stored `control_read_scope` (bounded
object IDs and permitted list/create domains); its scope digest is the canonical digest of that scope.
Unknown objects/list domains cannot be authorized by caller UUIDs. Read-only planning can use that
stored inspection grant while Configuration Protection is locked. Mutation requires a separate exact
candidate-scope native authority and stored native approval decision after any required native unlock.
Host recipe/schedule authorities are host-issued only; source-issued rights cannot authorize host-store
mutation and host-issued rights cannot authorize native configuration. Receiving wire references never
establishes the other issuer's trust: native verification occurs on source, host verification before local
writes. Synthetic contexts model both private stores; no new signature or portable bearer grant is added.

## Authority, approval and immutable execution

Pairing proves installation identity only. `agent_authority/1` is a **sanitized scoped description**, with explicit issuer, of a native/host-issued
stored grant or the pure bounded-export derivation above, not a bearer token or a client-authored grant. Receiving a JSON object
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
identity+revision, both issuer-owned authority references, scope/settings/plan digests,
native/profile/recipe revisions, capability digest and expiry. Canonical digest is sorted compact UTF-8 JSON (unescaped `/`, no Unicode normalization, no
floats in metadata). The plan digest excludes only its own `plan_sha256` field. Scope digest includes
resolved/logical dates, zone, capture axes, resolved metric IDs and the entire explicit product (including
projection selectors, catalog pins and output). Any change requires a new plan and
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
run-now; native schedule inspect/update/enable/disable/inspect-pending/discard-pending; native
destination inspect/update. **All five domains additionally have a typed `plan` branch**, including
native profiles. Host-owned DTOs execute in host stores locally, not as mobile RPC; v4 relays native
controls only. No generic dispatcher, display-name fallback or arbitrary file/URL execution is added.

Closed `agent_control_plan_request/1` and the domain-specific `control_request.operation.verb: plan`
branch both carry the **whole candidate `proposal`**, not just the object to inspect. A proposal has
one fixed domain/verb, stable object ID, expected revision, and full typed `value` for create/update;
discard additionally names the pending binding digest. Create preallocates a requested stable ID with
`expected_revision: 0`, requiring absence at acceptance. That ID is a target, never authority. Action
verbs bind their exact action and current object/dependency revisions rather than accepting untyped
patches. The domain-specific plan branch cannot carry a proposal for another domain.

`agent_control_plan/1` echoes the proposal, peer, request/planning-authority IDs, required mutation/run
right, capability digest, sorted unique revision pins, required native actions and eight zero side-effect
counts. It reads only authorized configuration. `proposal_sha256` is SHA-256 of canonical proposal;
`scope_sha256` is SHA-256 of `{peer, proposal, revisions}`; `plan_sha256` excludes only itself. Plan
expiry is at most ten minutes. Pin the target revision/digest (or absence), referenced profile/recipe
revisions, existing native destination revision/digest and endpoint credential-**reference** revision.
Credential rotation or capability/destination/revision changes require a fresh plan. No credential value,
SAF/bookmark access grant or external endpoint probe is part of the plan.

A zero-health configuration approval journey is now expressible:

1. A native-authorized inspection reference from discovery (or host-local inspection grant) authorizes
   `control_plan_request` with a complete candidate. Planning while protected/locked remains read-only.
2. Source/host stores the issued candidate plan identity and returns `control_plan_response`. Missing
   native bindings return required actions; no planning request performs them or unlocks protection.
3. After a **separate native** exact candidate-scope authorization/decision (host-local decision for host
   stores), `control_approval_request` names the exact binding and optionally an already-known authority
   ID. When omitted, the issuer may select **only** an already stored native/host decision/grant for that
   binding; absence means approval required, never grant creation. Receiving the request is not the
   decision. Check issued plan, current revisions, protection, consent and entitlement; record/return
   `agent_control_approval/1` via `control_approval_response` with the issuer-owned authority reference
   (ID, issuer, revision, digest). The host learns an initially unknown mutation ID from this response.
   Exact per-candidate mutation grants need not be enumerated in discovery; discovery exposes existing
   planning/delegation references, not a grant-enrollment endpoint. Native unlock or other capability
   changes require a fresh current plan before approval. A read-only/export grant cannot be reused.
   Planning-authority ID may differ from mutation-authority ID; planning never creates/upgrades either.
4. Mutation `control_request` carries full **plan and approval records**, idempotency key and exact
   proposal fields. No `approval_id`-only mutation is accepted. Match the candidate byte-for-byte,
   issued plan/approval identities, exact mutation-authority reference and rights, peer,
   revision/capability/expiry and current native gates
   before an atomic configuration transaction. Rehashing client boxes never makes an issued record.
5. A mutation `control_receipt` must echo `mutation_binding` (full control binding, approval ID and exact
   request digest), resulting revision/value digest and native actions. Read receipts omit it. Unknown
   outcomes replay the persisted receipt, never a second mutation. Index is `(authenticated peer,
   domain, object_id, idempotency_key)`; exact retries return stored receipts even after expiry/revision
   advance, while any changed bytes reject. Concurrent requests use CAS, never last-writer-wins.

Sanitized receipts return bounded typed items/revision/digest/actions, never native secrets. No health
capture occurs in a configuration transaction; recipe/schedule run authority only creates a fresh export
planning journey, not permission to bypass its export approval.

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
values. Summary is not permission to disclose raw records. Native record identity has **closed source-specific branches**, not an Android-shaped common metadata
requirement. HealthKit preserves original UUID, exact native object-type identifier and observed origin;
it omits last-modified/client-ID/client-version and explicitly reports `not_exposed_by_source` for all
three in `metadata_status`. HKSourceRevision application version and optional HK sync metadata are not
relabeled client record versions. Sample end, capture time and zero never fill an unavailable field.
Health Connect preserves its actual record ID/data origin and observed Metadata fields. Nullable client
ID is omitted with status `absent`; uncaptured metadata is omitted with `not_captured`, never invented.
Actual observed native version zero remains a value. `available` requires the corresponding member;
all other statuses forbid one. `not_captured` metadata makes evidence capture incomplete, never complete;
strict projections require explicit partial acceptance. Supported-but-unset client ID (`absent`) and
legitimately unexposed source metadata do not fabricate a failure or zero. Provider-native identity only
carries fields its reviewed source exposes.

Nested SDK children without native IDs are `derived_child` with `parent_record_id` and exact
`parent_record_type`; they carry no fabricated UUID or copied parent last-modified/client metadata.
Native/external identities omit parent members rather than using empty strings. Ordinary Health Connect
Record metadata APIs are not claimed absent; missing capture is distinct from APIs that do not expose
metadata (HealthKit, nested children, or separately reviewed external/provider products).

`record_type`, catalog `native_record_type` and dictionary `native_type` use a separate case-preserving,
1–256-character native-identifier grammar (`[A-Za-z_][A-Za-z0-9_.:$-]*`), not registry semantic-ID grammar.
Examples are `HKQuantityTypeIdentifierStepCount`, `androidx.health.connect.client.records.HeartRateRecord`
and nested `HeartRateRecord$Sample`. Android catalog identifiers are fully qualified SDK class names;
Apple identifiers are exact HKObjectType.identifier strings. Unknown/unavailable source mappings omit
native type instead of inventing another platform's API. Supported/planned catalog rows must have one.
Native types never replace `metric_id`/selector IDs and are checked against the selected source catalog.
All source/native identifier strings remain inert; they never become paths or URLs to execute.

Every source time declares `precision`: `source_nanoseconds` (actual Instant representation),
`source_milliseconds` (nanos divisible by one million), `source_seconds` (nanos zero), or
`source_binary64_seconds`. For HealthKit Date, the latter requires `source_binary64_bits`: 16 lowercase
hex digits encoding the exact big-endian IEEE-754 bits of the **returned** `timeIntervalSince1970` value.
Reject nonfinite bits. Compute total normalized nanoseconds by exact rational decoding and nearest-integer
rounding, ties to even; split with floor/divmod into epoch seconds plus nonnegative nanos. Verify that
view against the bits, retain the bits as authority for original precision, and do not claim integer-nanos
source storage. Session durations use that declared normalized view; it is not finer sensor evidence.
A last-modified time is source metadata, never substituted for measurement time. Missing original offsets
stay null, not inferred from the export zone. Native 64-bit client versions require lossless integer
parsing (including values beyond JavaScript safe integers). The [SDK/source review](source-review.md)
records the exact evidence and remaining native verification gates.

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

## B08 accepted projection product and adapter trace

`source_projection_request/1` is a **selector value**, not a health-read/preview RPC. Draft standalone
v4 `projection_request`/`projection_response` discriminators are removed before native DTO adoption.
Projection uses the same issued-plan → stored approval → v4 execute → durable transfer path as exports.
No health-data-producing endpoint accepts a selector DTO alone.

`agent_export_intent.product` is a closed union. Daily/generated files use `type: generated_files` and
existing daily output policies. Projection uses `type: source_projection`,
`product_id: android_source_projection_v1`, full `request: source_projection_request/1` and `output`:
profile `android-source-projection-v1`, media/write mode, `layout: per_day`, subfolder/folder/basename
(date tokens only). Daily `settings_policy`, saved/default settings, raw/archive product selectors and
implicit ZIP/dictionary are forbidden for this branch. Common capture selection/peer/dates/zone must
exactly match the embedded request; archive is `none`. Projection `native_records` is selected typed
source evidence, not a complete provider-native snapshot.

The [reviewed projection catalog](reviewed-projection-catalog.json) declares five **planned** bounded
field/object mappings: Steps daily aggregate, Heart Rate daily average, Steps interval count, Heart Rate
child-sample BPM, and selected Steps record evidence. Request field IDs explicitly select supported
members of requested objects; all fields/metric IDs agree. No arbitrary pointers, field reflection,
unknown-ID fallback, `all_metrics` or unresolved categories in this bounded edition. Other metrics/
provider products require separately reviewed mappings, not fabricated observations. Discovery separately
advertises `source_projection`, supported `projection_products` and the exact projection-catalog digest;
an absent feature has an empty product list/zero digest. Source-catalog and selector-catalog digests are
both pinned. Discovery supplies `projection_source_catalog` as **health-free** compiled unit/type/
permission/feature metadata (no queried days/values/missing-record counts); it needs no separate query
right or metadata health read. Absent projection omits it. The static selector catalog is not an
installed-provider or implementation availability assertion.

`metric_series` and projection `summary` remain **daily aggregate facts** (native reducer/statistic and
priority semantics). `selected_series` is instead a list of `source_observation` records: field ID,
`selection_metric_id` (authorization/attribution only, not a claim of average/sum), native property key,
point/interval role, original native/derived-child identity, actual start and interval end if exposed,
owner date, canonical unit and lossless native integer. `heart_rate.samples.bpm` is a point BPM, never
`heart_rate_avg`'s daily average. Its sample identity retains parent record ID/type and does not copy
parent modification/client metadata. Interval Steps counts retain original start/end; a point has no
invented end. Observation ID hashes its canonical record excluding only itself. Neither timestamps nor
identity may disappear into a daily metric item; do not recompute native daily aggregates from raw points.

The fixture journey `projection-product-*` / `projection-journal-*` / `projection-transfer-*` freezes:

1. Authenticated paired host + previously approved bounded source/host delegation/root references.
   **Both** delegations explicitly allow this product, detail, objects and fields. No phone settings edit.
2. Zero-health `plan_request` resolves only this explicit product. Plan returns
   `effective_projection_output`, empty saved/native setting revisions, origins for every selector/output
   leaf, resolved/logical dates, paths and eight zero side-effect counts. `settings_sha256` hashes explicit
   projection output; scope hashes the entire product as well as common capture/dates/metrics.
3. Separate stored exact decision → bound `approval_request`/response → `execute_request`. **Fingerprint
   is SHA-256 of canonical full v4 `agent_execute_request/1`**, including issued plan/approval,
   object/field/detail IDs, both catalogs, media/write/path settings, peer/root, job and idempotency keys.
   Rehashing/widening JSON is not new authority. Changed bytes require a fresh approval/job.
4. Before the first source read, durably store `agent_projection_job/1`: exact execute bytes/fingerprint,
   accepted timestamp, resolved scope and both frozen catalogs; state `accepted`, capture not started.
   Only then capture selected fields once. Persist same-job projection bytes, v4 artifact manifest,
   catalog snapshots and immutable spool. `spool_sha256` hashes canonical artifact-ID-sorted
   `{artifact_id, sha256, byte_count}` rows. Receipts cover every `object.<id>` and `field.<id>` branch
   including zero/unsupported/partial/failed states, plus every requested day via preserved coverage.
   Strict partial acceptance defaults false; bounded overflow fails, never drops dense intraday points.
5. V4 manifest binds **that** job, execute fingerprint, full approval binding and exact new profile/
   bytes/path/write mode. Base Android-v2 generic `TransferSession.request_fingerprint` carries the
   same v4 execute digest. Base `ArtifactManifest` is `kind: generated_file`,
   `schema: {id: healthmd.source_data_projection, major: 1}` and unchanged known file fields; this is
   generic file carriage, **not** a v2 `generated_files_v1` export request or daily product acceptance.
   No v2 `export_request`/`export_accepted` is synthesized for this product; v4 receipt is acceptance.
6. Existing partitions/chunks/acks/frames transfer the immutable bytes. Host cross-checks every
   overlapping base/v4 field and validates the source-shaped bytes with the frozen catalogs. V4 owns
   new profile/selector/approval metadata. Journal before/input/after digest-bound commit before append;
   replay returns `already_committed`, no second append. Final source acknowledgement makes completion.
7. Resume uses exact request/manifest/frontier and preserved spool/catalogs, not current phone settings,
   a new query snapshot, current reducer mappings or a recaptured source dataset. Expired query cache
   is irrelevant. Missing spool returns `spool_missing_restart_required`; changed fingerprint, root,
   selectors/profile, manifests or bytes reject. Job expiry/revocation still stop work without migration.

`source_data_projection/1` is always `is_complete_daily_document: false`; it never relabels source records
as Apple daily/HealthKit records, Android v4/v5/raw snapshots or reserved v2 `android_daily_records_v1`.

The independently versioned durable product is `android_source_projection_v1`; its exact
`artifact.profile` is **`android-source-projection-v1`** (kebab-case artifact IDs are not product IDs).
It maps only to `healthmd.source_data_projection` **schema version 1**, Android peer and the reviewed
Health Connect catalog in this edition (provider-native mappings remain unsupported), `is_complete_daily_document: false`:

| Artifact media type | Exact content framing | Write modes |
|---|---|---|
| `application/json` | One canonical projection document followed by one LF | `overwrite` |
| `application/x-ndjson` | Canonical projection lines with LF and unique ascending owner dates; explicit `per_day` product layout emits one owner-date document per artifact | `overwrite`, `append` |

NDJSON append is journaled once under the existing digest-bound commit contract. JSON append is rejected
rather than concatenating separate objects into an invalid JSON document. Neither media type becomes a
complete daily document. Media type is
authoritative; examples use `.json`/`.jsonl`. CSV/Markdown/ZIP media and Markdown merge are not this
projection profile. This minimal projection product does not imply ZIP/dictionary; any later container
must be explicitly approved and retain exact inner projection descriptors.
The profile is not a new frozen daily/output-settings profile: it is absent from `settings.output_profile`
and does not relabel Apple v8, Android v4/v5, HealthKit archives or Android raw snapshots.

Durable validators cross-check request/peer/source/provider/catalog/detail/owner-date/scope and selectors,
coverage/explicit partial acceptance, and exact framed bytes/count/SHA-256 against the manifest. Projection
scope digest is SHA-256 of the projection request excluding only `request_id`; all other controls remain.
Artifact verification must read preserved bytes, not recapture a transient query snapshot. JSON/NDJSON
cross-schema positive/negative vectors bind the profile to this schema, reject relabeling/expanded detail,
and preserve record/value units and identity. The metadata grammar alone is not byte validation. The schema enables a bounded
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
