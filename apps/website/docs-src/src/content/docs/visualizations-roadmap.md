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
<div><strong>43</strong><span>plugin renderers today</span></div>
<div><strong>18</strong><span>export data categories</span></div>
<div><strong>220+</strong><span>canonical export keys</span></div>
<div><strong>1</strong><span>generic metric layer still needed</span></div>
</div>

<span id="visualization-screenshot-gallery"></span>

## Visualization gallery

These previews render the actual Health.md Obsidian plugin visualization bundle in-browser against deterministic mock Health.md export data. They occupy the same gallery positions as the former static screenshots, but each card below is a live canvas/HTML renderer.

<link rel="stylesheet" href="/docs/assets/live-visualizations/assets/live-visualizations.css" />
<script type="module" src="/docs/assets/live-visualizations/assets/live-visualizations.js"></script>

### Summary and overview

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="intro-stats" aria-label="Live-rendered Intro stats visualization"></div>
  <figcaption><strong>Intro stats</strong><code>intro-stats</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="summary-card" aria-label="Live-rendered Summary card visualization"></div>
  <figcaption><strong>Summary card</strong><code>summary-card</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="trend-tile" aria-label="Live-rendered Trend tile visualization"></div>
  <figcaption><strong>Trend tile</strong><code>trend-tile</code></figcaption>
</figure>
</div>

### Activity

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="activity-rings" aria-label="Live-rendered Activity rings visualization"></div>
  <figcaption><strong>Activity rings</strong><code>activity-rings</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="vitals-rings" aria-label="Live-rendered Vitals rings visualization"></div>
  <figcaption><strong>Vitals rings</strong><code>vitals-rings</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="bar-chart" aria-label="Live-rendered Bar chart visualization"></div>
  <figcaption><strong>Bar chart</strong><code>bar-chart</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="activity-heatmap" aria-label="Live-rendered Activity heatmap visualization"></div>
  <figcaption><strong>Activity heatmap</strong><code>activity-heatmap</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="step-spiral" aria-label="Live-rendered Step spiral visualization"></div>
  <figcaption><strong>Step spiral</strong><code>step-spiral</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="weekday-average" aria-label="Live-rendered Weekday average visualization"></div>
  <figcaption><strong>Weekday average</strong><code>weekday-average</code></figcaption>
</figure>
</div>

### Heart

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="heart-terrain" aria-label="Live-rendered Heart terrain visualization"></div>
  <figcaption><strong>Heart terrain</strong><code>heart-terrain</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="heart-range" aria-label="Live-rendered Heart range visualization"></div>
  <figcaption><strong>Heart range</strong><code>heart-range</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="hrv-trend" aria-label="Live-rendered HRV trend visualization"></div>
  <figcaption><strong>HRV trend</strong><code>hrv-trend</code></figcaption>
</figure>
</div>

### Respiratory and oxygen

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="oxygen-river" aria-label="Live-rendered Oxygen river visualization"></div>
  <figcaption><strong>Oxygen river</strong><code>oxygen-river</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="oxygen-range" aria-label="Live-rendered Oxygen range visualization"></div>
  <figcaption><strong>Oxygen range</strong><code>oxygen-range</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="breathing-wave" aria-label="Live-rendered Breathing wave visualization"></div>
  <figcaption><strong>Breathing wave</strong><code>breathing-wave</code></figcaption>
</figure>
</div>

### Sleep

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="sleep-schedule" aria-label="Live-rendered Sleep schedule visualization"></div>
  <figcaption><strong>Sleep schedule</strong><code>sleep-schedule</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="sleep-quality-bars" aria-label="Live-rendered Sleep quality bars visualization"></div>
  <figcaption><strong>Sleep quality bars</strong><code>sleep-quality-bars</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="sleep-architecture" aria-label="Live-rendered Sleep architecture visualization"></div>
  <figcaption><strong>Sleep architecture</strong><code>sleep-architecture</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="sleep-polar" aria-label="Live-rendered Sleep polar visualization"></div>
  <figcaption><strong>Sleep polar</strong><code>sleep-polar</code></figcaption>
</figure>
</div>

### Mindfulness and mood

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-trend" aria-label="Live-rendered Mood trend visualization"></div>
  <figcaption><strong>Mood trend</strong><code>mood-trend</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-calendar-heatmap" aria-label="Live-rendered Mood calendar heatmap visualization"></div>
  <figcaption><strong>Mood calendar heatmap</strong><code>mood-calendar-heatmap</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-sleep-scatter" aria-label="Live-rendered Mood × sleep scatterplot visualization"></div>
  <figcaption><strong>Mood × sleep scatterplot</strong><code>mood-sleep-scatter</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-day-timeline" aria-label="Live-rendered Mood day timeline visualization"></div>
  <figcaption><strong>Mood day timeline</strong><code>mood-day-timeline</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-association-breakdown" aria-label="Live-rendered Mood by association visualization"></div>
  <figcaption><strong>Mood by association</strong><code>mood-association-breakdown</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-label-cloud" aria-label="Live-rendered Mood label cloud visualization"></div>
  <figcaption><strong>Mood label cloud</strong><code>mood-label-cloud</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-volatility" aria-label="Live-rendered Mood volatility visualization"></div>
  <figcaption><strong>Mood volatility</strong><code>mood-volatility</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-kind-split" aria-label="Live-rendered Daily vs momentary mood visualization"></div>
  <figcaption><strong>Daily vs momentary mood</strong><code>mood-kind-split</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-circadian-clock" aria-label="Live-rendered Circadian mood clock visualization"></div>
  <figcaption><strong>Circadian mood clock</strong><code>mood-circadian-clock</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-recovery-tile" aria-label="Live-rendered Recovery + mindset tile visualization"></div>
  <figcaption><strong>Recovery + mindset tile</strong><code>mood-recovery-tile</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="mood-association-matrix" aria-label="Live-rendered Mood association matrix visualization"></div>
  <figcaption><strong>Mood association matrix</strong><code>mood-association-matrix</code></figcaption>
</figure>
</div>

### Medications

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="medication-overview" aria-label="Live-rendered Medication overview visualization"></div>
  <figcaption><strong>Medication overview</strong><code>medication-overview</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="medication-inventory" aria-label="Live-rendered Medication inventory visualization"></div>
  <figcaption><strong>Medication inventory</strong><code>medication-inventory</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="medication-adherence-summary" aria-label="Live-rendered Medication adherence summary visualization"></div>
  <figcaption><strong>Medication adherence summary</strong><code>medication-adherence-summary</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="medication-dose-status" aria-label="Live-rendered Medication dose status visualization"></div>
  <figcaption><strong>Medication dose status</strong><code>medication-dose-status</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="medication-adherence-trend" aria-label="Live-rendered Medication adherence trend visualization"></div>
  <figcaption><strong>Medication adherence trend</strong><code>medication-adherence-trend</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="medication-recent-dose-events" aria-label="Live-rendered Medication recent dose events visualization"></div>
  <figcaption><strong>Medication recent dose events</strong><code>medication-recent-dose-events</code></figcaption>
</figure>
</div>

### Mobility, gait, and running form

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="walking-symmetry" aria-label="Live-rendered Walking symmetry visualization"></div>
  <figcaption><strong>Walking symmetry</strong><code>walking-symmetry</code></figcaption>
</figure>
</div>

### Workouts

<div class="visualization-gallery live-visualization-grid">
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="workout-log" aria-label="Live-rendered Workout log visualization"></div>
  <figcaption><strong>Workout log</strong><code>workout-log</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="workout-heart-rate" aria-label="Live-rendered Workout heart rate visualization"></div>
  <figcaption><strong>Workout heart rate</strong><code>workout-heart-rate</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="workout-zones" aria-label="Live-rendered Workout zones visualization"></div>
  <figcaption><strong>Workout zones</strong><code>workout-zones</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="workout-trends" aria-label="Live-rendered Workout trends visualization"></div>
  <figcaption><strong>Workout trends</strong><code>workout-trends</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="workout-intervals" aria-label="Live-rendered Workout intervals visualization"></div>
  <figcaption><strong>Workout intervals</strong><code>workout-intervals</code></figcaption>
</figure>
<figure class="visualization-shot visualization-live-shot">
  <div class="visualization-live-mount" data-healthmd-live-chart="workout-map" aria-label="Live-rendered Workout map visualization"></div>
  <figcaption><strong>Workout map</strong><code>workout-map</code></figcaption>
</figure>
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
