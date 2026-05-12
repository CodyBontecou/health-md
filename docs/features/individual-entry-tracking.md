# Individual Entry Tracking

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Individual Entry Tracking
- **Source files:** `HealthMd/iOS/Views/IndividualTrackingView.swift`, `HealthMd/Shared/Models/IndividualTrackingSettings.swift`, `HealthMd/Shared/Managers/IndividualEntryExporter.swift`, `HealthMd/Shared/Models/HealthData.swift`

## What it does

Individual Entry Tracking creates separate timestamped Markdown files for selected health events in addition to the normal daily summary. Instead of only writing “1 workout” or “average mood 76%” into a daily note, Health.md can create one file per mood entry, workout, blood pressure reading, blood glucose value, weight entry, or supported symptom entry.

This is useful when each event deserves its own Obsidian note, backlinks, tags, or review workflow.

## Who it is for

- Users who want each mood log or workout as a standalone note.
- Obsidian users building an entry-level database, not just daily summaries.
- Users tracking events that happen multiple times per day.
- Quantified-self users who want timestamped records for later review.

Do not use this if daily aggregate notes are enough. It writes extra files.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Tap **Individual Entry Tracking**.
4. Enable **Enable Individual Entry Tracking**.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected.
- Markdown-capable export destination.
- The source metric must be enabled under **Health Metrics**; categories with no enabled metrics are hidden.
- The master switch and at least one per-metric toggle must be enabled.

## Setup

1. Go to **Export → Individual Entry Tracking**.
2. Turn on **Enable Individual Entry Tracking**.
3. Tap **Enable Suggested Metrics** for mood, symptoms, workouts, blood pressure, and blood glucose, or expand categories and choose metrics manually.
4. Set **Entries Folder**. The default is `entries`.
5. Keep **Organize by Category** on if you want folders like `entries/mindfulness` and `entries/workouts`.
6. Adjust the filename template if needed. The default is `{date}_{time}_{metric}`.
7. Export a date that has matching data.

## Path behavior

With default settings, Health.md writes individual entries under the selected export root:

```text
<selected vault>/<Health.md subfolder>/entries/<category>/<filename>.md
```

Example:

```text
MyVault/Health/entries/mindfulness/2026_05_12_1030_daily_mood.md
MyVault/Health/entries/workouts/2026_05_12_0700_workouts.md
MyVault/Health/entries/vitals/2026_05_12_0900_blood_glucose.md
```

If **Organize by Category** is off, all entry files go directly into the entries folder.

## Filename placeholders

- `{date}` → `2026_05_12`
- `{time}` → `1030`
- `{metric}` → `daily_mood`, `workouts`, `blood_glucose`
- `{category}` → `mindfulness`, `workouts`, `vitals`

Health.md appends `.md` automatically.

## Example output

```markdown
---
date: 2026-05-12
time: "10:30"
datetime: 2026-05-12T10:30:00Z
type: mindfulness
metric: daily_mood
value: 0.70
valence: 0.70
feeling: Very Pleasant
labels:
  - Happy
  - Calm
associations:
  - Family
  - Fitness
---
```

Workout entries include workout-specific fields such as type, duration, calories, distance, heart rate, cadence, power, and running dynamics when available.

## Suggested metrics

The **Enable Suggested Metrics** action turns on commonly useful entry-level data:

- daily mood;
- average valence;
- momentary emotions;
- mindful minutes and sessions;
- symptoms;
- workouts;
- blood pressure;
- blood glucose.

## Tips

- Keep category folders enabled if you plan to query entries by folder in Obsidian.
- Use `{date}_{time}_{metric}` to avoid filename collisions for multiple entries in one day.
- Use individual tracking for event-style data, and daily Markdown/Bases export for daily summaries.
- Start with suggested metrics before enabling everything.
- Re-exporting a date can overwrite files with the same generated path.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No entry files were created | Master switch is off or no metrics are selected | Enable **Individual Entry Tracking** and at least one metric. |
| A category is missing | No metrics in that category are enabled in Health Metrics | Enable the metric under **Export → Health Metrics** first. |
| Files are in the wrong folder | Entries Folder or category organization setting differs from expectation | Check the folder preview in Individual Tracking. |
| Duplicate-looking files overwrite | Filename template is not unique enough | Include both `{date}` and `{time}` in the template. |
| Blood pressure entry missing | Both systolic and diastolic values are required for the combined entry | Verify Apple Health has both values for the date. |
| Symptoms do not create detailed entries | Detailed symptom extraction is currently placeholder-level | Use daily symptom counts until enhanced symptom entries ship. |

## Video outline

- **Suggested title:** Create One Obsidian Note per Mood, Workout, or Vital Entry
- **Hook:** “Daily summaries are great, but some health events deserve their own note.”
- **Demo flow:**
  1. Show a normal daily export.
  2. Open **Individual Entry Tracking** and enable the master switch.
  3. Use **Enable Suggested Metrics**.
  4. Show folder and filename previews.
  5. Export a day with mood and workout data.
  6. Open the generated entry notes in Obsidian.
- **Key screenshot/recording moments:** master switch, suggested metrics, folder preview, filename template, generated mood/workout entry files.
- **CTA / next video:** “Next, we’ll focus specifically on Apple State of Mind mood exports.”

## Implementation notes

- `IndividualTrackingSettings` stores the global toggle, per-metric configs, entries folder, category-folder preference, and filename template.
- `IndividualTrackingView` only shows categories that already have enabled metrics in export settings.
- `IndividualEntryExporter.extractIndividualSamples(...)` currently extracts State of Mind entries, workouts, blood pressure, blood glucose, weight, and placeholder symptom support.
- `IndividualEntryExporter.exportIndividualEntries(...)` writes one Markdown file per enabled sample.
- Individual entry files use YAML frontmatter only; they are designed to be easy to query in Obsidian.
