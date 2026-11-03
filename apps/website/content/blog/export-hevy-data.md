---
title: "Export Hevy data: workout CSV or daily health files"
description: "Save Hevy workout or measurement exports first, or organize records already shared to Apple Health or Health Connect. Check history and strength-log limits."
lead: "Keep your Hevy training copy separate from daily files made from the records that reached your phone's health store."
date: "2026-11-02"
updated: "2026-11-02"
verified: "2026-11-02"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-apple-health-workouts
  - export-health-connect-to-obsidian
  - export-polar-flow-data
draft: false
tags:
  - hevy
  - workouts
  - csv
  - health-connect
---

**Use Hevy's own export first when you want a copy of the training or measurements you logged there.** You do not need Health.md for that download. Health.md offers a different workflow: daily files from selected records already available in Apple Health or Android Health Connect.

A phone health-store export is not automatically a copy of your strength-training log. Choose the source that contains the information you need before installing another app.

## Download from Hevy

Hevy's [current export instructions](https://help.hevyapp.com/hc/en-us/articles/43708290987415-Exporting-Your-Data-from-Hevy), checked **November 2, 2026**, give this route:

1. Open **Profile → Settings → Export & Import Data → Export Data**.
2. Choose **Export Workouts** or **Export Measurements**, depending on the records you need.
3. Save the generated file using your device's available save or share options.

The two choices cover different information: workouts from your training history versus measurements logged in Hevy. Its help page describes spreadsheet-compatible output that you may need to open or import as CSV. Keep an untouched original, then inspect the actual dates, units and columns before changing it.

For exercise-level analysis, first check whether the native file contains the set, repetition, weight or note fields you need. This guide does not promise particular column names, file delivery methods, plan entitlements or complete historical coverage that were not verified in an actual export.

## Check what reached Apple Health

For an iPhone daily-note workflow, verify Hevy's outgoing connection first. Hevy's [Apple Health troubleshooting guide](https://help.hevyapp.com/hc/en-us/articles/36957445562775-Hevy-Not-Syncing-to-Apple-Health-Step-by-Step-Troubleshooting-Guide) describes **Profile → gear icon → Apple Health → Connect** and a permissions check. It also says to check **Apple Health** under **Sync With** when saving a workout.

Its important history limit: **workouts logged while syncing was not working will not retroactively appear in Apple Health after the issue is fixed**. Do not assume reconnecting creates the missing history.

Inspect a known completed workout in Apple Health before exporting. Check its source, start time and available values. Hevy's permission to write and Health.md's permission to read are separate. If the workout is absent, another exporter cannot read it from that store; keep the native Hevy download for the missing training history.

## Save daily files on iPhone

Continue only if the records are already present in Apple Health and you want selected daily CSV, JSON or Markdown files alongside other authorized metrics.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

Follow the [first iPhone export guide](/docs/iphone-first-export/) to grant read access and choose a writable folder. Enable **Workouts**, select one known workout's start day and preview the output before writing. Start small, then expand the date range only after checking the saved file.

For the iPhone route, CSV has several rows describing a workout, such as type, duration and available energy or heart-rate statistics. Those are fields, not separate sessions. JSON keeps workout objects together with IDs and exact timestamps. The [workout export guide](/blog/export-apple-health-workouts/) explains the distinction, including reported duration versus elapsed start-to-end time.

These are Apple Health records, not a direct Hevy account query or a Hevy-only filter. Do not infer that your exercise names, set order, repetitions, weights, personal records or training notes have been reconstructed. Use Hevy's native copy whenever preserving the strength log is the goal. Health.md does not import that CSV back into Hevy.

## Android and Health Connect

Hevy's [connection documentation](https://help.hevyapp.com/hc/en-us/articles/34895971528727-How-to-Connect-to-MyFitnessPal-Apple-Health-Health-Connect) describes enabling Health Connect integration in Hevy settings and reviewing permissions. Check the connection available on your own phone and inspect the records that actually arrived; do not assume the iPhone history behavior, field coverage or CSV labels apply identically on Android.

If the required records are already in Health Connect, follow the [Health Connect export guide](/health-connect-export/) to select metrics and dates, preview one day and save files to a chosen folder.

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md for Android</a>

A linked app does not establish full history, all strength-training fields or permission to read every category. Keep the native workout and measurement files when those are the records you need to preserve.

## Verify a small example before combining days

For a **fictional** comparison, imagine a workout logged in Hevy on Monday while sharing was broken, then another on Tuesday after sharing worked. Tuesday's presence in the phone health store does not prove Monday was recovered. Do not replace Monday's absent workout with a zero-duration session.

For your own export, compare one known session's date, duration, units and available source information with the saved daily file. Keep original files and inspect overlapping exports before counting sessions. Multiple recordings or re-exports can describe the same activity; adding every row or copy can inflate a total.

Core folder export creates no Health.md health-data server copy by default. A chosen cloud folder, spreadsheet upload or shared file follows that destination's rules. Keep personal training files private and use the [local-only workflow](/blog/export-health-data-without-the-cloud/) when that suits your storage needs.
