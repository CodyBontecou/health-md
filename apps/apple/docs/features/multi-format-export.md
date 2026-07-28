# Multi-Format Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Export Formats
- **Source files:** `HealthMd/Shared/Models/AdvancedExportSettings.swift`, `HealthMd/Shared/Managers/VaultManager.swift`, `HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift`

## What it does

One export action can write Markdown, Obsidian Bases, JSON, and CSV for every selected date. All use schema v7 summaries and the same selected metrics, but each has a deliberate role:

| Format | Role |
|---|---|
| Markdown | Readable summaries plus lossless status/counts/diagnostics. |
| Obsidian Bases | Queryable summary properties plus lossless status/counts. |
| JSON | Authoritative complete public `healthkit_record_archive`. |
| CSV | Same canonical records as JSON, one RFC 4180-safe JSON row per record. |

**Lossless Health Records** is on by default for new installs. An existing explicit off setting stays summary-only across all formats.

## Setup

1. Open **Export → Export Formats**.
2. Enable any combination of Markdown, Obsidian Bases, JSON, and CSV.
3. Choose metrics and review **Lossless Health Records**.
4. Configure paths/format settings and choose iPhone Folder or Connected Mac.
5. Preview one day, then export.

## Filenames

```text
Health/2026-07-15.md
Health/2026-07-15-bases.md
Health/2026-07-15.json
Health/2026-07-15.csv
```

Bases receives `-bases` only when readable Markdown is also selected. A three-day/four-format run writes up to 12 daily files, plus enabled side effects/roll-ups.

## Cross-format contract

- JSON and CSV canonical records are deterministically ordered and preserve UUID parity.
- Markdown/Bases do not embed canonical records. Their `raw_capture_status`, archive schema, counts, failures, and warnings let readers assess completeness.
- Summary values remain available in every format.
- Individual entries derive from the canonical archive once present.
- A `partial` archive stays partial in every format; successful file writing does not upgrade capture status.

## Size and transport

Lossless JSON/CSV can be much larger than Markdown/Bases because they include routes, waveforms, clinical/binary content, and attachments. Current Connected Mac jobs use bounded checksum-validated frames rather than an unbounded whole payload, but capture and final file serialization can still use substantial memory.

Disable formats you do not need and export smaller date ranges for dense records.

## Tips

- Use Markdown + JSON for readable notes plus source-complete backup.
- Use Bases + CSV for Obsidian dashboards plus table ingestion.
- Keep both JSON and CSV only when downstream workflows need both representations.
- Update v5/v6 consumers before mixing v7 output; parsers should branch by schema version.
- Treat non-Markdown outputs as regenerated files.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Select-format warning | All formats off | Enable at least one. |
| Bases has `-bases` | Markdown is also selected | Intentional collision prevention. |
| Markdown lacks raw records | It intentionally summarizes | Use JSON or CSV. |
| JSON/CSV status is partial | A source query did not complete | Inspect manifest/diagnostics; do not accept as complete. |
| Mac transfer/serialization fails | Lossless multi-format job is large | Keep apps open, reduce days/formats, or use summary-only. |
| Update overwrote JSON/CSV/Bases | Only readable Markdown has merge sections | Treat other formats as regenerated output. |

## Video outline

- **Suggested title:** Export Apple Health Summaries and Lossless Records Together
- **Hook:** “One run can create readable notes, database properties, and a source-complete archive.”
- **Demo flow:** select all formats, compare roles/status, verify JSON/CSV UUID parity, then send a bounded Mac job.

## Implementation notes

- `ExportFormat` supports Markdown, Bases, JSON, and CSV.
- `VaultManager.writeOneFormat(...)` applies each renderer/write behavior.
- `HealthKitRecordArchiveSerializer` ensures JSON/CSV canonical parity.
- Mac-target jobs carry one settings snapshot and use the same shared exporters.
