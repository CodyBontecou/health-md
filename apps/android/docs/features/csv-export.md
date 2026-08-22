# CSV export

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export
- **Source files:** `data/export/CsvExporter.kt`

## What it does

Writes spreadsheet-friendly CSV with one row per metric — and, when granular data is included, one row per timestamped sample. The header is always six columns: `Date,Category,Metric,Value,Unit,Timestamp`.

## Who it is for

- Spreadsheet users (Excel, Google Sheets, LibreOffice).
- Data analysts pulling health data into Python/R notebooks.

## Where to find it

1. Enable **CSV** in **Export Format** on the Export tab.
2. Export; one `.csv` file appears per day at your destination.

## Prerequisites

- Health Connect permission for the categories you want exported.
- A folder selected through the Android folder picker.
- CSV enabled in [multi-format export](./multi-format-export.md).

## Setup

1. Enable the CSV format card.
2. (Optional) Enable granular data if you want timestamped sample rows, not just daily aggregates.
3. Export and open the file in your spreadsheet app.

## Example output

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-05-12,Sleep,Total Sleep,7.2,hours,
2026-05-12,Activity,Steps,8432,count,
2026-05-12,Heart,Heart Rate Sample,62,bpm,2026-05-12T07:41:00
```

Aggregate rows leave the Timestamp column empty; sample rows carry an ISO 8601 timestamp.

## Tips

- Numbers are formatted with US separators so spreadsheets parse them consistently regardless of device locale.
- Values containing commas or quotes are escaped with standard CSV quoting — files open cleanly in Excel and Sheets.
- Metric labels are the cross-platform canonical ones (for example `Flights Climbed`, `Cardio Fitness (VO2 Max)`); a few Android-only extras keep a second row where Health Connect has no Apple equivalent.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Only aggregate rows, no samples | Granular data not enabled | Enable granular data for timestamped sample rows |
| One column instead of six in Excel | File opened with wrong delimiter settings | Import as comma-separated UTF-8 |
| Two similar rows for one metric | One is the canonical label, the other an Android extra | Expected; filter on the Metric column |

## Video outline

- **Suggested title:** Health Data in Your Spreadsheet: CSV Exports
- **Hook:** "Pivot-table your sleep."
- **Demo flow:**
  1. Export a day as CSV.
  2. Open in Google Sheets.
  3. Build a quick chart from Heart Rate Sample rows.
- **Key screenshot/recording moments:** raw CSV text, spreadsheet chart.
- **CTA / next video:** [JSON export](./json-export.md).

## Implementation notes

`CsvExporter` emits the fixed six-column header and uses `formatInvariant` (Locale.US) for numbers and ISO 8601 for timestamps. Label canonicalization (Core Sleep + Light Sleep second row, Flights Climbed, VO2 Max under Activity with the Mobility row kept as an Android extra, HRV, Blood Oxygen Sample, Sleep Stage `stage (Ns)` rows) follows the Tier-0/Tier-1 ledger documented in [`android-ios-gap-matrix.md`](../export-contract/android-ios-gap-matrix.md) and the contract in [`ios-export-contract.md`](../export-contract/ios-export-contract.md) §3. Cells are RFC 4180-quoted when they contain commas, quotes, or newlines.
