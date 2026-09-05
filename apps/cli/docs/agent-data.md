# Agent Data store

`healthmd mcp serve-data` exposes an explicitly configured local store of Health.md exports to a
local MCP host. It is a separate, five-tool, data-only surface. It does not pair with a phone, run
HealthKit or Health Connect queries, interpret health values, or write to the source directory.

Two local backing stores implement the same storage-neutral `ArtifactStore` boundary with
identical grant, query, response, and MCP operation contracts: an export directory and a
Health.md-owned SQLite database. A third read-only backing serves a BYO S3-compatible
(Cloudflare R2) object store bucket prefix laid out like an export directory. A hosted
Cloudflare implementation can use the same grant, query, response, and MCP operation
contracts; upload/synchronization, accounts, OAuth, retention, and marketplace packaging are
not implemented by these commands.

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
`"--database", "/absolute/private/path/agent-data.sqlite"` to serve an imported SQLite database,
or `"--object-store-url", "https://…", "--bucket", "name"` to serve an object store prefix):

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

The database schema is versioned with `PRAGMA user_version` (currently 2) plus an `application_id`
file marker, with a forward-migration path for future versions; a database created by a newer
Health.md version is rejected rather than misread. Serving opens the database read-only. Every
record value, record chunk, and artifact chunk is verified against the stored SHA-256 before any
bytes are returned; a corrupted payload row surfaces as a `healthmd_agent_store_corrupt` error
and as a `sha_mismatch_count` diagnostic in `doctor`, never as silent data. `doctor` additionally
reports the schema version, a SQLite `quick_check` result, and supersession counts.

Import is storage-side only: grants are not consulted during import and apply only when the
database is served.

## Object store backing

The third backing is a read-only, S3-compatible object store (Cloudflare R2): a bucket prefix
you populated yourself with Health.md exports, laid out like an export directory — artifact
files under their own file names. The bucket is never written: the store issues only
`ListObjectsV2`, `HEAD` object, and `GET` object requests (path-style addressing), so there is
no upload, delete, or write path anywhere in the client. Response receipts report the backing
class `object_store`; the query, authorization, and response contracts are otherwise identical
to the directory and database stores.

```bash
healthmd mcp serve-data \
  --object-store-url https://accountid.r2.cloudflarestorage.com \
  --bucket healthmd-exports \
  --prefix exports/ \
  --grant /absolute/path/to/agent-data-grant.json
```

`--object-store-url`, `--directory`, and `--database` are mutually exclusive and exactly one is
required; `--bucket` is required with `--object-store-url` and `--prefix` optionally selects the
bucket subtree (`exports` and `exports/` both normalize to `exports/`; omit it to serve the whole
bucket). The optional rebuildable `--index` path applies to this backing exactly as it does to the
directory store, with the same private default location; the database store remains the only one
that owns its index internally.

**Credentials policy.** Credentials are read only from the environment —
`HEALTHMD_OBJECT_STORE_ACCESS_KEY_ID` and `HEALTHMD_OBJECT_STORE_SECRET_ACCESS_KEY` — and never
accepted as flags, so secret material cannot appear in `argv` or process listings. Missing or
empty variables fail at open with a stable health-free error before any request is sent; no
credential material ever appears in an error, log, receipt, or diagnostic.

**URL policy.** `https://` is required for non-loopback hosts. `http://` is accepted only for
loopback hosts (`127.0.0.1`, `localhost`, `[::1]`) as the local-testing affordance; any other
plaintext endpoint is refused at open.

**Layout, bounds, and lifecycle.** The listing under the prefix mirrors a directory scan:
supported artifacts are the same recognized JSON/NDJSON export shapes, unsupported extensions are
skipped, malformed candidates are counted in `doctor` diagnostics without becoming queryable,
and the rebuildable external index is refreshed by re-listing on every query with cursors bound
to the index revision (a changed bucket invalidates old cursors with `healthmd_agent_cursor_stale`).
Objects are bounded to 64 MiB per whole-object read — larger objects are counted invalid rather
than fetched, a deliberate divergence from the directory store, which bounds only JSON artifacts
at that size because every object read is a network fetch held in memory. Verified artifact bytes
are cached per store instance (bounded), so chunked whole-artifact reads fetch each artifact once;
remote mutation between queries is caught by the re-list fingerprint.

**Grant asymmetry.** The grant gates everything and is a local absolute JSON file exactly as for
the other backings — but it cannot be stored "outside" a remote bucket, so there is no
containment rule like the directory store's. A grant-shaped object inside the bucket is ordinary
unrecognized content (counted as ignored, zero records) and is never loaded as a grant; the
serving grant always comes from the local `--grant` path.

**Authentication and compatibility.** Requests are signed with hand-written AWS Signature
Version 4 (`aws4_request`, service `s3`, `x-amz-content-sha256: UNSIGNED-PAYLOAD`, region `auto`)
against the frozen S3 subset; the implementation is unit-tested against the RFC 4231 HMAC vectors
and the published AWS `SigV4` GET-object known answer. Real R2/S3 endpoints are not exercised in
this repository's loop: compatibility is by specification through that subset, proven against
the synthetic loopback double in `tests/agent_data_object.rs` (which `SigV4`-verifies every request
and asserts only list/head/get methods are ever sent) and, through its own embedded double, by
the shared store-parity kit in `tests/agent_data_stdio.rs`, which runs the same ten end-to-end
scenarios unchanged against all three backings — directory, database, and object store.
This build carries no TLS socket layer, so
`https://` endpoints validate per the URL policy and then fail health-free at transport with a
stable error stating that boundary; only loopback `http://` endpoints can be reached today. Wiring
TLS egress for production R2 endpoints is deliberately deferred to a later cycle rather than
approximated.

## Local ingestion (protocol v1)

`healthmd data ingest` is the local Rust half of the Agent Data ingestion protocol defined by
[`packages/contracts/agent-data/v1/contract.md`](../../../packages/contracts/agent-data/v1/contract.md).
One upload is one artifact described by one `healthmd.agent_data_ingest` v1 manifest:

```bash
healthmd data ingest \
  --database /absolute/private/path/agent-data.sqlite \
  --manifest /absolute/upload/manifest.json \
  --artifact /absolute/upload/day.json
```

All three paths must be absolute, and the database must live apart from the upload files. The
command always prints one `healthmd.agent_ingest_response` v1 receipt and exits `0` whenever the
protocol completed — including for the four stable rejection classes — so automation reads the
`outcome` field rather than the exit status. Non-zero exits are reserved for CLI-level failures
where no receipt could be produced (for example a relative path or an unusable database), mirroring
`data import`.

Validation and receipts are health-free: the manifest is checked strictly against the JSON schema
semantics (unknown fields, bounds, formats, the four artifact kinds, both platforms, the
complete-or-finalized-partial completeness grammar, and the rule that `raw_snapshot` and
`raw_changes` uploads must be complete), then the artifact bytes are verified by exact length and
SHA-256. Rejections use exactly the stable codes:

- `truncated` — the artifact's actual length differs from the manifest's `byte_count`;
- `checksum_invalid` — the artifact's SHA-256 differs from the manifest digest;
- `manifest_incomplete` — the manifest is unreadable, oversized, or structurally
  incomplete/unidentifiable (a missing manifest file, invalid JSON, an unknown field, an
  unfinalized partial, or a partial raw artifact);
- `transient` — see the local mapping decision below.

**Local `transient` mapping decision.** For this file-based local ingest, `transient` maps only to
genuine transient I/O conditions: the artifact file cannot be read as bytes at dispatch time (it is
missing at dispatch, is a directory or special file, or its read fails). The gateway-side reading —
where an unfinalized, not-yet-complete upload is the transient class — does not apply locally
because an unfinalized partial manifest already fails the strict manifest grammar and is rejected
as `manifest_incomplete`. The gateway transport mapping below documents the one deliberate
divergence; the four contract codes themselves are stable.

### Self-hosted ingestion gateway (protocol v1 reference)

`healthmd data ingest-serve` is the self-hosted reference gateway for the ingestion protocol's
HTTPS transport mapping: a loopback HTTP/1.1 listener fronting the same `SQLite` ingestion
machinery as `data ingest`. The hosted/Cloudflare gateway of a later cycle mirrors this surface.

```bash
healthmd data ingest-serve \
  --database /absolute/private/path/agent-data.sqlite
```

`--bind` (default `127.0.0.1:8791`), `--allowed-host`, and `--allowed-origin` carry the same names
and validation as the data HTTP surface: the listener binds loopback only, accepts loopback
`Host` values by default (non-loopback hosts are rejected until allowlisted), and rejects any
browser `Origin` until explicitly allowlisted — all validated before the database is opened or
created, and per request before any request logic runs. The reference serves plain HTTP on
loopback; a hosted deployment terminates TLS in a co-resident reverse proxy in front of this
listener and never exposes it directly.

Framing: one `POST /v1/ingest` request per upload. The body is exactly one `\n`-terminated
`healthmd.agent_data_ingest` v1 manifest line followed immediately by the artifact bytes, with
`Content-Type: application/x-healthmd-agent-data-ingest` and an exact `Content-Length`
(chunked transfer encoding is rejected in v1). HTTP/1.1 with `Connection: close` per request —
no keep-alive in the reference. Bodies are bounded to the 64 MiB artifact bound plus 64 KiB of
framing.

Every validated outcome answers `HTTP 200` with the same `healthmd.agent_ingest_response` v1
receipt `data ingest` prints; rejections are protocol outcomes, never HTTP error statuses.
Transport-level failures answer health-free, path-free code+message JSON: an over-bound body →
`413`, a wrong method → `405`, an unknown path → `404`, a wrong or missing media type → `415`, a
malformed request (including chunked encoding) → `400`, and an unconfigured `Host` or `Origin` →
`403` with no body.

The frozen outcome mapping (the normative text lands in
[`packages/contracts/agent-data/v1/contract.md`](../../../packages/contracts/agent-data/v1/contract.md)):

| Upload shape | Outcome |
| --- | --- |
| Connection closes before the full `Content-Length` body arrives | the server simply closes with NO receipt — the phone-side retryable class |
| Artifact bytes shorter (or longer) than `byte_count` | `truncated` receipt |
| Bytes SHA-256 ≠ manifest digest | `checksum_invalid` receipt |
| Manifest unparseable / schema-invalid / unknown fields / grammar violations, except the unfinalized-partial shape | `manifest_incomplete` receipt |
| Completeness is `partial` and `finalized` is not `true` | `transient` receipt (the gateway reading, detected before strict validation) |
| Any other server-side read/dispatch failure | `transient` receipt |

**Documented surface divergence.** An unfinalized partial upload is the retryable `transient`
class for the gateway — the reading of an upload still in progress on the phone — detected before
strict manifest validation, while local `data ingest` keeps its cycle-2 classification
(`manifest_incomplete`) because the strict manifest grammar still rejects the shape. This is the
only divergence between the two surfaces: manifest validation, integrity verification, atomic
idempotent promotion, and receipts are shared byte-for-byte. `record_count` stays strictly
informational over the gateway as well: a declared count disagreeing with the stored bytes is
still accepted.

Retry guidance: treat `transient` receipts and receipt-less connection closes as retryable with
bounded backoff — an identical manifest+bytes re-upload is idempotent and returns a byte-identical
receipt — and do not re-send after `truncated` or `checksum_invalid` without new bytes. The
gateway opens (or creates) and migrates the same `SQLite` store at startup and fronts the same
per-request validation and promotion path; verified bytes are spooled to a private temporary
file during promotion so recognition is byte-identical with `data import`, and the store stays
servable with `serve-data --database`. The concurrency model is a std thread-per-connection
accept loop with one `Connection: close` request per connection — deliberately minimal for the
reference; hosted deployment, accounts, OAuth, and TLS termination are later cycles.

Promotion into the SQLite store is a single atomic transaction reusing the import machinery:
exact artifact bytes plus indexing metadata are inserted once per SHA-256 identity, so re-ingesting
identical bytes returns a byte-identical receipt, creates no duplicate rows, and does not advance
the store content revision (no cursor invalidation beyond the existing content-revision
semantics). When the read model recognizes the artifact bytes, the stored row is exactly what
`data import` would store for the same bytes, so ingested artifacts are immediately servable with
`serve-data --database`. When the bytes are integrity-verified but not recognized by the read
model, they are still stored unchanged with the manifest-declared schema identity and zero record
rows — never a fabricated index. There is deliberately no rejection code for unrecognized content
in v1.

Stored revisions group into owner-date partitions (`ingested_partitions`, schema version 2 — an
additive migration; version-1 databases upgrade in place and stay readable). Within a partition
the newest complete accepted revision is authoritative; a partial revision never displaces a
complete one, and while no complete revision exists the newest accepted partial is authoritative
and is always reported with its explicit partial status and covered owner dates, so partial
coverage is never concealed. A complete restatement of identical bytes upgrades the recorded
revision's completeness; it never downgrades. Authority flips are recorded as supersession
bookkeeping (`ingest-partition:<owner_date>` observations) and, like directory supersessions,
never delete anything: retention stays user-controlled and deferred.

The hosted gateway store, accounts, and the public HTTPS endpoint remain later cycles per the
contract; `data ingest-serve` above is the self-hosted reference realization of the transport
mapping.
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
`--directory`/`--database`/`--object-store-url` exclusivity and grant validation are unchanged
by the transport choice, the store opens only after the listener policy validates, and no
fallback exists between the data and direct surfaces over either transport.

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
