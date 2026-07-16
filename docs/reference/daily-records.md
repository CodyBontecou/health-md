# Daily records

A Health.md daily record combines a readable summary projection with optional source-level Apple Health records.

```text
healthmd.health_data v6
├── identity, date, timezone, and units
├── optional summary sections
├── raw capture status
├── optional healthkit_record_archive
└── optional exporter diagnostics
```

Use summaries for dashboards and journaling. Use the canonical archive for source identity, exact measurements, provenance, and relationships.

## Top-level fields

| Field | Type | Presence | Meaning |
|---|---|---|---|
| `schema` | string | Always | `healthmd.health_data`. |
| `schema_version` | integer | Always | Current daily contract version, `6`. |
| `date` | `YYYY-MM-DD` string | Normal successful document | Calendar day represented by the summary. |
| `type` | string | Always | Normally `health-data`; serialization-error fallback documents use a distinct value. |
| `time_context` | object | Always | Captured calendar timezone and machine timestamp timezone. |
| `unit_system` | string | JSON | Structured v6 JSON currently reports `metric`; display preferences affect prose, not canonical structured values. |
| `units` | object | JSON/frontmatter | Exported summary key to canonical unit. Empty/list-like fields are omitted. |
| `raw_capture_status` | enum string | Always | `complete`, `partial`, `not_requested`, or `legacy_unavailable`. |
| Summary sections | object/array | Conditional | Emitted only when the selected section has retained data. |
| `healthkit_record_archive` | object | Conditional | Present when source capture was requested and available. |
| `diagnostics` | object | Conditional | Export/fetch partial failures outside the archive query manifest. |

The exact generated top-level paths and observed types are listed in [`generated/core/daily-json-fields.md`](./generated/core/daily-json-fields.md).

## Time context

```json
{
  "time_context": {
    "calendar_timezone": "UTC",
    "timestamp_timezone": "UTC"
  }
}
```

- `calendar_timezone` is the IANA timezone used to assign the daily date and render short clock values.
- `timestamp_timezone` is always `UTC` for complete machine timestamps.
- Canonical archive timestamps have a fixed nine-digit fractional component.
- Summary compatibility windows can differ from canonical ownership. Sleep summaries retain Health.md's established night-oriented attribution, while raw records belong to the day containing their source start date.

## Summary sections

Daily JSON may emit these sections. Fields are omitted when no retained value exists.

| Section | Examples of data represented | Notes |
|---|---|---|
| `sleep` | Duration, stage durations, bedtime/wake, stage samples | Readable projection; raw sleep categories remain in the archive. |
| `activity` | Steps, energies, exercise, stand time/hours, distances, VO2 Max | VO2 Max includes source provenance and carry-forward state when available. |
| `heart` | Resting/walking/average/min/max rate, HRV, samples | Summary values can be aggregates over many source samples. |
| `vitals` | Respiratory rate, oxygen, temperature, blood pressure, glucose, samples | Blood-pressure truth is the canonical correlation graph, not inferred sessions. |
| `body` | Weight, height, BMI, body fat, lean mass, waist | Canonical structured units are stable. |
| `nutrition` | Energy, macronutrients, water, caffeine, fats | Nutrient totals are projections over selected source records. |
| `mindfulness` | Mindful activity and State of Mind views | Source UUIDs and exact labels/associations are retained in canonical records. |
| `mobility` | Walking, stairs, running mechanics, six-minute walk | Values use canonical units independent of display preference. |
| `hearing` | Headphone and environmental sound levels | Additional hearing events may be archive-only. |
| `reproductiveHealth` | Selected reproductive summary values | Many newer reproductive/pregnancy definitions are archive-only. |
| `cyclingPerformance` | Speed, power, cadence, FTP | Workout-associated samples also appear in workout graphs. |
| `vitamins` | Every selected vitamin total | Microgram keys use the canonical `µg` unit in the v6 dictionary. |
| `minerals` | Every selected mineral total | Microgram and milligram nutrients remain distinct. |
| `symptoms` | Symptom occurrence counts | Source categories and raw values live in the archive. |
| `medications` | Inventory summaries and dose-event projections | Canonical dose events and inventory identities are retained separately. |
| `other` | UV, daylight, falls, alcohol, insulin, hygiene, water/depth | Exact availability depends on OS and authorization. |
| `workouts` | Identity, type, duration, distance, rates, laps, splits, route, series | The canonical workout graph is authoritative for complete public source data. |

The exhaustive metric-to-summary-key table is generated at [`generated/core/metric-catalog.md`](./generated/core/metric-catalog.md). It includes every selected metric definition, category, HealthKit identifier, source aggregation, canonical summary keys, units, and archive-only status. [`generated/core/metric-examples.md`](./generated/core/metric-examples.md) provides one synthetic, source-derived reference entry for every metric ID.

## Omission and null rules

Health.md favors omission over fabricated values:

- A missing metric is not exported as zero.
- An empty optional summary section is omitted.
- A missing source/device field is omitted from the canonical object.
- A successful empty source query is represented in the query manifest with `record_count: 0`; it is not converted into a fake sample.
- UUID-free public values do not receive fabricated HealthKit UUIDs.
- Unavailable binary bytes do not receive fabricated data or checksums.

Downstream databases should distinguish `missing`, `zero`, `false`, and `empty list`.

## Summary keys versus JSON fields

Health.md exposes two structured summary styles:

1. Nested JSON fields such as `activity.activeCalories`.
2. Flat frontmatter/Bases keys such as `active_calories`.

The data dictionary maps flat keys to metric IDs, units, HealthKit identifiers, and aggregation rules. A flat key can be renamed by the user; its `canonicalKey` remains stable in the dictionary.

JSON field names and flat frontmatter names are not interchangeable. Use the generated references for each format rather than guessing a conversion.

## Units

Structured output uses stable units. Examples include:

- distances in explicit meter/kilometer/mile fields;
- body mass in kilograms;
- temperatures in degrees Celsius;
- percentages either as documented ratios or explicit percent fields;
- Stand Time in minutes and Stand Hours as a distinct hour count;
- microgram nutrients as `µg`, matching the production v6 dictionary;
- exact canonical HealthKit units inside source quantity payloads.

Markdown prose can use the selected Metric or Imperial display preference. Never infer a structured unit from rendered prose.

## Capture-state examples

### Lossless complete

`raw_capture_status: complete` with an archive means all planned supported branches completed. The archive can legitimately contain zero records.

### Lossless partial

`raw_capture_status: partial` means at least one requested branch failed, was cancelled, was skipped, or was unsupported. Successful sibling records remain usable. Inspect the manifest before accepting the day as complete.

### Summary-only

`raw_capture_status: not_requested` means Lossless Health Records was explicitly off for this export. No canonical archive is present.

### Legacy peer or persisted record

`raw_capture_status: legacy_unavailable` means the source predates canonical archive support or arrived from a peer that could not provide it.

## Complete synthetic examples

- [`generated/core/summary-day.json`](./generated/core/summary-day.json)
- [`generated/core/lossless-day.json`](./generated/core/lossless-day.json)
- [`generated/core/summary-day.csv`](./generated/core/summary-day.csv)
- [`generated/core/lossless-day.csv`](./generated/core/lossless-day.csv)
- [`generated/core/summary-day.md`](./generated/core/summary-day.md)
- [`generated/core/summary-day-bases.md`](./generated/core/summary-day-bases.md)

These files are generated by production exporters. They are examples, not templates to mutate into a different schema.
