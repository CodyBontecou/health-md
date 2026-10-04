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
only specific controls, and must advertise that honestly. Absent features reject locally before reads.
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
for sorting/fingerprints. V4 is not Swift associated-value `_0` encoding. Fields/enums are snake_case,
UUIDs are lowercase v4 text, timestamps whole-second RFC3339 UTC `Z`. Required fields must exist.
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
| `execute_request`, `execution_receipt` | `agent_execute_request`, `agent_execution_receipt` |
| `cancel_request`, `resume_request` | `agent_cancel_request`, `agent_resume_request` |
| `artifact_manifest`, `commit_receipt` | `agent_artifact_manifest`, `agent_commit_receipt` |
| `control_request`, `control_receipt` | `agent_control_request`, `agent_control_receipt` |
| `query_request`, `query_response` | `source_query_request`, `source_query_response` |
| `query_cancel`, `query_cancelled` | `source_query_cancel`, `source_query_cancelled` |
| `projection_request`, `projection_response` | `source_projection_request`, `source_data_projection` |
| `rejected` | `agent_error` |

Unknown types fail closed. `source_query` includes independently discovered `metric_catalog`,
`metric_series`, `sleep_session_listing`, `workout_listing`, `coverage`, `period_comparison`,
`workout_sleep_alignment`, `source_record_listing`, `derive_packet`. Fixed CLI/MCP tool names can map
these operations; no generic dispatcher or arbitrary query language is added. Android must not receive
Swift v3 `queryRequest` bytes. Existing iPhone `healthmd.query_* /1` results cannot be relabeled without
an explicit v4 source adapter/availability review.

## Configuration → execution → durable transfer

1. Discovery/settings reads are read-only. Host validates and privately binds its native destination.
2. `plan_request` resolves configuration only. `all_available` does not invoke earliest-health-date reads;
   no exact target promise until explicit dates are provided. No content preview/quota/grant/wake mutation.
3. Host obtains scope-specific stored approval. Source checks stored native/host authority references;
   pairing and possession of JSON never mint configuration or export rights.
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
New native products (projection/dictionary/ZIP) require appropriate validators, not Apple raw relabeling.

`resume_request` must exactly match the accepted peer/destination/request/manifests/frontier. Already
committed descriptors are byte-identical only. Pending bytes are disposable; committed output is not.
Expiry/cancellation/revoked authority and missing spool fail honestly. Lost final delivery replays the
preserved artifact and commit receipts without new reads. A local timeout or MCP cancellation stops
waiting only; durable source cancellation requires `cancel_request` scope/authority verification and
source-acknowledged `execution_receipt: cancelled`.

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
