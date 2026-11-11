---
title: "Export Zepp and Amazfit data: downloads or Apple Health files"
description: "Find Zepp's personal-data export, or save records already shared to Apple Health as daily CSV, JSON or notes. Check sharing, history and archive limits first."
lead: "Start with Zepp's own download for account data. On iPhone, verify what reached Apple Health before making daily files with Health.md."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - export-huawei-health-data
  - export-apple-health-workouts
  - export-health-data-without-the-cloud
draft: false
tags:
  - zepp
  - amazfit
  - apple-health
  - csv
---

To export Zepp or Amazfit data, choose between **Zepp's own personal-data download** and **daily files from records already shared to Apple Health**. You do not need Health.md for Zepp's download.

Health.md reads authorized Apple Health records and saves selected data to a folder as Markdown, CSV or JSON. It does not sign in to Zepp, import its archive or recover records that Zepp has not shared.

## Choose the route for your task

| Your task | Start with |
| --- | --- |
| Request personal data held by Zepp | Zepp's privacy-support export |
| Keep an activity file for another training service | Your device's supported native activity export; check its available fields and formats |
| Put shared iPhone health records beside daily notes or other health data | Verify Apple Health records, then make a small Health.md export |

An account download, an activity file and a daily summary serve different purposes. A file from one route is not proof that another contains the same history, sensor samples or calculated scores.

## Request Zepp's personal-data export

Zepp's [privacy-support page](https://www.zepp.com/privacy-support), checked **October 30, 2026**, provides an **Export data** option. It also documents **Profile → Setting → Exercising user rights** in the Zepp app. Follow the current prompts for your account and keep the original download.

That page distinguishes **Zepp** from **Zepp Life**, which has a separate **Profile → Setting → Account and Security** route. Check which app you use before following a menu path. Labels can vary by version or region.

Inspect the resulting archive before planning a conversion. The support page does not specify a universal CSV schema or guarantee that every value visible in the app is included. This guide does not supply a parser for that archive.

Zepp's [September 2026 announcement](https://zepp.com/blog/your-data-your-storage-your-choice) describes cloud-sync controls in version 10.8.5 and places expanded export and restoration in future phases. Changing where new data is stored is a separate operation from downloading or restoring historical data. Do not assume announced future capabilities are available in your installed app.

## Verify Amazfit records in Apple Health

Amazfit's [Zepp sharing instructions](https://support.amazfit.com/en/amazfit_gts_2_mini/docs/N6cUdJxDRo6rbfxiLs1cJDBrnRd) document Apple Health sharing and adding Zepp as a data source. Those instructions belong to a specific device support page; they do not establish an identical field list or menu for every Amazfit device.

1. Sync your watch with the Zepp app and enable its Apple Health connection where available.
2. In Apple Health, review Zepp's permission to write the categories you want.
3. Open a known day's relevant records and check that Zepp actually contributed data.
4. Compare dates and available detail before choosing an export range.

Check the representation you need, not just whether a connection switch is on. A visible workout does not establish that its route or continuous heart-rate stream was shared. A sleep entry does not establish that a proprietary sleep or recovery score is present. Do not assume enabling sharing backfills your complete Zepp history.

### What about Android and Health Connect?

This guide establishes the iPhone workflow. It does not establish current Zepp-to-Health Connect setup steps, outgoing categories or historical coverage. Older Google Fit instructions and a generic integration logo are insufficient to determine those details.

If you already have relevant records in Health Connect, use the [Health Connect export guide](/health-connect-export/) for that separate workflow. Verify the actual source records first; a Google Fit connection alone does not prove that they reached Health Connect.

## Make one daily file after checking the source

Once the records you need are present, [get Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969) and follow [your first iPhone export](/docs/iphone-first-export/):

1. Grant Health.md separate read access to the relevant Apple Health categories.
2. Choose a writable Files folder, one completed day and the metrics you checked.
3. Preview the output, export and open the saved file.
4. Compare dates, units and values against Apple Health before widening the range or adding formats.

Markdown is the first-export default. Add CSV for tables or JSON for structured processing using the [format guide](/docs/format/). Multiple days create separate daily files. Apple Health may contain contributions from other apps, so a daily total is not automatically a Zepp-only total.

The [fictional daily CSV](/docs/reference/generated/core/summary-day.csv) illustrates Health.md output, not a Zepp archive or proof that Amazfit shares every sample field. Filter the intended Category, Metric and Unit before treating Value as numeric; it also contains text and metadata. Missing data is unavailable, not zero.

For session details and date assignment, use the [workout guide](/blog/export-apple-health-workouts/). For sleep and journal dates, use the [sleep guide](/blog/export-apple-health-sleep-data/). Daily summaries do not become GPX, FIT or TCX activity files by changing the extension.

## Resolve a missing record at the right step

- **Missing from Apple Health:** check Zepp sync, outgoing categories and write permissions. Health.md cannot export an unshared record.
- **Present in Apple Health but absent from the saved file:** check Health.md read permissions, metric selection, date range and destination.
- **Different totals or repeated records:** check multiple data sources, overlapping dates and re-exports before combining files.
- **Missing proprietary scores or full history:** retain Zepp's original download and inspect its contents. Shared records do not reconstruct Zepp's calculations.

## Keep track of where files go

Core folder exports require no Health.md account and create no Health.md server copy by default. A synced destination and any downstream service have their own storage rules. Inspect files for detailed times, identifiers or locations before sharing them.

The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it; it has no public signup or automatic device sync and is not generally available. This folder workflow does not upload to that pilot. See the [retention policy](/privacy-policy.html#retention) and [local destination guide](/blog/export-health-data-without-the-cloud/) for storage and backup choices.
