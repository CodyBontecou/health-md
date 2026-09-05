# Agent Data store

`healthmd mcp serve-data` exposes an explicitly configured local store of Health.md exports to a
local MCP host. It is a separate, five-tool, data-only surface. It does not pair with a phone, run
HealthKit or Health Connect queries, interpret health values, or write to the source directory.

Two local backing stores implement the same storage-neutral `ArtifactStore` boundary with
identical grant, query, response, and MCP operation contracts: an export directory and a
Health.md-owned SQLite database. A hosted Cloudflare implementation can use the same grant,
query, response, and MCP operation contracts; upload/synchronization, accounts, OAuth, retention,
and marketplace packaging are not implemented by these commands.

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

An MCP host configuration uses the installed `healthmd` executable with these arguments (substitute
`"--database", "/absolute/private/path/agent-data.sqlite"` for the directory arguments to serve
an imported SQLite database):

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

## SQLite database backing

The second local backing store is a single Health.md-owned SQLite database. It stores the EXACT
artifact bytes plus indexing metadata (metric IDs, source IDs, owner dates, instants, detail
levels, record locators, SHA-256 identities, schema identity, and capture completeness) and
exposes the identical five-tool contract; response receipts report the backing class `database`
instead of `directory`, which changes storage provenance only — not query or authorization
semantics.

Create and populate the database from a directory of recognized exports. The database path must
be absolute and live outside the import directory:

```bash
healthmd data import \
  --database /absolute/private/path/agent-data.sqlite \
  --directory /absolute/path/to/healthmd-exports
```

Then serve it instead of the directory:

```bash
healthmd mcp serve-data \
  --database /absolute/private/path/agent-data.sqlite \
  --grant /absolute/private/path/agent-data-grant.json
```

`--database` and `--directory` are mutually exclusive and exactly one is required; `--index`
only applies to directory backing because the database owns its index internally. The grant must
be a regular non-symlink JSON file stored outside the database file.

Import semantics are non-destructive by design:

- Idempotent: re-importing identical bytes creates no duplicate rows; the import receipt counts
  them as duplicates and the store revision is unchanged.
- Append-only: recognized artifacts are inserted with their exact bytes; ignored (unrecognized)
  and invalid (malformed or incomplete) files are counted in the receipt and in `doctor`
  diagnostics, never made queryable.
- Supersession bookkeeping without deletion: when a path's bytes change, the new artifact is
  appended and the observation is recorded; the previous artifact and its payloads remain
  stored and queryable. No deletion, purge, or rewrite is ever performed — retention stays
  user-controlled.

The database schema is versioned with `PRAGMA user_version` (currently 1) plus an `application_id`
file marker, with a forward-migration path for future versions; a database created by a newer
Health.md version is rejected rather than misread. Serving opens the database read-only. Every
record value, record chunk, and artifact chunk is verified against the stored SHA-256 before any
bytes are returned; a corrupted payload row surfaces as a `healthmd_agent_store_corrupt` error
and as a `sha_mismatch_count` diagnostic in `doctor`, never as silent data. `doctor` additionally
reports the schema version, a SQLite `quick_check` result, and supersession counts.

Import is storage-side only: grants are not consulted during import and apply only when the
database is served.

## Transports

`stdio` is the default transport and stays byte-identical: one JSON-RPC 2.0 document per
`\n`-terminated line on standard input/output, exactly as MCP hosts configure it today.

Builds that compile the shared Streamable HTTP transport (the `streamable-http` feature; the
`oauth-resource-server` feature implies it) can serve the *identical* five-tool catalog, grant
enforcement, response contracts, and session handling over Streamable HTTP on a loopback
listener — the same transport the direct `mcp serve-http` surface uses:

```bash
healthmd mcp serve-data \
  --serve-transport streamable-http \
  --bind 127.0.0.1:8787 \
  --directory /absolute/path/to/healthmd-exports \
  --grant /absolute/private/path/agent-data-grant.json
```

`--serve-transport` selects `stdio` (default) or `streamable-http`; the flag is named
`--serve-transport` because the root `--transport` option selects the direct mobile connection
(`manual-ip`/`nearby`) and applies globally to every subcommand. `--bind` (default
`127.0.0.1:8787`), `--allowed-host`, and `--allowed-origin` carry the same names, defaults, and
validation as the direct HTTP surface. The listener binds loopback only, accepts loopback Host
values by default, and rejects any browser `Origin` until explicitly allowlisted; a hosted
deployment terminates TLS in a co-resident reverse proxy instead of exposing this listener.
`--directory`/`--database` exclusivity and grant validation are unchanged by the transport
choice, the store opens only after the listener policy validates, and no fallback exists
between the data and direct surfaces over either transport.

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
