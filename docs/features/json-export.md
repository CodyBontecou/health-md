# JSON Export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Export Formats
- **Source files:** `HealthMd/Shared/Export/JSONExporter.swift`, `HealthMd/Shared/Models/AdvancedExportSettings.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

JSON export writes Apple Health data as a structured `.json` file for each exported date. The file contains top-level metadata (`date`, `type`, `units`) and nested objects for categories with data, such as `sleep`, `activity`, `heart`, `vitals`, `nutrition`, `mindfulness`, `mobility`, and `workouts`.

Use JSON when you want Health.md output that is easy to parse from scripts, notebooks, dashboards, APIs, or other apps. The API Endpoint export target also uses this same public daily JSON shape inside its upload envelope.

## Who it is for

- Users analyzing health data with code.
- People feeding health summaries into automations or LLM workflows.
- Users who want nested workout details, laps, splits, routes, paired blood-pressure readings, and other time-series samples when available.

Use Markdown for reading in Obsidian and CSV for spreadsheet-style rows.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. In **Export Formats**, enable **JSON** for file exports, or choose **API Endpoint** if you want Health.md to POST JSON records directly.
4. Export a date or date range.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected.
- At least one metric enabled under **Health Metrics**.
- **JSON** selected in Export Formats.

## Setup

1. Enable **JSON** in **Export Formats**.
2. Keep or disable other formats depending on whether you also want Markdown, CSV, or Bases files.
3. Choose filename and folder templates.
4. Choose date/time and unit preferences in **Format Customization**.
5. Export.

## Example output

```json
{
  "schema": "healthmd.health_data",
  "schema_version": 5,
  "date": "2026-05-12",
  "type": "health-data",
  "time_context": {
    "calendar_timezone": "America/Los_Angeles",
    "timestamp_timezone": "UTC"
  },
  "unit_system": "metric",
  "units": {
    "active_calories": "kcal"
  },
  "activity": {
    "steps": 8432,
    "activeCalories": 420,
    "exerciseMinutes": 45
  },
  "sleep": {
    "totalDuration": 27000,
    "totalDurationFormatted": "7h 30m",
    "bedtime": "23:15",
    "bedtimeISO": "2026-05-12T06:15:00Z"
  }
}
```

Example path for a file export:

```text
MyVault/Health/2026-05-12.json
```

For API Endpoint export, the same daily record appears inside a `healthmd.api_export` POST body instead of being written as a standalone `.json` file. With WHOOP's provider-specific rollout flag enabled, API Endpoint uses envelope v2 and includes schema-v1 WHOOP sidecars under `external_records`; otherwise the wrapper remains v1.

## Tips

- JSON uses nested category objects, so check whether a key exists before reading it.
- Complete timestamps use UTC and end in `Z`; convert them to `time_context.calendar_timezone` for display. Short clock fields such as `bedtime` are already formatted in that calendar timezone.
- `HKTimeZone` inside sample metadata is source metadata and may differ from the daily calendar timezone.
- With Time-Series Data enabled, `vitals.bloodPressureSamples` retains each systolic/diastolic pair, start/end timestamp, unit, and available correlation metadata.
- Durations are usually numeric seconds plus a formatted companion field when useful.
- Numeric structured values use the canonical units identified by the top-level `units` map; formatted companion strings are intended for display.
- Use filename and folder templates to make JSON file exports easy to batch-process.
- Use [API Endpoint Export](./api-endpoint-export.md) when you want Health.md to send JSON directly to your own HTTP(S) ingest endpoint.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No JSON file was written | JSON format is disabled | Enable **JSON** in Export Formats. |
| A category is missing | That category had no data or no enabled metrics | Enable metrics and verify Apple Health has samples for the date. |
| Re-export replaced the file | JSON has no section merge behavior | This is expected; Update falls back to overwrite for JSON. |
| Script fails on missing keys | JSON omits empty categories | Treat category fields as optional. |
| Units are unexpected | JSON includes canonical and formatted values | Inspect `units` for the canonical unit and use formatted fields for display. |
| ISO timestamps appear several hours different | Complete timestamps are UTC while clock fields use the calendar timezone | They represent the same instant. Parse the UTC value and convert it to `time_context.calendar_timezone`; do not change the device timezone to UTC. |

## Video outline

- **Suggested title:** Export Apple Health as JSON from Health.md
- **Hook:** “Markdown is great for reading; JSON is great for building with your health data.”
- **Demo flow:**
  1. Enable JSON export.
  2. Export one day.
  3. Open the JSON file and show top-level category objects.
  4. Show workout details if present.
  5. Mention scripts and dashboards as next steps.
- **Key screenshot/recording moments:** Export Formats, generated `.json`, nested workout object.
- **CTA / next video:** “Next, we’ll export the same data as CSV for spreadsheets.”

## Implementation notes

- `HealthData.toJSON(customization:)` builds a `[String: Any]` dictionary and serializes it with pretty printing.
- Empty categories are omitted from the output.
- JSON includes detailed arrays for sleep stages, paired blood-pressure samples, other vital samples, workout laps, splits, routes, and time-series data when present in the snapshot.
- `VaultManager.writeOneFormat(...)` writes JSON with the configured filename and folder path.
- `APIExportClient` reuses the public daily JSON output for each record in the API upload envelope.
- Write mode `.update` only merges Markdown; JSON is overwritten with fresh content.
