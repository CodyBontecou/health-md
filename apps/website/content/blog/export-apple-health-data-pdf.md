---
title: "How to export Apple Health data as a PDF"
description: "Create an Apple Health PDF with Health.md's Clinician Report. Choose dates and measurements, review coverage and reading tables, then explicitly save or share the report."
lead: "On iPhone, open Health.md Settings → Clinician Report, choose a period and measurements, generate the report, review the PDF, then choose Share or Save PDF."
date: "2026-10-26"
updated: "2026-10-26"
category: "Workflow guide"
related:
  - apple-health-to-excel
  - export-health-data-without-the-cloud
  - export-apple-health-sleep-data
draft: false
verified: "2026-10-26"
verified_by: "Codex (agent)"
verified_method: traced
tags:
  - apple-health
  - pdf
  - report
  - export
---

Health.md can turn selected Apple Health measurements into a descriptive PDF through **Clinician Report**. You choose the period, measurements and level of detail, inspect the generated report on your iPhone, then explicitly save or share it.

This is a document workflow in **Settings**, rather than another format in the daily export picker. It does not convert an existing Apple XML archive or automatically send a report to a clinician.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

## Choose a PDF or a data export

| Your task | Use |
| --- | --- |
| Read or share a selected health summary | Clinician Report PDF, generated on iPhone. |
| Analyze daily values in a spreadsheet | [CSV export](/apple-health-to-csv/), followed by the Excel or Sheets workflow. |
| Preserve selected public source records for software | JSON/CSV with the appropriate [data-detail settings](/docs/format/). |
| Keep recurring daily files | The regular export and [scheduling workflow](/docs/scheduling/). PDF reports are not a scheduled export format. |
| Obtain Apple's native archive | Apple's XML export, explained in the [Apple Health export guide](/apple-health-export/). |

Clinician Report is available on **iPhone and Android**; the Apple PDF workflow described here is on iPhone, not the Mac app. Android uses Health Connect and its own native controls; start from Settings → Clinician Report and the [report documentation](/docs/clinician-report/).

## 1. Open Clinician Report and choose a period

On iPhone, open **Health.md → Settings → Profiles & Reports → Clinician Report**. You do not need to configure a vault, export folder, or daily export format first.

Choose **7, 30, or 90 days**, or enter a custom start and end date. The report period includes both dates and uses the device timezone pinned when the report is prepared. The preset ranges include today, so a current day's coverage or total may still change as records arrive.

For a first check, use a short period where you know some records exist. If you want completed days only, choose an appropriate custom range. Verify the period printed on the report before sharing it; do not assume every preset excludes today.

## 2. Select the measurements and detail

Clinician Report currently offers these 11 measurement areas:

- Blood pressure.
- Heart rate and resting heart rate as two separate choices.
- Weight and blood glucose.
- Oxygen saturation, respiratory rate and body temperature.
- Sleep duration, steps and workouts.

Choose only the areas needed for the document. The report has its own measurement selection; confirm it here rather than assuming your usual daily-export toggles define the report. Apple read authorization is still required for the selected data. Review permissions using [Apple's Health access instructions](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) if necessary.

Choose **Summary only** for compact sections, or **Summary + individual readings** for the additional available reading tables. Tables vary by measurement: steps are daily totals, while other sections can show timestamped readings or workout entries. Do not assume “individual readings” means a full raw archive for every metric.

HRV is not one of the current report measurement choices. Use the [HRV CSV/JSON guide](/blog/export-apple-health-hrv/) if that is the data you need. A PDF of the supported measurements is not an export of every Apple Health type.

You may optionally enter a **display name**. Health.md uses it in this report and does not save it as a report setting; the generated filename does not contain it. The PDF itself can still identify you through that name and its contents. Leaving the field blank does not anonymize health records.

## 3. Generate and review the report

Tap **Generate Report** in the English iPhone interface. Health.md reads the selected data, prepares the descriptive sections and renders the PDF on the device. When a document is available, review it before opening the share sheet.

Check these details:

- **Period and identity:** confirm the start/end dates and any display name.
- **Selection:** check that the intended measurements appear and unwanted information is excluded.
- **Units:** read the units printed with each value. The current glucose report uses **mg/dL**; do not relabel it mmol/L. Other supported values can reflect the applicable unit preference.
- **Coverage and counts:** distinguish days with data, reading counts and unavailable sections. They answer different questions.
- **Detailed tables:** inspect timestamps, values and available source labels when you selected reading tables.
- **Disclosure:** read the report's missing-data and descriptive-use notes.

For example, an inclusive October 1–7 range spans seven calendar dates. Measurements on two of those dates do not establish a complete week, even if there are many readings on those two dates. Conversely, a section with no available data does not prove that a measurement or event never occurred.

Blood pressure rows require trustworthy paired systolic/diastolic records. The report does not invent pairs from unrelated values. That can make its count lower than a list that displays individual systolic or diastolic entries separately.

Use the edit control to change the configuration and regenerate if the preview is wrong. This PDF reports recorded facts and coverage; it does not diagnose, calculate clinical risk, or recommend treatment.

## 4. Explicitly save or share the PDF

When the document is ready, choose **Share or Save PDF**. This opens the iPhone share sheet. Choose **Save to Files** to retain a copy, or choose the intended recipient/app for sharing. If no reportable data is available, review the range and permissions rather than assuming a valid PDF was created.

The generated filename follows the report title and ISO start/end dates with a `.pdf` extension. Review the actual filename and destination, especially if a previous report covers the same dates. The optional display name is not included in that filename.

After saving, open the copy in Files and verify that the document, dates and pages are the ones you intended. Opening a share sheet is not the same as completing a save or delivery; you can cancel it. Previewing alone does not save a copy into your chosen Files folder.

Selecting iCloud Drive or another synced destination puts the saved report under that provider's rules. Email, messaging, document storage, and other recipient apps can create additional copies. Review the destination before completing the share action.

## Privacy and retained copies

Reading, normalization and PDF rendering for this workflow happen on the device. The report workflow does not automatically upload to Health.md or enroll you in a clinician service. It is separate from the clinician portal, and any informational link in the document is not an automatic delivery path.

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. Generating this report does not upload it to that pilot. See [Health.md's retention and destination boundaries](/privacy-policy.html#retention).

Temporary report artifacts support preview and sharing. Do not treat the preview as your durable saved copy or infer that closing it removes copies already saved or sent elsewhere. Saved files, recipient copies, backups and derived documents follow their own storage and deletion rules. For a local Files destination and separate backup checks, use the [local export guide](/blog/export-health-data-without-the-cloud/).

## Troubleshooting

- **No measurement selected:** select at least one before generating the report.
- **A section has no data:** check source records, selected period and read authorization. Apple Health may make denied reads indistinguishable from empty results; the report describes data unavailable to Health.md rather than proving absence.
- **Blood pressure count is lower than expected:** check whether the source contains actual paired records. Unpaired values are not turned into guessed pairs.
- **Controls are disabled:** preparation or rendering may be in progress. Wait for it to finish or close the workflow to cancel the operation.
- **No saved PDF in Files:** check whether you completed Save to Files, the selected folder and its availability. A cancelled share does not create your intended saved copy.
- **You need a measurement outside the report's set:** use the appropriate CSV/JSON export guide instead of expecting the PDF to include unsupported sections.

For the concise product reference, see [Clinician Report](/docs/clinician-report/). For analysis rather than a document, continue with [Apple Health to Excel](/blog/apple-health-to-excel/) or [Google Sheets](/blog/apple-health-to-google-sheets/).
