# Direct extension v4 — agent bridge and Android source queries

Status: **deferred foundation**. No installed producer advertises or implements this version yet.
B01/B05 define bytes here before B06-B14 native/client work. This does not expand frozen CLI 1.0 scope.

Normative [closed envelope schema](envelope.schema.json), [agent/query semantics](../../agent-bridge/v1/contract.md),
[synthetic byte candidates](../../agent-bridge/v1/fixtures/conformance.json), and
[required native-generation gates](../../agent-bridge/v1/conformance.md).

## Independent negotiation without old unknown cases

Keep pairing selectors 1/2/3, transcript/domain strings, deployed role `macos_cli`, TCP 17647,
`u64be(length)||JSON`, 2 MiB outer bound, `HMDSC001` secure sequence, and `HMDDIRCT` frame version 1.
No pairing selector 4, new encryption, endpoint, notification or credential enrollment is introduced.

The existing Swift-shaped hello uses **only existing fields**. New peers may add integer `4` to its
existing `protocolVersions` array (Apple `[1,3,4]`, Android `[2,4]`, portable host `[1,2,3,4]`). Do NOT add
an `agentBridge`/query field to an old Android hello: its `DirectJson.ignoreUnknownKeys = false` decoder
rejects unknown properties. Source review checked both native and Rust hello decoders.

B06/B09 clients must change version dispatch deliberately: select/retain base application **1 for Apple,
2 for Android** for deployed controls; independently intersect `4` as an extension. Do not use the old
highest-version selector to reinterpret application 2 as 4. Existing Apple query extension 3 is negotiated
separately. A peer without `4` never receives any v4 discriminator, even a discovery probe. Missing Android
base 2 still fails closed; no downgrade to Apple v1. Existing old stored jobs use their original base wire.

Only after authenticated matching hellos both include 4 may host send a v4 `discovery_request`. Source
returns v4 `discovery_response` with `healthmd.agent_discovery/1`. Feature tokens, exact output profiles,
settings policies, query operations, capability revision/digest, native actions and resource limits are
then independently intersected. Advertising 4 alone is **not** support for every feature. Source discovery
must match authenticated source/host identities. A source may implement only planning, only query, or
only specific native controls, and must advertise that honestly. Discovery also returns a bounded list
of sanitized source-owned stored authority references; it never returns a bearer grant, host root or
secret. An empty reference list requires native authorization before first planning. Host-owned authority
references come from the host private-store catalog, not phone discovery. Absent features reject locally before reads.
Android `source_hello` and its existing v2 products remain separate and byte-compatible.

| Peer | Behavior |
|---|---|
| Old Apple / new host | Application v1 and advertised iPhone query v3 only |
| Old Android / new host | Application v2 only; typed query/explicit settings unavailable |
| New phone / old host | Existing hello shape; no v4 payloads; old operations only |
| Android / source query v4 host | Base v2 plus independently discovered `source_query` and supported operations |
| Apple / bridge v4 host | Base v1 plus independently discovered agent controls; iPhone v3 queries unchanged |
| Pairing selector 3 only | No implication of source platform, query v3, bridge v4 or authority |

## Exact v4 bytes

Each inner control document is canonical UTF-8 JSON:

```json
{"protocol_version":4,"type":"discovery_request","payload":{"schema":"healthmd.agent_discovery_request","schema_version":1,"request_id":"00000000-0000-4000-8000-000000000064","peer":{"source_installation_id":"00000000-0000-4000-8000-000000000001","host_installation_id":"00000000-0000-4000-8000-000000000002","platform":"android"}}}
```

The example is readable rather than key-sorted; canonical byte candidates in the fixture are normative
for sorting/fingerprints. V4 is not Swift associated-value `_0` encoding. Fields/enums are snake_case.
Control/installation UUIDs are lowercase v4 text; native source UUIDs retain their source identity in
canonical lowercase form without forcing version 4. Control timestamps are whole-second RFC3339 UTC `Z`.
Source times additionally declare precision (Instant nanos vs Date binary64 vs provider millis/seconds),
retaining checked normalized seconds/nanos and exact Date bits, never invented metadata timestamps.
Required fields must exist.
Absent optional members are omitted, not null; only exact source offsets explicitly admit null.
Metadata numbers are JSON integers, never Boolean-as-integer or floats. Typed measured decimals are
strings. Reject duplicate JSON keys, unknown fields, nonfinite values, invalid Unicode scalars and
excess depth/nodes/strings before constructing typed objects. Bounds are in agent v1; schema references
are local and offline, not fetchable remote authorization.

Canonical JSON = recursively key-sorted, compact, unescaped Unicode and `/`, no normalization and no
trailing LF in fingerprint input. Array order is normative (sorted unique sets, explicit presentation
order retained). SHA-256 is lowercase hex. Wire outer encoding/framing remains deployed v1.

## Closed message list

| `type` | Payload schema / 1 |
|---|---|
| `discovery_request`, `discovery_response` | `agent_discovery_request`, `agent_discovery` |
| `plan_request`, `plan_response` | `agent_plan_request`, `agent_export_plan` |
| `approval_request`, `approval_response` | `agent_approval_request`, `agent_approval` |
| `execute_request`, `execution_receipt` | `agent_execute_request`, `agent_execution_receipt` |
| `cancel_request`, `resume_request` | `agent_cancel_request`, `agent_resume_request` |
| `artifact_manifest`, `commit_receipt` | `agent_artifact_manifest`, `agent_commit_receipt` |
| `control_plan_request`, `control_plan_response` | `agent_control_plan_request`, `agent_control_plan` |
| `control_approval_request`, `control_approval_response` | `agent_control_approval_request`, `agent_control_approval` |
| `control_request`, `control_receipt` | `agent_control_request`, `agent_control_receipt` |
| `query_request`, `query_response` | `source_query_request`, `source_query_response` |
| `query_cancel`, `query_cancelled` | `source_query_cancel`, `source_query_cancelled` |
| `rejected` | `agent_error` |

Unknown types fail closed. `source_query` includes independently discovered `metric_catalog`,
`metric_series`, `sleep_session_listing`, `workout_listing`, `coverage`, `period_comparison`,
`workout_sleep_alignment`, `source_record_listing`, `derive_packet`. Fixed CLI/MCP tool names can map
these operations; no generic dispatcher or arbitrary query language is added. Android must not receive
Swift v3 `queryRequest` bytes. Source-specific native identity branches omit unsupported client/version/
last-modified metadata, require explicit availability states and retain exact case-sensitive SDK/HK type
identifiers separately from semantic IDs. Date's binary64 precision is not relabeled Instant nanosecond
precision; see the agent v1 source evidence and timestamp round-trip rules. Existing iPhone `healthmd.query_* /1` results cannot be relabeled without
an explicit v4 source adapter/availability review.

## Configuration → execution → durable transfer

1. Discovery/settings reads are read-only. Source lists only references to already stored native
   delegation/inspection authority. Host obtains its separately stored output authority and **previously**
   registered private destination binding locally. Pairing alone authorizes neither store. Planning cannot
   register roots/grants, allocate credentials, mutate settings or enroll wake.
2. `plan_request` names the discovered native authority ID/revision, host authority reference and intent.
   Both owners look up their private records and check bounded export delegation before pure scoped
   authority derivation. The result plan/binding pins both references; no new authority ID is minted.
   This resolves configuration only. `all_available` does not invoke earliest-health-date reads;
   no exact target promise until explicit dates are provided. No content preview/quota/grant/wake mutation.
3. `approval_request` carries issued plan ID and full binding. Issuer checks the **separately stored**
   exact human/policy decision and returns `approval_response`, never grants authority just because the
   request arrived. Each owner verifies its own stored authority. Source-native and host output scopes
   are independently derived within existing delegation bounds; host JSON cannot mint native rights.
   Future in-bounds scopes/already approved host destinations require new plans/approvals/jobs, not phone
   setting edits. Outside bounds requires separate human authorization. Configuration grants are never
   derived from export delegation.
4. `execute_request` carries the exact plan/approval, idempotency key and job ID. Source validates
   revisions/bindings/actions and journals acceptance before capture. `execution_receipt: accepted` pins
   the exact v4 request digest and binding. Creation/expiry are seven-day native job state.
5. Source emits the v4 `artifact_manifest` with v4 binding/request digest and exact source profile bytes.
6. Transfer uses **unchanged base control messages**: Apple v1 `transferSession`/`fileManifest` and
   partition controls; Android v2 `transfer_session`/`artifact_manifest` and partition controls. The
   existing request-fingerprint fields carry SHA-256 of canonical **v4 execute request** for this v4
   accepted job. Its durable journal pins `request_contract: healthmd.agent_execute_request/1` internally
   so validators cannot mistakenly recompute a v1/v2 request hash. V4 adapter cross-checks base manifests
   against every overlapping v4 manifest field (IDs, paths, byte counts, digests, write modes; profile/
   schema only where the base manifest exposes them). V4 remains the authority for metadata absent from
   base v1 manifests. No unknown fields are added to any base message. Frames, partition chain, windows and final acknowledgement remain v1.
7. Host validates every partition/artifact and commits handle-relatively with durable digest-bound commit
   plans/receipts. Source completion confirmation plus exact manifest/frontier enables terminal v4 receipt.

This is a new adapter path, not permission to pass an unvalidated v4 request through an old raw receiver.
No silent v4-to-v1/v2 request conversion: unavailable feature rejects, preserving old peers/bytes/jobs.

B08 projection is an explicit `agent_export_intent.product: source_projection` with product ID
`android_source_projection_v1`, full selector request and explicit projection output. Daily settings
policy is forbidden in that branch. Discovery advertises its product and frozen selector-catalog digest
separately, including a health-free `projection_source_catalog` with zero queried-day/value/missing
counts (no query privilege or health lookup required). Object/field/detail IDs, both catalogs and output
settings bind the scope/plan/approval and canonical **full v4 execute fingerprint**. Selector DTOs alone are not execution; draft standalone
`projection_request`/`projection_response` messages are removed before native conformance.

Persist `agent_projection_job/1` acceptance and exact execute/fingerprint/catalog snapshots **before**
health reads, then freeze the captured spool and v4 manifest. V4 `execution_receipt: accepted` is the
only product acceptance; do not synthesize v2 `export_request`/`export_accepted` with
`generated_files_v1`, reserved `android_daily_records_v1` or raw-snapshot selectors. V2 generic transfer
session carries the v4 digest, and its unchanged generic artifact descriptor uses `kind: generated_file`
and `schema: {id: healthmd.source_data_projection, major: 1}`. That file-carriage kind is not a product
identity. No new fields/enums/frames are inserted into the base protocol. Cross-check base IDs/path/
mode/count/digest/schema against v4 metadata; v4 remains authority for new profiles and approved scope.

Projection `selected_series` retains intraday source-observation identity, timestamp/precision,
point/interval role and native value key. It is never daily `metric_series`/aggregate facts. Per-day
projection artifacts preserve original record/sample timestamps; no inferred point end or parent
client/last-modified metadata. B08/B09 native tests must trace exact selectors through approval,
pre-read acceptance, capture journal, base transfer, append commit and resume without recapture,
preference lookup or transient-cache dependence; missing spool requires a fresh approved job.
New native products (projection/dictionary/ZIP) require appropriate validators, not Apple raw relabeling.
`android_source_projection_v1` uses manifest profile `android-source-projection-v1` and only
`healthmd.source_data_projection/1`: one canonical LF-terminated JSON document (`application/json`,
overwrite only) or owner-date LF-terminated projection lines (`application/x-ndjson`, explicit `per_day`
layout, overwrite/append). Cross-check all source/request/detail/scope/coverage fields and exact byte count/digest
from preserved artifacts before exposure or replay. This is not an Android v4/v5/HealthKit/raw profile.

`resume_request` must exactly match the accepted peer/destination/request/manifests/frontier. Already
committed descriptors are byte-identical only. Pending bytes are disposable; committed output is not.
Expiry/cancellation/revoked authority and missing spool fail honestly. Lost final delivery replays the
preserved artifact and commit receipts without new reads. A local timeout or MCP cancellation stops
waiting only; durable source cancellation requires `cancel_request` scope/authority verification and
source-acknowledged `execution_receipt: cancelled`.

## Closed configuration planning and approval relay

V4 relays native profile/destination/schedule controls. Host recipe/schedule stores use the same closed
DTOs **locally**; a phone must reject those host-store operations rather than implementing a remote
filesystem/scheduler dispatcher. Native discovery must not advertise host-owned operations as phone RPC.

`control_plan_request` carries a fixed typed candidate proposal; the `control_request` domain `plan`
branches (including native profile) normalize to that same request. The response freezes the exact
proposal, required right, peer, sorted target/dependency/credential-reference revision pins, capability
digest, ten-minute expiry and eight integer-zero side-effect counts. No health/earliest-date/preview,
quota/output/settings/credential/wake work is allowed. Missing grants are required native actions only.

`control_approval_request` references the exact issued binding and optionally an existing authority ID.
If omitted, only a **previously stored** native decision/grant for that exact binding may be selected; no
JSON request creates one or remotely unlocks Configuration Protection. Return stored
`control_approval_response` with its native authority ID/revision/digest only after issuer/grant/plan/
revision/protection/consent/entitlement checks. This is how the host learns a per-candidate mutation
reference that was not previously listed in discovery. Mutation `control_request` includes **full plan + approval + identical proposal fields** and an
idempotency key, not a lone approval ID. Any candidate/target/credential/cadence/profile/peer/capability
change requires new planning/approval. The read planning authority can differ from the native mutation
authority; no export authority is upgraded. Human native authorization is an implementation gate, not a
new grant-creation message. Mutations produce bound receipts; exact accepted retries replay stored
receipts without reapplying configuration, including after expiry or revision advance.

The control scope digest covers `{peer, proposal, revisions}`; proposal digest covers the entire closed
proposal; plan digest excludes only its own digest. `control_binding` pins plan ID, peer, all these
digests, capability digest, revisions and expiry. The same fields are echoed in approval and mutation
receipt. Unknown IDs/rehashing client JSON cannot create issued records; pending recovery always keeps
its original authority. Native/configuration implementation and zero-call tracing are **not run** here.

Query capture/continuation is transient, not durable export resume. Query-cancel acknowledgement binds
request, peer, dataset and scope; expiry/background/service stop/restart clears snapshots. No signed
cursor can cause recapture against a different dataset. Resource budgets and cursor MAC format are
pinned by agent v1. Error codes are fixed and health-free, with no rejected values/parser exceptions.

## Implementation and release gates

First implement typed Rust models and native-produced vectors, then Swift/Kotlin adapters and negotiation
fake-peer tests. Do not advertise integer 4 before its installed decoder/discovery path is complete.
Require old-peer hello/query/export regression, exact new canonical/digest agreement and native authority,
path, revision, cursor, quota/zero-read tests. Preserve all historical fixtures. Native/cross-platform
physical and consumer tests remain explicitly not run in this foundation; see
[conformance and integration instructions](../../agent-bridge/v1/conformance.md).
