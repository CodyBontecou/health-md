---
title: "How to export Zepp and Amazfit data (GPX, archive, Apple Health)"
description: "Zepp has no single Export button. Get one workout as GPX, request your full Zepp data, or send Zepp data to Apple Health and export daily files."
lead: "Pick the route for your task: one workout as GPX, your full account data, or daily files from Apple Health on iPhone."
date: "2026-10-30"
updated: "2026-11-25"
verified: "2026-11-25"
verified_by: "Claude (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - export-strava-data
  - export-apple-health-workouts
  - export-huawei-health-data
draft: false
tags:
  - zepp
  - amazfit
  - apple-health
  - gpx
  - csv
---

**Zepp has no single Export button for everything. Pick the route that matches what you need:** one workout as a GPX file, all the data Zepp holds about you, or daily health files on your iPhone through Apple Health. Zepp does not document a per-activity GPX, TCX or FIT export in the app for every watch, so check your watch's support page.

| Task | Route | What you get | Source |
| --- | --- | --- | --- |
| One workout as GPX | Older watches (Amazfit Stratos 3, Pace): export on the watch, copy over USB. Other watches: connect Strava or Relive in Zepp, then download from Strava | A GPX file for that activity | [Amazfit support](https://support.amazfit.com/it/amazfit_stratos_3/docs/CQCWdRLxEoJhw8x9UcLcsMESnsq), [Amazfit GTS 2 mini support](https://support.amazfit.com/en/amazfit_gts_2_mini/docs/N6cUdJxDRo6rbfxiLs1cJDBrnRd) |
| Full account data | Zepp's personal-data export (Exercising user rights) | A download from Zepp; format and timing are not documented | [Zepp privacy support](https://www.zepp.com/privacy-support) |
| Daily files on iPhone | Share Zepp to Apple Health, verify, then export with Health.md | Markdown, CSV or JSON per day | [Amazfit support](https://support.amazfit.com/en/amazfit_gts_2_mini/docs/N6cUdJxDRo6rbfxiLs1cJDBrnRd), [Apple iPhone User Guide](https://support.apple.com/guide/iphone/welcome/ios) |

Health.md reads authorized Apple Health records and saves them to a folder. It does not sign in to Zepp, import Zepp's archive or recover records Zepp has not shared. Nothing below documents a Zepp importer or full-history backfill.

## Export one workout as a GPX file

**Older watches (Amazfit Stratos 3, Pace).** Amazfit's [Stratos 3 support document](https://support.amazfit.com/it/amazfit_stratos_3/docs/CQCWdRLxEoJhw8x9UcLcsMESnsq) describes exporting an activity record from the watch as a GPX file. In short: open the activity record on the watch, swipe left, tap **Export**, connect the watch to a computer over USB and find the file in the GPX folder. That page is written for those older models (the Pace has its own FAQ entry, [FAQ 658](https://support.amazfit.com/en/faq/658); see also [FAQ 992](https://support.amazfit.com/en/faq/992)). Do not assume your watch has the same menu.

**Other watches.** Amazfit's [GTS 2 mini support page](https://support.amazfit.com/en/amazfit_gts_2_mini/docs/N6cUdJxDRo6rbfxiLs1cJDBrnRd) documents connecting Strava and Relive under **Profile → Add accounts** in the Zepp app. Once activities have synced to Strava, download the original or GPX from strava.com using the [Strava export guide](/blog/export-strava-data/). Only activities that reached Strava can be downloaded there, and a GPX needs recorded GPS points.

Renaming a daily summary or CSV to `.gpx`, `.fit` or `.tcx` does not make it an activity file.

## Request your full Zepp or Zepp Life data

Zepp's [privacy-support page](https://www.zepp.com/privacy-support) provides an **Export data** option. In the **Zepp** app, it points to **Profile → Setting → Exercising user rights**. In **Zepp Life**, the route is **Profile → Setting → Account and Security**. Check which app you use before following a path; labels can vary by version or region.

Zepp does not document the archive's format, contents or how long it takes. Keep the original download and inspect it before planning any conversion. This guide does not supply a parser for it.

Zepp's [September 2026 announcement](https://zepp.com/blog/your-data-your-storage-your-choice) describes cloud-sync controls in version 10.8.5 and places expanded export and restoration in future phases. Changing where new data is stored is not a historical export or restore, and announced future features may not be in your installed app.

## Send Zepp data to Apple Health

Amazfit's [Zepp sharing instructions](https://support.amazfit.com/en/amazfit_gts_2_mini/docs/N6cUdJxDRo6rbfxiLs1cJDBrnRd) cover Apple Health sharing for one device; other watches may differ.

1. Sync your watch with the Zepp app and enable the Apple Health connection where your watch offers it.
2. On the iPhone, open Apple Health, tap your profile picture, then **Apps → Zepp**, and turn on the categories you want. See the Health section of the [Apple iPhone User Guide](https://support.apple.com/guide/iphone/welcome/ios).
3. Open a known day in Apple Health and confirm Zepp records are there.
4. Compare dates and detail before choosing an export range.

Check the data you need, not just that the switch is on. A visible workout does not prove its route or continuous heart-rate stream was shared. Sleep entries do not carry proprietary scores such as PAI or a sleep score. Enabling sharing does not backfill your complete Zepp history.

If you use a Zepp Life scale, check that weight reached Apple Health, then see the [Apple Health weight export guide](/blog/export-apple-health-weight-data/).

## Make a daily file with Health.md

Once the records are present, [get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969) and follow [your first iPhone export](/docs/iphone-first-export/):

1. Grant Health.md separate read access to the relevant Apple Health categories.
2. Choose a writable Files folder, one completed day and the metrics you checked.
3. Preview the output, export and open the saved file.
4. Compare dates, units and values against Apple Health before widening the range or adding formats.

Markdown is the first-export default. Add CSV for tables or JSON for structured processing using the [format guide](/docs/format/). Multiple days create separate daily files. Apple Health may hold records from other apps, so a daily total is not automatically Zepp-only. Missing data is unavailable, not zero.

For session details, see the [workout guide](/blog/export-apple-health-workouts/); for sleep, the [sleep guide](/blog/export-apple-health-sleep-data/). The wider [Apple Health export guide](/apple-health-export/) covers other sources.

## Android and Health Connect

This guide establishes the iPhone workflow. It does not establish current Zepp-to-Health Connect setup steps, outgoing categories or historical coverage. Older Google Fit instructions and a generic integration logo are insufficient to determine those details.

If you already have relevant records in Health Connect, use the [Health Connect export guide](/health-connect-export/) for that separate workflow. Verify the actual source records first; a Google Fit connection alone does not prove that they reached Health Connect.

## Troubleshooting

- **Missing from Apple Health:** check Zepp sync, outgoing categories and write permissions. Health.md cannot export an unshared record.
- **Present in Apple Health but absent from the saved file:** check Health.md read permissions, metric selection, date range and destination.
- **Different totals or repeated records:** check multiple data sources, overlapping dates and re-exports before combining files.
- **Missing proprietary scores or full history:** retain Zepp's original download and inspect its contents. Shared records do not reconstruct Zepp's calculations.

## Where files go

Core folder exports require no Health.md account and create no Health.md server copy by default. A synced destination and any downstream service have their own storage rules. Inspect files for detailed times, identifiers or locations before sharing them.

The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it; it has no public signup or automatic device sync and is not generally available. This folder workflow does not upload to that pilot. The folder workflow writes files to a folder you choose; see the [local destination guide](/blog/export-health-data-without-the-cloud/) and the [retention policy](/privacy-policy.html#retention) for storage and backup choices.
