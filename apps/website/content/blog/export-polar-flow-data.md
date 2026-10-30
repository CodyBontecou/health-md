---
title: "Export Polar Flow data: native files or shared daily records"
description: "Download Polar Flow training files or an account archive, or save shared Apple Health and Health Connect records as daily files. Check archive and sharing limits."
lead: "Use Polar's own downloads for training files. For daily files and notes, first verify the records Flow actually shared to your phone's health store."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-apple-health-workouts
  - export-zepp-amazfit-data
  - export-health-data-without-the-cloud
draft: false
tags:
  - polar
  - workouts
  - apple-health
  - health-connect
---

**Polar Flow already provides training downloads and an account-data request. You do not need Health.md for those exports.** Choose them when you need the files Polar supplies directly.

Health.md offers a separate workflow: daily CSV, JSON or Markdown files from selected records already shared to Apple Health or Health Connect. This route does not import Polar's downloaded files, connect directly to a Polar account or reconstruct Polar's proprietary calculations.

## Choose the representation you need

| Your task | Start with |
| --- | --- |
| Keep one training session or an activity file for another service | Polar Flow's native training export |
| Request available account data | Polar account download; review its algorithm-derived-data exclusions |
| Keep selected shared records beside daily notes or other health data | Verify Apple Health or Health Connect records, then use Health.md |

A training file, an account archive, a shared sleep record and a calculated score are different outputs. None should be treated as a universal backup of everything shown in Flow.

## Export a training session directly from Flow

Polar's [training export instructions](https://support.polar.com/en/export-training-sessions-flow), checked **October 30, 2026**, use the Flow website:

1. Open **Diary** and select a training session.
2. Open **Export** and choose an available format or ZIP option.
3. Keep the original download and inspect it before importing elsewhere.

Polar documents route exports in **GPX or FIT** and other training data in **TCX, CSV or FIT**. Multisport exports have their own format choices. A format name does not guarantee that a session contains every optional field or that another service interprets it identically.

This native training CSV is distinct from Health.md's daily CSV. The workflow below does not turn daily totals or JSON coordinates into a GPX, FIT or TCX activity file.

## Request account data and read the exclusions

Follow Polar's [account-download instructions](https://support.polar.com/en/how-to-download-all-your-data-from-polar-flow): sign in at [account.polar.com](https://account.polar.com/), choose **Download your data**, then **Download**. Polar emails you when collection is ready and documents a two-week download window after that email.

Polar explicitly excludes data derived using its algorithms, naming activity and sleep information as examples. **Do not assume this archive includes every value visible in Flow.** Inspect its contents and keep the original files.

Some supported records may separately reach a phone's health store through sharing. That does not mean Health.md can recreate an excluded Polar algorithm, score or complete historical dataset.

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

## Protect the destination and detailed records

Workout exports can contain exact times, identifiers or locations. Inspect the actual file before sharing it; a summary selection is not a universal guarantee that coordinates are absent.

Core folder exports require no Health.md account and create no Health.md server copy by default. Synced folders and downstream services have their own storage rules. The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot.

Read the [retention policy](/privacy-policy.html#retention) and [local destination guide](/blog/export-health-data-without-the-cloud/) for storage and backup checks. For another watch ecosystem, use the [Garmin export guide](/blog/export-garmin-connect-data/) and its distinct sharing requirements.
