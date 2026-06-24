---
title: Visualizations & Roadmap
description: Current Health.md Obsidian visualization coverage and planned charts organized by exported data type.
---

Health.md exports a schema-versioned local data set for Markdown, Obsidian Bases, JSON, and CSV. The visualization roadmap below connects that data surface to the companion Obsidian visualization plugin: what already exists, what the exported data can support next, and which categories need generic schema-aware charting.

<div class="callout">
<strong>Data source.</strong>
<p style="margin-top:6px;">This page is organized from Health.md's export schema and data dictionary: activity, sleep, heart, vitals, body, nutrition, mindfulness, medications, workouts, reproductive health, symptoms, hearing, and lifestyle/environment metrics.</p>
</div>

## Current visualization coverage

<div class="reference-stats">
<div><strong>35+</strong><span>plugin renderers today</span></div>
<div><strong>18</strong><span>export data categories</span></div>
<div><strong>220+</strong><span>canonical export keys</span></div>
<div><strong>1</strong><span>generic metric layer still needed</span></div>
</div>

## Foundation roadmap

The biggest product gap is not one missing chart. It is a generic schema-aware metric layer that lets any exported Health.md field be plotted without writing a custom parser and renderer for every metric.

### Built

- Schema compatibility detection for daily exports, legacy files, rollups, and data dictionary files.
- JSON, CSV, Markdown, and Obsidian Bases loading.
- Rollup awareness so weekly/monthly/yearly summaries do not pollute daily charts.
- Source-file navigation from chart points back to the contributing Health.md file.

### Planned

- **Generic schema-aware metric accessor** — read `_healthmd_data_dictionary.json` for labels, units, categories, aggregation rules, and aliases.
- **Generic metric trend** — line/area chart for any numeric exported key.
- **Generic metric bars** — generalized daily/weekly/monthly bars with goal and threshold lines.
- **Generic calendar heatmap** — any daily numeric metric as a calendar grid.
- **Visualization coverage report** — show fields present in a vault vs fields covered by dedicated renderers.

---

## Summary and overview

### Built

- `intro-stats` — dataset summary with totals, averages, sleep, and vitals.
- `summary-card` — Apple-style KPI card with sparkline and prior-period comparison.
- `trend-tile` — trends-card comparison between current and prior windows.

### Planned

- Auto-generated dashboard based on fields present in the selected Health.md folder.
- Schema coverage dashboard by data category.
- Correlation summary cards, such as sleep vs mood, HRV vs workouts, symptoms vs medications, or alcohol vs sleep.

---

## Activity

Health.md exports steps, active energy, basal energy, exercise time, stand time, flights climbed, walking/running distance, cycling, swimming, wheelchair activity, downhill snow distance, move time, physical effort, and VO₂ max.

### Built

- `activity-rings`
- `vitals-rings`
- `bar-chart`
- `activity-heatmap`
- `step-spiral`
- `weekday-average`

### Planned

- Activity load dashboard for steps, calories, exercise, stand hours, and physical effort.
- VO₂ max trend.
- Move / exercise / stand consistency chart.
- Distance mix chart across walking/running, cycling, swimming, wheelchair, and snow sports.
- Swimming distance + stroke chart.
- Wheelchair distance + push chart.

---

## Sleep

Health.md exports total sleep, bedtime, wake time, deep/REM/core/awake/in-bed durations, and granular sleep-stage intervals.

### Built

- `sleep-schedule`
- `sleep-quality-bars`
- `sleep-architecture`
- `sleep-polar`

### Planned

- Sleep debt and consistency score.
- Sleep stage ratio trend.
- Bedtime/wake regularity heatmap.
- Sleep + HRV + resting heart rate recovery dashboard.

---

## Heart

Health.md exports resting heart rate, walking heart rate, average/min/max heart rate, HRV, heart-rate samples, HRV samples, heart-rate recovery, and AFib burden.

### Built

- `heart-terrain`
- `heart-range`
- `hrv-trend`

### Planned

- Resting heart-rate trend.
- Walking heart-rate trend.
- Heart-rate recovery trend.
- AFib burden chart.
- HRV + resting heart rate recovery tile.
- Circadian heart-rate profile by time of day.

---

## Respiratory and oxygen

Health.md exports blood oxygen average/min/max, blood oxygen samples, respiratory-rate average/min/max, and respiratory-rate samples.

### Built

- `oxygen-river`
- `oxygen-range`
- `breathing-wave`

### Planned

- Dedicated respiratory range chart.
- Oxygen desaturation event chart.
- Overnight respiratory dashboard combining sleep stages, oxygen, and respiratory rate.

---

## Vitals

Health.md exports body temperature, blood pressure, blood glucose, basal body temperature, wrist temperature, electrodermal activity, forced vital capacity, FEV1, peak expiratory flow, and inhaler usage.

### Built

- Partial coverage through summary cards and generic daily charts.

### Planned

- Blood pressure systolic/diastolic range chart with threshold bands.
- Blood glucose range chart.
- Body, basal, and wrist temperature trend.
- Wrist temperature recovery / illness tile.
- Respiratory function dashboard for FVC, FEV1, peak flow, and inhaler usage.
- Electrodermal activity / stress trend.

---

## Body measurements

Health.md exports weight, height, BMI, body fat percentage, lean body mass, and waist circumference.

### Built

- No dedicated body composition renderer yet.

### Planned

- Body composition dashboard.
- Weight trend with rolling average and goal line.
- BMI trend with category bands.
- Body fat vs lean mass chart.
- Waist circumference trend.

---

## Mobility, gait, and running form

Health.md exports walking speed, step length, double support, walking asymmetry, stair ascent/descent speed, six-minute walk, walking steadiness, running speed, running stride length, ground contact time, vertical oscillation, and running power.

### Built

- `walking-symmetry`

### Planned

- Gait dashboard.
- Walking steadiness gauge.
- Six-minute walk trend.
- Stair ascent/descent speed chart.
- Running form dashboard for speed, stride, ground contact, vertical oscillation, and power.

---

## Workouts

Health.md exports workout counts, minutes, calories, distance, workout types, heart-rate stats, running/cycling form metrics, power, elevation, laps, splits, route points, heart-rate zones, and workout time-series samples.

### Built

- `workout-log`
- `workout-heart-rate`
- `workout-zones`
- `workout-trends`
- `workout-intervals`
- `workout-map`

### Planned

- Workout calendar heatmap.
- Training load chart from duration and intensity.
- Weekly workout distribution by type.
- Pace and speed trend by workout type.
- Elevation gain/loss trend.
- Route comparison small multiples.
- Power curve / best efforts.
- Running form and cycling performance dashboards.

---

## Mindfulness and mood

Health.md exports mindful minutes, mindful sessions, State of Mind entries, average valence, daily mood, momentary emotions, labels, and associations.

### Built

- `mood-trend`
- `mood-calendar-heatmap`
- `mood-sleep-scatter`
- `mood-day-timeline`
- `mood-association-breakdown`
- `mood-label-cloud`
- `mood-volatility`
- `mood-kind-split`
- `mood-circadian-clock`
- `mood-recovery-tile`
- `mood-association-matrix`

### Planned

- Mindful minutes trend.
- Mindful session streak/calendar.
- Mood vs medication adherence.
- Mood vs nutrition, alcohol, and caffeine.
- Mood label timeline.

---

## Medications

Health.md exports medication inventory, active/archived counts, dose event counts, taken/skipped counts, medication details, RxNorm/coding metadata, dose quantities, schedule type, scheduled/start/end dates, statuses, and metadata.

### Built

- `medication-overview`
- `medication-inventory`
- `medication-adherence-summary`
- `medication-dose-status`
- `medication-adherence-trend`
- `medication-recent-dose-events`

### Planned

- Medication schedule timeline.
- Medication adherence calendar heatmap.
- Medication lateness chart comparing scheduled time to taken time.
- Dose quantity trend.
- Medication vs symptom/mood correlation views.
- RxNorm / coding detail panel.

---

## Nutrition

Health.md exports dietary calories, protein, carbohydrates, fat, saturated fat, monounsaturated fat, polyunsaturated fat, fiber, sugar, sodium, cholesterol, water, and caffeine.

### Built

- No dedicated nutrition renderer yet.

### Planned

- Nutrition dashboard.
- Macro split chart.
- Calories in vs active calories chart.
- Hydration trend.
- Caffeine daily amount / timing chart.
- Sugar and sodium threshold charts.
- Fiber and protein goal progress.

---

## Vitamins and minerals

Health.md exports vitamins A, B6, B12, C, D, E, K, thiamin, riboflavin, niacin, folate, biotin, pantothenic acid, calcium, iron, potassium, magnesium, phosphorus, zinc, selenium, copper, manganese, chromium, molybdenum, chloride, and iodine.

### Built

- No dedicated micronutrient renderer yet.

### Planned

- Micronutrient heatmap.
- Recommended daily value progress grid.
- Vitamin trend dashboard.
- Mineral trend dashboard.
- Deficiency/excess flag panel.
- Nutrition completeness score.

---

## Hearing

Health.md exports headphone audio level and environmental sound level.

### Built

- Partial summary-level coverage only.

### Planned

- Hearing exposure trend.
- Loud-day calendar.
- Safe exposure threshold bands.
- Weekly exposure summary.

---

## Reproductive health and cycle tracking

Health.md exports menstrual flow, sexual activity, ovulation test result, cervical mucus quality, and intermenstrual bleeding.

### Built

- No dedicated reproductive health renderer yet.

### Planned

- Cycle calendar.
- Menstrual flow heatmap.
- Fertility signal timeline.
- Cycle symptom overlay combining reproductive health, symptoms, mood, and sleep.
- Spotting / intermenstrual bleeding timeline.

---

## Symptoms

Health.md exports daily symptom counts for headache, fatigue, nausea, dizziness, mood changes, sleep changes, appetite changes, hot flashes, chills, fever, lower back pain, bloating, constipation, diarrhea, heartburn, coughing, sore throat, runny nose, shortness of breath, chest pain, skipped heartbeat, rapid heartbeat, acne, dry skin, hair loss, memory lapse, night sweats, vomiting, abdominal cramps, breast pain, pelvic pain, body ache, fainting, loss of smell, loss of taste, wheezing, sinus congestion, bladder incontinence, and vaginal dryness.

### Built

- No dedicated symptom renderer yet.

### Planned

- Symptom calendar heatmap.
- Symptom frequency leaderboard.
- Symptom co-occurrence matrix.
- Flare timeline.
- Symptom correlation explorer.
- Body-system grouped symptom dashboard.

---

## Other health, lifestyle, and environment

Health.md exports UV exposure, time in daylight, falls, blood alcohol, alcoholic beverages, insulin delivery, toothbrushing, handwashing, water temperature, and underwater depth.

### Built

- No dedicated lifestyle/environment renderer yet.

### Planned

- Daylight / UV calendar.
- Falls timeline.
- Alcohol vs sleep / HRV chart.
- Insulin delivery trend.
- Toothbrushing and handwashing streaks.
- Water temperature / underwater depth chart.

---

## Priority order

1. Generic schema-aware metric infrastructure.
2. Generic trend, bar, and calendar heatmap renderers.
3. Vitals suite: blood pressure, glucose, temperature, respiratory function.
4. Body composition dashboard.
5. Nutrition dashboard.
6. Symptom heatmap, leaderboard, and correlation views.
7. Cycle / reproductive health calendar.
8. Micronutrient heatmap and RDA grid.
9. Expanded mobility and running form dashboard.
10. Hearing and lifestyle/environment charts.

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Last updated 2026-06-24</p>
