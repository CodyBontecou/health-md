# JSON Export

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Export Formats; Export → Lossless Health Records
- **Source files:** `HealthMd/Shared/Export/JSONExporter.swift`, `HealthMd/Shared/Export/HealthKitRecordArchiveSerializer.swift`, `HealthMd/Shared/Models/HealthKitRecord.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

JSON export writes one structured `.json` document per exported date. In schema v6 it keeps the familiar daily summary objects and, when **Lossless Health Records** is on, embeds the authoritative public source archive at `healthkit_record_archive`.

Use JSON for scripts, notebooks, dashboards, backups, API ingestion, or any workflow that needs exact source records. Markdown and Obsidian Bases intentionally remain summary-oriented; JSON is the complete machine-readable format. The [daily-record reference](../reference/daily-records.md) and [canonical-record reference](../reference/canonical-healthkit-records.md) include exhaustive generated field inventories and complete synthetic files.

## Setup

1. Open **Export → Export Formats** and enable **JSON**.
2. Choose metrics under **Health Metrics**.
3. Leave **Lossless Health Records** on for canonical records, or turn it off for summary-only JSON.
4. Choose the date range, filename/folder templates, and target.
5. Preview one day, then export.

Lossless Health Records is on by default for new installs. Health.md preserves an existing explicit off choice.

## Minimal example output

The complete all-fields synthetic output is generated at [`docs/reference/generated/core/lossless-day.json`](../reference/generated/core/lossless-day.json).

```json
{
  "schema": "healthmd.health_data",
  "schema_version": 6,
  "date": "2026-07-15",
  "type": "health-data",
  "raw_capture_status": "complete",
  "time_context": {
    "calendar_timezone": "America/Los_Angeles",
    "timestamp_timezone": "UTC"
  },
  "unit_system": "metric",
  "units": {
    "steps": "count"
  },
  "activity": {
    "steps": 8432
  },
  "healthkit_record_archive": {
    "schema": "healthmd.healthkit_records",
    "schema_version": 1,
    "capture_status": "complete",
    "ownership": {
      "owner_date": "2026-07-15",
      "assignment_rule": "record_start_in_half_open_day_interval"
    },
    "records": [],
    "query_manifest": {
      "results": []
    },
    "integrity_warnings": [],
    "medication_inventory": []
  }
}
```

Example path:

```text
MyVault/Health/2026-07-15.json
```

API Endpoint export places the same daily document inside a `healthmd.api_export` envelope instead of writing it to disk.

## Reading the archive

A UUID-backed record preserves its original UUID, type, kind, exact start/end, undetermined-duration flag, source revision and OS, device, recursively typed metadata, exact payload, relationships, and direct/dependency metric attribution.

The archive can include:

- ordinary discrete/cumulative/series quantities and categories;
- blood-pressure and food correlations;
- full workout graphs, routes, events, activities, statistics, associated samples, effort edges, and WorkoutKit plans;
- ECG, audiogram, heartbeat, scored-assessment, State of Mind, medication, activity-summary, and characteristic records;
- clinical/FHIR, CDA, verifiable, vision, and attachment data.

Public values without an `HKObject` UUID appear in `external_records`. They intentionally have no fabricated UUID, source revision, or device. Binary values use base64. Available attachments include SHA-256 checksums; unavailable bytes do not get a fake value. Source URLs are preserved but never fetched.

## Completeness and ownership

Check `raw_capture_status` before consuming the archive:

- `complete` can include a successful empty archive;
- `partial` means at least one requested branch did not complete;
- `not_requested` means Lossless Health Records was off and the archive is absent;
- `legacy_unavailable` means an older record or peer could not supply it.

The query manifest distinguishes successful-empty, unsupported, skipped, cancelled, and failed queries. Do not infer complete capture from the presence of some records.

Raw records belong to a day by source start time in the captured timezone. Their timestamps are never clipped. Sleep summary fields retain their established noon-to-noon compatibility behavior and may therefore use a different presentation window.

## Tips

- Branch on both top-level schema v6 and archive schema v1.
- Use UUID or documented external identity for deduplication; never collapse similar-looking samples by value/time.
- Treat typed metadata as tagged values and preserve unknown tags/raw enums.
- Complete canonical timestamps are UTC RFC 3339 values. Convert to `time_context.calendar_timezone` only for display.
- Summary categories remain optional and omit empty data.
- VO2 Max summaries include source UUID/time, carry-forward state, and age when available.
- Actual blood-pressure pairs come from canonical correlations. Health.md does not infer sessions or session averages.
- Export smaller ranges when records contain dense routes, ECG waveforms, FHIR/CDA bytes, or attachments.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No JSON file was written | JSON format is disabled | Enable **JSON** in Export Formats. |
| `healthkit_record_archive` is missing | Lossless Health Records was off or the record came from a legacy peer | Check `raw_capture_status`; re-enable lossless capture and re-export if needed. |
| Archive says `partial` | A query failed, was cancelled, skipped, or unsupported | Inspect `query_manifest`, `integrity_warnings`, and top-level `diagnostics.partial_failures`. |
| Archive is complete but empty | Queries succeeded and returned no readable records | This is valid; HealthKit can also make denied read access look empty. |
| Script loses integer/type detail | Typed metadata was flattened | Parse each metadata `{type, value}` envelope instead of coercing values. |
| File is very large | Dense samples or binary data were retained | Export fewer dates or turn Lossless Health Records off when summaries are sufficient. |
| Re-export replaced the file | JSON has no section merge behavior | This is expected; Update falls back to overwrite for JSON. |

## Video outline

- **Suggested title:** Export a Lossless Apple Health Archive as JSON
- **Hook:** “Keep readable daily summaries and the exact public HealthKit records behind them.”
- **Demo flow:** enable JSON and Lossless Health Records, export one day, inspect status/ownership/records/manifest, show a typed record and an intentionally partial example.
- **CTA:** “Next, use the same canonical records as spreadsheet-safe CSV rows.”

## Implementation notes

- `HealthData.toJSON(customization:)` builds the v6 daily document and preserves existing summaries.
- `HealthKitRecordArchiveSerializer` owns deterministic `healthmd.healthkit_records` v1 serialization; app-internal `Codable` is not the public contract.
- `JSONExporter` adds `raw_capture_status`, diagnostics, and the archive.
- `APIExportClient` reuses this public daily JSON inside the API envelope.
- `VaultManager.writeOneFormat(...)` writes the configured JSON path; non-Markdown Update overwrites.
