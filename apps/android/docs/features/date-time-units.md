# Date, Time, and Unit Preferences

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Settings
- **Source files:** `domain/model/FormatPreferences.kt`, `presentation/settings/FormatCustomizationScreen.kt`, `data/export/MarkdownExporter.kt`, `data/export/JsonExporter.kt`, `data/export/CsvExporter.kt`

## What it does

Choose how dates, times, and quantities are written in your exports: seven date formats, four time formats (12/24-hour, with or without seconds), and a Metric/Imperial unit system. The choices shape human-readable output in every format — Markdown, Obsidian Bases, JSON, and CSV — while machine-readable JSON values stay in their canonical units.

## Who it is for

- Anyone whose journal reads better as `January 13, 2026` than `2026-01-13`, or vice versa.
- People outside the US who want 24-hour clock times and Metric units (the defaults).
- Spreadsheet users who want CSV numbers pre-converted to their unit system.

## Where to find it

1. Open the **Export** tab.
2. Tap the **Advanced Export Settings** card ("Metrics, daily notes, individual tracking, format customization").
3. Tap **Format Customization** — the row whose subtitle shows your current date format and unit system.
4. A quick Metric/Imperial **Units** toggle also sits directly on the Export tab's configuration section, without opening Format Customization.

## Prerequisites

- None beyond a working export setup. Preferences apply to future exports; existing files are immutable historical output.

## Setup

1. Under **Date Format**, pick one of:
   - **ISO 8601** — `2026-01-13` (default; best for sorting)
   - **US Short** — `01/13/2026`
   - **US Long** — `January 13, 2026`
   - **EU Short** — `13/01/2026`
   - **EU Long** — `13 January 2026`
   - **Compact** — `20260113`
   - **Friendly** — `Mon, Jan 13, 2026`
2. Under **Time Format**, pick:
   - **24-hour** — `14:30` (default)
   - **24-hour with seconds** — `14:30:45`
   - **12-hour** — `2:30 PM`
   - **12-hour with seconds** — `2:30:45 PM`
3. Under **Unit System**, pick **Metric** ("Kilometers, kilograms, Celsius") or **Imperial** ("Miles, pounds, Fahrenheit"). Metric is the default.
4. Run a preview or export; the choices apply to all formats written in that run.

Formatting preferences persist with your export settings and travel between devices inside a [Shared Setup](./share-my-setup.md) file (`presentation.dateFormat`, `presentation.timeFormat`, `presentation.units`).

## Where each preference applies

| Output surface | Date format | Time format | Unit system |
|---|---|---|---|
| [Markdown](./markdown-export.md) | Frontmatter `date`, `# Health Data — <date>` heading | Workout times, sleep-stage tables, timestamped sample tables | Display strings for distance, weight, temperature, speed, water |
| [Obsidian Bases](./obsidian-bases.md) | Frontmatter date | Workout/event times | Same display conversions as Markdown |
| [JSON](./json-export.md) | Top-level `date`; `units: metric \| imperial` declares the system | — | Numeric values stay canonical (e.g. `distance` in meters); `distanceFormatted` follows the preference |
| [CSV](./csv-export.md) | `Date` column | Bedtime/wake times, sample timestamps | Numeric values are converted (kg/lbs, °C/°F, km/mi) with a unit column naming the unit |
| Filenames | — | — | — |

Filename dates are **not** affected: the `{date}` placeholder in [filename templates](./filename-templates.md) always renders ISO `yyyy-MM-dd` so files sort correctly regardless of the display preference.

## Unit conversions

| Quantity | Metric | Imperial |
|---|---|---|
| Distance (large) | km | mi |
| Distance (small) | m | ft below 0.1 mi |
| Weight | kg | lbs (× 2.20462) |
| Height | cm | ft′ in″ |
| Temperature | °C | °F |
| Speed | km/h | mph |
| Length (waist, etc.) | cm | in |
| Volume (water) | L | oz (× 33.814) |

## Example output

The same day under the defaults (ISO, 24-hour, Metric) vs US Long + 12-hour + Imperial:

```markdown
# Health Data — 2026-01-13

## 🏃 Activity
- **Walking/Running Distance:** 5.00 km
- **Water:** 2.00 L
- **Running** — 30m (at 14:30) — 5.00 km
```

```markdown
# Health Data — January 13, 2026

## 🏃 Activity
- **Walking/Running Distance:** 3.11 mi
- **Water:** 67.6 oz
- **Running** — 30m (at 2:30 PM) — 3.11 mi
```

The three settings are independent: the heading follows the date format, values follow the unit system, and workout clock times follow the time format.

## Tips

- Keep **ISO 8601** for daily notes you sort or link by date; `Friendly` reads best in journal prose.
- JSON consumers should read numeric values, never parse `distanceFormatted` — the formatted string follows your display preference, the number does not.
- CSV numbers are converted to your unit system and labeled in a unit column; check that column before charting.
- The [export preview](./export-preview.md) renders with your current preferences, so preview before re-exporting.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Filename date didn't change after switching format | `{date}` is always ISO `yyyy-MM-dd` | Use other [filename template](./filename-templates.md) placeholders or keep ISO for sorting |
| JSON numbers unchanged after switching to Imperial | JSON numeric fields are canonical by design | Read `units` and `distanceFormatted`, or convert client-side |
| Old files still show the previous format | Existing files are immutable historical output | Re-export the affected dates |
| Change didn't stick | Edits run through the "Prevent Accidental Changes" lock | Unlock configuration changes in Settings, then edit |

## Video outline

- **Suggested title:** Dates, Times, and Units: Make Health.md Exports Read Your Way
- **Hook:** "Your data, in your units — without breaking the machine-readable layer."
- **Demo flow:**
  1. Show default ISO/24-hour/Metric export.
  2. Switch to Friendly + 12-hour + Imperial in Format Customization.
  3. Preview the same day and diff the two outputs side by side.
- **Key screenshot/recording moments:** the three radio groups on Format Customization; Metric vs Imperial CSV rows.
- **CTA / next video:** [Frontmatter customization](./frontmatter-customization.md).

## Implementation notes

- `DateFormatPreference` (7 values with Java `DateTimeFormatter` patterns), `TimeFormatPreference` (4 values), and `UnitPreference` (`METRIC`, `IMPERIAL`) live in `domain/model/FormatPreferences.kt`; `UnitConverter` implements every conversion table above. Defaults (`ISO8601`, `HOUR_24`, `METRIC`) are set on `FormatCustomization` in `domain/model/ExportSettings.kt` and are unchanged by `analyticalDefault()`.
- `FormatCustomizationScreen.kt` renders the three sections plus the frontmatter link and markdown template options; the Export screen's quick picker writes the same `unitPreference` through `ExportViewModel.updateFormatCustomization`, and both paths run through `performConfigurationChange` (accidental-change lock). `applyDatePlaceholders` in `ExportSettings.kt` hardcodes `{date}` to `yyyy-MM-dd`.
- Exporters: `MarkdownExporter` and `ObsidianBasesExporter` format dates, times, and unit strings for display; `JsonExporter` emits `units` (lowercase enum name) and keeps numeric fields canonical with `distanceFormatted` as the display string; `CsvExporter` converts numeric values and appends a unit column.
- Shared Setup wire format: `SharedSetupV2Mapper` writes lowercase enum names in `presentation` (`dateFormat`, `timeFormat`, `units`); import maps `imperial` to `IMPERIAL` and anything else to `METRIC`, and decodes date/time values by exact enum name.
- Deliberate differences from the Apple page (`apps/apple/docs/features/date-time-units.md`): Apple documents a two-context time model (`calendar_timezone` vs UTC machine timestamps) and canonical structured units under export schema v8; Android exports carry no time-context block — times are formatted local wall-clock values from Health Connect — and Android JSON is frozen v4/analytical v5. Apple's CSV uses canonical `Unit` values; Android's CSV converts numeric values to the chosen system. These are platform differences, not aliases.
