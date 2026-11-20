---
title: "Export Google Fit data: Takeout and Google Health move"
description: "Download Google Fit data with Takeout (select only Fit) before the Google Health move, then get daily CSV, JSON or Markdown files on Android."
lead: "Google is turning the Fitbit app into Google Health and has said Fit users will be invited to migrate later. Download a Takeout archive first, then use Health Connect for daily files."
date: "2026-10-30"
updated: "2026-11-20"
verified: "2026-11-20"
verified_by: "Claude (agent)"
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

To export Google Fit data now, open [Google Takeout](https://takeout.google.com/), choose **Deselect all**, select only **Fit**, and create the export. That gives you an account archive you can keep. Google has said the Fitbit app is becoming the **Google Health** app and that it will invite Fit users to migrate their data later; that migration is a separate step from Google. On Android, Health Connect plus Health.md gives you daily CSV, JSON or Markdown files for new days, not old history.

> **Quick answer (checked November 20, 2026)**
>
> - **Full archive now:** Google Takeout with only **Fit** selected.
> - **The move to Google Health:** wait until Google offers it, and download a Takeout archive first.
> - **Ongoing daily files on Android:** Health Connect plus Health.md, for new days going forward.

**You do not need Health.md for Google's own download.** Health.md does not read a Takeout ZIP, migrate Fit history or connect to a Google account.

## What's changing with Google Fit (as of November 20, 2026)

- **Fitbit app to Google Health.** Google's [May 7, 2026 announcement](https://blog.google/products-and-platforms/products/google-health/google-health-app/) says the Google Health app "starts rolling out to all users on May 19".
- **Migration for Fit users.** The same post says: "We'll invite Google Fit users to migrate their data into Google Health app later this year."
- **Fit APIs.** Google's [Android Developers migration FAQ](https://developer.android.com/health-and-fitness/guides/health-connect/migrate/migration-faq) says the Google Fit APIs, including the Fit REST API, will be deprecated in 2026. Developers can no longer sign up for them as of May 1, 2024.

**Not announced in the sources checked:** the migration invitation date, which Fit data types will move, and a shutdown date for the Fit app. Check the Google Health app and Google's help center for the invitation. Download a Takeout archive *before* acting on any migration prompt, and keep the original ZIP.

## Download your Fit archive with Google Takeout

These steps follow Google's [Fit download help](https://support.google.com/fit/answer/3024190?hl=en):

1. Sign in to [Google Takeout](https://takeout.google.com/) with the account that holds your Fit data.
2. Choose **Deselect all**.
3. Select **Fit** and check its data options.
4. Choose **Next step**.
5. Choose a delivery method: an email link, or Drive, Dropbox, OneDrive or Box.
6. Choose a one-time export, or a scheduled export (every 2 months for 1 year).
7. Choose **.zip** or **.tgz** and a maximum file size.
8. Choose **Create export**.

Archives can take minutes to days. Google's help says they expire after about 7 days and can be downloaded up to 5 times. Downloading does not delete your data from Google's servers.

Inside the archive, open `archive_browser.html`. This guide does not promise specific Fit filenames or columns; inspect the folder and `archive_browser.html` to see what your account produced.

## Fit and Google Health are separate Takeout products

Fit history and Google Health (formerly Fitbit) data are separate products in Takeout. For the Google Health side, follow the [Fitbit and Google Health export guide](/blog/export-fitbit-data/), which covers Takeout, TCX workouts and CSV.

## Open the archive in a spreadsheet

On a computer, open CSV files in a spreadsheet and JSON files in a text editor or a JSON-aware tool. Check what each file contains first, and keep the date and unit columns beside every value so numbers stay interpretable.

## Moving to a new phone

Fit data is tied to your Google account, not the phone, so signing in on the new phone is separate from any local file. Android's Health Connect backup and restore is a different thing: on Android 14 or later it saves a Health Connect backup to a cloud provider. Read Google's [backup and restore guide](https://support.google.com/android/answer/15323271?hl=en) and its coverage limits. That ZIP is distinct from Takeout and from Health.md files; Health.md does not import either.

## Daily files going forward with Health Connect and Health.md

Google's [Health Connect on Google Fit guide](https://support.google.com/fit/answer/12830119?hl=en) documents **Profile → Settings → Health Connect → Sync Fit with Health Connect**, and **Manage data and access → Connected apps** to review permissions. If the setting is missing, check Google's current instructions.

Then verify actual records: open Health Connect and confirm a completed day contains the fields and source you intend to export. Sharing does not prove full history. Health Connect does not backfill years of Fit history, and Health.md's history read permission is separate from Fit's permission to share.

Once you have the Takeout archive, get ongoing daily files:

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md on Google Play</a>

1. In Health.md, choose the **Health Connect** source and grant read access to the relevant categories.
2. Select the metrics you verified. Start with one completed day and a writable folder.
3. Choose **CSV**, **JSON** or **Markdown**.
4. Export and open the saved file. Compare date, values and units with Health Connect before widening the range.

See the [Android setup guide](/docs/android/) for folder access and history permissions. For daily notes, continue with the [Health Connect to Obsidian guide](/blog/export-health-connect-to-obsidian/). The [fictional Android CSV excerpt](/assets/samples/health-connect-summary-excerpt.csv) shows Health.md output; it is not a Takeout file. See also the [Health Connect export guide](/health-connect-export/) and [format reference](/docs/format/). Absent fields are unavailable data, not zero, and overlapping source and re-exported files should not be added together.

## If you started on iPhone

Google's [iPhone Fit documentation](https://support.google.com/fit/answer/10066680?co=GENIE.Platform%3DiOS&hl=en) describes sharing Apple Health data into Google Fit. For records already in Apple Health, use the [Apple Health export guide](/apple-health-export/).

## Privacy and account boundaries

Core Health.md folder exports require no Health.md account and create no Health.md server copy by default. The local folder export workflow does not remove records held by Google; synced folders and downstream services follow their own rules. The separate, opt-in, single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, has no public signup and no automatic device sync, and is not generally available. The folder workflow does not upload to it. See the [retention policy](/privacy-policy.html#retention) and [local destination guide](/blog/export-health-data-without-the-cloud/).

## FAQ

### Is Google Fit shutting down?

Google says the Fit APIs will be deprecated in 2026 and that Fit users will be invited to migrate to Google Health later this year. In the sources checked on November 20, 2026, Google has not published a shutdown date for the Fit app.

### Will my Fit history move to Google Health automatically?

Google has said it will invite Fit users to migrate their data. It has not said, in the sources checked, when or which data types. Download a Takeout archive first.

### Can I export Google Fit to CSV?

Takeout gives an archive; inspect it and `archive_browser.html` for the formats your account produced. Health.md can write new days from Health Connect as CSV on Android.

### Does exporting delete my data?

No. Google's help says downloading does not delete data from its servers.
