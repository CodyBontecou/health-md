# Agent Data store

`healthmd mcp serve-data` exposes an explicitly configured directory of Health.md exports to a
local MCP host. It is a separate, five-tool, data-only surface. It does not pair with a phone, run
HealthKit or Health Connect queries, interpret health values, or write to the source directory.

This is the first local implementation of the storage-neutral `ArtifactStore` boundary. A hosted
Cloudflare implementation can use the same grant, query, response, and MCP operation contracts;
upload/synchronization, accounts, OAuth, retention, and marketplace packaging are not implemented
by this command.

## Start the server

Create a grant outside the export directory. Paths must be absolute:

```json
{
  "schema": "healthmd.agent_data_grant",
  "schema_version": 1,
  "metrics": {
    "type": "explicit",
    "metric_ids": ["healthmd.health_data#/activity/steps"]
  },
  "sources": { "type": "all_available" },
  "dates": {
    "type": "exact",
    "start_date": "2026-01-01",
    "end_date": "2026-12-31"
  },
  "times": { "type": "all_available" },
  "detail_levels": ["common"],
  "bulk_download": false
}
```

Inspect the offline tool contract, then run the stdio server:

```bash
healthmd mcp schema --data
healthmd mcp serve-data \
  --directory /absolute/path/to/healthmd-exports \
  --grant /absolute/private/path/agent-data-grant.json
```

An MCP host configuration uses the installed `healthmd` executable with these arguments:

```json
{
  "command": "/absolute/path/to/healthmd",
  "args": [
    "mcp",
    "serve-data",
    "--directory",
    "/absolute/path/to/healthmd-exports",
    "--grant",
    "/absolute/private/path/agent-data-grant.json"
  ]
}
```

The default rebuildable index is kept in Health.md's private application-data directory, outside
the export tree. `--index /absolute/private/path/index.json` selects another external index path.
The source directory, grant, and index may not be symlinks into ambiguous locations.

## Read model

The server recognizes these existing artifacts without rewriting them:

- Apple or Android daily `health-data` JSON, alone, in an array, or inside a
  `healthmd.api_export` envelope;
- Apple `healthmd.healthkit_records` v1 records embedded in a lossless daily export;
- API v2 `healthmd.external_provider_daily` sidecars;
- complete Android `healthmd.raw-snapshot` v1 JSON or NDJSON; and
- complete Android `healthmd.raw-changes` v1 JSON.

Unsupported files are ignored. Malformed candidates and incomplete raw artifacts are counted in
`doctor` diagnostics but are never made queryable. JSON artifacts are bounded to 64 MiB; NDJSON
lines are bounded to 2 MiB. Scans skip symlinks, stop at 10,000 candidate files and 32 directory
levels, and rebuild the external index when the source fingerprint changes. Every source record or
artifact chunk is verified against its indexed SHA-256 before it is returned.

Start with `healthmd_data_catalog`. V1 metric identifiers preserve their source grammar:

- common values: `healthmd.health_data#` plus an RFC 6901 JSON Pointer;
- Apple lossless values: `healthmd.healthkit_records#metric:` plus exact exported attribution; and
- Android raw values: `healthmd.raw-snapshot#wire:` or `healthmd.raw-changes#wire:` plus exact wire
  type.

V1 deliberately does not claim that similar Apple and Android values are semantically equivalent.
The catalog is the authoritative way for an agent or grant editor to discover identifiers and
source IDs present in a store.

## Authorization behavior

One grant governs the configured store. Every catalog and record read is intersected with its
metric, source, inclusive owner-date, half-open instant, and common/lossless gates. Records with
multiple metric attributions require all of those metrics to be granted. An exact instant gate
excludes records without a parseable instant; an owner-date gate remains independently useful for
daily summary values. The grant is loaded and validated when the server starts; restart the MCP
server after intentionally replacing it.

Whole-artifact listing and download are stricter because one file can mix many metrics and layers.
They require all metric, source, date, and time selections to be `all_available`, both detail
levels, and `bulk_download: true`. Returned chunks preserve the original bytes and SHA-256.

The fixed surface contains only:

- `healthmd_data_catalog`
- `healthmd_data_records`
- `healthmd_data_record_read`
- `healthmd_data_artifacts`
- `healthmd_data_artifact_read`

There are no status, pairing, export, filesystem path, SQL, shell, diagnosis, recommendation, or
write tools. The phone and original export artifacts remain the sources of truth.

The normative language-neutral contract is
[`packages/contracts/agent-data/v1/contract.md`](../../../packages/contracts/agent-data/v1/contract.md).
