# JSON Export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Export Formats
- **Source files:** `HealthMd/Shared/Export/JSONExporter.swift`, `HealthMd/Shared/Models/AdvancedExportSettings.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

JSON export writes Apple Health data as a structured `.json` file for each exported date. The file contains top-level metadata (`date`, `type`, `units`) and nested objects for categories with data, such as `sleep`, `activity`, `heart`, `vitals`, `nutrition`, `mindfulness`, `mobility`, and `workouts`.

Use JSON when you want Health.md output that is easy to parse from scripts, notebooks, dashboards, or other apps.

## Who it is for

- Users analyzing health data with code.
- People feeding health summaries into automations or LLM workflows.
- Users who want nested workout details, laps, splits, routes, and time-series samples when available.

Use Markdown for reading in Obsidian and CSV for spreadsheet-style rows.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. In **Export Formats**, enable **JSON**.
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
  "date": "2026-05-12",
  "type": "health-data",
  "units": "metric",
  "activity": {
    "steps": 8432,
    "activeCalories": 420,
    "exerciseMinutes": 45
  },
  "sleep": {
    "totalDuration": 27000,
    "totalDurationFormatted": "7h 30m",
    "bedtime": "23:15",
    "bedtimeISO": "2026-05-11T23:15:00Z"
  }
}
```

Example path:

```text
MyVault/Health/2026-05-12.json
```

## Tips

- JSON uses nested category objects, so check whether a key exists before reading it.
- Durations are usually numeric seconds plus a formatted companion field when useful.
- Some raw values remain in HealthKit base units while formatted strings use your unit preference.
- Use filename and folder templates to make JSON exports easy to batch-process.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No JSON file was written | JSON format is disabled | Enable **JSON** in Export Formats. |
| A category is missing | That category had no data or no enabled metrics | Enable metrics and verify Apple Health has samples for the date. |
| Re-export replaced the file | JSON has no section merge behavior | This is expected; Update falls back to overwrite for JSON. |
| Script fails on missing keys | JSON omits empty categories | Treat category fields as optional. |
| Units are unexpected | JSON includes raw and formatted values | Prefer formatted fields for display; inspect `units` for user preference. |

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
- JSON includes detailed arrays for sleep stages, samples, workout laps, splits, routes, and time-series data when present in the snapshot.
- `VaultManager.writeOneFormat(...)` writes JSON with the configured filename and folder path.
- Write mode `.update` only merges Markdown; JSON is overwritten with fresh content.
