# Workout Details

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Health Metrics → Workouts; Export → Individual Entry Tracking
- **Source files:** `HealthMd/Shared/Protocols/SystemHealthStoreAdapter+CanonicalWorkouts.swift`, `HealthMd/Shared/Protocols/SystemHealthStoreAdapter+WorkoutKit.swift`, `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/IndividualEntryExporter.swift`

## What it does

Workout export has two layers:

- readable daily/individual summaries with type, time, duration, distance, energy, heart-rate/running/cycling details, laps, splits, zones, route/sample counts, and metadata;
- a canonical lossless workout graph in JSON/CSV when **Lossless Health Records** is on.

The canonical graph is authoritative. Markdown and Obsidian Bases intentionally show summaries, structured presentation fields, and diagnostics/counts rather than every route point or associated source object.

## Setup

1. Enable **Workouts** under **Export → Health Metrics**.
2. Leave **Lossless Health Records** on for the full public graph.
3. Choose JSON or CSV for source-complete analysis; add Markdown/Bases for readable notes.
4. Optional: enable **Individual Entry Tracking → Workouts** for one note per canonical workout UUID.
5. Export a date with workouts.

## Canonical coverage

When public APIs and authorization allow, Health.md preserves:

- original workout UUID, source revision/OS, device, metadata, exact start/end, and recorded duration;
- stable display name/sport plus HealthKit activity symbolic and raw identities;
- every workout event, including unknown future raw values;
- multi-activity workouts and every public statistics dictionary;
- all workout routes and every public location field;
- associated quantity, category, and specialized samples with workout edges;
- route, parent/child, activity, and association relationships;
- workout-effort relationships, activity edges, and related known/unknown samples;
- exact WorkoutKit attached-plan and scheduled-plan data representations;
- query outcomes for each graph/child operation.

Distinct records are never collapsed because they look alike. Repeated views merge only by the same UUID. WorkoutKit schedule values use documented external identity because they are not HKObjects.

## Readable Markdown example

```markdown
## Workouts

### 1. Running

- **Time:** 07:04
- **Duration:** 32m 14s
- **Distance:** 5.02 km
- **Calories:** 381 kcal
- **Avg Heart Rate:** 148 bpm
- **Avg Cadence:** 168 spm
- **Avg Power:** 238 W
- **GPS Route:** 1842 points

#### Samples

| Metric | Samples |
|---|---:|
| Heart Rate | 1840 |
| Speed | 1799 |
| Cadence | 1799 |
| Altitude | 1801 |
```

This is a useful presentation, not the complete graph. JSON `healthkit_record_archive.records` contains the workout, routes, associated samples, payloads, and relationships. CSV carries the same canonical records as JSON rows.

## Individual workout entries

With Individual Entry Tracking, the source workout UUID is the identity authority. A UUID-matched compatibility projection can enrich zones/laps/splits, but cannot replace or duplicate the canonical record. Entry frontmatter includes `canonical_record_json` and source/provenance fields.

Example path:

```text
MyVault/Health/entries/workouts/2026_07_15_0704_workouts_workouts_10000000-0000-0000-0000-000000000001.md
```

Canonical paths append the tracked metric and lowercase source UUID. UUID-free legacy compatibility entries keep the shorter path shape. See the generated [filename/path matrix](../reference/generated/individual/filename-path-matrix.md) for both tiers and collision behavior.

## Time and duration

Workout source end time is the actual HealthKit end date. Recorded duration remains a separate field, so paused time is not reconstructed by pretending `end = start + duration`. Canonical start/end are never clipped to the daily boundary; day ownership uses source start in the captured timezone.

## Partial graph behavior

A failed route-location, associated-sample, effort, plan, or attachment child query:

- retains successful workout and sibling records;
- marks the archive `partial`;
- records the exact query status/error and partial failure;
- never substitutes an empty child as if capture completed.

Unsupported or unprompted WorkoutKit capabilities are `unsupported`/`skipped`, not successful empty.

## Tips

- Use JSON for route points, events, activities, statistics, associated samples, effort edges, and exact plan bytes.
- Use CSV when you want the same canonical objects in a table pipeline.
- Use Markdown/Bases for readable training logs and counts.
- Keep both daily archive and individual note UUIDs when joining data.
- Dense routes, associated series, attachments, and plans can make files large; export fewer days at a time.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Workout missing | Metric off/no source workout/read access unavailable | Enable Workouts and inspect query manifest. |
| Route count appears but points do not | Markdown/Bases summarize dense source data | Read JSON/CSV canonical route records. |
| Archive says partial | A graph child failed/cancelled/skipped/was unsupported | Inspect child query status; retained siblings remain valid. |
| End time differs from start + duration | Workout included pauses | Keep actual end and recorded duration separately. |
| Scheduled plan skipped | Capability/authorization state did not allow read | Review manifest; Health.md does not prompt through ordinary HealthKit access. |
| Standalone note absent | Individual Workouts off or canonical workout missing | Enable tracking and inspect source query status. |

## Video outline

- **Suggested title:** Export the Complete Public Apple Health Workout Graph
- **Hook:** “Keep a readable training note and the route/events/associations behind it.”
- **Demo flow:** inspect Markdown summary, JSON workout/routes/relationships, a paused workout, a partial route child, and UUID-backed individual entry.

## Implementation notes

- `SystemHealthStoreAdapter+CanonicalWorkouts` maps workout envelopes, events, activities, statistics, routes, associated samples, and effort relationships.
- `SystemHealthStoreAdapter+WorkoutKit` preserves exact public plan representations and capability outcomes.
- `HealthKitManager` merges repeated views only by UUID and preserves child query results/warnings.
- `MarkdownExporter`/Bases render presentation detail and counts; `HealthKitRecordArchiveSerializer` owns source-complete JSON/CSV.
- `IndividualEntryExporter` joins presentation to canonical workouts only by source UUID.
