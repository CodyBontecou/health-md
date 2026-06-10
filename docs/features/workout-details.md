# Workout Details

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Health Metrics → Workouts; Export → Individual Entry Tracking
- **Source files:** `HealthMd/Shared/Models/HealthData.swift`, `HealthMd/Shared/Protocols/HealthStoreProtocol.swift`, `HealthMd/Shared/Protocols/SystemHealthStoreAdapter.swift`, `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/IndividualEntryExporter.swift`, `HealthMd/Shared/Export/MarkdownExporter.swift`

## What it does

Workout Details exports Apple Health workouts with richer fields than a simple workout count. Health.md includes workout type, time, duration, distance, pace or speed, calories, heart-rate stats, running dynamics, cycling metrics, elevation, laps, splits, route point counts, and time-series sample counts when available.

Workout detail is included in the main daily Markdown export when **Workouts** is enabled. Markdown renders the data as readable sections and tables rather than an inline YAML block. Obsidian Bases exports include the same rich workout structure in the frontmatter under `workout_details`, JSON exposes structured workout objects, and you can opt into one standalone rich Markdown file per workout by enabling **Workouts** in Individual Entry Tracking.

## Who it is for

- Runners, cyclists, swimmers, hikers, and strength-training users reviewing workouts in Obsidian.
- Users who want training notes next to sleep, recovery, and mood data.
- Users comparing pace, heart rate, power, cadence, and elevation over time.
- Users who want one note per workout.

Do not expect every field for every workout. Apple Health only returns metrics that were recorded by the device/app and supported for that workout type.

## Where to find it

1. Open Health.md.
2. Go to **Export → Health Metrics**.
3. Enable **Workouts**.
4. Export to include rich workout detail in the main daily Markdown file. If you also want one note per workout, enable **Individual Entry Tracking → Workouts**.

## Prerequisites

- HealthKit permission granted.
- Workouts recorded in Apple Health for the selected date.
- **Workouts** enabled in Health Metrics.
- A vault/folder selected.
- For route, split, power, cadence, and running dynamics: a device/app that records those fields.

## Setup

1. In **Export → Health Metrics**, enable **Workouts**.
2. In **Export Formats**, choose Markdown, JSON, CSV, Obsidian Bases, or a combination.
3. Export a day with one or more workouts.
4. Optional: for standalone workout notes, go to **Individual Entry Tracking**, enable the master switch, and enable **Workouts**.
5. Open the generated daily export, and any individual workout notes if you opted into them.

## Example daily Markdown output

```markdown
## Workouts

### 1. Running

- **Time:** 07:04
- **Duration:** 32m 14s
- **Distance:** 5.02 km
- **Pace:** 6:25 /km
- **Calories:** 381 kcal
- **Avg Heart Rate:** 148 bpm
- **Max Heart Rate:** 176 bpm
- **Avg Cadence:** 168 spm
- **Avg Stride Length:** 1.04 m
- **Avg Ground Contact:** 246 ms
- **Avg Vertical Oscillation:** 8.1 cm
- **Avg Power:** 238 W
- **Elevation Gain:** 42 m
- **GPS Route:** 1842 points

#### Details

| Field | Value |
|---|---|
| Source | Health.md |
| Activity Type | Running |
| Sport | running |
| Start | 2026-05-12T07:04:00Z |
| End | 2026-05-12T07:36:14Z |
| Duration | 32:14 |
| Distance | 5.02 km (5.02 km / 3.12 mi) |
| Average Pace | 6:25 /km |
| Speed | 9.4 km/h / 5.8 mph |
| GPS Route Points | 1842 |

- **Splits:**

| # | Start | End | Distance | Time | Pace | Speed | Avg HR | Max HR | Avg Power | Avg Cadence |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 07:04:00 | 07:10:18 | 1.00 km | 6:18 | 6:18 /km | 9.5 km/h / 5.9 mph | 141 bpm | 153 bpm | 226 W | 166 spm |
| 2 | 07:10:18 | 07:16:45 | 1.00 km | 6:27 | 6:27 /km | 9.3 km/h / 5.8 mph | 149 bpm | 162 bpm | 238 W | 169 spm |

#### Samples

| Metric | Samples |
|---|---:|
| Heart Rate | 1840 |
| Speed | 1799 |
| Cadence | 1799 |
| Altitude | 1801 |
```

## Example individual workout path

```text
MyVault/Health/entries/workouts/2026_05_12_0704_workouts.md
```

## Example individual workout entry

```markdown
---
date: 2026-05-12
time: "07:04"
datetime: 2026-05-12T07:04:00Z
type: workout
metric: workouts
source: Health.md
activity_type: "Running"
sport: running
tags:
  - workout
  - healthmd
duration_sec: 1934
duration: "32:14"
calories: 381
distance_m: 5020
distance_km: 5.02
hr_avg: 148
hr_max: 176
cadence_avg_spm: 168
power_avg_w: 238
sample_counts:
  heart_rate: 1840
  power: 1799
heart_rate_zones:
  zone3:
    label: Tempo
    range: "122-138"
    seconds: 420
    duration: "7:00"
splits:
  - split: 1
    distance_km: 1.00
    time_sec: 378
    duration: "6:18"
    pace_per_km: "6:18 /km"
    hr_avg: 141
    hr_max: 153
    power_avg_w: 226
    cadence_avg_spm: 166
---

# Running — 2026-05-12

**32:14 | 5.02 km | HR 148 bpm | 381 cal**

## Splits

| # | Distance | Time | Pace | Avg HR | Max HR | Avg Power | Avg Cadence |
|---|---|---|---|---|---|---|---|
| 1 | 1.00 km | 6:18 | 6:18 /km | 141 bpm | 153 bpm | 226 W | 166 spm |
```

Individual workout entries are frontmatter-first so they can be queried as standalone Obsidian records, with readable Markdown sections underneath for review.

## Supported workout details

Health.md can export these fields when HealthKit provides them:

- workout type;
- start and end time;
- duration;
- calories;
- distance;
- pace or speed;
- average, minimum, and maximum heart rate;
- running cadence;
- stride length;
- ground contact time;
- vertical oscillation;
- cycling cadence;
- average and maximum power;
- elevation gain/loss;
- manual laps with distance, duration, pace/speed, average/max heart rate, average power, and average cadence when samples are available;
- derived distance splits with the same interval breakdown;
- GPS route point count;
- structured workout frontmatter for zones, laps, splits, sample counts, route counts, and metadata in Obsidian Bases and standalone workout notes;
- time-series counts for heart rate, speed, power, cadence, stride length, ground contact, vertical oscillation, and altitude.

## Tips

- Use Markdown for readable training logs with detail tables instead of inline YAML code blocks.
- Use Obsidian Bases when you want frontmatter-only daily records with `workout_details` nested under the header.
- Use JSON for full structured route/time-series analysis.
- Use Individual Entry Tracking if each workout should become its own Obsidian note.
- If Individual Entry Tracking is off, the detailed workout content remains in the main daily Markdown export instead of being written to separate workout files.
- Workout detail is included in the daily Markdown export by default when Workouts is enabled; the Time-Series Data toggle is not required for the summary/sample-count sections.
- For best detail, record workouts with Apple Watch or another app that writes rich HealthKit workout data.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Workout is missing | Workouts metric is disabled or no workout exists for the date | Enable **Workouts** and verify Apple Health has the workout. |
| No route or splits appear | Workout has no GPS route or route permission/data is unavailable | Check the source app/device and Health permissions. |
| Running dynamics are missing | Device did not record stride, ground contact, or vertical oscillation | Use supported Apple Watch/workout hardware and re-record future workouts. |
| Power or cadence is missing | Workout type or device did not provide those metrics | Verify the workout app writes power/cadence to HealthKit. |
| Markdown only shows sample counts | Dense workout samples are summarized in Markdown | Export JSON for full structured sample arrays. |
| Standalone workout file was not created | Individual Entry Tracking for workouts is off, Workouts metric is disabled, or no workout exists for the date | Enable **Individual Entry Tracking → Workouts**, enable **Workouts**, and verify Apple Health has the workout. |

## Video outline

- **Suggested title:** Turn Apple Health Workouts into Obsidian Training Notes
- **Hook:** “Health.md can export the details behind each workout, not just the fact that you worked out.”
- **Demo flow:**
  1. Show a workout in Apple Fitness/Health.
  2. Enable **Workouts** in Health.md metrics.
  3. Export the day and show the workout section in Markdown.
  4. Explain that the detailed workout data is in the main daily Markdown export.
  5. Optional: enable Individual Entry Tracking for Workouts and open the generated standalone workout note.
- **Key screenshot/recording moments:** workout metric toggle, workout Markdown section, splits table, sample counts, standalone workout frontmatter.
- **CTA / next video:** “Next, we’ll combine workout details with mood and recovery data in Obsidian Bases.”

## Implementation notes

- `HealthKitManager` requests workout read access through `HKObjectType.workoutType()`.
- `HealthStoreProviding.WorkoutValue` carries core workout data plus heart-rate stats, running/cycling metrics, elevation, laps, splits, route, and `WorkoutTimeSeries`.
- `SystemHealthStoreAdapter.queryWorkouts(...)` fetches workouts, heart-rate stats, running/cycling metrics, lap events, routes, elevation, derived splits, and time-series data where available.
- `MarkdownExporter.workoutsListMarkdown(...)` renders readable workout sections, detail tables, lap/split tables, route point counts, metadata tables, and per-series sample-count tables so non-individual exports retain the workout-note detail without embedding a YAML code block.
- `ObsidianBasesExporter` asks `ExportDataSnapshot.frontmatterLines(...)` to include rich `workout_details` frontmatter for Bases-only database records.
- `IndividualEntryExporter.extractIndividualSamples(...)` creates one sample per workout when Workouts is enabled in Individual Entry Tracking.
