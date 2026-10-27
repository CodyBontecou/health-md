---
title: "Apple Health XML export: open export.xml and choose CSV"
description: "Open an Apple Health export ZIP, find export.xml, and understand XML-to-CSV conversion. Compare preserving an existing archive with making a fresh selected export."
lead: "Already have an Apple Health archive? Keep the original, open a copy, and choose whether you need its source records or a fresh export of selected dates and metrics."
date: "2026-10-27"
updated: "2026-10-27"
category: "Export guide"
related:
  - apple-health-to-excel
  - export-health-data-without-the-cloud
  - health-md-vs-health-auto-export
draft: false
verified: "2026-10-27"
verified_by: "Codex (agent)"
verified_method: traced
tags:
  - apple-health
  - xml
  - csv
  - export
---

**Apple Health's built-in export produces XML, not a ready-made spreadsheet.** If you already have `export.zip`, keep the original archive and work from a copy. If you only need selected dates and metrics in CSV, you can instead create a fresh export from the iPhone.

**Health.md does not import or convert Apple's XML archive.** It reads the Apple Health data you authorize on your device and writes selected CSV, JSON, Markdown, or Obsidian files. The archive workflow below is separate.

<a class="button" href="/docs/reference/generated/core/summary-day.csv">Try a fictional CSV sample</a>

This sample is Health.md output, not a conversion of your XML. It contains fictional values and can help you check a spreadsheet import before using personal records.

## 1. Create or locate the Apple Health archive

On iPhone, open **Health → Summary**, tap your picture or initials, then choose **Export All Health Data**. When the share sheet appears, choose where to save or send the export. Apple's [Health sharing guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) documents this XML export.

This built-in action is for the archive. It does not offer the metric and date selection used in Health.md's export picker. If you want that workflow instead, go to [export Apple Health to CSV](/apple-health-to-csv/).

## 2. Open the ZIP and find export.xml

The [applehealth2csv project's documentation](https://github.com/muquit/applehealth2csv) describes the native `export.zip` archive and its `export.xml` file. Keep any other extracted files with the archive rather than assuming the XML is the only useful output.

- **On iPhone:** find the ZIP in Files and tap it to uncompress it. Open the resulting folder and look for `export.xml`. See [Apple's ZIP instructions](https://support.apple.com/102532).
- **On Mac:** double-click the ZIP in Finder, then inspect the extracted folder. See [Apple's Mac unzip guide](https://support.apple.com/guide/mac-help/zip-and-unzip-files-and-folders-on-mac-mchlp2528/mac).
- **On Windows:** right-click the ZIP, choose **Extract All**, and follow the prompts. See [Microsoft's extraction instructions](https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/zip-and-unzip-files).

Uncompressing a file does not convert its data. A text editor can inspect XML, but opening the file is different from producing usable spreadsheet rows. For a large archive, use a tool designed to process that size rather than pasting the whole file into a browser tab or chat.

## 3. Understand what an XML record means

XML stores named fields and can contain nested information. A record's type, unit, source, and start and end times matter when turning it into a table. The converter's [documented record output](https://github.com/muquit/applehealth2csv#how-to-use) illustrates those fields.

For example, an interval with **25 steps**, unit **count**, from **09:00 to 09:05** describes one fictional interval. It is not automatically a daily step total. Preserve the unit and time offset, and decide how records should be grouped before calculating a daily or weekly summary.

Do not combine overlapping sources or repeated exports as if every row were an additional independent measurement. A converted table's row count alone does not establish complete coverage or the same totals shown in the Health app.

## 4. Convert an existing archive, or make a fresh CSV

<div class="article-table-scroll" role="region" aria-label="Choose an XML archive or selected CSV workflow" tabindex="0">

| Your starting point | Next step | What to check |
|---|---|---|
| You need records from an existing archive | Use a converter that explicitly supports Apple Health XML | Supported record types, preserved fields, units, timestamps, and any errors |
| You want selected current Apple Health data in a spreadsheet | Export selected metrics and dates with Health.md | One known day, selected detail, destination, and actual saved file |
| You need readable daily notes | Export Markdown or Obsidian output with Health.md | Note filename, properties, date attribution, and write behavior |

</div>

One separate command-line option is [applehealth2csv](https://github.com/muquit/applehealth2csv). Its documentation describes local conversion from `export.zip` or `export.xml` to CSV or JSON and shows separate metric files. Follow that project's installation and usage instructions. We checked its documentation on October 27, 2026; we have not executed the converter or verified its compatibility with every current Apple record type.

For a fresh Health.md export, authorize the metrics you need, select **CSV**, choose one completed day and a destination, then preview and export. Health.md writes daily CSV files. Use the [CSV import walkthrough](/apple-health-to-csv/) for Excel, Sheets, or Numbers, or the [Obsidian walkthrough](/blog/export-apple-health-data-to-obsidian/) for notes.

The free CSV sample above has Health.md's own row contract. A third-party converter can produce different columns and files; do not apply Health.md column formulas to it without checking the headers.

## 5. Verify the output before expanding the range

1. Choose one metric and one date you can check in Apple Health.
2. Confirm whether the output contains individual readings, intervals, or daily aggregates. Keep different representations separate.
3. Check the unit, date, time offset, missing values, and source fields retained by the tool. Missing output is not a measured zero.
4. Inspect conversion warnings and unsupported types. Keep the original archive even after a small result looks correct.
5. Only then combine dates or build charts. Keep an untouched copy of the converted output so you can revisit the transformation.

If a fresh device export is empty or a file was not saved, use the [missing-data troubleshooting checklist](/docs/troubleshooting/). It distinguishes source access, date selection, detail level, and destination failures.

## Common questions

### Can I rename export.xml to CSV?

No. Renaming changes the filename, not the XML structure. Use a compatible parser or converter for an existing archive, or create a fresh CSV export from the device.

### Can Health.md open an old export.zip?

No. Health.md's selected-data workflow reads authorized Apple Health data on the iPhone. It does not turn an old archive into new files. Use an archive-compatible tool if those historical files are your only source.

### Is Apple's XML archive the same as Health.md Lossless Health Records?

No. Lossless Health Records is Health.md's separate, Apple-only representation of selected public source records, with its own capture status and versioned contract. It is not Apple's XML archive or a copy of Apple's private database. See the [canonical record reference](/docs/reference/canonical-healthkit-records/).

### Do I need to upload the archive?

A local converter can process it on your computer. An online service may handle the file differently; check whether it uploads or retains data before choosing it. This Health.md page has no file upload or XML processing tool.

If selected device exports fit your goal, [try Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969). It includes five export actions followed by a lifetime unlock; see [purchase details](/docs/paywall/). For Android data, use the separate [Health Connect export guide](/health-connect-export/).
