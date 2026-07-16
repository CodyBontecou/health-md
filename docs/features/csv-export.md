# CSV Export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Export Formats; Export → Lossless Health Records
- **Source files:** `HealthMd/Shared/Export/CSVExporter.swift`, `HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

CSV export writes one spreadsheet-friendly `.csv` file per date. Schema v6 uses a six-name header and adds canonical JSON rows when **Lossless Health Records** is on. For compatibility, many aggregate rows serialize five fields by omitting the trailing empty `Timestamp`; metadata, canonical, diagnostic, and timestamped rows commonly serialize all six. Consumers must accept both row widths.

CSV is lossless because each source object is carried as canonical JSON in the `Value` cell, not flattened into a fragile set of columns. Use it in Numbers, Excel, Google Sheets, DuckDB, or scripts that support RFC 4180 CSV. Use JSON when nested object traversal is more convenient.

## Setup

1. Open **Export → Export Formats** and enable **CSV**.
2. Choose metrics under **Health Metrics**.
3. Leave **Lossless Health Records** on for canonical rows, or turn it off for summary-only rows.
4. Export one day first and import it with a standard RFC 4180 parser.

The complete generated CSV files and exhaustive row contract are in [Export formats](../reference/export-formats.md#csv).

## Row contract

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-07-15,Metadata,schema,healthmd.health_data,,
2026-07-15,Metadata,schema_version,6,,
2026-07-15,Raw HealthKit,Raw Capture Status,complete,status,
2026-07-15,Raw HealthKit,Archive Manifest,"{""capture_status"":""complete"",...}",json,2026-07-15T07:00:00.000000000Z
2026-07-15,Raw HealthKit,Raw HealthKit Record,"{""original_uuid"":""..."",...}",json,2026-07-15T15:04:12.125000000Z
2026-07-15,Activity,Steps,8432,count,
```

Canonical row types:

| Metric | Purpose |
|---|---|
| `Raw Capture Status` | `complete`, `partial`, `not_requested`, or `legacy_unavailable`. |
| `Archive Manifest` | Archive schema, ownership, full query manifest, warnings, and medication inventory; excludes record arrays. |
| `Raw HealthKit Record` | One UUID-backed canonical record. |
| `Raw HealthKit External Record` | One public UUID-free value with an honest external identity. |
| `Query Failure` | One failed or cancelled query as canonical JSON. |
| `Integrity Warning` | One archive warning as canonical JSON. |
| `Partial Failure` | One daily exporter/fetch diagnostic as canonical JSON. |

The JSON in a `Raw HealthKit Record` row is the same canonical object embedded in JSON export. UUID ordering and values must match across both formats.

The header always names `Date,Category,Metric,Value,Unit,Timestamp`. A five-field aggregate row has no timestamp field; a six-field row may contain a timestamp or an explicit empty final field. Parse by the header and treat a missing final field as an empty Timestamp.

## CSV safety

Canonical values can contain commas, quotes, and real line breaks. Health.md applies RFC 4180 escaping and does not replace those characters with semicolons or spaces. Use a CSV parser rather than splitting lines or commas manually.

Binary values inside canonical JSON are base64. Available attachment data includes SHA-256 checksums. Source URLs are strings only and are never fetched.

## Summary rows

Existing daily metric rows remain. Aggregate rows may have an empty `Timestamp`; source rows use exact UTC source-start timestamps. Examples include:

```csv
2026-07-15,Activity,Stand Time,42.5,minutes,
2026-07-15,Activity,Stand Hours,9,hours,
2026-07-15,Vitals,Blood Pressure Sample,124/81,mmHg,2026-07-15T16:00:00Z
2026-07-15,Activity,VO2 Max Carried Forward,true,boolean,
```

Stand Time is duration; Stand Hours is a distinct count of stood hours. Blood-pressure source truth is in canonical correlation rows; compatibility sample rows are convenient projections, not a session model.

## Tips

- Parse the header by name and tolerate new metric rows.
- Read schema/version and `Raw Capture Status` before processing source rows.
- Parse `Unit: json` cells as JSON while preserving tagged metadata and raw enums.
- Deduplicate only by original UUID or documented external identity.
- A successful empty manifest is different from a failed, skipped, cancelled, or unsupported query.
- Use canonical units from each record/summary row; reviewed micronutrients distinguish `µg` from `mg`.
- For large lossless files, import in a tool that can stream RFC 4180 CSV rather than opening everything in a spreadsheet.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No CSV file was written | CSV format is disabled | Enable **CSV** in Export Formats. |
| JSON appears split across rows | Importer does not honor RFC 4180 quoted newlines | Use a standards-compliant CSV import/parser. |
| No canonical rows appear | Lossless Health Records was off or the source is legacy | Check the `Raw Capture Status` row and re-export if needed. |
| Status is `partial` | One or more planned branches did not complete | Inspect manifest, query failure, warning, and partial failure rows. |
| Some timestamps are blank | Daily aggregates have no single source instant | Use canonical source rows when event identity matters. |
| Spreadsheet is slow | Dense records/binary data made the file large | Export fewer days or use a streaming database/script. |
| Re-export replaced edits | CSV is regenerated, not merged | Do not hand-edit generated CSV files. |

## Video outline

- **Suggested title:** Export Lossless Apple Health Records to CSV
- **Hook:** “Spreadsheet rows stay simple while each original HealthKit object remains intact as canonical JSON.”
- **Demo flow:** export one day, explain summary vs canonical rows, parse one JSON cell, inspect capture status, and import with a standards-compliant tool.

## Implementation notes

- `HealthData.toCSV(customization:)` emits `Date,Category,Metric,Value,Unit,Timestamp`.
- `CSVFieldEscaper` preserves RFC 4180 commas, quotes, and line breaks while escaping unsupported control characters.
- `HealthKitRecordArchiveSerializer` produces the same deterministic canonical objects used by JSON.
- `VaultManager.writeOneFormat(...)` writes CSV; Update falls back to overwrite.
