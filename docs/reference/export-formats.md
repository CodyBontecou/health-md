# Export formats

Health.md uses one captured daily data set to produce formats with different roles. JSON and CSV carry canonical source records. Markdown and Obsidian Bases remain intentionally readable.

## Capability matrix

| Capability | JSON | CSV | Markdown | Obsidian Bases |
|---|---:|---:|---:|---:|
| Daily summaries | Yes | Yes | Yes | Yes |
| Canonical UUID-backed records | Embedded | Canonical JSON rows | No | No |
| UUID-free external records | Embedded | Canonical JSON rows | Count only | No dedicated count |
| Full query manifest | Embedded | Archive Manifest row | Counts/safe details | Failure count only |
| Typed recursive metadata | Embedded | Canonical JSON rows | No | No |
| Exact binary values | Base64 | Base64 inside JSON cell | No | No |
| Relationship graph | Embedded | Canonical JSON rows | No | No |
| Human-readable sections | Limited | Limited | Yes | Frontmatter only |
| Custom frontmatter keys | No | No | Yes | Yes |
| Update/merge user writing | No | No | Yes | Generated frontmatter file |

## JSON

JSON is the authoritative single-file daily representation.

- Top-level schema: `healthmd.health_data` v7.
- Nested archive: `healthmd.healthkit_records` v1 when lossless capture is requested and available.
- Keys are sorted in production output for deterministic serialization.
- Optional summary sections and fields are omitted when absent.
- Binary values are base64.
- Canonical timestamps use UTC; summary display times use captured calendar context.

Complete examples:

- [`generated/core/summary-day.json`](./generated/core/summary-day.json)
- [`generated/core/lossless-day.json`](./generated/core/lossless-day.json)

### JSON parser guidance

- Parse numbers without converting all integers to floating point when exactness matters.
- Preserve unknown object keys and enum strings.
- Branch on metadata `type` tags.
- Treat the canonical archive as source truth, not summary arrays.

## CSV

CSV begins with the header:

```csv
Date,Category,Metric,Value,Unit,Timestamp
```

Production v7 rows have an intentional compatibility detail:

- many aggregate rows serialize five fields and omit the trailing empty Timestamp field;
- metadata, diagnostic, canonical, and timestamped sample rows commonly serialize six fields.

Consumers must accept both five- and six-field records under the six-name header. A missing sixth field means no timestamp for that aggregate row.

Do not split CSV on commas or physical newline characters. Canonical JSON cells can contain commas, quotes, and embedded line breaks. Use an RFC 4180 parser.

### Canonical row types

| Category / Metric | Purpose |
|---|---|
| `Raw HealthKit / Raw Capture Status` | Daily capture status. |
| `Raw HealthKit / Archive Manifest` | Archive metadata, ownership, query manifest, warnings, and inventory without record arrays. |
| `Raw HealthKit / Raw HealthKit Record` | One canonical UUID-backed record JSON object. |
| `Raw HealthKit / Raw HealthKit External Record` | One UUID-free public record JSON object. |
| `Raw HealthKit / Query Failure` | One failed/cancelled query result. |
| `Raw HealthKit / Integrity Warning` | One warning. |
| `Diagnostics / Partial Failure` | One exporter/fetch partial failure. |

JSON and CSV canonical record UUIDs and objects must match.

Complete examples and generated row inventory:

- [`generated/core/summary-day.csv`](./generated/core/summary-day.csv)
- [`generated/core/lossless-day.csv`](./generated/core/lossless-day.csv)
- [`generated/core/csv-row-contracts.md`](./generated/core/csv-row-contracts.md)

## Markdown

Markdown is a readable daily note. With **Include Metadata** on (the default), it includes schema/time/unit frontmatter. With that user-controlled setting off, the entire frontmatter block is omitted, so the Markdown file does not identify its schema or expose the machine-readable `units` map. Its body includes:

- selected daily summary sections;
- optional workout details and compatibility sample tables;
- compact lossless capture diagnostics.

It does not embed recursive canonical records, route graphs, clinical payloads, waveforms, or binary data. Pair it with JSON or CSV when source identity matters.

Complete generated example:

- [`generated/core/summary-day.md`](./generated/core/summary-day.md)
- [`generated/core/lossless-day.md`](./generated/core/lossless-day.md)

## Obsidian Bases

Bases output is a frontmatter-only Markdown file. It exposes selected summary properties and compact diagnostics for database views.

Reserved v7 diagnostics are:

- `raw_capture_status`
- `raw_record_count`
- `raw_query_failure_count`
- `raw_integrity_warning_count`
- `raw_record_schema`
- `raw_record_schema_version`

There are no dedicated Bases/frontmatter properties for external-record count or medication-inventory count. Markdown's body can show those additional counts.

Complete generated examples:

- [`generated/core/summary-day-bases.md`](./generated/core/summary-day-bases.md)
- [`generated/core/lossless-day-bases.md`](./generated/core/lossless-day-bases.md)

## Units by format

- JSON uses structured canonical values and a `units` map.
- CSV uses the `Unit` column.
- Markdown prose can use selected display units.
- Bases uses stable values plus a frontmatter `units` map.
- Canonical record quantities carry their own exact unit.

The v7 data dictionary uses `µg` for microgram summary keys.

## Summary-only behavior

When Lossless Health Records is off:

- `raw_capture_status` is `not_requested`;
- JSON has no `healthkit_record_archive`;
- CSV has no canonical record/manifest rows;
- Markdown/Bases retain compact status/frontmatter behavior;
- summaries remain available.

Connected jobs in true summary-only mode neither fetch nor transfer a hidden archive.

## Write behavior

- JSON and CSV are regenerated; Update falls back to overwrite.
- Markdown can use Update to replace Health.md-managed sections while preserving user sections.
- Bases is generated frontmatter intended for database consumption.
- When Markdown and Bases are both enabled, Bases uses a `-bases.md` suffix to avoid collisions.

## Serialization failures

Production file writers use throwing serialization paths and fail the affected date rather than silently omitting a malformed canonical record. Convenience preview methods can emit an explicit machine-readable serialization-error fallback. Consumers must not treat that fallback as a complete health-data document.
