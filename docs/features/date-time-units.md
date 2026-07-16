# Date, Time, and Units

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Format Customization
- **Source files:** `HealthMd/iOS/Views/FormatCustomizationView.swift`, `HealthMd/Shared/Models/FormatPreferences.swift`, `HealthMd/Shared/Models/HealthKitRecord.swift`

## What it does

Date/Time settings control human-readable formatting. Unit settings control Markdown prose and display strings. Structured schema v7 summaries and canonical records use stable units independent of the Metric/Imperial display preference. The exhaustive field and unit contract is in [Daily records](../reference/daily-records.md).

## Setup

1. Open **Export → Format Customization**.
2. Pick a date format (ISO is best for sorting).
3. Pick 12/24-hour time and optional seconds.
4. Pick Metric or Imperial display units.
5. Preview, then re-export dates that should use the new presentation.

## Two time contexts

Every daily v7 record carries:

```yaml
time_context:
  calendar_timezone: America/Los_Angeles
  timestamp_timezone: UTC
```

- `calendar_timezone` is the captured IANA timezone for the top-level date, day boundaries, and short clock fields.
- Complete machine timestamps are UTC.
- Canonical source rows use RFC 3339 UTC with a fixed nine-digit fractional component.
- `HKTimeZone` in metadata belongs to the source sample and may differ during travel.

Canonical day ownership uses source start time in the half-open captured calendar day. Raw start/end are never clipped. Sleep summaries intentionally retain their noon-to-noon compatibility window, so use archive ownership for reconstructing events.

## Structured unit contract

- Frontmatter/Bases values and their `units` map are canonical.
- JSON summaries and canonical quantity payloads are canonical.
- CSV uses canonical `Unit` values. In schema v7, extended cycling, vitamin, mineral, reproductive, and other summary rows resolve those values from the production data dictionary.
- Markdown prose may use selected display units.
- Explicit suffixes are authoritative: `weight_kg`, `height_m`, `water_l`, `walking_running_km`, and `walking_running_mi`.

Example prose:

```markdown
- **Walking/Running Distance:** 3.11 mi
- **Weight:** 154.3 lbs
- **Body Temperature:** 98.6°F
```

The corresponding structured values remain stable.

## Important units

- Stand Time uses minutes; Stand Hours is a separate count of stood hours.
- VO2 Max uses `mL/kg/min` in summary output and keeps source time/UUID/carry-forward provenance.
- HealthKit record quantities keep the exact canonical unit selected for that object type.
- Micronutrients are not all interchangeable. Structured summary keys and the data dictionary use `µg` versus `mg`; canonical HealthKit quantity payloads preserve the reviewed source/query unit string, including `mcg` for microgram source types. These strings describe the same microgram scale in different public layers and must not be confused with milligrams.
- Binary metadata is base64 in canonical JSON, not a unit conversion.

## Tips

- Use ISO dates and complete UTC timestamps for joins/sorting.
- Convert UTC to `calendar_timezone` only for display.
- Do not reinterpret a carried-forward VO2 value as measured on the export date.
- Read units from the record or data dictionary rather than hard-coding them.
- Re-export v5 or v6 dates when corrected v7 unit, provenance, or roll-up calendar behavior matters.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| ISO and clock times differ | ISO is UTC; clock uses captured calendar timezone | Convert the UTC instant for display. |
| Record crosses midnight | Raw dates are intentionally unclipped | Use start-time ownership and retain full end time. |
| Sleep appears on a different raw day | Summary uses compatibility noon-to-noon behavior | Use canonical ownership for source records. |
| Summary/dictionary shows `µg` while a canonical source payload shows `mcg` | Both denote the reviewed microgram scale in their respective layers | Trust each exported unit; do not rescale either to `mg`. |
| Old files use older units | Existing files are immutable historical output | Re-export under schema v7. |
| Filename date did not change | Filename placeholders are separate | Update the filename template. |

## Video outline

- **Suggested title:** Understand Health.md Dates, Timezones, and Exact Units
- **Hook:** “Readable local time and exact machine timestamps can coexist without changing source data.”
- **Demo flow:** change display settings, inspect UTC/calendar timezone, compare a midnight-spanning record and sleep summary, then show canonical micronutrient units.

## Implementation notes

- `DateFormatPreference`, `TimeFormatPreference`, and `UnitConverter` handle presentation.
- `ExportTimeContext` captures daily calendar timezone while canonical timestamps remain UTC.
- `HealthKitDailyOwnershipMetadata` records the exact owner interval and assignment rule.
- `HealthKitRecordCatalog` defines reviewed canonical quantity units, including micronutrients.
