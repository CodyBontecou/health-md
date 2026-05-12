# Workout Details

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export → Health Metrics → Workouts; Export → Time-Series Data; Export → Individual Entry Tracking
- **Source files:** `HealthMd/Shared/Models/HealthData.swift`, `HealthMd/Shared/Protocols/HealthStoreProtocol.swift`, `HealthMd/Shared/Protocols/SystemHealthStoreAdapter.swift`, `HealthMd/Shared/Managers/HealthKitManager.swift`, `HealthMd/Shared/Managers/IndividualEntryExporter.swift`, `HealthMd/Shared/Export/MarkdownExporter.swift`

## What it does

Workout Details exports Apple Health workouts with richer fields than a simple workout count. Health.md includes workout type, time, duration, distance, pace or speed, calories, heart-rate stats, running dynamics, cycling metrics, elevation, laps, splits, route point counts, and time-series sample counts when available.

You can keep workouts inside the daily Markdown export, export them as structured JSON, or create one standalone Markdown file per workout with Individual Entry Tracking.

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
4. Optional: enable **Time-Series Data** for advanced workout telemetry.
5. Optional: enable **Individual Entry Tracking → Workouts** for one file per workout.

## Prerequisites

- HealthKit permission granted.
- Workouts recorded in Apple Health for the selected date.
- **Workouts** enabled in Health Metrics.
- A vault/folder selected.
- For route, split, power, cadence, and running dynamics: a device/app that records those fields.

## Setup

1. In **Export → Health Metrics**, enable **Workouts**.
2. In **Export Formats**, choose Markdown, JSON, CSV, Obsidian Bases, or a combination.
3. Turn on **Time-Series Data** if you want granular workout sample counts and fuller JSON.
4. For standalone workout notes, go to **Individual Entry Tracking**, enable the master switch, and enable **Workouts**.
5. Export a day with one or more workouts.

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

- **Splits:**

| # | Time | Pace | Avg HR |
|---|---|---|---|
| 1 | 6:18 | 6:18 /km | 141 bpm |
| 2 | 6:27 | 6:27 /km | 149 bpm |

- **Heart Rate Samples:** 1840
- **Speed Samples:** 1799
- **Cadence Samples:** 1799
- **Altitude Samples:** 1801
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
type: workouts
metric: workouts
value: Running
workout_type: Running
duration_minutes: 32
calories: 381
distance_meters: 5020
avg_heart_rate: 148
max_heart_rate: 176
avg_running_cadence: 168
avg_power_w: 238
---
```

Individual workout entries are frontmatter-focused so they can be queried as standalone Obsidian records.

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
- manual laps;
- derived distance splits;
- GPS route point count;
- time-series counts for heart rate, speed, power, cadence, stride length, ground contact, vertical oscillation, and altitude.

## Tips

- Use Markdown for readable training logs.
- Use JSON for full structured route/time-series analysis.
- Use Individual Entry Tracking if each workout should become its own Obsidian note.
- Enable Time-Series Data before exporting workouts if you care about sample-level telemetry.
- For best detail, record workouts with Apple Watch or another app that writes rich HealthKit workout data.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Workout is missing | Workouts metric is disabled or no workout exists for the date | Enable **Workouts** and verify Apple Health has the workout. |
| No route or splits appear | Workout has no GPS route or route permission/data is unavailable | Check the source app/device and Health permissions. |
| Running dynamics are missing | Device did not record stride, ground contact, or vertical oscillation | Use supported Apple Watch/workout hardware and re-record future workouts. |
| Power or cadence is missing | Workout type or device did not provide those metrics | Verify the workout app writes power/cadence to HealthKit. |
| Markdown only shows sample counts | Dense workout samples are summarized in Markdown | Export JSON for full structured sample arrays. |
| Standalone workout file was not created | Individual Entry Tracking for workouts is off | Enable the master switch and the `workouts` metric. |

## Video outline

- **Suggested title:** Turn Apple Health Workouts into Obsidian Training Notes
- **Hook:** “Health.md can export the details behind each workout, not just the fact that you worked out.”
- **Demo flow:**
  1. Show a workout in Apple Fitness/Health.
  2. Enable **Workouts** in Health.md metrics.
  3. Export the day and show the workout section in Markdown.
  4. Turn on Time-Series Data and explain sample counts/JSON.
  5. Enable Individual Entry Tracking for workouts.
  6. Open the generated standalone workout note.
- **Key screenshot/recording moments:** workout metric toggle, workout Markdown section, splits table, sample counts, standalone workout frontmatter.
- **CTA / next video:** “Next, we’ll combine workout details with mood and recovery data in Obsidian Bases.”

## Implementation notes

- `HealthKitManager` requests workout read access through `HKObjectType.workoutType()`.
- `HealthStoreProviding.WorkoutValue` carries core workout data plus heart-rate stats, running/cycling metrics, elevation, laps, splits, route, and `WorkoutTimeSeries`.
- `SystemHealthStoreAdapter.queryWorkouts(...)` fetches workouts, heart-rate stats, running/cycling metrics, lap events, routes, elevation, derived splits, and time-series data where available.
- `MarkdownExporter.workoutsListMarkdown(...)` renders readable workout sections, lap/split tables, route point counts, and per-series sample counts.
- `IndividualEntryExporter.extractWorkoutSamples(...)` creates one individual sample per workout for standalone entry files.
