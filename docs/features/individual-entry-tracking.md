# Individual Entry Tracking

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Individual Entry Tracking
- **Source files:** `HealthMd/iOS/Views/IndividualTrackingView.swift`, `HealthMd/Shared/Managers/IndividualEntryExporter.swift`, `HealthMd/Shared/Models/HealthKitRecord.swift`

## What it does

Individual Entry Tracking creates separate timestamped Markdown files for selected source events in addition to the normal daily summary. With schema v6 and **Lossless Health Records** on, those files derive from canonical HealthKit records rather than inferred daily values.

Supported source-event notes include ordinary selected quantity/category records, State of Mind, workouts, blood-pressure correlations, medication doses, symptoms, vitals, clinical/specialized records, and other enabled record-level metrics. Each canonical entry can retain original UUID, exact start/end, source, metric attribution, and the complete canonical record JSON.

## Authority and fallback rules

When `healthkit_record_archive` is present, it is the sole authority for individual-entry identity and payloads:

- one source UUID can produce at most one entry for a selected metric;
- repeated compatibility projections do not create duplicate notes;
- failed, skipped, unsupported, or successful-empty canonical queries do not fall back to a daily aggregate;
- blood pressure comes from a real correlation and its real systolic/diastolic components;
- workout compatibility data may enrich presentation only after a UUID match.

For explicit summary-only (`not_requested`) or legacy (`legacy_unavailable`) data, Health.md can retain compatibility entry behavior, including clearly marked aggregate fallbacks where supported. A daily blood-pressure average is never substituted when a canonical archive exists.

## Setup

1. Leave **Lossless Health Records** on for source-backed entries.
2. Open **Export → Individual Entry Tracking**.
3. Enable **Individual Entry Tracking**.
4. Use **Track All Enabled Metrics** or choose individual metrics.
5. Set **Entries Folder** (default `entries`).
6. Keep **Organize by Category** on if desired.
7. Adjust the filename template (default `{date}_{time}_{metric}`).
8. Export a date with matching source records.

## Paths and filenames

Default layout:

```text
MyVault/Health/entries/mindfulness/2026_07_15_1030_daily_mood.md
MyVault/Health/entries/workouts/2026_07_15_0700_workouts.md
MyVault/Health/entries/vitals/2026_07_15_0900_blood_pressure.md
```

Placeholders:

- `{date}` → `2026_07_15`
- `{time}` → `1030`
- `{metric}` → `daily_mood`, `workouts`, `blood_glucose`
- `{category}` → `mindfulness`, `workouts`, `vitals`

When two generated paths share a minute, Health.md adds a deterministic seconds/milliseconds suffix rather than dropping an entry.

## Canonical entry example

```markdown
---
date: 2026-07-15
time: "10:30"
datetime: 2026-07-15T17:30:00.125000000Z
metric: daily_mood
entry_kind: healthkit_record
original_uuid: 10000000-0000-0000-0000-000000000001
object_type_identifier: HKDataTypeStateOfMind
record_kind: state_of_mind
start_datetime: 2026-07-15T17:30:00.125000000Z
end_datetime: 2026-07-15T17:30:00.125000000Z
has_undetermined_duration: false
raw_record_schema: healthmd.healthkit_records
raw_record_schema_version: 1
canonical_record_json: '{"original_uuid":"10000000-0000-0000-0000-000000000001",...}'
valence: 0.70
feeling: Very Pleasant
labels: [Happy, Calm]
associations: [Family, Fitness]
---
```

Nested canonical fields are also exposed as stable JSON strings where available: source revision, device, metadata, payload, relationships, and metric attribution. Consumers should treat `canonical_record_json` as authoritative.

## Specialized entries

- **State of Mind:** exact source kind, valence, labels, associations, UUID, and start/end.
- **Workout:** canonical workout source record and graph identity, with UUID-matched readable zones/laps/splits when available.
- **Blood pressure:** one correlation entry with component UUIDs and actual paired values. No proximity-based session inference.
- **Medication:** one dose event with source event UUID, status, actual/scheduled dose, schedule, and inventory relationship.
- **Ordinary quantity/category:** exact source value/unit or raw category value and canonical metadata.

UUID-free external records remain in JSON/CSV archive output; Health.md does not fabricate UUID-backed entry identity for them.

## Tips

- Keep UUID and canonical JSON fields if another tool imports or deduplicates entry notes.
- Use JSON/CSV daily exports as the complete archive; individual Markdown entries are a useful per-event view.
- Treat `entry_kind: daily_aggregate` as compatibility data, not an original HealthKit event.
- Check daily `raw_capture_status` before assuming an entry set is complete.
- Start with event-style metrics to avoid creating many files.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No entry files were created | Master switch/metric is off or no canonical record matched | Enable tracking and inspect the daily query manifest. |
| Daily summary has a value but no entry | Summary data and source capture have different completeness | Do not infer a source event; inspect `raw_capture_status` and query status. |
| Blood-pressure entry is missing | No complete canonical correlation/components were returned | Check HealthKit access and the correlation query diagnostics. |
| Only a marked aggregate entry appears | Lossless capture was not requested or source data is legacy | Enable Lossless Health Records and re-export for source-backed identity. |
| Duplicate-looking notes exist | Distinct HealthKit UUIDs have similar values/times | Keep both; Health.md deduplicates only repeated views of the same UUID. |
| A category is absent | No enabled trackable metrics are in it | Enable the metric under **Health Metrics** first. |

## Video outline

- **Suggested title:** Create One Obsidian Note per Real Apple Health Record
- **Hook:** “Each note can point back to an exact HealthKit UUID instead of a guessed daily event.”
- **Demo flow:** enable lossless capture and entry tracking, export mood/workout/BP, inspect canonical fields, then contrast a summary-only aggregate fallback.

## Implementation notes

- `IndividualEntryExporter.extractIndividualSamples(...)` uses `HealthKitRecordArchive` exclusively when present.
- `extractCanonicalRecordSamples(...)` emits direct metric records and deduplicates by `UUID + metric`.
- Specialized canonical mappers preserve State of Mind, workout, medication, and blood-pressure presentation without replacing source identity.
- Aggregate fallback is allowed only for `notRequested` or `legacyUnavailable` records.
