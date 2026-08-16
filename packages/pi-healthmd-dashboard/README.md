# Health.md dashboard for Pi

Experimental, local-first, read-only Pi extension for inspecting approved Health.md JSON or fetching bounded typed query responses through the Health.md CLI/MCP server. Package: `@healthmd/pi-health-dashboard`.

## Safety and model disclosure

There is intentionally no per-tool confirmation. Filesystem loading is restricted to **approved realpath roots**:

- `--healthmd-data <path>` and `HEALTHMD_DATA_PATH=<path>` approve and load that root at startup.
- The user-authored `/healthmd load <path>` command approves and loads that root.
- The model-callable `healthmd_load` tool may subsequently load only the approved root or realpath descendants.

Traversal, outside paths, symlink inputs, and symlink aliases escaping a root are rejected. If no root exists, the tool directs the user to approve one by flag, environment variable, or command. Directory traversal ignores symlinks and loads regular `.json` files only.

`healthmd_fetch` is a separate validated source. It invokes only the 13 fixed read-only readiness, catalog, and typed-query operations through newline-delimited MCP stdio; explicit CLI mode supports the nine query operations accepted by `healthmd query`. MCP mode starts `healthmd mcp serve-read-only` unless a standalone helper is explicitly configured. The model cannot supply an executable, arbitrary command, raw-export selector, pairing operation, or file-export operation; no backend/transport fallback occurs. Subprocesses use argument arrays without a shell, an allowlisted environment that excludes unrelated Pi/provider secrets, bounded stdout/stderr, cancellation, a 1–3,600 second timeout, and terminate-to-kill process-group escalation. Typed queries must return structurally valid `healthmd.query_response/1` or `healthmd.mcp_query_pages/1`; wrong versions and malformed pages fail closed. Accepted responses then pass through the same lossless parser, contract classifier, index bounds, and model-output limits as files.

**Loaded or fetched health evidence can enter model context and Pi session/JSON output.** The extension does not add custom Pi session entries, but ordinary tool calls/results may be persisted by Pi. Approve only data intended for model disclosure.

Defaults bound loading to 256 documents, 100,000 traversed directory entries (including non-JSON entries), 32 MiB per file, 128 MiB total, 500,000 scalar leaves, 1,000,000 total nodes, depth 256, 4 KiB per indexed path, 64 MiB across retained index paths, 10,000 digest references, and 1,024 characters per numeric token. Depth is preflighted before parsing. Approved-root confinement is carried through traversal and final open; files are opened no-follow where supported, sized before allocation, rechecked against their opened device/inode and canonical path, read with a hard cap, and closed. Query evidence is at most 24,000 UTF-8 bytes; every tool result is at most 45,000 UTF-8 bytes, below Pi's 50 KB tool-result limit. Structured values, provenance, and tool result objects use bounded previews rather than repeatedly serializing whole subtrees.

## Install and use

From this repository:

```sh
pi install ./packages/pi-healthmd-dashboard
# Or try it without installing:
pi -e ./packages/pi-healthmd-dashboard --healthmd-data /explicit/path/to/export.json
```

Once the package is published publicly:

```sh
pi install npm:@healthmd/pi-health-dashboard
HEALTHMD_DATA_PATH=/explicit/path/to/export-directory pi
```

For live typed queries, install/pair the standalone `healthmd` CLI, keep Health.md foreground on iPhone, and use the default least-privilege MCP transport. The portable CLI is currently `0.1.0-alpha.1` and its public mobile pairing matrix remains pending physical qualification:

```sh
healthmd direct pair
pi --healthmd-cli-path "$(command -v healthmd)" --healthmd-fetch-transport mcp
```

A Mac app bundled stdio helper can be selected explicitly with `--healthmd-mcp-path /Applications/Health.md.app/Contents/Helpers/healthmd-mcp` or `HEALTHMD_MCP_PATH`. Other configuration variables are `HEALTHMD_CLI_PATH`, `HEALTHMD_FETCH_TRANSPORT=cli|mcp`, `HEALTHMD_DEVICE_ID`, `HEALTHMD_CLI_PORT`, and `HEALTHMD_CACHE_DIR`. CLI mode is explicit (`transport: "cli"` or `--healthmd-fetch-transport cli`); MCP is the default because query arguments travel over stdin rather than the process list.

Tools:

- `healthmd_load`: load a path under an already approved root; hashes exact bytes and checks digest references.
- `healthmd_fetch`: execute a fixed typed read-only operation over CLI or MCP, then index its canonical response in memory and, when configured, persist it in the cache.
- `healthmd_query`: bounded semantic metric, generic path, or search evidence from the current file/fetched store.
- `healthmd_view`: select metric/path/search targets, chart/table, date window, zoom, pan, show, or hide.

Supported MCP fetch operations are `healthmd_status`, `healthmd_doctor`, `healthmd_capabilities`, `healthmd_metrics`, `healthmd_metric_chart`, `healthmd_sleep_sessions`, `healthmd_training_alignment`, `healthmd_workouts`, `healthmd_coverage`, `healthmd_compare_periods`, `healthmd_training_evidence`, `healthmd_query`, and `healthmd_evidence_packet`. Pairing and durable file exports deliberately remain outside this extension.

Interactive commands: `/healthmd dashboard`, `/healthmd load <path>`, `/healthmd fetch <operation> <JSON-object>`, `/healthmd cache <directory|off>`, `/healthmd show`, `/healthmd hide`, `/healthmd reset`, `/healthmd status`. `/healthmd cache <directory>` is an explicit durable opt-in: the extension stores validated response bytes as content-addressed, mode-0600 JSON objects, remembers the canonical directory in the user configuration, and restores up to 64 responses/128 MiB at startup while verifying manifest sizes and SHA-256 digests. Cache files retain exact CLI/MCP origin and operation through a bounded manifest. `off` disables future persistence without deleting health data. `--healthmd-cache-dir` or `HEALTHMD_CACHE_DIR` overrides the remembered directory. Reset clears loaded data and the session's approved roots, returns the compact widget to its hidden startup state, and does not delete or disable the configured cache. `/healthmd dashboard` opens a 96%-width interactive TUI dashboard with curated domain summary cards, available-only grouped navigation, single-identity metric trends, typed records, and coverage/provenance screens. Its first-run view recommends a bounded 30-day history and explains foreground-iPhone readiness; press Enter or F, then choose 1/2/3 to fetch a validated 7/30/90-day range from the configured read-only source. The overview explicitly reports when too few dated days are loaded for trends. Use 1–8 for direct All/Activity/Sleep/Heart/Mobility/Recovery/Body/Other navigation, `/` to search names, semantic IDs, units, sources, and providers, `?` for contextual help, ↑/↓ to navigate, and ←/→ to inspect chart dates. Chart mode defaults to automatic: snapshots remain cards, connected date-ready series use lines, and valid disconnected observations use bars; V cycles auto/bar/line. O/D/T/C or Tab changes screens, A includes unavailable metrics, G cycles domains, W cycles chart windows, `[ ]` pans, `+/-` zooms, R refreshes, and Escape closes. The focused Sleep domain renders validated stage composition as a terminal pie chart when space permits, while constrained and all-domain summaries use a complete stacked bar. Sleep composition is shown only when stage totals are identity-compatible and consistent with total sleep; no clinical reference ranges are invented. Charts never combine distinct metric/unit/source/provider/platform/contract identities. The compact persistent widget starts hidden, remains available for opt-in at-a-glance context, and can be toggled with `/healthmd show` or `/healthmd hide`. RPC/print/JSON modes retain tools without constructing TUI components.

Discussion examples:

- “Chart WHOOP recovery HRV from the approved export.” → query/select `hrv_rmssd_ms`; provider identity remains WHOOP.
- “Compare Apple and Android HRV.” → separate series by semantic ID/statistic/platform; do not combine SDNN and RMSSD.
- “Show medication and route evidence.” → generic path/search indexing remains available, subject to output bounds and model disclosure.

## Supported contract matrix

The exported pure `src/contracts.ts` registry/adapter has no Pi imports and explicitly classifies:

| Contract family | Reader behavior |
|---|---|
| Proposed `healthmd.health_data` v9 / `unified-cross-platform-v1` | Full bundled JSON Schema validation plus current proposal-fixture mapping, source/platform, calendar, capture, provenance, ordering, exact-number, and provider invariants; valid documents marked experimental; recognized invalid v9 remains generically indexed with bounded errors |
| Shipped Apple `healthmd.health_data` v5-v8 | Identified as historical Apple daily data; no cross-platform equivalence inferred |
| Android frozen v4, analytical v5, unversioned samples | Distinct identities retained |
| `healthmd.healthkit_records` archive | Source-fidelity generic indexing with lossless large integer parsing |
| Android raw snapshot/manifest and merge/raw references | Distinct raw/reference identities; digest resolution never implies semantic equivalence |
| Typed `healthmd.provider.whoop_daily` and external-provider daily | Provider identity retained; provider facts do not populate primary metrics |
| Health.md rollups | Identified as rollup evidence; rollup rules are not inferred for provider/platform data |
| `healthmd.api_export` and `healthmd.raw_result` envelopes | Envelope identity retained while all nested generic paths remain searchable |
| Typed CLI/MCP `healthmd.query_response` / `healthmd.mcp_query_pages` | Distinct validated `query_response` / `mcp_query_pages` identities; transport origin and operation retained; metric IDs, typed units, owner dates, source IDs, evidence, coverage, missingness, cursors, and limitations remain indexed |
| Other `healthmd.*` and arbitrary JSON | `generic_healthmd` or `generic_json` fallback; every domain is indexed without normalization claims |

`LoadedDocument` and index entries expose exact schema identity/version, contract kind, validity, origin/operation, and bounded errors. Date context keeps `ownerDate` separate from nearest `recordTimestamp`; the display date is the nearest record timestamp when present. Charts accept numeric metric/path/search targets, sort and filter the full bounded index before pagination, exclude evidence/coverage metadata from metric series, and refuse mixed contract/schema/path/unit/statistic/provider/platform/source/origin scales or any series containing unsafe exact values.

Numbers are parsed with `lossless-json`'s number/BigInt parser so source-fidelity large integer tokens are not rounded. Model-visible serializers safely render bigint as exact decimal text. Proposed-v9 tagged binary64 and integer objects receive representation-specific validation, including finite IEEE-754 values, canonical signed/unsigned decimal strings, 40-character maximum, negative-zero display, and safe-chart restrictions.

## Interpretation rules

- Preserve units, statistics, owner dates, record timestamps, missingness, explicit zero, capture status, source path, provider/platform identity, provenance, references, and coverage.
- Never infer Apple/Android/provider equivalence. WHOOP RMSSD, HealthKit SDNN, and Health Connect RMSSD remain distinct.
- The dashboard is not a medical device and must not diagnose.
- Unified v9 is a proposed reader contract; this package does not write it and does not indicate a shipped writer.

The contracts manifest has consumer inventory fields, so this experimental reader is listed only for the deferred unified-v9 contract; no authoritative contract bytes or hashes are changed. The npm package carries byte-identical snapshots of the proposed v9 and provider-sections schemas for standalone validation, and tests compare those snapshots to their canonical monorepo sources.

## Development

```sh
npm install
npm test
npm run typecheck
npm pack --dry-run
```

Production-package validation installs the generated tarball in a temporary directory and runs the actual Pi 0.84.1 extension loader/command discovery. Runtime peer APIs use Pi's required `*` ranges; development and compatibility tests pin `@earendil-works/pi-coding-agent` and `@earendil-works/pi-ai` 0.84.1.

License: AGPL-3.0-only.
