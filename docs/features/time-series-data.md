# Time-Series Data

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Time-Series Data
- **Source files:** `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Models/HealthData.swift`, `HealthMd/Shared/Protocols/HealthStoreProtocol.swift`, `HealthMd/Shared/Protocols/SystemHealthStoreAdapter.swift`, `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Export/MarkdownExporter.swift`

## What it does

Time-Series Data adds timestamped samples to exports instead of only daily totals and averages. This lets you reconstruct intraday graphs, inspect sleep-stage intervals, review heart-rate and HRV readings, and keep richer workout telemetry alongside the daily summary.

Markdown keeps this readable with compact tables or sample counts. JSON contains the most complete structured representation for downstream analysis.

## Who it is for

- Users who want more than one daily number per metric.
- Obsidian users who want expandable tables for sleep, heart rate, HRV, and workouts.
- Runners/cyclists who want workout splits, route counts, laps, and sensor sample counts.
- Users exporting JSON for charts, scripts, or LLM analysis.

Do not enable it if you only want short daily notes. Time-series data can make exports larger, especially when sending a Mac-target export over the local network.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Find **Time-Series Data**.
4. Enable **Include Time-Series Data**.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected, or a connected Mac with a selected destination folder for Mac-target exports.
- At least one export format selected.
- Relevant metrics enabled under **Health Metrics**.
- Apple Health must have granular samples for the selected date.

## Setup

1. In **Export → Time-Series Data**, turn on **Include Time-Series Data**.
2. Enable the metrics you care about in **Export → Health Metrics**.
3. Choose **Markdown** for readable details, **JSON** for full structured samples, or both.
4. Export one day first to inspect file size and formatting.
5. Use scheduled exports or Mac-target exports only after confirming the output is useful and the payload size is reasonable.

## Example output

Markdown sleep stages are rendered as an expandable table:

```markdown
<details>
<summary>Sleep Stages Timeline (18 intervals)</summary>

| Time | Stage | Duration |
|------|-------|----------|
| 23:14 | inBed | 7h 52m |
| 23:31 | core | 42m |
| 00:13 | deep | 55m |

</details>
```

Heart samples appear similarly:

```markdown
<details>
<summary>Heart Rate Samples (96 readings)</summary>

| Time | BPM |
|------|-----|
| 08:01 | 62 |
| 08:06 | 65 |

</details>
```

Workout Markdown summarizes dense series instead of printing every sample:

```markdown
- **Heart Rate Samples:** 1840
- **Speed Samples:** 1799
- **Cadence Samples:** 1799
- **Altitude Samples:** 1801
```

## Supported granular data

Current granular export support includes:

- sleep stage intervals;
- heart rate samples;
- HRV samples;
- blood oxygen samples;
- blood glucose samples;
- respiratory rate samples;
- workout laps;
- workout splits;
- workout GPS route point counts;
- workout time-series counts for heart rate, speed, power, cadence, stride length, ground contact time, vertical oscillation, and altitude.

Availability depends on the device, watch sensors, workout type, and Apple Health permissions.

## Tips

- Use JSON when you plan to chart or programmatically analyze samples.
- Use Markdown when you want a human-readable daily note with collapsible details.
- Export a single date before backfilling months of data or sending a large Mac-target job.
- If notes become too large, turn time-series data off and keep daily aggregates only.
- Pair this with workout details when filming advanced fitness workflows.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| No sample table appears | No granular samples exist for that metric/date | Check Apple Health for the same date and metric. |
| Only daily averages appear | Time-Series Data is disabled or metric is disabled | Enable **Include Time-Series Data** and the relevant Health Metric. |
| Workout shows sample counts but not full samples | Markdown intentionally summarizes dense workout series | Export JSON for full structured time-series data. |
| Export files are large | Granular samples add many records | Disable Time-Series Data or export fewer days at once. |
| Mac export transfer fails | Granular samples made the local Multipeer payload large and the connection dropped | Keep both apps foregrounded and nearby, or retry fewer days at a time. |
| Some workout fields are missing | Sensor or workout type did not record that field | Verify Apple Watch/device support and Health permissions. |

## Video outline

- **Suggested title:** Export Intraday Apple Health Samples with Health.md
- **Hook:** “Daily averages hide the shape of your day. Time-series export keeps the actual samples.”
- **Demo flow:**
  1. Export a day with Time-Series Data off.
  2. Turn on **Include Time-Series Data**.
  3. Re-export the same day.
  4. Compare sleep stages, heart-rate samples, and workout sample counts in Markdown.
  5. Send the same one-day export to Connected Mac to show the Mac receives the iPhone setting.
  6. Open the JSON output and show where full structured samples live.
- **Key screenshot/recording moments:** Time-Series Data toggle, sleep-stage details block, heart-rate table, workout sample counts, JSON sample array.
- **CTA / next video:** “Next, we’ll turn workouts into detailed training notes.”

## Implementation notes

- `ExportTabView.timeSeriesSection` binds the toggle to `AdvancedExportSettings.includeGranularData`.
- `HealthData` stores `TimeSample` and `SleepStageSample` arrays for granular data.
- `HealthStoreProviding` abstracts quantity/category sample queries plus workout route, split, lap, and time-series values.
- `SystemHealthStoreAdapter` reads workout routes, derives distance splits, extracts laps, and fetches workout time-series where available.
- `MarkdownExporter` renders sleep, heart, and HRV samples directly, while workout time-series are summarized by sample count in Markdown.
- Mac-target exports receive the same granular `HealthData` records from iPhone; macOS does not query HealthKit.
