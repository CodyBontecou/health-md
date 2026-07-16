# Health.md export reference

This reference documents the data Health.md can produce for users, scripts, databases, and connected applications. It covers readable daily summaries and the source-level Apple Health records behind them.

The reference is written for two audiences:

- **Users** deciding which formats and metrics to export.
- **Developers** building parsers, automations, data warehouses, Obsidian workflows, or connected clients.

All committed examples use deterministic synthetic data. They contain no real health information.

## Contract authority

When sources disagree, use this order:

1. Production exporters, serializers, metric catalogs, and protocol models.
2. The committed versioned export-schema signature.
3. Generated examples and generated field inventories.
4. Explanatory prose.

The generated artifacts are rebuilt by running the real production code against a fixed synthetic corpus. CI compares regenerated output byte-for-byte with the committed files. This keeps examples from drifting into hand-written approximations.

## Current schemas

| Surface | Identifier | Current version | Purpose |
|---|---:|---:|---|
| Daily record | `healthmd.health_data` | 6 | Daily summaries, diagnostics, and optional canonical archive. |
| Canonical Apple Health archive | `healthmd.healthkit_records` | 1 | Source records, provenance, relationships, query results, and external records. |
| Roll-up summary | `healthmd.rollup_summary` | 6 | Weekly, monthly, and yearly projections derived from daily summaries. |
| API Endpoint envelope | `healthmd.api_export` | 1 or 2 | One or more daily records sent to a configured endpoint; v2 adds provider sidecars. |
| Strict CLI raw result | `healthmd.raw_result` | 1 | Canonical daily records returned through the Mac CLI without writing files. |
| Connected app protocol | Versioned capabilities/messages | Independent | Mac–iPhone requests, progress, transfer, acknowledgement, and results. |

Versions advance independently. A newer API or connected-protocol envelope does not automatically change the daily-record schema.

## Choose an export surface

| Need | Recommended surface | Exact source records? | Human-readable? |
|---|---|---:|---:|
| Complete machine archive | JSON | Yes | Partly |
| Spreadsheet or stream ingestion | CSV | Yes, as canonical JSON cells | Partly |
| Daily journal | Markdown | No; compact diagnostics only | Yes |
| Obsidian database properties | Obsidian Bases | No; compact diagnostics only | Frontmatter |
| One note per source event | Individual Entry Tracking | Selected UUID-backed records | Yes |
| Send to your own service | API Endpoint | Yes when lossless capture is enabled | No |
| Terminal automation | Mac CLI strict raw | Yes | No |
| Weekly/monthly/yearly trends | Roll-ups | No; summary projections | Yes |

## Reference map

- [Daily records](./daily-records.md): top-level structure, summary layers, omission rules, units, and format mapping.
- [Canonical Apple Health records](./canonical-healthkit-records.md): UUID-backed records, external identities, metadata tags, payloads, relationships, and specialized domains.
- [Query manifests and diagnostics](./query-manifests-and-diagnostics.md): completeness, status values, failures, warnings, and partial results.
- [Export formats](./export-formats.md): JSON, CSV, Markdown, and Obsidian Bases contracts and complete examples.
- [Individual Entry Tracking](./individual-entry-tracking.md): source-backed note identity, filenames, frontmatter, and fallbacks.
- [API and CLI](./api-and-cli.md): API Endpoint envelopes, local control responses, strict raw results, and exit behavior.
- [Connected Mac–iPhone protocol](./connected-mac-iphone-protocol.md): requests, capabilities, progress, bounded transfers, and results.
- [Data dictionary and roll-ups](./data-dictionary-and-rollups.md): metric definitions, units, aggregation, and period summaries.
- [Generated documentation workflow](./generation.md): how examples are produced and checked.

## Generated references

The generated directory contains complete, copyable fixtures rather than shortened snippets:

- [`generated/core/`](./generated/core/): daily exports, canonical records, data dictionary, metric catalog, path/type inventories, and CSV contracts.
- [`generated/cli/`](./generated/cli/): CLI requests, responses, raw results, errors, and exit-code behavior.

Generated files may be large because they intentionally exercise optional branches and specialized payloads. Start with the hand-written reference pages, then open the complete fixture relevant to your integration.

## Compatibility rules for consumers

1. Branch on every declared schema identifier and version.
2. Preserve unknown keys, enum values, metadata tags, and record kinds when possible.
3. Treat absent optional fields as absent, never as zero or false.
4. Inspect capture status and every query result before claiming completeness.
5. Use source UUIDs or documented external identities for deduplication.
6. Use canonical archive timestamps for source-event joins; summary clock fields are presentation values.
7. Parse CSV with an RFC 4180 implementation. Do not split on commas or physical lines.
8. Keep historical files under their original version. Never relabel older exports as v6.

## Privacy

Lossless exports may include exact timestamps, route locations, medications, mental-wellbeing entries, clinical content, source/device details, ECG measurements, documents, and binary attachments. Health.md keeps local exports on the selected device or destination, but API and CLI users control where copied data goes. Apply encryption, access controls, retention limits, and logging policies appropriate for sensitive health information.
