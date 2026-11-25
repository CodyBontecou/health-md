---
title: "Export Polar Flow data: one session, all your data, or daily files"
description: "Export one Polar Flow session as GPX, TCX, CSV or FIT, download your account data, or save shared Apple Health records as daily files."
lead: "Flow exports one session at a time; the account download covers the rest, minus activity and sleep summaries. Daily files come from what Flow shares to your phone."
date: "2026-10-30"
updated: "2026-11-23"
verified: "2026-11-23"
verified_by: "isobot (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-apple-health-workouts
  - export-fitbit-data
  - export-coros-data
draft: false
tags:
  - polar
  - workouts
  - apple-health
  - health-connect
---

**To export one Polar Flow session, use flow.polar.com. To get everything else, request your account data at account.polar.com.** Both are Polar's own tools, checked against Polar's pages on **November 23, 2026**.

- **One session:** on flow.polar.com open **Diary**, open the session, then use **Export** at the top right and choose GPX, TCX, CSV, FIT or a ZIP. Routes export as GPX or FIT; heart rate, calories and cadence export as TCX, CSV or FIT; multisport sessions export as GPX, FIT or TCX.
- **All your data:** sign in at account.polar.com, choose **Download your data**, then **Download**. Polar emails you when it is ready, and you then have two weeks to download it. It excludes data derived with Polar's algorithms, so it has **no activity or sleep summaries**.
- **Many sessions:** Polar's instructions describe exporting one session at a time. They do not describe a multi-session export in Flow web.
- **Daily files next to other data:** if Flow shares to Apple Health or Health Connect, Health.md can save those shared records as daily CSV, JSON or Markdown. See [the Health.md steps](#section-make-one-daily-export-with-health-md) once you have checked what Flow shares.

| Your task | Start with |
| --- | --- |
| Keep one training session or an activity file for another service | Flow web: Diary → session → Export |
| Request your account data (without activity and sleep summaries) | account.polar.com → Download your data |
| Keep selected shared records beside daily notes or other health data | Verify Apple Health or Health Connect records, then use Health.md |

A training file, an account download, a shared sleep record and a calculated score are different outputs. None should be treated as a universal backup of everything shown in Flow. Health.md does not import Polar's downloaded files, connect to a Polar account or reconstruct Polar's proprietary calculations.

## Export a training session from Flow web

Polar's [training export instructions](https://support.polar.com/en/export-training-sessions-flow), checked **November 23, 2026**, use the Flow website:

1. Open **Diary** and click a training session.
2. Open the **Export** drop-down at the top right and choose **TCX**, **CSV**, **FIT**, **GPX** or a ZIP package.
3. Keep the original download and inspect it before importing elsewhere.

By data type, Polar documents a route as **GPX or FIT**, and other training data such as heart rate, calories and cadence as **TCX, CSV or FIT**. Multisport sessions export as **GPX, FIT or TCX**. Polar recommends the ZIP option for slow connections or large files, and says to **extract the ZIP before importing GPX or TCX files** into other services. A format name does not guarantee that a session contains every optional field or that another service interprets it identically.

This native training CSV is distinct from Health.md's daily CSV. The workflow below does not turn daily totals or JSON coordinates into a GPX, FIT or TCX activity file.

## Download all your Polar data

Follow Polar's [account-download instructions](https://support.polar.com/en/how-to-download-all-your-data-from-polar-flow), checked **November 23, 2026**.

**What is not included:** Polar excludes data derived using its algorithms, naming activity and sleep information as examples. Expect no activity or sleep summaries, and do not assume the download includes every value visible in Flow.

**How:** sign in at [account.polar.com](https://account.polar.com/), choose **Download your data**, then **Download**. Collection can take a while. Polar emails you when it is ready, and you have two weeks to download it after that email.

Polar's page does not state the file format. Open the ZIP, check what it contains and keep the original files.

Some supported records may separately reach a phone's health store through sharing. That does not mean Health.md can recreate an excluded Polar algorithm, score or complete historical dataset.

## Exporting from the Polar Flow phone app

Polar's export page covers the Flow web service only; it does not describe file exports from the phone app. For GPX, TCX, CSV or FIT files, use flow.polar.com in a browser. Otherwise use the phone-sharing route below.

## Verify Flow's phone-sharing route

### iPhone: Polar Flow to Apple Health

Polar's [Apple Health guide](https://support.polar.com/en/support/connecting_polar_flow_with_apple_health) uses **More → General settings → Apple Health**. Enable the connection, choose the categories to share and authorize them.

This connection runs **from Flow to Apple Health**, not in reverse. Polar lists workouts, steps, energy, weight, sleep duration and sleep times among shared information. Its heart-rate sharing covers **workout heart rate, not continuous heart rate**. Do not assume all-day sensor history or a proprietary sleep score reached Apple Health.

For a recent sharing gap, Polar documents **Sync now** under the Apple Health toggle as resending the last two weeks. That is not an unlimited-history backfill promise. Inspect the actual day and source records before widening an export range.

### Android: Polar Flow to Health Connect

Polar's [Health Connect guide](https://support.polar.com/ca-en/flow-app-health-connect) uses **General settings → Health Connect**. Choose the data to share and allow the requested categories; use **Manage permissions** for later changes.

Its documented fields include workouts, workout heart rate, daily steps, sleep with stages and supported biometrics. Routes and laps depend on availability. Active calories exclude basal energy, while total calories include it; do not add active and total calories together.

The guide describes new Flow data reaching Health Connect while the connection remains active. It does not establish that all older Flow history is copied. Check a known day's actual records and fields. Android's stage list is not a promise that Apple's shared sleep representation is identical.

## Make one daily export with Health.md

Continue after the records you need are present in the phone's health store:

- [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Grant Health.md separate read access to the relevant categories. On Android, choose the **Health Connect** source.
2. Select the metrics or workouts you verified. Start with one completed day and a writable folder.
3. Choose **CSV** for table inspection, **JSON** for structured processing or **Markdown** for daily notes.
4. Preview, export and open the saved file. Check its date, units, values and location against the phone's source records before increasing the range.

Use [your first iPhone export](/docs/iphone-first-export/) or the [Android setup guide](/docs/android/) for folder and history access. A longer range creates separate daily files. A connected source does not establish full coverage, and another app may contribute records to the same health store.

For iPhone sessions, follow the [Apple Health workout guide](/blog/export-apple-health-workouts/) for start-day assignment, JSON session grouping and reported versus elapsed duration. For sleep, follow the [sleep export guide](/blog/export-apple-health-sleep-data/) and its journal-date rule. Do not assume the workout and sleep date conventions are the same.

## Inspect the correct sample before combining files

The [fictional Apple daily CSV](/docs/reference/generated/core/summary-day.csv) and [fictional Apple JSON](/docs/reference/generated/core/summary-day.json) illustrate Health.md output. The separate [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) illustrates Android activity output. None is a native Polar file or proof that Flow supplies every sample field.

Use a CSV-aware importer. Filter the intended Category, Metric and Unit before converting Value to numbers; the full column also contains text and metadata. Several rows can describe one workout, so counting rows is not counting sessions. Keep optional details and platform-specific fields distinct using the [format guide](/docs/format/).

Check overlapping dates, re-exports and multiple sources before combining files. Do not add samples, lap subtotals and complete session totals together. A missing field is unavailable data, not zero, and an exported daily value does not by itself reproduce a Flow dashboard calculation.

## When data is missing

- **Absent from Apple Health or Health Connect:** check Flow synchronization, the outgoing category and write permissions first. An exporter cannot recover unshared data.
- **Present on the phone but absent from the file:** check Health.md read access, metric selection, date rules, history access and the actual saved destination.
- **A workout has no route or sensor stream:** a session summary does not establish those details exist. Inspect the native training file when that is the representation you need.
- **A score differs or is absent:** keep proprietary calculations separate from shared measurements. Health.md does not rebuild Polar's excluded algorithms from daily totals.

This guide covers **Polar Flow**. If you use Polar Beat, use its own [Apple Health sharing instructions](https://support.polar.com/us-en/connecting-polar-beat-with-apple-health); do not apply Flow's menus or history behavior automatically.

## Combining Polar with Fitbit, Garmin or other exports

- **Keep each source's original files.** A Polar download, a Fitbit Takeout archive and a Garmin export use different structures; do not overwrite one with another.
- **Use one shared health store as the common layer** only where the devices actually share to it. Check a known day in Apple Health or Health Connect to see which records each source wrote.
- **Watch for duplicate workouts** when two sources write the same session, and never add active and total calories together.
- **Health.md exports what is in the health store.** It does not import Polar or Fitbit archive files.

For the other sources, see the [Fitbit export guide](/blog/export-fitbit-data/) and [Garmin export guide](/blog/export-garmin-connect-data/). For spreadsheet work with the daily files, see [Apple Health to Excel](/blog/apple-health-to-excel/) or the [Health Connect export page](/health-connect-export/).

## Common questions

### Can I export all Polar Flow sessions at once?

Polar's export instructions describe one session at a time. For wider coverage, request your account data and inspect it, or use daily files from records Flow shares to your phone.

### What format is the Polar data download?

Polar's page does not say. Open the ZIP and check its contents.

### Does the Polar download include sleep and activity summaries?

No. Polar excludes data derived with its algorithms, and names activity and sleep information as examples.

### Can I export from the Polar Flow app?

Polar's export page covers the Flow website only. Use flow.polar.com in a browser for file exports.

## Protect the destination and detailed records

Workout exports can contain exact times, identifiers or locations. Inspect the actual file before sharing it; a summary selection is not a universal guarantee that coordinates are absent.

Core folder exports require no Health.md account and create no Health.md server copy by default. Synced folders and downstream services have their own storage rules. The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot.

Read the [retention policy](/privacy-policy.html#retention) and [local destination guide](/blog/export-health-data-without-the-cloud/) for storage and backup checks. For Strava activities, see the [Strava export guide](/blog/export-strava-data/). For another watch ecosystem, use the [Garmin export guide](/blog/export-garmin-connect-data/) and its distinct sharing requirements.
