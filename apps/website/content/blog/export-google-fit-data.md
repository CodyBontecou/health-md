---
title: "Export Google Fit data: Takeout or Health Connect files"
description: "Choose Google Takeout for available Fit account data, or daily files from actual Health Connect records. Check permissions, history and Google Health differences."
lead: "Keep an account archive with Google Takeout, or save selected records already available in Android Health Connect as daily CSV, JSON or notes."
date: "2026-10-30"
updated: "2026-10-30"
verified: "2026-10-30"
verified_by: "Codex (agent)"
verified_method: traced
platform: android
category: "Workflow guide"
related:
  - export-fitbit-data
  - export-health-connect-to-obsidian
  - export-health-data-without-the-cloud
draft: false
tags:
  - google-fit
  - takeout
  - health-connect
  - csv
---

To export Google Fit data, first choose between an account archive and selected daily files. **You do not need Health.md to request Google's own download.** Health.md offers a separate Android workflow for records actually available in Health Connect.

This workflow does not import a Google Takeout archive, restore Google Fit history or connect directly to your Google Fit account. A local health-store record is a different representation from the account data Google's export includes.

## Choose the route for your task

| Your task | Start with |
| --- | --- |
| Keep available Google Fit account data | Google Takeout, using the product choices offered for your account |
| Back up Health Connect for a supported restore | Android's native Health Connect backup and restore, with its coverage limits |
| Use selected shared records in daily files or notes | Verify actual Health Connect records, then use Health.md |
| Export Google Health or Fitbit data | The separate Google Health/Fitbit export instructions |

**Google Fit, Google Health and Health Connect are distinct names and workflows.** If your records are now in Google Health, follow the [Fitbit and Google Health export guide](/blog/export-fitbit-data/) rather than assuming Google Fit menus or archive contents apply.

## Request the account archive through Google Takeout

Google Fit's [download help](https://support.google.com/fit/answer/3024190?hl=en), checked **October 30, 2026**, points to Google Takeout:

1. Open [Google Takeout](https://takeout.google.com/) with the account that holds the data.
2. Review the selected products and keep the Fit data offered for that account. Remove unrelated product selections if you only want that export. Inspect any included-data options.
3. Choose **Next step**, then the archive type, file size and delivery method. For a single download, choose a one-time archive.
4. Create the export and follow Google's delivery instructions. For email delivery, use the download link when it arrives.

Open the archive on a computer and inspect its included format guidance before conversion. Product availability, files and included data depend on the account; this guide does not promise a particular Fit CSV filename or schema. Recent changes may not appear in an archive requested earlier. Downloading does not delete Google's server data.

Health.md does not turn that ZIP into daily CSV or load it back into Google Fit. Keep the original archive independently if it is the record you need.

## Check the documented Google Fit connection on Android

Google's [Health Connect on Google Fit guide](https://support.google.com/fit/answer/12830119?hl=en) documents **Profile → Settings → Health Connect → Sync Fit with Health Connect**. Review **Manage data and access → Connected apps** to inspect the connection and permissions.

This is an Android route. It gives Fit access to read or edit Health Connect records; it is not proof that every Google Fit account record has been copied to the phone. Check a completed day's actual records in Health Connect, including the fields and source you intend to export.

If that setting is absent from your installed app or account, verify the current Google instructions and account download options first. This guide does not establish that a particular app version, setting or historical dataset is available to every account.

Fit's permission to share data and Health.md's permission to read it are separate. A successful connection alone cannot establish full history, a particular sample stream or the same totals shown in a Google Fit dashboard. Other apps can also contribute records to Health Connect.

## Use native Health Connect backup for a restore task

If you want a supported Health Connect restore, read Google's [backup and restore guide](https://support.google.com/android/answer/15323271?hl=en). Its Android 14-or-later workflow saves a backup ZIP to a chosen cloud provider; review Google's current coverage limits before relying on it.

That backup ZIP is distinct from Google Takeout and from Health.md's daily analysis files. Health.md's folder workflow below does not import either ZIP or replace the system's restore procedure.

## Save selected daily files with Health.md

Continue after the records you need are present in Health Connect:

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md on Google Play</a>

1. In Health.md, choose the **Health Connect** source and grant read access to the relevant categories.
2. Select the metrics you verified. Start with one completed day and a writable folder.
3. Choose **CSV** for a table, **JSON** for structured processing or **Markdown** for daily notes.
4. Preview, export and open the actual saved file. Compare the date, values, units and destination with the phone's source records before widening the range.

Follow the [Android setup guide](/docs/android/) for system requirements, folder access and history permissions. A longer range produces separate daily files. Increasing that range does not recover records absent from Health Connect or bypass historical read restrictions.

For Obsidian, continue with the [Health Connect daily-note guide](/blog/export-health-connect-to-obsidian/). A local daily file preserves the selected output returned by the platform, not necessarily every field, calculated score, goal or account-specific result in Google Fit.

## Inspect the Android sample before personal files

The [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) shows Health.md activity output. It is not a Google Fit Takeout file or proof that Google Fit supplied the sample values. Do not apply a Takeout column map to it without inspecting the different structure.

Use a CSV-aware importer and select the intended Category, Metric and Unit before converting Value to numbers. The full export can contain text and metadata. Keep units and time context with each value, and check the actual labels rather than assuming the Apple and Android outputs match.

Do not add source samples, daily totals and re-exported copies together. Review overlapping dates and keep the intended version of each file. An absent field is unavailable data, not measured zero; a connected app does not prove a complete day of recording.

For the broader format and platform boundaries, use the [Health Connect export guide](/health-connect-export/) and [format reference](/docs/format/).

## If you started on iPhone

Google's [iPhone Fit documentation](https://support.google.com/fit/answer/10066680?co=GENIE.Platform%3DiOS&hl=en) describes sharing **Apple Health data into Google Fit**. That does not establish that a Google Fit account archive was written back to Apple Health.

For records already present in Apple Health, use the [Apple Health export guide](/apple-health-export/). For account-only history, inspect the native download route above. The Health Connect instructions on this page apply to Android.

## Keep account, destination and privacy boundaries separate

Core Health.md folder exports require no Health.md account and create no Health.md server copy by default. That does not remove existing records held by Google or other source services. Synced folders and downstream services follow their own storage and privacy rules.

The separate optional, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. This folder workflow does not upload to that pilot. Review the actual file before sharing it, and follow the [retention policy](/privacy-policy.html#retention) and [local destination guide](/blog/export-health-data-without-the-cloud/) for storage and backup checks.
