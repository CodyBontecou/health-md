---
title: "Export Clue data: native JSON or shared Apple Health files"
description: "Download Clue's password-protected JSON archive, or export period records already shared to Apple Health as daily files. Check history and flow-label limits."
lead: "Keep Clue's own download for tracked history and app settings. Use daily files only for records that actually reached Apple Health."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - apple-health-xml-export
  - export-apple-health-data-to-obsidian
  - export-health-data-without-the-cloud
draft: false
tags:
  - clue
  - apple-health
  - json
  - export
---

**Clue provides its own tracked-data download. You do not need Health.md to get it.** Choose that file for the history and settings Clue supplies, especially records that have never reached Apple Health.

Health.md offers a separate iPhone workflow: daily Markdown, CSV or JSON from selected, authorized Apple Health records. It does not sign in to Clue, import its ZIP or JSON, or recreate its predictions.

## Download your tracked data directly from Clue

Clue's [native download instructions](https://support.helloclue.com/hc/en-us/articles/17320910724125-How-do-I-get-a-copy-of-my-Clue-data), checked **October 30, 2026**, use **More (=) → Settings → Download my data → Request data**.

Keep the unique password displayed in the app, then open the link emailed to your Clue account address. Clue documents a **72-hour link expiry** and a password-protected ZIP containing JSON with tracked data and app settings. Save the original archive and inspect the extracted files.

This native JSON and Health.md's daily JSON have different structures. Inspect actual fields before processing either, and do not assume that another app can restore every part of the download.

## Check Clue's outgoing Apple Health scope

Clue's [sharing instructions](https://support.helloclue.com/hc/en-us/articles/20199556038813-Can-I-export-my-data-from-Clue-to-Apple-Health-or-Apple-Health-to-Clue) describe **More → Settings → Apple Health → Go to Settings**, then **Health → Data Access & Devices → Clue** on the Apple side to authorize sharing.

The outgoing scope described is period timing and flow. **Clue's “heavy” and “super heavy” both become “heavy” in Apple Health.** The shared label cannot preserve that original distinction.

The guide describes transferring period points tracked after permission is granted, rather than automatically copying earlier history. Keep the native download for original history; do not delete and re-enter old records just to test this workflow. Inspect a known day's actual Apple Health records and source before relying on the shared route.

This page follows **Clue to Apple Health**. Clue's older FAQ and its [October 26 release notes](https://support.helloclue.com/hc/en-us/articles/18141097264413-What-s-new-in-the-Clue-app) differ on reverse importing: the release notes describe importing periods into Clue. Do not treat the older reverse-import limitation as current proof of unavailability. Importing into Clue is separate from exporting daily files here.

Wearable records arriving in Clue do not establish that symptoms, notes, predictions or those same wearable records are written back to Apple Health. This guide does not establish Clue-to-Health Connect export on Android.

## Save one verified day with Health.md

Continue only if Apple Health contains what you need. [Get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969) and use [your first iPhone export](/docs/iphone-first-export/):

1. Grant Health.md separate read access. Clue's write permission does not authorize another app to read.
2. Select the relevant reproductive-health metric, one completed day and a writable folder.
3. Preview, save and open the result. Start with the guide's Markdown workflow; add CSV or JSON after the destination works.
4. Compare the day and label with the actual Apple Health record before increasing the range.

Health.md's Apple **Menstrual Flow** daily summary selects the most recent matching flow record starting within that day. It is a categorical label, not a numeric score or every change logged in Clue. The native archive remains a separate representation.

Longer ranges create separate daily files. Other apps can also contribute Apple Health records, so the result is not automatically Clue-only. Missing output is unavailable data, not zero or proof of a particular flow state.

## Preserve labels when processing files

Use a CSV-aware importer and select the intended Category and Metric before processing Value. Flow labels are text; do not convert them to numbers. Keep daily summaries separate from underlying individual records, and check overlapping dates, repeated exports and multiple sources before combining files.

The [fictional Apple CSV](/docs/reference/generated/core/summary-day.csv) and [fictional Apple JSON](/docs/reference/generated/core/summary-day.json) show Health.md's general format. They are not Clue downloads or evidence that Clue supplies every sample field. Use the [format guide](/docs/format/) for output contracts.

## Choose storage for the extracted files

The native archive's password protection does not automatically protect every extracted file or copy. Check the destination and its access settings before sharing.

Core Health.md folder exports require no Health.md account and create no Health.md server copy by default. Synced folders and downstream services have separate storage rules. The optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it; it has no public signup or automatic device sync and is not generally available. This folder workflow does not upload to that pilot.

Read the [local destination guide](/blog/export-health-data-without-the-cloud/) and [retention policy](/privacy-policy.html#retention). Retain Clue's native download when you need its original history and settings; a daily Apple Health export is not a full account backup.
