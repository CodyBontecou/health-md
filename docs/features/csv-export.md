# CSV Export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Export Formats
- **Source files:** `HealthMd/Shared/Export/CSVExporter.swift`, `HealthMd/Shared/Models/FormatPreferences.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

CSV export writes Apple Health data as a spreadsheet-friendly `.csv` file for each exported date. Each row is one metric or sample, with columns for date, category, metric name, value, unit, and optional timestamp.

Use CSV when you want to open Health.md data in Numbers, Excel, Google Sheets, DuckDB, or other table tools.

## Who it is for

- Spreadsheet users.
- Users who want quick charts without writing a JSON parser.
- Analysts who prefer long-form metric rows over nested objects.

Use Markdown for human-readable notes and JSON for nested workouts/routes/time-series structures.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. In **Export Formats**, enable **CSV**.
4. Export a date or date range.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected.
- At least one metric enabled under **Health Metrics**.
- **CSV** selected in Export Formats.

## Setup

1. Enable **CSV** in **Export Formats**.
2. Choose metric categories under **Health Metrics**.
3. Set unit preference in **Format Customization → Units**.
4. Choose filename/folder templates if needed.
5. Export and open the `.csv` in your spreadsheet app.

## Example output

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-05-12,Activity,Steps,8432,count
2026-05-12,Activity,Active Calories,420,kcal
2026-05-12,Sleep,Total Duration,27000,seconds
2026-05-12,Heart,Resting Heart Rate,58,bpm
2026-05-12,Workouts,Running Duration,1800,seconds
```

Example path:

```text
MyVault/Health/2026-05-12.csv
```

## Tips

- CSV is “long” format: filter by Category or Metric to isolate values.
- Some sample rows include a Timestamp column, such as heart-rate samples or sleep-stage intervals.
- For charts over time, export a date range and combine CSV files in your spreadsheet or script.
- Use consistent units before building charts.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No CSV file was written | CSV format is disabled | Enable **CSV** in Export Formats. |
| Spreadsheet splits rows oddly | A value contains punctuation or labels | Import as CSV and keep the standard comma delimiter. |
| Re-export replaced edits | CSV has no merge/update structure | Do not hand-edit generated CSV files; re-export from Health.md. |
| Values look like seconds | Durations are exported as numeric seconds for analysis | Convert seconds to hours/minutes in your spreadsheet. |
| Some timestamps are blank | Daily aggregate rows do not have a specific sample timestamp | This is expected; only sample rows use Timestamp. |

## Video outline

- **Suggested title:** Export Apple Health to CSV for Spreadsheets
- **Hook:** “If you want Apple Health in a spreadsheet, Health.md can write clean CSV files.”
- **Demo flow:**
  1. Enable CSV export.
  2. Export a week of data.
  3. Open one CSV and explain columns.
  4. Import multiple files into a spreadsheet.
  5. Create a simple steps or sleep chart.
- **Key screenshot/recording moments:** CSV toggle, generated CSV, spreadsheet filter/chart.
- **CTA / next video:** “Next, we’ll choose date, time, and unit formats.”

## Implementation notes

- `HealthData.toCSV(customization:)` renders a header row followed by metric rows.
- Columns are `Date,Category,Metric,Value,Unit,Timestamp`.
- Unit conversion uses `UnitConverter` from `FormatPreferences.swift` where applicable.
- CSV writes one file per selected date and format through `VaultManager.writeOneFormat(...)`.
- Write mode `.update` falls back to overwrite for CSV because there is no Markdown section structure to merge.
