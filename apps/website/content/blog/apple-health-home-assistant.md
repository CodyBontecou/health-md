---
title: "Apple Health in Home Assistant: sensors or daily files"
description: "Use Home Assistant's native health sensors for a dashboard, or Health.md for daily CSV, JSON and notes. Check time windows and custom API requirements."
lead: "Start with the Companion app for supported dashboard sensors. Choose a separate export when you need daily files or a receiver you maintain."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - health-md-vs-health-auto-export
  - private-health-data-webhooks
  - export-health-connect-to-obsidian
draft: false
tags:
  - home-assistant
  - apple-health
  - health-connect
  - export
---

**Start with Home Assistant's own Companion app when you want its supported health sensors on a dashboard.** Current documentation covers Apple Health on iPhone and Health Connect on Android. Health.md is an additional option for people who also want selected health data in daily files or a custom ingestion pipeline.

Health.md does not provide a ready-made Home Assistant integration, entity map or dashboard card. A CSV file, a sensor's current state and a historical health record are different representations.

## Choose the output you actually need

| Your task | Start with |
| --- | --- |
| Display supported health values in Home Assistant | Companion app health sensors and their permissions |
| Keep daily CSV, JSON or Markdown outside the dashboard | Health.md folder exports from authorized Apple Health or Health Connect records |
| Send iPhone exports into a server pipeline you maintain | Health.md API Endpoint plus a receiver and explicit Home Assistant mapping |
| Get a destination-specific third-party integration | Check the provider's current Home Assistant setup and compatibility |

If a supported Companion sensor meets your need, you do not need Health.md for that sensor. For destination-specific options, the [Health Auto Export comparison](/blog/health-md-vs-health-auto-export/) explains the distinction between configurable files and dedicated integrations.

## Start with the Companion app's health sensors

The [official sensor guide](https://companion.home-assistant.io/docs/core/sensors/), checked **October 30, 2026**, documents separate phone paths:

- **iPhone:** open **Settings → Companion app → Sensors**, select the intended server where applicable, then **Apple Health Sensors**. Enable selected sensors and authorize their data types. These sensors are not macOS health readers.
- **Android:** use the documented **Health Connect sensors** and check that the source app has written the records. The guide lists Android 9+ with the Play Store version and Android 14+ with all versions; Android 13 or older needs the separate Health Connect app.

Check your installed app's supported sensors. The documentation includes some separately marked beta additions; a listed future-version sensor is not proof that your installed release exposes it.

## Compare dates before comparing numbers

Companion sensors use metric-specific windows: some are today's totals, while others show a recent reading. Its [released iOS sleep calculation](https://github.com/home-assistant/iOS/blob/2524b83e1f6769ea781205a61cad5d1960806544/Sources/Shared/API/Webhook/Sensors/Health/HealthKitSleepSummary.swift) uses a **6 PM to 6 PM** window. Health.md's daily sleep summaries use a **noon-to-noon** journal window.

For example, a Tuesday afternoon nap can fall in Tuesday's Health.md journal day while contributing to the Companion app's preceding sleep night. Preserve the original timestamps and each app's date meaning when comparing results. This Apple sensor comparison does not establish identical Android sleep aggregation.

Read the Companion sensor's unit, aggregation and update behavior alongside Health.md's [sleep-date guide](/docs/sleep-date-attribution/). Permission, source availability and background execution can affect what appears. A dashboard value alone does not establish that every historical record has transferred.

## Make daily files when you need a separate archive

Continue with Health.md when selected daily files are part of your workflow:

- [Get Health.md for iPhone](https://apps.apple.com/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Verify one completed day's records in Apple Health or Health Connect.
2. Grant Health.md separate read access, select the metrics you need and choose a writable folder. On Android, choose the Health Connect source.
3. Preview, export and open the saved file. Check its date, units and values against the source.
4. Widen the date range only after that first export succeeds.

Use [first iPhone export](/docs/iphone-first-export/) or [Android setup](/docs/android/) for the actual controls. Markdown is the iPhone first-export default; choose CSV for tables or JSON for structured processing using the [format guide](/docs/format/).

A range creates separate daily files. These exports do not automatically create Home Assistant entities or import the phone's entire history into its recorder. Another app can contribute records to the same health store, so a daily total is not automatically a single-device total.

The [fictional Apple CSV](/docs/reference/generated/core/summary-day.csv) and separate [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) illustrate Health.md output. Neither is a Home Assistant sensor export or proof of full source coverage. Filter the intended Category, Metric and Unit before treating Value as numeric; it can also contain text and metadata. Missing data is unavailable, not zero.

## Plan a custom iPhone API pipeline separately

For a receiver you control, Health.md's [API Endpoint guide](/docs/api-endpoint/) documents an iPhone JSON POST to a URL you configure. The receiver must validate the versioned envelope and daily records, retain failure and coverage evidence, and handle repeated dates deliberately.

Home Assistant's [RESTful integration](https://www.home-assistant.io/integrations/rest/) consumes an endpoint. That is a different direction from Health.md pushing an export. A receiver could store an accepted export and expose a deliberately mapped response for a sensor, but **you must build and maintain that adapter**.

Do not point Home Assistant at the Mac helper's loopback API from another machine or assume the Health.md envelope matches a sensor's expected response. A successful HTTP response also does not prove that the intended entity or historical series was updated.

Start with the [private webhook guide](/blog/private-health-data-webhooks/) for authentication, bounded validation, durable acceptance and repeated-export handling. This section describes the documented iPhone API target; it does not promise an equivalent Android API Endpoint target. Android readers can use the folder workflow above.

## Check the destination and retention rules

Companion sensors send selected data to your Home Assistant server. Health.md folder exports save to the destination you choose and create no Health.md server copy by default. Synced folders and your own receiver have their own storage and retention rules.

The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it. It has no public signup or automatic device sync and is not generally available. This folder workflow does not upload to that pilot.

Inspect detailed times, identifiers and locations before sharing files. Keep payloads and credentials out of public traces and issue reports. See [local storage choices](/blog/export-health-data-without-the-cloud/) and the [retention policy](/privacy-policy.html#retention).
