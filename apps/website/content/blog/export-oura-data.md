---
title: "Export Oura data: account download or daily CSV files"
description: "Oura doesn't name its export's file format. Request the download, or get daily CSV, JSON or Markdown files from Oura records in Apple Health or Health Connect."
lead: "Oura's own download preserves account data. Health.md offers a separate route for selected records already shared to Apple Health or Health Connect on your phone."
date: "2026-10-30"
updated: "2026-11-19"
verified: "2026-11-19"
verified_by: "Claude (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-clue-data
  - export-health-connect-to-obsidian
  - export-whoop-data
draft: false
tags:
  - oura
  - apple-health
  - health-connect
  - csv
---

**What format is the Oura export?** Oura's help page does not name the file format of the Membership Hub download, so open it and check the file extensions before you import anything. What Oura does document: you request the download in Membership Hub, it can take up to 10 days, and Oura emails you when it is ready. Durations are given in total seconds, and field meanings follow its API V2 documentation. The download works with or without an active membership. If you need spreadsheet rows, Health.md can write one CSV, JSON or Markdown file per day from the Oura records your phone's health store already holds.

That is how Oura's [Export & Share Your Oura Data](https://support.ouraring.com/hc/en-us/articles/360025441594-Export-Share-Your-Oura-Data) page reads as of November 19, 2026. **You do not need Health.md for Oura's own download or reports.**

## Choose the output before choosing an app

| Output | Format | What's in it | Who makes it |
| --- | --- | --- | --- |
| Membership Hub account download | Not named by Oura; check the file extensions | Your Oura account data; durations in seconds, fields per API V2 | Oura |
| Shareable Report | Printable PDF summary | Sleep, Cycle Insights or Menopause Insights; fixed timeframe and data types | Oura app |
| Health.md daily files | CSV, JSON or Markdown, one file per day | Only the records shared to Apple Health or Health Connect that you select | Health.md, on your phone |
| Oura API V2 | JSON responses | Oura data models such as daily sleep, readiness and activity; needs an OAuth application | Developers' own code |

Health.md reads authorized records from Apple Health on iPhone or Health Connect on Android. It does not import Oura's downloaded archive or connect this workflow directly to your Oura account. A shared-store export is not a backup of everything in Oura, and it does not include Oura's Readiness or Sleep Scores.

## Request the account download from Oura

These steps follow Oura's [export instructions](https://support.ouraring.com/hc/en-us/articles/360025441594-Export-Share-Your-Oura-Data):

1. Log in to the [Membership Hub](https://membership.ouraring.com/) with your Oura account.
2. Select **Export data**.
3. Select **Request your data**.
4. Wait for Oura's email. Preparation can take up to 10 days.
5. Return to the Membership Hub and download the export.

The account download is available without active membership. Health.md does not convert these files.

### Before you import it

- Check the file extensions and open one file in a text editor before choosing a spreadsheet import setting.
- Check the units. Oura gives durations in total seconds, not hours and minutes; divide by 3600 for hours.
- Keep the original download untouched and work on a copy.
- Look up field meanings in the [Oura API V2 documentation](https://cloud.ouraring.com/v2/docs), which Oura's help page names as the description of its data models.

## Use a Shareable Report for a printable summary

In the Oura app, open the menu in the upper-left corner, select **Reports**, then **Shareable Reports**. Oura lists Shareable Reports for Gen2, or Gen3 and later with active membership. The Sleep report covers Gen2 and active members; Cycle Insights and Menopause Insights are for active members on Gen3 or later. You cannot change the timeframe or the type of data included. The result is a PDF summary you can print or share, not rows for a spreadsheet.

## Check sharing eligibility and coverage

Oura lists both its [Apple Health integration](https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration) and [Android Health Connect integration](https://support.ouraring.com/hc/en-us/articles/10786105824531-Health-Connect-by-Android-Integration) for **Gen2**, or **Gen3 and later with an active membership**. The account download's membership rule does not make every integration available without membership.

The shared types differ by platform. As of November 19, 2026, Oura's Apple Health page lists active energy, heart rate, height, mindful minutes, respiratory rate, sleep, steps, weight, workouts and workout routes as written to Apple Health. Its Health Connect page lists active calories burned, distance, exercise, steps, height, weight, sleep, heart rate and heart rate variability. Heart rate variability is on the Health Connect list but not the Apple Health list. Check the current list for your phone and inspect an actual record. Do not infer that a type Oura reads from another app is also a type it writes out.

Oura's Readiness Score and Sleep Score are not listed as outgoing types on those integration pages. Do not expect them to appear just because sleep or heart-rate records were shared. Sharing selected records does not reproduce Oura's scores or algorithms.

### On iPhone

In Oura, open the menu, then **Settings → Data sharing → Apple Health**, and turn on **Connect to Health**. Review which categories Oura may write in Apple Health's app permissions. Health.md needs its own read authorization; granting Oura access does not grant Health.md access.

Pick a completed day, then inspect the relevant records and their source in Apple Health. Other apps and devices can contribute to the same metric. A daily Health.md total should not be described as Oura-only or expected to equal Oura's dashboard automatically.

### On Android

In Oura, open the menu, then **Settings → Data Sharing → Health Connect**, and use the toggles to choose the relevant sharing categories. Check that Oura may write the desired types and that an actual record for your chosen day exists in Health Connect. Health.md needs separate read access to those types.

Oura's current instructions say its Google Fit integration is no longer available. Follow the Health Connect route rather than an old Google Fit tutorial. The [Fitbit export guide](/blog/export-fitbit-data/) covers the same shift for Fitbit tools that used the retired Fitbit Web API. The shared store can contain records from multiple apps; this workflow does not promise an Oura-only source filter.

## Export a small selection with Health.md

This is the route that gives you a known format: one file per day in CSV, JSON or Markdown, built from records Oura has shared to your phone. Only continue once you have confirmed the records are available on your phone. Choose the download for that phone:

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

For sleep crossing midnight, compare the same timezone and journal date using the [sleep-date examples](/docs/sleep-date-attribution/#sleep-date-examples). The [Apple Health sleep export guide](/blog/export-apple-health-sleep-data/) covers choosing sleep metrics on iPhone. Apple Health and Health Connect have different source and aggregation semantics; use the relevant guide rather than combining their files as interchangeable rows.

## Keep account services and file destinations distinct

Oura's app, account download and integrations have their own data handling rules. The separate local Health.md folder workflow requires no Health.md account and creates no Health.md server copy by default. Synced folders and apps you open files in have their own storage policies.

The optional single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it. It has no public signup, no automatic device sync and is not generally available. This folder workflow does not upload to the pilot. See the [privacy policy's retention boundaries](/privacy-policy.html#retention).

## Common questions

### What file format does Oura export your data in?

Oura's help page does not specify the file format of the Membership Hub download, so check the file extensions after you download it. Oura does document that durations are in total seconds and that field meanings follow its API V2 data models. If you need a format you choose, Health.md writes daily CSV, JSON or Markdown files from Oura records shared to Apple Health or Health Connect.

### Can I export my Oura data without an active membership?

Yes. Oura says the Membership Hub download is available with or without active membership. It can take up to 10 days, and Oura emails you when it is ready. The Apple Health and Health Connect integrations are different: Oura lists them for Gen2, or Gen3 and later with active membership.

### Can I get Oura data into Excel or Google Sheets?

Yes, as daily CSV rows from the Oura records shared to Apple Health or Health Connect, exported with Health.md. Then follow the [Google Sheets guide](/blog/apple-health-to-google-sheets/) or the [Excel guide](/blog/apple-health-to-excel/). For Oura's own download, check its file extensions first and convert durations from seconds.

### Does Oura send Readiness or Sleep Scores to Apple Health?

No. Oura's Apple Health and Health Connect pages do not list Readiness Score or Sleep Score as shared types. Sleep records are shared, but the scores stay in Oura.
