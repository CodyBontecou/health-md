# Date, Time, and Units

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Format Customization
- **Source files:** `HealthMd/iOS/Views/FormatCustomizationView.swift`, `HealthMd/Shared/Models/FormatPreferences.swift`, `HealthMd/Shared/Models/AdvancedExportSettings.swift`

## What it does

Date and Time settings control how Health.md formats exported dates and times. Unit settings control human-readable Markdown prose, previews, and display strings for distances, weights, temperatures, lengths, volumes, speeds, paces, and related values. Structured data in schema v4 exports (frontmatter, Obsidian Bases, JSON values/units, and CSV values/Unit columns) uses stable canonical units regardless of the Metric/Imperial display preference.

## Who it is for

- Users outside the default ISO/24-hour/metric setup.
- Users who want exports to match their locale or Obsidian habits.
- Users building charts where consistent units matter.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Tap **Format Customization**.
4. Use **Date Format**, **Time Format**, and **Unit System**.

## Prerequisites

- Health.md installed and HealthKit permission granted.
- A selected export format.
- Existing or future exports to regenerate with the new formatting.

## Setup

1. Open **Export → Format Customization**.
2. Pick a **Date Format**:
   - ISO 8601: `2026-01-13`
   - US Short: `01/13/2026`
   - US Long: `January 13, 2026`
   - EU Short: `13/01/2026`
   - EU Long: `13 January 2026`
   - Compact: `20260113`
   - Friendly: `Mon, Jan 13, 2026`
3. Pick a **Time Format**:
   - 24-hour: `14:30`
   - 24-hour with seconds: `14:30:45`
   - 12-hour: `2:30 PM`
   - 12-hour with seconds: `2:30:45 PM`
4. Pick **Metric** or **Imperial** units.
5. Check the preview.
6. Re-export any existing dates that should use the new style.

## Example output

Metric settings:

```markdown
- **Walking/Running Distance:** 5.00 km
- **Weight:** 70.0 kg
- **Body Temperature:** 37.0°C
```

Imperial settings:

```markdown
- **Walking/Running Distance:** 3.11 mi
- **Weight:** 154.3 lbs
- **Body Temperature:** 98.6°F
```

## Tips

- Use ISO 8601 dates for sorting, scripting, and Obsidian queries.
- Choose 24-hour time if you want compact, unambiguous workout and sleep timestamps.
- Spreadsheet formulas and dashboards can rely on schema v4 structured exports keeping the same units across Metric/Imperial display settings.
- Complete ISO timestamps are always UTC. Short display times use `time_context.calendar_timezone`, which is captured with the daily record.
- Large-distance frontmatter keys use explicit unit suffixes and are emitted together when enabled, for example `cycling_km` and `cycling_mi`.
- Re-export after changing units; existing files are not rewritten automatically.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Old files still show old units | Settings only affect new exports | Re-export the affected dates. |
| Filename date did not change | Filename templates use fixed `{date}` placeholder behavior | Date format changes content, not filename placeholder expansion. |
| CSV duration values are in seconds | Durations are exported numerically for analysis | Convert seconds in your spreadsheet or use Markdown for formatted durations. |
| JSON has both raw and formatted fields | JSON preserves machine-friendly values | Use formatted fields for display and raw fields for calculations. |
| ISO and short clock times look different | ISO timestamps are UTC; short clock fields use the captured calendar timezone | Convert the UTC instant to `time_context.calendar_timezone`; do not set the device timezone to UTC. |
| Obsidian sorting is strange | Non-ISO date strings sort as text | Use ISO 8601 for queryable dates. |

## Video outline

- **Suggested title:** Customize Dates, Times, and Units in Health.md
- **Hook:** “Make Health.md exports match how you actually read measurements.”
- **Demo flow:**
  1. Show default preview.
  2. Switch date and time formats.
  3. Switch Metric to Imperial.
  4. Export and compare Markdown prose output, then show that CSV/JSON/frontmatter values remain unit-stable for automation.
  5. Explain why ISO dates are best for automation.
- **Key screenshot/recording moments:** Format preview, unit picker, before/after export.
- **CTA / next video:** “Next, we’ll customize frontmatter fields for Obsidian.”

## Implementation notes

- `DateFormatPreference` and `TimeFormatPreference` define the available formatter patterns.
- `UnitPreference` supports `.metric` and `.imperial`.
- `UnitConverter` formats distance, weight, height, temperature, pace, speed, length, and volume.
- `FormatCustomizationView.previewText` shows a live sample for date, time, distance, weight, and temperature.
- Filename/folder placeholders are handled separately by `AdvancedExportSettings.applyDatePlaceholders(...)`.
