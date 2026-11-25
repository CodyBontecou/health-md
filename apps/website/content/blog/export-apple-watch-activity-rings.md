---
title: "Export Apple Watch Activity rings (Move, Exercise, Stand) to CSV or JSON"
description: "Get Apple Watch Activity rings history out of Apple Health: Apple's native export.zip, or one CSV or JSON file per day with Move, Exercise and Stand totals from Health.md."
lead: "Apple's native export puts ring history inside one large export.xml. Health.md writes one file per day with the ring totals as named columns. Neither is a workouts export."
date: "2026-11-25"
updated: "2026-11-25"
category: "Workflow guide"
platform: apple
related:
  - export-apple-health-workouts
  - export-apple-health-steps-data
  - apple-health-to-excel
draft: false
verified: "2026-11-25"
verified_by: "Claude (agent)"
verified_method: traced
tags:
  - apple-health
  - apple-watch
  - activity
  - csv
  - export
---

**Can you export Activity rings history from an iPhone and Apple Watch?** Yes, two ways. Apple's native route is **Health → your picture or initials → Export All Health Data**, which gives `export.zip` with ring history inside `export.xml`, a large XML file that also holds every other record. The Health.md route writes one CSV, JSON or Markdown file per day with the ring **totals** (Active Energy, Exercise Time, Stand Hours) as named columns or fields. Rings are daily totals; individual workouts are a different thing, covered in the [workouts guide](/blog/export-apple-health-workouts/).

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

For current access and trial details see [plans and trials](/docs/paywall/). Manual export runs on your iPhone and does not require a Mac.

## Rings versus workouts

The Move, Exercise and Stand rings summarize a whole day. A workout is one recorded session with a start, end and type. If you want sessions, use the [workouts guide](/blog/export-apple-health-workouts/). If you want one row per day for your rings, keep reading.

## Option 1: Apple's native export

Apple's [Share your health data guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) describes the export:

1. Open the **Health** app and tap your picture or initials.
2. Tap **Export All Health Data** and save or share the resulting `export.zip`.

Ring history is in `export.xml`, alongside workouts and every other record. It is one large XML file, not a spreadsheet. To turn it into rows, see [Apple Health XML export](/blog/apple-health-xml-export/).

Apple's HealthKit [`HKActivitySummary`](https://developer.apple.com/documentation/healthkit/hkactivitysummary) documents the Move, Exercise and Stand values and their goals. If you need ring **goals**, this native export is the route to check. This guide does not list the XML attribute names, because that needs a real export to confirm.

## Option 2: daily ring totals with Health.md

1. Open Health.md and authorize the relevant health categories.
2. Open **Health Metrics → Activity** and enable **Active Energy**, **Exercise Time** and **Stand Hours**. Add **Stand Time** or **Move Time** if you want them (Move Time is for Move-time mode).
3. Choose **CSV** or **JSON**, select one known day, and choose a writable Files folder.
4. Tap **Preview** and check the date and totals, then export. Open the saved file to confirm it was written.

See [your first iPhone export](/docs/iphone-first-export/) for setup and folder selection, and [how to export Apple Health data](/apple-health-export/) for the other formats.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

| Ring | Health.md metric | Key | Unit |
| --- | --- | --- | --- |
| Move | Active Energy | `active_calories` | kcal, daily sum |
| Exercise | Exercise Time | `exercise_minutes` | min, daily sum |
| Stand | Stand Hours | `stand_hours` | count of hours with a stand |
| Stand (minutes) | Stand Time | `stand_time_minutes` | min, daily sum |
| Move (time mode) | Move Time | `move_minutes` | min, daily sum |

These come from the [metric catalog](/docs/reference/generated/core/metric-catalog/). Apple documents the underlying types: [`activeEnergyBurned`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned), [`appleExerciseTime`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/appleexercisetime) and [`appleStandHour`](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/applestandhour).

## What's not in the daily files

Ring **goals** and "ring closed" status are **not** daily summary fields, and neither are award badges. The catalog's Activity Summary record type (rings and goals) is archive only, and its documented observed fields are just the date and active energy; see the Activity summary section of the [specialized records reference](/docs/reference/generated/core/specialized-records/). For goals, use Apple's `export.xml`.

## Check one known day against the Fitness app

Pick a finished day, open it in the Fitness app, and compare the ring values with your exported file. Don't expect an exact match. Active Energy in Health.md is a daily sum, and it can differ from the Move ring if several sources contribute, if the calendar day or time zone differs, or if the day was iPhone-only. Today's numbers can still change as data syncs, so re-export an affected day rather than adding two exports together.

## Into Excel or Google Sheets

A date range produces one file per day. Export as CSV, then combine the files with the local combiner and CSV guidance on [Apple Health to CSV](/apple-health-to-csv/), and follow the [Excel walkthrough](/blog/apple-health-to-excel/) from there.

## Where the files go

Files are written to the folder you choose on your device, using the local folder export workflow. Synced folders and anything you share them with follow their own rules. The Health.md Cloud pilot is separate, opt-in, single-owner and not generally available; the folder workflow does not upload to it. See [retention and destination boundaries](/privacy-policy.html#retention).

## FAQ

**Can I export rings from the Fitness app?** No Fitness-app export is documented. Apple documents the export in the Health app.

**Does it include ring goals?** Not in Health.md's daily files. Use Apple's `export.xml`.

**Can I export only one month?** With Health.md, yes: select that date range. Apple's native export always covers all of your Health data.

**Does it work without an Apple Watch?** The iPhone can record some Move data on its own, so you may see rows without a watch. Whether a given day has them depends on your data; check one day first.
