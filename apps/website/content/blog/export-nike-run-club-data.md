---
title: "Export Nike Run Club runs: Nike's data request and the Apple Health route"
description: "Nike's help pages document no per-run CSV or GPX export from Nike Run Club. Request your data from Nike, or export runs already in Apple Health."
lead: "Nike's help pages describe a data request for your full history and an Apple Health connection for day-to-day use. Health.md exports the runs already in Apple Health."
date: "2026-11-27"
updated: "2026-11-27"
verified: "2026-11-27"
verified_by: "Claude (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - export-apple-health-workouts
  - export-strava-data
  - apple-health-export-xml-workout-distance
draft: false
tags:
  - nike-run-club
  - workouts
  - apple-health
  - csv
---

**Nike's help pages document no per-run CSV or GPX download in Nike Run Club.** Two routes are documented. For your full history, Nike offers a data request: sign in to your Nike Member profile in a web browser, then **Account Settings → Privacy → Download Your Data → Request Data**. For day-to-day use on iPhone, connect NRC to Apple Health. Health.md can then export the runs that are in Apple Health as CSV, JSON or daily Markdown files, on your iPhone. Apple's own `export.zip` is the no-install alternative.

Health.md reads only what is in Apple Health. It does not connect to a Nike account, import Nike's archive, recover runs that never synced, or write GPX, FIT or TCX.

## What Nike offers

Nike's help pages describe no CSV or GPX export for individual runs in the app. That is about what Nike documents today, not a promise that it will never exist.

For your whole history, Nike's help article [What happened to my Nike data?](https://www.nike.com/help/a/nike-data-protection) describes a data request:

1. In a web browser, sign in to your Nike Member profile.
2. Open **Account Settings** and the **Privacy** tab.
3. Choose **Download Your Data**, then **Request Data**.

Nike says it emails a download link to your profile email address within seven days, and you may need a Member profile code to confirm your identity. Nike doesn't document the file formats in the archive, so this guide doesn't describe them. Nike's [privacy webform](https://www.nike.com/help/privacy) also covers requests to have data deleted, corrected or exported.

Nike's inactivity policy, as that article describes it: after two years of inactivity, individual run and workout data is aggregated; after five years, the profile and its data are deleted. If you plan to leave NRC, request your data before then.

## Which route should you use?

| I want… | Use |
| --- | --- |
| My full Nike account history | Nike's data request (above) |
| Runs in a spreadsheet | Apple Health, then Health.md CSV and the [Excel guide](/blog/apple-health-to-excel/) |
| Per-run JSON for scripts | Health.md JSON |
| GPX for Strava or another service | Neither Nike's help pages nor Health.md offer this. Check the destination's own importer, and see the [Strava guide](/blog/export-strava-data/). |
| A backup of everything in Health | Apple's `export.zip`; see the [XML export guide](/blog/apple-health-xml-export/) |

## Step 1: Send NRC runs to Apple Health

Nike's help article [How do I connect NRC or NTC to Apple Health?](https://www.nike.com/help/a/connect-nrc-health-app) gives this path:

1. On your iPhone, open **Settings** and scroll to **Privacy & Security**.
2. Tap **Health**, then **Nike Run Club**.
3. Choose which data to share with Health.

Nike says data then flows from NRC to Health, and names active energy, heart rate, walking and running distance, and workouts. Nike doesn't mention routes, so don't assume NRC routes reach Health.

Then open the **Health** app and check that a run you know about appears as a workout.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Export the runs already in Apple Health with Health.md</a>

See [purchase details](/docs/paywall/) for access options.

## Step 2: Export one known day first

This follows the [Apple Health workouts guide](/blog/export-apple-health-workouts/):

1. In Health.md, authorize your health categories and enable **Workouts** in **Health Metrics**.
2. Choose **CSV** or **JSON** and start with **Summary**.
3. Select the calendar day a known run **started**.
4. Choose a writable folder in Files.
5. Tap **Preview**, check the date and workouts, then export. Open the saved file and confirm its contents.

Several CSV rows describe one run, so don't count rows as runs. For one object per run, use JSON. The workouts guide explains the columns and the sample values. For Apple's alternative, see its [Share your health data](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) guide: **Health → your picture or initials → Export All Health Data** produces `export.zip`.

## Limits

- Runs that never synced to Apple Health can't be recovered through Health.md.
- Nike doesn't say whether routes and pace splits reach Health, and a recorded workout doesn't guarantee that every field exists.
- Health.md doesn't write GPX, FIT or TCX, and doesn't connect to Nike.
- Android: Nike's help pages don't document Health Connect for NRC, so this guide offers no Android route.

## FAQ

**Can I export NRC to CSV?** Nike's help pages document no CSV export from the app. Once runs are in Apple Health, Health.md can export them as CSV.

**How long does Nike's data request take?** Nike says it emails a download link within seven days.

**Does NRC sync to Apple Health automatically?** Nike says that once connected, data flows from NRC to Health. Set it up under **Settings → Privacy & Security → Health → Nike Run Club**.

**Can I get GPX?** Nike's help pages don't document it, and Health.md doesn't write GPX. Apple's `export.zip` stores recorded routes as GPX in `workout-routes/` when a route exists in Health; see the [workouts guide](/blog/export-apple-health-workouts/). For other services, check their importers. More on Health.md is at [how to export Apple Health data](/apple-health-export/).

**Does this work on Android?** Nike's help pages don't document Health Connect for NRC.
