---
title: "How to export your Apple Health medication log (taken and skipped doses)"
description: "Apple's Export PDF lists your current medications. To export the dose log, taken and skipped doses with times, use Health.md on iPhone with iOS 26 or later."
lead: "Apple's Export PDF gives you a list of current medications. Health.md on iOS 26 or later can export the dose log (taken or skipped, with times) as CSV, JSON or Markdown."
date: "2026-11-22"
updated: "2026-11-22"
category: "Workflow guide"
related:
  - export-apple-health-data-pdf
  - apple-health-xml-export
  - export-apple-health-blood-pressure
draft: false
verified: "2026-11-22"
verified_by: "Claude (agent)"
verified_method: traced
platform: apple
tags:
  - apple-health
  - medications
  - export
  - csv
---

Apple's built-in **Export PDF** on the Medications screen gives you a copy of your *current medications*, not a history of the doses you logged. If you want the dose log as a file (each dose marked taken or skipped, with its time), you need an app that reads HealthKit's medication dose events. On an iPhone running **iOS 26 or later**, Health.md can export that log as CSV, JSON or Markdown.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a> (needs iOS 26 or later for medications)

## The short answer: list vs log

Apple documents the native route in [Add and log medications with iPhone, iPad, and Apple Watch](https://support.apple.com/en-us/105064) and the [iPhone User Guide](https://support.apple.com/guide/iphone/iph811670c81/ios): open Health, tap **Browse → Medications**, scroll to **More**, and choose **Export PDF**. Apple describes the result as a PDF of your current medications.

Some people report that this PDF shows medication names and strengths but not individual doses and times; see [this Apple Community thread](https://discussions.apple.com/thread/255966235). That is a user report, not Apple documentation, so check the PDF you get on your own device.

| Option | What you get |
| --- | --- |
| Apple Export PDF | A PDF of current medications (per Apple). No app needed, no dose log. |
| Health.md daily file | One file per day with dose counts and lists, as CSV, JSON or Markdown. Needs iOS 26+. |
| Health.md Individual Entry file | One Markdown file per logged dose. Needs iOS 26+. |

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a> (needs iOS 26 or later for medications)

## What Apple's other exports do and don't cover

Apple's **Export All Health Data** produces a full archive; see [how to open an Apple Health XML export](/blog/apple-health-xml-export/). This guide makes no claim about whether that archive's `export.xml` contains medication dose events. Check your own archive if you need to know.

For a PDF of other measurements, see [how to export Apple Health data as a PDF](/blog/export-apple-health-data-pdf/).

## Export the dose log with Health.md (iPhone, iOS 26+)

1. Install Health.md on an iPhone running iOS 26 or later. Medication export is not available on earlier iOS versions; the app says "Medication export requires iOS 26 or later" and other metrics still export.
2. In the metric selection, turn on the **Medications** category. It is **opt-in**: it is off by default and uses a separate permission flow, so it is not switched on by "select all" or by onboarding.
3. In the iOS prompt that follows, choose which medications Health.md may read. Apple's HealthKit asks for access per medication ([WWDC25 session 321](https://developer.apple.com/videos/play/wwdc2025/321/)), and Health.md sees only the ones you select.
4. Pick one known day and a writable Files folder. Follow [your first iPhone export](/docs/iphone-first-export/) for the folder setup.
5. Export as CSV or JSON, then open the file and check it against what you see in the Health app.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a> (needs iOS 26 or later for medications)

## What the export contains

Each daily file summarizes your medications for that day. In Markdown the fields are:

- `medication_count`, `active_medication_count`, `archived_medication_count`
- `medication_dose_count`, `medication_taken_count`, `medication_skipped_count`
- `medication_details` (a list of your medications) and `medication_dose_events` (a list of the logged doses)

JSON uses the same data with camelCase names such as `medicationCount`, `doseEventCount`, `takenDoseCount` and `skippedDoseCount`.

For one file per dose, turn on [Individual Entry Tracking](/docs/individual-tracking/) for Medications. The [fictional sample entry](/docs/reference/generated/individual/medication-dose.md) is fixture output, not anyone's records. It shows `status: taken`, a `scheduled_datetime` of 09:14 next to a logged `start_datetime` of 09:19, and a `dose_quantity` of 1.5 against a `scheduled_dose_quantity` of 2 tablets.

## Limits

- Requires iOS 26 or later.
- Reads only the medications you authorized.
- Reads only doses that were actually logged. A missing log is not a skipped dose.
- Clinical medication records from health providers are a separate HealthKit type and are not part of this feature.
- There is no Android route: Health Connect has no equivalent medication dose-event catalog.
- Health.md does not interpret doses or give medical advice.

## Where the file goes

The export is written to the folder you chose on your device. Core folder exports need no Health.md account and create no Health.md server copy by default; see [exporting health data without the cloud](/blog/export-health-data-without-the-cloud/). The separate Health.md Cloud pilot is opt-in, single-owner and not generally available, and it does not receive folder exports. If you share a file with a clinician, open it first and check what it contains.
