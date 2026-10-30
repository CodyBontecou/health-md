---
title: "Export Oura data: account download or daily CSV files"
description: "Choose Oura's account download, a shareable report, or daily files from Apple Health or Health Connect. Check membership, permissions and shared records first."
lead: "Oura's own download preserves account data. Health.md offers a separate route for selected records already shared to Apple Health or Health Connect on your phone."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-apple-health-data-to-obsidian
  - export-health-connect-to-obsidian
  - export-fitbit-data
draft: false
tags:
  - oura
  - apple-health
  - health-connect
  - csv
---

To export Oura data, decide whether you need your account's download, a printable report, or selected daily records for a spreadsheet or notes. **You do not need Health.md for Oura's own download or reports.**

Health.md reads authorized records from Apple Health on iPhone or Health Connect on Android. It does not import Oura's downloaded archive or connect this workflow directly to your Oura account. A shared-store export is not a backup of everything in Oura.

## Choose the output before choosing an app

| You need | Start with |
| --- | --- |
| Oura's downloadable account data | Oura Membership Hub |
| A supported printable summary | Oura's Shareable Reports |
| Selected daily CSV, JSON or Markdown files | Records actually shared to Apple Health or Health Connect, then Health.md |
| Oura-specific scores or fields absent from your phone's shared store | Check Oura's own download and official API documentation |

## Request the account download from Oura

Follow Oura's [export instructions](https://support.ouraring.com/hc/en-us/articles/360025441594-Export-Share-Your-Oura-Data): sign in to the [Membership Hub](https://membership.ouraring.com/), choose **Export data → Request your data**, then download from the hub after its email arrives. Preparation can take up to ten days.

The account download is available without active membership. Keep the original files and inspect their structure before spreadsheet import; Health.md does not convert them.

For an eligible printable summary, use **Reports → Shareable Reports** in Oura. Check the official instructions for supported contents and eligibility. A PDF is a different output from daily spreadsheet rows.

## Check sharing eligibility and coverage

Oura lists both its [Apple Health integration](https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration) and [Android Health Connect integration](https://support.ouraring.com/hc/en-us/articles/10786105824531-Health-Connect-by-Android-Integration) for **Gen2**, or **Gen3 and later with an active membership**. The account download's membership rule does not make every integration available without membership.

The shared types differ by platform. For example, Oura lists steps and sleep on both outgoing lists; it lists heart rate variability for Health Connect, while its Apple Health outgoing list does not list that metric. Check the current list for your phone and inspect an actual record. Do not infer that a type Oura reads from another app is also a type it writes out.

Oura's Readiness Score and Sleep Score are not listed as outgoing types on those integration pages. Do not expect them to appear just because sleep or heart-rate records were shared. Sharing selected records does not reproduce Oura's scores or algorithms.

### On iPhone

In Oura, open **Settings → Data sharing → Apple Health** and enable the connection. Review which categories Oura may write in Apple Health's app permissions. Health.md needs its own read authorization; granting Oura access does not grant Health.md access.

Pick a completed day, then inspect the relevant records and their source in Apple Health. Other apps and devices can contribute to the same metric. A daily Health.md total should not be described as Oura-only or expected to equal Oura's dashboard automatically.

### On Android

In Oura, open **Settings → Data Sharing → Health Connect** and choose the relevant sharing categories. Check that Oura may write the desired types and that an actual record for your chosen day exists in Health Connect. Health.md needs separate read access to those types.

Oura's current instructions say its Google Fit integration is no longer available. Follow the Health Connect route rather than an old Google Fit tutorial. The shared store can contain records from multiple apps; this workflow does not promise an Oura-only source filter.

## Export a small selection with Health.md

Only continue once you have confirmed the records are available on your phone. Choose the download for that phone:

- [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969)
- [Get Health.md on Google Play](https://play.google.com/store/apps/details?id=com.healthmd.android)

1. Authorize the relevant read categories. On Android, use the **Health Connect** source.
2. Choose a writable folder, select **CSV**, and start with one known day and a small metric set.
3. Preview and export, then open the actual saved file. Compare its date, units, values and destination with the source records.
4. Increase the range after that check. Daily exports produce separate files for the selected days.

Use the [iPhone CSV walkthrough](/apple-health-to-csv/) or [Android setup guide](/docs/android/) for the platform's actual controls. JSON and Markdown are alternatives when those formats better fit your script or notes.

## Inspect the right sample and units

Try fictional files before using personal data:

| Export path | Sample and interpretation |
| --- | --- |
| Apple Health on iPhone | [Generated daily CSV](/docs/reference/generated/core/summary-day.csv), with the [daily steps explanation](/blog/export-apple-health-steps-data/) |
| Health Connect on Android | [Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv), with the [Health Connect export guide](/health-connect-export/) |

These are Health.md samples, not Oura account downloads. Filter the intended Category, Metric and Unit before converting Value to numbers; that column can also contain text. Keep daily summaries separate from timed records and overlapping exports.

Oura documents duration values in seconds in its download. Check each file's actual units before formatting. Health.md formats have their own units and structure.

## Diagnose missing days before widening the export

If a record is absent from Apple Health or Health Connect, inspect Oura's sharing settings and synchronization first. If it exists there but is absent from the file, check Health.md's selected metrics, dates, read access and saved destination. Missing output is not a measured zero.

Health Connect's normal history window includes up to 30 days before read permission was first granted to Health.md, plus later data; broader access is conditional. That permission limit is separate from how much history Oura shared. See [Android's history documentation](https://developer.android.com/health-and-fitness/health-connect/read-data#read-older-data). A wider export range cannot recreate records never shared.

For sleep crossing midnight, compare the same timezone and journal date using the [sleep-date examples](/docs/sleep-date-attribution/#sleep-date-examples). Apple Health and Health Connect have different source and aggregation semantics; use the relevant guide rather than combining their files as interchangeable rows.

## Keep account services and file destinations distinct

Oura's app, account download and integrations have their own data handling rules. The separate local Health.md folder workflow requires no Health.md account and creates no Health.md server copy by default. Synced folders and apps you open files in have their own storage policies.

The optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. It has no public signup, no automatic device sync and is not generally available. This folder workflow does not upload to the pilot. See the [privacy policy's retention boundaries](/privacy-policy.html#retention).
