---
title: "Apple Health to Notion: a manual CSV import workflow"
description: "Bring selected Apple Health daily totals into Notion with a small CSV. Practice with fictional steps, preserve dates and units, and avoid duplicate imports."
lead: "Keep your original health files, prepare a small steps table, and import a deliberate snapshot into Notion."
date: "2026-11-01"
updated: "2026-11-01"
verified: "2026-11-01"
verified_by: "Codex (agent)"
verified_method: traced
platform: apple
category: "Workflow guide"
related:
  - apple-health-to-excel
  - apple-health-to-google-sheets
  - export-health-data-without-the-cloud
draft: false
tags:
  - apple-health
  - notion
  - csv
---

**Use a manual CSV import when you want selected Apple Health totals alongside your Notion notes.** This is a file workflow, not a live connection: exporting another day on your phone does not update a Notion database.

If you only need an archive, Apple's [built-in export](https://support.apple.com/en-euro/guide/iphone/iph5ede58c3d/ios) is the starting point: open Health, tap your profile and choose **Export All Health Data**. Apple supplies XML. Keep that archive if you need it; this guide does not import XML into Notion or convert an existing Apple archive.

## Practice before exporting your own records

[Download the fictional Notion steps example](/assets/downloads/notion-steps-example.csv). It contains **one illustrative row**, derived from the site's [synthetic iPhone Summary fixture](/docs/reference/generated/core/summary-day.csv): **March 15, 2026, 12,500 steps**. No account or Health.md installation is needed to inspect it.

The example is a deliberately prepared table, not Health.md's original CSV schema. Its columns are:

| Column | Purpose |
| --- | --- |
| Name | A readable row label, such as `2026-03-15 steps` |
| ExportDate | The original day label, kept as text |
| Steps | The selected numeric daily total |
| Unit | `count`, retained to distinguish the measurement |
| SourceFile | A provenance label for the input file |

Start in a disposable database with this fictional file. Do not mix the example with personal exports. Expect one row and 12,500 steps on the first import. Importing it again adds a duplicate row: two copies still describe one source day, not 25,000 steps.

## Export one completed day on iPhone

For a repeatable daily-file workflow, Health.md reads authorized Apple Health categories and writes to a folder you select.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

Follow the [first iPhone export guide](/docs/iphone-first-export/). Start with one completed day and a writable Files folder. After the initial Markdown export works, choose CSV and Summary, select Steps, and preview the output. Use `YYYY-MM-DD` for the export date format in this exercise.

A longer range creates daily files. The iPhone CSV header is `Date,Category,Metric,Value,Unit,Timestamp`; metadata and status strings share the Value column with measurements. Some summary rows omit the final Timestamp field. Keep the originals before preparing a smaller table.

For this steps recipe, retain only rows whose **Category is Activity**, **Metric is Steps** and **Unit is count**. Copy Date into ExportDate and Value into Steps. Add a descriptive Name and the original filename as SourceFile. Use a proper spreadsheet CSV import rather than splitting text at every comma; other exported fields can contain quoted commas or newlines.

Save the prepared five-column table as a **new UTF-8 CSV file** for the Notion import. Keep the original daily exports untouched.

The [Excel walkthrough](/blog/apple-health-to-excel/) explains inspecting and filtering daily files. The existing [browser CSV combiner](/apple-health-to-csv/#combine-csv-files) can append daily files before that filtering, locally in your browser. It preserves duplicate rows; it does not decide which re-export is authoritative.

## Import a snapshot into Notion

**Importing a CSV uploads its contents to Notion.** Use the fictional file first; review storage and sharing controls before substituting personal records.

Notion's [current import instructions](https://www.notion.com/help/import-data-into-notion), checked **November 1, 2026**, describe desktop/web CSV import:

1. Open **Settings → Import → CSV** and select the fictional file first.
2. Create a new database and map its columns. Use Name as the title, Steps as a number, and ExportDate, Unit and SourceFile as text.
3. Check the imported day label and value against the file before importing personal rows.

Notion creates database rows from CSV and lets you map properties. Its **Merge with CSV** option adds rows; it does not update matching records. Imports are not currently offered on mobile. Notion documents limits of **5 MB per file on Free** and **50 MB on paid plans**; keep the first test small.

This recipe intentionally preserves the date as text, avoiding an assumed date-parser or timezone conversion. If you later create a Notion Date property for calendar views, check the actual day before relying on it. No Notion interface or authenticated import was exercised for this guide.

## Add new days without double-counting

Maintain a small import log outside the database: filename, covered dates and when you imported it. Before each upload, compare the incoming days with that log. A repeated day or a corrected export needs a deliberate replacement decision, not another blind append.

For your own steps table, keep one chosen Summary row per intended day. Do not add Detailed Time-Series samples, weekly/monthly rollups or other units to those daily totals. A missing steps row means unavailable data for this workflow, not a measured zero. If you cannot establish which version to keep, stop and compare the source exports before calculating totals.

## Choose whether Notion is the right destination

Core folder export creates no Health.md health-data server copy by default. **Importing a CSV uploads its contents to Notion.** Review the destination's storage and sharing controls before using personal records; the CSV may reveal more than the metric you intended to share. Export only what you need, and keep originals private.

If you want files that remain in a local notes folder, use the [Obsidian export workflow](/blog/export-apple-health-data-to-obsidian/) instead. If you need automatic Notion synchronization, this manual recipe does not provide it. Choose an integration only after checking its actual data access, update behavior and privacy terms.
