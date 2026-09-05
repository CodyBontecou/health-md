# Health.md Agent Data v1

## Status and scope

`healthmd.agent_data_grant` v1, `healthmd.agent_data_query` v1, and
`healthmd.agent_query_response` v1 define Health.md's read-only data surface for AI agents.
They do not define an analysis service, a diagnosis service, a write-back API, or a new health
export schema. `healthmd.agent_data_ingest` v1 and `healthmd.agent_ingest_response` v1 add the
separate phone-to-gateway upload contracts; see [Ingestion](#ingestion).

The source artifacts remain the frozen Apple and Android JSON or NDJSON contracts that produced
them. Agent Data v1 indexes those artifacts without rewriting them. A returned common-data value
is the value at the reported JSON pointer. A returned lossless value is the complete source record
at the reported locator. Exact whole-artifact reads return the original stored bytes.

## Authorization

One grant applies to one configured data store. Effective access is always the intersection of:

1. records present in the configured store;
2. the grant's metric, source, owner-date, instant, detail-level, and bulk-download policy; and
3. the filters in the agent's request.

Every request is authorized again at read time. Catalog results contain only granted data. A
scoped instant grant excludes records that do not carry a parseable instant; owner-date-only daily
values remain available through the independent date gate. A source record attributed to multiple
metric IDs is returned only when the grant permits every attributed metric ID.

`all_available` is an explicit grant value, not an implicit default. Exact whole-artifact reads
require `bulk_download: true` and unrestricted metric, source, date, and instant selections plus
both `common` and `lossless` detail levels. This prevents a mixed artifact from bypassing a
record-level grant.

`source_id` is an opaque, catalog-discovered provenance namespace supplied by the reader. V1
directory readers use the source export schema for common and Apple lossless records,
`provider:<provider-id>` for provider sidecars, and the raw schema for Android raw records. A
consumer must not guess source IDs from display labels.

## Metric identity

Agent Data v1 does not invent cross-platform semantic equivalence.

- Common daily JSON fields use a schema-qualified JSON pointer, for example
  `healthmd.health_data#/activity/steps`.
- Apple lossless records use their exact metric attribution, for example
  `healthmd.healthkit_records#metric:heart_rate_avg`.
- Android raw records use their exact wire type, for example
  `healthmd.raw-snapshot#wire:steps`.

Agents discover these identifiers with `healthmd_data_catalog` and return them unchanged. A later
unified health-data schema may add shared semantic aliases without changing these v1 identities.

## Fixed MCP operations

- `healthmd_data_catalog`: list granted metrics, sources, layers, and coverage.
- `healthmd_data_records`: list granted records with bounded inline values.
- `healthmd_data_record_read`: read one authorized oversized record as bounded JSON byte chunks.
- `healthmd_data_artifacts`: list whole artifacts only when the grant permits bulk download.
- `healthmd_data_artifact_read`: read exact authorized artifact bytes in bounded chunks.

Every operation uses opaque, query-bound, index-bound cursors. A cursor from an older index or a
different request is rejected. Responses are factual data and provenance only. They never contain
trends, comparisons, recommendations, or conclusions.

The response receipt identifies the backing class as `directory`, `database`, or `object_store`;
this changes storage provenance, not query or authorization semantics.

## Stored revisions and cleanup

V1 readers are append-safe and non-destructive. They may index complete or explicitly partial
daily exports, but reject structurally incomplete raw snapshots and raw-change archives. They do
not delete, rewrite, repair, or promote source artifacts. Supersession and cleanup policy are
outside this contract.

## Ingestion

`healthmd.agent_data_ingest` v1 and `healthmd.agent_ingest_response` v1 define the
phone-to-gateway upload surface. One ingestion protocol serves managed cloud, convenient
bring-your-own, private bring-your-own, and self-hosted gateways. The phone uploads exact
existing Health.md artifacts; the gateway validates and stores them unchanged. V1 defines no
third-party schemas, no producer-side transformation, and no transport; the HTTPS transport and
gateway implementation are later cycles. Promotion in gateway stores does not change the
append-safe, non-promoting behavior of local V1 directory readers.

An upload is one artifact described by one manifest, `agent-data-ingest.schema.json`, carrying:

- the artifact's own schema identity and a concrete schema version;
- the artifact kind, source platform, physical format, and media type;
- the owner-date partition identity the artifact belongs to;
- the byte length and SHA-256 of the exact uploaded bytes;
- an optional record count the phone may declare as a cheap manifest/bytes consistency aid; and
- completeness: `complete`, or `partial` with an explicit finalization marker and the covered
  owner dates.

`record_count` is INFORMATIONAL in v1. The phone MAY declare it, and ingestion attaches no
v1 semantics to it: cross-checking a declared count against the stored artifact is deferred to
the gateway implementation cycle and must not add a new rejection code or reinterpret any of the
four existing ones.

Artifact uploads are bounded to 64 MiB, matching the read model's JSON artifact bound. NDJSON
uploads remain subject to the read model's 2 MiB line bound during content validation. The
recognized kinds are the read model's standalone artifact families: `health_data_daily`,
`external_provider_daily`, `raw_snapshot`, and `raw_changes`. `raw_snapshot` and `raw_changes`
artifacts must be uploaded as `complete`; structurally incomplete raw artifacts are rejected.
Embedded `healthkit_records` are not a standalone upload kind; they ride inside lossless daily
exports.

The gateway accepts complete artifacts that validate, and accepts finalized, schema-valid
partial daily exports only when the manifest carries the explicit partial status and integrity
metadata. It rejects truncated, transient (not finalized), checksum-invalid, and
manifest-incomplete uploads with the stable, health-free codes `truncated`, `transient`,
`checksum_invalid`, and `manifest_incomplete` in `agent-ingest-response.schema.json`. V1
defines exactly these four rejection classes.

Receipts are health-free. They carry no health values, no interpretation, no account identity,
and no paths: only the accepted or rejected outcome, the stored revision identity, and the
authoritative partition view.

### Promotion

Stored revisions group into owner-date partitions. Partition keying is settled v1 semantics:
each manifest's single `owner_date` keys the partition — the exported day for daily artifacts and
the capture day for `raw_snapshot` and `raw_changes` artifacts. Splitting one artifact across
multiple date partitions would change these semantics and requires a versioned contract change.
Within a partition, the newest complete accepted revision is authoritative. A partial revision
never displaces a complete one: while a complete revision exists it remains authoritative and
any stored partial shadows nothing. When
no complete revision exists, the newest accepted partial is authoritative and is always
reported with its explicit partial status and covered owner dates, so partial coverage is never
concealed from agents. The stored revision identifier is the SHA-256 of the stored artifact
bytes, identical to the `artifact_id` the read model reports.

### Non-destructive v1

V1 ingestion implements promotion and health-free receipts only. Gateways must not delete,
purge, or rewrite stored revisions, and V1 makes no retention decisions; retention policy is not
yet user-confirmed and remains deferred to a later contract version.
