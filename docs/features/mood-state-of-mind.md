# Mood and State of Mind

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Health Metrics → Mindfulness; Export → Individual Entry Tracking
- **Source files:** `HealthMd/Shared/Models/HealthData.swift`, `HealthMd/Shared/Protocols/HealthStoreProtocol.swift`, `HealthMd/Shared/Protocols/SystemHealthStoreAdapter.swift`, `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/IndividualEntryExporter.swift`, `HealthMd/Shared/Export/MarkdownExporter.swift`

## What it does

Mood and State of Mind export reads Apple Health's public State of Mind samples, including **Daily Mood** and **Momentary Emotion**. Daily summaries keep average valence, labels, associations, and counts.

With **Lossless Health Records** on, JSON/CSV also preserves each source UUID, exact start/end, source/device/typed metadata, raw and symbolic kind/classification/labels/associations, and valence. Individual Markdown files derive from those canonical records rather than a daily average.

## Who it is for

- Users who log mood or emotions in Apple Health.
- Journalers who want mood context in Obsidian daily notes.
- Users comparing mood with sleep, workouts, HRV, caffeine, or symptoms.
- Users who want each mood log as a standalone note.

Do not use this if you have not recorded State of Mind entries in Apple Health; Health.md cannot invent mood data.

## Where to find it

1. Open Health.md.
2. Go to **Export → Health Metrics**.
3. Open **Mindfulness**.
4. Enable the State of Mind metrics you want, such as **Daily Mood**, **Momentary Emotions**, or **Average Valence**.
5. Optional: go to **Export → Individual Entry Tracking** and enable mood metrics for one-file-per-entry output.

## Prerequisites

- iPhone with State of Mind data in Apple Health.
- iOS 18 or later for HealthKit State of Mind reads.
- HealthKit permission granted.
- Mindfulness/State of Mind metrics enabled in Health.md.
- A vault/folder selected for export.

## Setup

1. Log a mood or emotion in Apple Health.
2. In Health.md, grant Health permissions when prompted.
3. Enable Mindfulness metrics under **Health Metrics**.
4. Leave **Lossless Health Records** on for source identity and complete payloads.
5. Export a day with State of Mind data.
6. For standalone notes, enable **Individual Entry Tracking** and choose the mood metrics.

## Example daily Markdown output

```markdown
## Mindfulness

- **Mindful Minutes:** 12 min
- **Sessions:** 2

- **Average Mood:** 76% (Pleasant)
- **Daily Mood Entries:** 1
- **Momentary Emotions:** 2
- **Emotions/Moods:** Calm, Grateful, Happy
- **Associated With:** Family, Fitness, Work

### Mood Entries

- **08:30** (Daily Mood): 82%, Calm, Grateful
- **15:45** (Momentary Emotion): 68%, Focused
```

The detailed **Mood Entries** subsection appears in standard Markdown when summary output is enabled and there are five or fewer State of Mind entries for the day.

## Example individual entry path

```text
MyVault/Health/entries/mindfulness/2026_05_12_0830_daily_mood.md
MyVault/Health/entries/mindfulness/2026_05_12_1545_momentary_emotions.md
```

## Example individual entry output

```markdown
---
date: 2026-05-12
time: "08:30"
datetime: 2026-05-12T08:30:00.000000000Z
type: mindfulness
metric: daily_mood
entry_kind: healthkit_record
original_uuid: 10000000-0000-0000-0000-000000000001
raw_record_schema: healthmd.healthkit_records
raw_record_schema_version: 1
value: 0.64
valence: 0.64
feeling: Very Pleasant
labels:
  - Calm
  - Grateful
associations:
  - Family
  - Fitness
---
```

## How valence works

Apple State of Mind uses a `-1.0` to `1.0` valence scale:

| Range | Health.md description |
|---|---|
| -1.0 to -0.6 | Very Unpleasant |
| -0.6 to -0.2 | Unpleasant |
| -0.2 to 0.2 | Neutral |
| 0.2 to 0.6 | Pleasant |
| 0.6 to 1.0 | Very Pleasant |

Health.md also converts valence to a 0 to 100 percent display for readable Markdown summaries.

## Tips

- Use daily Markdown export to see mood next to sleep, activity, and HRV.
- Use individual entry tracking if you want each source UUID to be its own Obsidian object.
- Keep labels and associations enabled in Apple Health; they make exports more useful than valence alone.
- Compare average valence with sleep duration, workouts, caffeine, and symptoms in Obsidian Bases.
- If you log many mood entries per day, use individual entries instead of relying on the daily note summary.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No mood data appears | No State of Mind entries exist for that date | Add entries in Apple Health and re-export the date. |
| State of Mind metrics are unavailable | Device/OS does not support State of Mind HealthKit reads | Use an iPhone on iOS 18 or later. |
| Average mood is missing | Average Valence metric is disabled or no entries exist | Enable the metric and verify data in Apple Health. |
| Individual mood files were not created | Tracking is off or canonical query did not return the source record | Enable tracking and inspect `raw_capture_status`/manifest. |
| Daily average exists but no source entry file | Source capture failed/was empty | Health.md does not invent an individual event from the average when an archive exists. |
| Labels or associations are empty | Apple Health entry did not include them | Edit/log richer State of Mind entries in Apple Health. |

## Video outline

- **Suggested title:** Export Apple Health Mood and State of Mind to Obsidian
- **Hook:** “Your journal can include how you felt, not just how many steps you took.”
- **Demo flow:**
  1. Show State of Mind entries in Apple Health.
  2. Enable Mindfulness metrics in Health.md.
  3. Export the day to Markdown.
  4. Show average mood, labels, and associations in Obsidian.
  5. Enable Individual Entry Tracking and export again.
  6. Open one generated mood entry file.
- **Key screenshot/recording moments:** Health Metrics → Mindfulness, daily Markdown mood section, individual mood file frontmatter.
- **CTA / next video:** “Next, we’ll track each workout as its own training note.”

## Implementation notes

- `HealthKitManager` adds `HKSampleType.stateOfMindType()` to read permissions on iOS 18+.
- `SystemHealthStoreAdapter` maps `HKStateOfMind` to a canonical structured `HealthKitRecord`, preserving UUID/provenance/raw values.
- `MindfulnessData` remains the compatibility summary projection.
- `MarkdownExporter.mindfulnessMetricsMarkdown(...)` renders summaries and small presentation lists.
- `IndividualEntryExporter` prefers canonical State of Mind records and uses compatibility arrays only for explicit summary-only/legacy data.
