---
title: "Apple Watch VO2 Max (Cardio Fitness): Why It Isn't Updating and How to Export It"
description: "Where Apple Watch VO2 max (Cardio Fitness) lives, which workouts Apple counts, why it may not update, and how to keep the history as CSV, JSON, Markdown or export.xml."
lead: "Apple calls VO2 max Cardio Fitness. Here is where to find it, which workouts Apple uses, why days pass without a new value, and how to keep the history as a file."
date: "2026-11-25"
updated: "2026-11-25"
category: "Export guide"
related:
  - export-apple-health-workouts
  - export-apple-health-heart-rate
  - apple-health-xml-export
draft: false
verified: "2026-11-25"
verified_by: "Claude (agent)"
verified_method: traced
platform: apple
tags:
  - apple-health
  - vo2-max
  - apple-watch
  - export
---

**Cardio Fitness is Apple Watch's estimate of your VO2 max.** Apple only estimates it from **Outdoor Walk, Outdoor Run or Hiking** workouts started in the Workout app, on Apple Watch Series 3 or later. Indoor workouts, including ones that use gym equipment, don't count. To see it, open **Health → Browse → Heart → Cardio Fitness**. To keep the history as a file, use Apple's free **Export All Health Data**, or Health.md's daily CSV, JSON or Markdown files, which mark each day's value as either **measured that day** or **carried forward** from an earlier estimate.

## What Cardio Fitness measures

Apple's support article, [Track your cardio fitness levels](https://support.apple.com/en-us/108790), describes Cardio Fitness as an estimate of VO2 max, the maximum amount of oxygen your body can use during exercise, made from heart rate and motion sensor data. Apple lists a supported range of 14 to 65 mL/kg/min and gives classifications for users 20 and older. The estimate uses your age, sex, weight, height and any medications that may affect heart rate. Apple says certain conditions or medications that limit heart rate might cause an overestimate.

This page gives no "good VO2 max" table. The Health app compares you with people of your age and sex, so use it for context, and ask a clinician what your numbers mean.

## Why your VO2 max isn't updating or is blank

Every item below comes from [Apple's article](https://support.apple.com/en-us/108790). This page does not list forum fixes such as re-pairing or erasing the watch, because Apple doesn't document them.

- **The workout type.** Only Outdoor Walk, Outdoor Run and Hiking workouts in the Workout app count. Indoor workouts, including ones that use gym equipment, do not.
- **The watch.** You need Apple Watch Series 3 or later.
- **The first estimate takes time.** Apple says the first estimate needs at least 24 hours of wear, plus several qualifying workouts and passive measurements.
- **Your details.** Age, sex, weight and height in **Health Details** feed the estimate, so keep them current. That is Apple's list of inputs, not a guaranteed fix.
- **The Update option.** Apple's article describes an **Update** option in Health that can revise earlier estimates. See the article for its current wording.
- **Days without a new value are normal.** Nothing in Apple's article promises a new estimate every day. Health.md's carried-forward flag shows this directly: a day can show the latest earlier estimate instead of a new one.

## See the trend in the Health app

Open **Health**, tap **Browse**, then **Heart**, then **Cardio Fitness**. Apple's article describes the D, W, M, 6M and Y ranges for the chart and the low-level notifications Cardio Fitness can send. Check your own iPhone for the options your iOS version offers.

## Export the history: Apple's own route first

1. Open **Health → Summary**, tap your picture or initials, then choose **Export All Health Data**. Apple documents this in its [Health sharing guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios).
2. Save or send the resulting `export.zip`. Inside is `export.xml`.
3. Look for records of type `HKQuantityTypeIdentifierVO2Max`, Apple's [HealthKit identifier](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/vo2max). The unit is mL/min·kg.

This route is free and complete, but it is one big archive with every record. See [how to open export.xml](/blog/apple-health-xml-export/) and [Apple Health to Excel](/blog/apple-health-to-excel/) for turning it into rows.

## Daily values with Health.md

Health.md for iPhone writes the latest VO2 max estimate recorded up to the end of each day. Each value comes with details about the underlying measurement:

- **CSV rows:** `Cardio Fitness (VO2 Max)` (mL/kg/min), `VO2 Max Source Start`, `VO2 Max Source End`, `VO2 Max Source UUID`, `VO2 Max Carried Forward` (boolean) and `VO2 Max Age` (seconds, measured at the start of the exported day; 0 for a value measured that day).
- **JSON fields:** `activity.vo2Max`, `vo2MaxSourceStartDate`, `vo2MaxSourceEndDate`, `vo2MaxSourceUUID`, `vo2MaxCarriedForward` and `vo2MaxAgeSeconds`.
- **Markdown:** a line such as `Cardio Fitness (VO2 Max): 42.5 mL/kg/min`, with a "Source measurement: … (carried forward)" or "(measured in this day)" sub-bullet.

A value counts as carried forward when its measurement started before the start of the exported day. Here is a **fictional** CSV excerpt from Health.md's generated sample day (not a real person's data):

```csv
2026-03-15,Activity,Cardio Fitness (VO2 Max),42.5,mL/kg/min,2026-03-14T00:00:00.000000000Z
2026-03-15,Activity,VO2 Max Source UUID,00000000-0000-0000-0000-000000000700,uuid,2026-03-14T00:00:00.000000000Z
2026-03-15,Activity,VO2 Max Source Start,2026-03-14T00:00:00.000000000Z,datetime,2026-03-14T00:00:00.000000000Z
2026-03-15,Activity,VO2 Max Source End,2026-03-14T00:01:00.000000000Z,datetime,2026-03-14T00:00:00.000000000Z
2026-03-15,Activity,VO2 Max Carried Forward,true,boolean,2026-03-14T00:00:00.000000000Z
2026-03-15,Activity,VO2 Max Age,86400,seconds,2026-03-14T00:00:00.000000000Z
```

This fictional day, 2026-03-15, shows 42.5 mL/kg/min, carried forward (`true`), measured 86400 seconds (one day) before the day began. You can download the full [fictional sample CSV](/docs/reference/generated/core/summary-day.csv).

**Charting tip:** to plot real measurements only, filter rows where Carried Forward is `false`, or keep one row per Source UUID. Otherwise one estimate repeated across many days looks like a flat trend. The metric is enabled by default. A day before your first estimate has no row, which means no value, not zero. See the [metric catalog](/docs/reference/generated/core/metric-catalog/) and [Apple Health to CSV](/apple-health-to-csv/) for the row format.

Want to see which days had a real VO2 max reading and which repeated an older one? Health.md for iPhone writes it to CSV, JSON or Markdown in a folder you choose.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

## Use the history

- **Spreadsheet:** import the daily CSV files using the [Excel walkthrough](/blog/apple-health-to-excel/) and filter `Carried Forward = false`.
- **Notes:** write the values into daily notes with [Apple Health to Obsidian](/blog/export-apple-health-data-to-obsidian/).
- **Alongside workouts:** the outdoor sessions that feed the estimate export in [Apple Health workouts](/blog/export-apple-health-workouts/).
- **Alongside heart rate:** see [exporting heart rate](/blog/export-apple-health-heart-rate/).

## Where the files go

Health.md writes files to a folder you choose on your device, using the local folder export workflow. Synced folders and anything you share follow their own providers' rules. The separate Health.md Cloud pilot is opt-in, single-owner and not generally available, and folder exports are not uploaded to it.

## Common questions

### Where is VO2 max on Apple Watch or iPhone?

In the Health app on iPhone: **Browse → Heart → Cardio Fitness**. Apple calls it Cardio Fitness.

### Why hasn't my VO2 max updated?

Check Apple's rules above: a qualifying outdoor workout, Apple Watch Series 3 or later, enough wear time for the first estimate, and current Health Details. Days without a new value are normal, and Health.md marks them as carried forward.

### Which workouts count?

Per Apple, Outdoor Walk, Outdoor Run and Hiking workouts started in the Workout app.

### Does an indoor run or treadmill count?

No. Apple says indoor workouts, including ones that use gym equipment, don't count.

### Can I export VO2 max to Excel?

Yes. Export daily CSV files with Health.md and open them in Excel, or convert Apple's `export.xml`. See [Apple Health to Excel](/blog/apple-health-to-excel/).
