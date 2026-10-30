---
title: "How to export health data without the cloud"
description: "Export Apple Health to a local folder with Health.md. Choose On My iPhone, verify saved files, and check sync, backup, and analysis settings before sharing records."
lead: "For a local Apple Health export, choose a non-synced folder on your iPhone, export a small selection, and inspect the saved file. Review backups and any app you open it in separately."
date: "2026-09-26T12:00:00.000Z"
updated: "2026-10-25"
category: "Workflow guide"
related:
  - local-first-health-data-architecture
  - export-apple-health-data-to-obsidian
  - apple-health-xml-export
draft: false
verified: "2026-10-25"
verified_by: "Codex (agent)"
verified_method: traced
tags:
  - healthmd
  - apple-health
  - privacy
  - local-first
---

You can export selected Apple Health data with Health.md without sending that export through a Health.md server. The iPhone reads authorized HealthKit data, builds the output on the device, and writes it to the folder you choose. No Health.md account is required for this local folder workflow.

Keeping the resulting files out of cloud storage takes another decision: choose a **non-synced local folder**, then check its backup settings and what happens when you open or share the files. Selecting a local destination does not change your existing Apple Health, iCloud, or device-backup settings.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

The subscription-enabled phone release offers weekly/yearly subscriptions and Lifetime. Eligible subscriptions include a 7-day trial; existing purchases remain valid. This manual iPhone workflow needs no Mac. The steps below are for Apple Health; for Android's source and folder picker, use the [Health Connect export guide](/health-connect-export/).

## What “without the cloud” covers

This guide keeps the **export path** on your phone: Apple Health → Health.md → a chosen local folder. It does not certify that your phone, its backups, or every app you use is cloud-free.

| Choice | What to check |
| --- | --- |
| On My iPhone | Local storage location; review app/device backup settings separately. |
| iCloud Drive or a cloud-backed Files provider | The provider can sync the exported file under its own rules. An offline copy is not evidence that no cloud copy exists. |
| An Obsidian vault or desktop folder | Inspect the actual location, sync software, and backups; the folder name alone does not establish where copies go. |
| An API destination or AI upload | Selected records leave the folder workflow for that endpoint or model provider. |

Apple distinguishes [On My iPhone, iCloud Drive, external storage, and third-party Files locations](https://support.apple.com/en-us/102570). Use the location shown in Files, not just a folder called “Private” or “Health.”

The separate opt-in, single-owner Health.md Cloud pilot retains only API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This local folder export does not upload to that pilot. See [Health.md's retention and destination policy](/privacy-policy.html#retention).

## 1. Pick a local destination before exporting

1. In Files, open **Browse → On My iPhone** and identify a writable local folder for the export. If the location is unavailable or you cannot create/select a folder there, resolve that before exporting; do not substitute iCloud Drive and assume it has the same storage boundary.
2. In Health.md, select the **Local iPhone Folder** target and choose that folder through the folder control.
3. Check the selected folder's location. For this walkthrough, it should be under On My iPhone, rather than iCloud Drive or a cloud provider's Files location.

A folder on the phone is distinct from a guarantee about backups. Apple's [iCloud Backup documentation](https://support.apple.com/en-us/108770) explains that app data can be backed up even when it is not synced through iCloud Drive. Review the backup behavior of the app/location that owns your folder and any device or computer backup you use. This guide does not disable or change backups for you.

If your requirement is that no copy ever reaches cloud storage, resolve both sync and backup settings before exporting personal records. Keep an appropriate recovery plan for the files you choose to retain; local storage alone does not protect against device loss.

## 2. Authorize a small selection and preview it

1. Authorize the Apple Health categories you want Health.md to read. Start with a metric such as Steps and one known day.
2. Choose a format: **CSV** for a spreadsheet, **JSON** for structured processing, or **Markdown/Obsidian Bases** for notes. Start with **Summary** and add detail only when you need it.
3. Tap **Preview** and inspect the date, selected values, and units. Previewing is a check of the requested output; verify the saved files after export too.
4. Confirm that the local folder target is ready, then run the export.

Follow [your first iPhone export](/docs/iphone-first-export/) for setup and permissions. A longer date range produces daily files; one export action can write multiple days and formats. See [formats and data detail](/docs/format/) for Summary, Detailed Time-Series, and the Apple-only Lossless Health Records archive.

Export only what you need for the task. A plain file is not anonymized: records and files can contain sensitive dates, source identifiers, provenance, and, with selected detailed/lossless data, additional records or attachments.

## 3. Verify the actual saved file

Open the selected folder in Files and inspect the output from the one-day export:

- Confirm the file is in the intended **On My iPhone** location, not a similarly named synced folder.
- Check the filename/date and open the file. Compare its values and units with the preview and intended selection.
- If a metric or day is absent, check the source records, authorization, selected date, and metrics before expanding the range. An absent value does not establish a measured zero or identify a particular permission state.
- If no file was saved, check folder access and reselect the destination if necessary. See [export troubleshooting](/docs/troubleshooting/).

For CSV, the header is `Date,Category,Metric,Value,Unit,Timestamp`. Value is mixed-type, so filter the metric and unit before numeric analysis. Some summary rows omit the final Timestamp field. The [CSV guide](/apple-health-to-csv/) explains the row shapes and provides a synthetic sample for testing imports without personal records.

Checking a saved file establishes its location and content. It is not a network audit or proof that backup software has no copy. The verification record for this article is based on source and documentation tracing, not a newly executed device export or traffic capture.

## 4. Keep the same boundary when using the files

Opening a local file in a different app can change where its data is stored. Inspect the destination for each next step:

- **Spreadsheets:** choose a local workbook location and review that application's sync and backup behavior. Saving to OneDrive or importing into Google Sheets creates a provider-managed copy. The [Excel guide](/blog/apple-health-to-excel/) explains the import steps.
- **Notes:** confirm the Obsidian vault's actual location and whether iCloud, Obsidian Sync, another sync tool, or backup software handles it. See [Apple Health to Obsidian](/blog/export-apple-health-data-to-obsidian/).
- **AI analysis:** uploading a CSV or JSON to a model provider shares those records with that provider. Local CLI/MCP transport is a separate workflow; returned values still follow the agent's transcript, storage, and model-provider settings. See [health data and AI](/health-data-for-ai/).
- **Sharing or API delivery:** inspect the intended recipient or endpoint and its storage rules before sending. An export that started locally can still gain remote copies later.

Manual folder export does not mean the app never uses a network. Purchases, optional scheduling, provider authorization, and product operations have their own data paths. Health.md's [privacy policy](/privacy-policy.html#operations) describes those boundaries and the exclusions on health data in telemetry. Use this guide to choose a health-data destination, not as a promise that every request from the device is disabled.

## Copies, backups, and deletion

You can manage the saved file in Files, but deleting one copy is not a command to delete every other copy. Synced copies, backups, recipient services, app imports, and derived reports follow their own retention and deletion rules. Check those destinations separately when removing an export.

Changing the export destination now does not relocate or delete older exports. Review previous folders and uploads if you used a synced or remote destination before. Protect retained files and the device or computer holding them as sensitive records.

## A final check before exporting more

Confirm the source is Apple Health on this iPhone, the target is your intended non-synced folder, the saved sample has the right date and contents, and sync/backup/downstream-app behavior matches your requirement. Then increase the range or selected metrics.

For the broader export choices, see [how to export Apple Health data](/apple-health-export/). For the engineering explanation of device reads and destination boundaries, read [local-first health-data architecture](/blog/local-first-health-data-architecture/).
