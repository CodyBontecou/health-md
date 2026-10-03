# Individual Entry Tracking

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Settings → Individual Entry Tracking
- **Source files:** `app/src/main/java/com/healthmd/data/export/IndividualEntryExporter.kt`, `app/src/main/java/com/healthmd/presentation/settings/IndividualTrackingScreen.kt`, `app/src/main/java/com/healthmd/domain/model/IndividualTrackingSettings.kt`

## What it does

Alongside daily summary files, Individual Entry Tracking writes one timestamped Markdown file per discrete health record — a workout, a sleep stage, a blood-pressure reading — so single events become linkable, searchable notes in your vault instead of rows inside a daily aggregate.

## Who it is for

- Obsidian users who link individual workouts or vitals readings to daily notes or journal entries
- People reconstructing graphs later: each entry file keeps the exact event time
- Not for compact archiving — daily summaries plus JSON/CSV stay denser than one file per reading

## Where to find it

1. Open Health.md → **Settings**.
2. Tap **Individual Entry Tracking** ("Export individual timestamped health entries as separate files").
3. Enable **Enable Individual Tracking**, then choose which metrics track individually.

## Prerequisites

- Health Connect permission for the categories you track
- A folder destination selected through the Android folder picker
- Export format Markdown enabled (entries render as Markdown)

## Setup

1. Enable the global toggle.
2. Pick metrics per category with **Suggested** / **All** / **None** quick actions, or search.
3. Set the **Entries Folder Name** (default `entries`).
4. Set the **Filename Template** (default `{metric}-{date}-{time}`; tokens: `{date}`, `{time}`, `{metric}`, `{category}`).
5. Optionally toggle **Organize by Category** ("Group entries into category subfolders") and set per-metric custom folders.

## Example output

```text
vault/
├── Health/
│   └── 2026-02-05.md
└── entries/
    ├── workouts/2026-02-05_07-00_workouts.md
    ├── sleep/2026-02-05_22-30_sleep-rem.md
    └── vitals/2026-02-05_09-00_blood-pressure.md
```

Workout entries carry duration, type, calories, distance, elevation, heart-rate and speed stats, cadence/power when present, lap/split/segment counts, route status, and title/notes metadata.

## Tips

- Files that would collide get a numeric suffix, so two same-minute readings never overwrite each other.
- Keep per-metric tracking narrow — every reading becomes a file, so a continuous heart-rate source can generate many entries.
- Suggested set is a good start: it tracks the commonly linked records without firehosing.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No entry files appear | Global toggle off, or the metric not enabled for individual tracking | Enable the toggle and the specific metric |
| Entry in the wrong folder | Custom folder or Organize by Category settings | Check entries folder, template, and category toggles |
| Workout missing heart-rate details | Health Connect source did not include those samples | Entries only carry data the record actually provides |

## Video outline

- **Suggested title:** One Note Per Workout, Reading, and Sleep Stage
- **Hook:** "Your blood-pressure readings deserve their own pages."
- **Demo flow:** enable tracking → configure folder + template → export a day → open the generated entries.
- **Key screenshot/recording moments:** quick actions, filename-template tokens, vault tree.
- **CTA / next video:** Daily note injection.

## Implementation notes

`IndividualEntryExporter.exportEntries` filters by `settings.shouldTrackIndividually(metricId)` per family: workouts, planned workouts, menstruation periods, sleep stages, steps, heart rate, HRV, vital samples, mindfulness, and latest weight. `relativePathFor` composes `entriesFolder/category/template` and dedupes with a counter. Rendering applies `FormatCustomization` (renamed fields, casing) the same way daily exports do, so custom frontmatter names stay consistent. Same-file collisions are counted, never merged. Coverage of Android-only records (planned workouts, menstruation periods) is deliberate; Apple pages document their own set.
