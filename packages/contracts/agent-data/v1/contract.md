# Health.md Agent Data v1

## Status and scope

`healthmd.agent_data_grant` v1, `healthmd.agent_data_query` v1, and
`healthmd.agent_query_response` v1 define Health.md's read-only data surface for AI agents.
They do not define an analysis service, a diagnosis service, a write-back API, or a new health
export schema.

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
