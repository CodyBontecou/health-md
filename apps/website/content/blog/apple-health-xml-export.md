---
title: "Apple Health XML export: open export.zip and convert to CSV"
description: "Open export.zip and convert export.xml to CSV: unzip it, check a converter before uploading, or make a fresh selected export instead."
lead: "Holding Apple's export.zip? Unzip a copy, find export.xml, convert it with a parser, or skip the XML with a fresh export of selected dates and metrics."
date: "2026-10-27"
updated: "2026-11-28"
category: "Export guide"
related:
  - apple-health-export-xml-workout-distance
  - export-health-data-without-the-cloud
  - health-md-vs-health-auto-export
draft: false
verified: "2026-11-28"
verified_by: "Claude (agent)"
verified_method: traced
tags:
  - apple-health
  - xml
  - csv
  - export
---

**Apple Health's built-in export produces XML in a ZIP, not a ready-made spreadsheet.** Keep the original `export.zip` and work from a copy.

- **Open it:** unzip the copy with Files, Finder or Windows Extract All, then find `export.xml` (step 2).
- **View it:** a text editor can show the XML, but that is not the same as getting rows (see "View it without converting").
- **Convert it:** you can't rename `export.xml` to `.csv`. Use a parser or converter, and prefer one that runs on your computer, because an online one may upload the whole archive (step 4).
- **Only need some metrics or days?** A fresh CSV, JSON, Markdown or Obsidian export from the iPhone avoids the XML entirely.

**Have an archive → steps 2–4. Want selected days as CSV → make a fresh export.** Health.md does not import or convert Apple's XML archive: it reads the Apple Health data you authorize on your device and writes selected files.

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

Uncompressing a file does not convert its data.

## Looking for one metric?

**Workout distance?** Start with [how to find workout distance in export.xml](/blog/apple-health-export-xml-workout-distance/). For other metrics, each guide below covers the matching identifier name documented by Apple.

<div class="article-table-scroll" role="region" aria-label="Guides by metric" tabindex="0">

| You want | Apple's HealthKit identifier | Guide |
|---|---|---|
| Workout distance | Workouts are separate `<Workout>` elements | [Workout distance in export.xml](/blog/apple-health-export-xml-workout-distance/) |
| Steps | [`HKQuantityTypeIdentifierStepCount`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/stepcount) | [Export Apple Health steps](/blog/export-apple-health-steps-data/) |
| Heart rate | [`HKQuantityTypeIdentifierHeartRate`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartrate) | [Export Apple Health heart rate](/blog/export-apple-health-heart-rate/) |
| Weight | [`HKQuantityTypeIdentifierBodyMass`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodymass) | [Finding weight in export.xml](/blog/export-apple-health-weight-data/) |
| Sleep | [`HKCategoryTypeIdentifierSleepAnalysis`](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/sleepanalysis) | [Sleep export guide](/blog/export-apple-health-sleep-data/) |
| Walking asymmetry and mobility metrics | [`HKQuantityTypeIdentifierWalkingAsymmetryPercentage`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/walkingasymmetrypercentage) | [Walking asymmetry guide](/blog/export-apple-health-walking-asymmetry/) |

</div>

Already have the rows and want to analyze them? See [Apple Health to Excel](/blog/apple-health-to-excel/) or [Apple Health to Python](/blog/apple-health-to-python/).

## View it without converting

A text editor can show the XML, but opening the file is different from producing usable spreadsheet rows. Large archives can stall a browser tab, and pasting the contents into a chat or web form may upload them. To get a table, use a tool built for the job (step 4).

## 3. Understand what an XML record means

XML stores named fields and can contain nested information. A record's type, unit, source, and start and end times matter when turning it into a table. The converter's [documented record output](https://github.com/muquit/applehealth2csv#how-to-use) illustrates those fields. Workouts are separate `<Workout>` elements whose distance can sit in a child element or an attribute; see [how to find workout distance in export.xml](/blog/apple-health-export-xml-workout-distance/). For sleep records specifically, see the [sleep export guide](/blog/export-apple-health-sleep-data/). For per-workout CSV or JSON instead, see [exporting Apple Fitness and Apple Health workouts](/blog/export-apple-health-workouts/).

For example, an interval with **25 steps**, unit **count**, from **09:00 to 09:05** describes one fictional interval. It is not automatically a daily step total. Preserve the unit and time offset, and decide how records should be grouped before calculating a daily or weekly summary.

Do not combine overlapping sources or repeated exports as if every row were an additional independent measurement. A converted table's row count alone does not establish complete coverage or the same totals shown in the Health app.

## 4. Choose a converter, or make a fresh CSV

<div class="article-table-scroll" role="region" aria-label="Choose an XML archive or selected CSV workflow" tabindex="0">

| Your starting point | Next step | What to check |
|---|---|---|
| Local command-line converter | Runs on your computer; the archive stays there | Supported record types, preserved fields, units, timestamps, and any errors |
| Web page that processes in the browser | May keep the file on your device, but confirm that in its own documentation | Whether anything is uploaded, whether large files stall the tab, and the same output checks |
| Web service that uploads | Sends the whole archive to someone else's server | Retention and deletion terms, who can access it, and whether you are comfortable uploading a whole-life health archive |
| Fresh Health.md export | Skips the XML: export selected metrics and dates as CSV, JSON, Markdown or Obsidian notes | One known day, selected detail, destination, and the actual saved file |

</div>

One local command-line example is [applehealth2csv](https://github.com/muquit/applehealth2csv). Its documentation describes local conversion from `export.zip` or `export.xml` to CSV or JSON and shows separate metric files. Follow that project's installation and usage instructions. We checked its documentation on October 27, 2026; we have not executed the converter or verified its compatibility with every current Apple record type.

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

### Why don't my converted totals match the Health app?

Overlapping sources can describe the same activity, and XML rows are intervals rather than daily totals. Don't treat every row as an additional independent measurement: a converted table's row count or a plain sum does not establish the same totals the Health app shows. Check one metric on one date, as in step 5.

### Is there an Apple Health export viewer?

Apple's export is a file archive, and [Apple's Health guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) describes no built-in viewer for it. You have two routes: unzip a copy and convert `export.xml` with a parser, or make a fresh selected export from the iPhone. We don't endorse any viewer app.

### Do I need to upload the archive?

A local converter can process it on your computer. An online service may handle the file differently; check whether it uploads or retains data before choosing it. This Health.md page has no file upload or XML processing tool.

If selected days and metrics are what you need, [try Health.md for iPhone](https://apps.apple.com/us/app/health-md/id6757763969). It includes five export actions followed by a lifetime unlock; see [purchase details](/docs/paywall/). For Android data, use the separate [Health Connect export guide](/health-connect-export/).
