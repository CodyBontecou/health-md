---
title: "Export Strong app data: CSV, migration and daily files"
description: "Download Strong workout CSV, understand why it is not a restore backup, and choose a supported migration or daily Apple Health and Health Connect export."
lead: "Preserve the native training file before choosing a migration or a separate daily health-data workflow."
date: "2026-11-03"
updated: "2026-11-03"
verified: "2026-11-03"
verified_by: "Codex (agent)"
verified_method: traced
platform: both
category: "Workflow guide"
related:
  - export-hevy-data
  - export-apple-health-workouts
  - export-polar-flow-data
draft: false
tags:
  - strong
  - workouts
  - csv
  - export
---

**Download Strong's own CSV when you want the workout information stored in Strong. Health.md is not needed for that export.** Keep it separate from an account backup, a migration file accepted by another app, and a daily export of records already shared to your phone's health store.

Those are different jobs. A file you can inspect in a spreadsheet is not necessarily something you can restore into the app that created it.

## Download the native workout CSV

Strong's [export help page](https://help.strongapp.io/article/235-export-workout-data), read **November 3, 2026**, documents:

- **iPhone:** in-app **Settings → Export Strong Data**.
- **Android:** in-app **Settings → Export Data**.

Save the spreadsheet-friendly CSV using the options your installed version offers. That help article was last updated in April 2021, so treat its menu labels as documented guidance, not a guarantee that every current version looks identical.

Keep an untouched original and inspect its actual dates, exercise names, units and available fields before analysis. Do not assume a particular column schema or complete history without checking the downloaded file. For a **fictional** unit check, `50 kg` and `50 lb` are not interchangeable; preserving the number while silently changing the unit corrupts the record.

## A workout CSV is not an account restore

Strong's [account-deletion guidance](https://help.strongapp.io/article/248-how-do-i-delete-my-account) explicitly says that an exported CSV cannot be imported back into a newly created Strong account. **Do not delete an account to test whether the CSV restores it.** A readable copy and a reversible backup are different things.

Its [May 2026 privacy policy](https://help.strongapp.io/article/232-privacy-policy) separately describes workout CSV export on iPhone/Android and an in-app request for the entirety of personal data, including settings. Use that distinction if you need more than the workout table. A broader data request still does not establish a restore format or migration guarantee.

If you are investigating missing workouts or account access, preserve the app and originals and follow Strong's account support guidance. This article does not perform recovery or recommend logging out, reinstalling or deleting data.

## Moving completed workouts to Hevy

If your goal is migration, Hevy has a [documented Strong import](https://help.hevyapp.com/hc/en-us/articles/35687878672663-Importing-Strong-Data-into-Hevy). It calls for a direct, unedited Strong CSV exported with Strong set to English and weight values in kilograms. The documented route is **Profile → Settings → Export & Import Data → Import Data → Import Strong CSV → Select File**.

Hevy says completed history is imported, but saved routines and superset connections are not preserved as such. Only one CSV import can be active; its instructions say to revert a previous import before using an updated file. Reverting removes the records added by that import. Read those instructions before acting on an existing import. No migration was executed for this guide, and we do not promise lossless transfer.

Health.md is not a Strong-to-Hevy converter. Do not substitute a Health.md daily CSV for the direct Strong file required by that importer. For Hevy's own downloads, see the separate [Hevy export guide](/blog/export-hevy-data/).

## Use daily files only after checking Apple Health

For daily notes or selected metrics beside other Apple Health data, first inspect whether the records you need actually reached Apple Health on your iPhone.

Strong's [Apple Health instructions](https://help.strongapp.io/article/147-sync-with-apple-health) describe **Profile → Settings → App Integrations → Apple Health → Connect**. That page was last updated in February 2022; check the controls in your installed version. Authorize only the categories needed for your workflow and verify a known completed session. A connection switch is not proof of full historical transfer.

If the required records are present, use Health.md's [first iPhone export guide](/docs/iphone-first-export/), grant its separate read access, select Workouts and preview one workout start day before writing to a chosen folder.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

For this iPhone route, CSV includes several fields per workout; counting every row would count fields rather than sessions. JSON keeps workout objects with IDs and exact start/end timestamps. The [workout file guide](/blog/export-apple-health-workouts/) covers duration versus elapsed time, duplicate recordings and longer daily exports.

This reads authorized Apple Health records, not a Strong account or a Strong-only source filter. It cannot reconstruct absent exercise sets, repetitions, weights or training notes. Keep the native CSV for the strength log.

## Android: verify the installed connection, not a version assumption

Strong's [Health Connect article](https://help.strongapp.io/article/254-google-fit-health-connect-integration), last updated in November 2024, describes support in Strong 6.0 Android beta and warns against rollback after upgrading. Its May 2026 privacy policy also describes permission-based Health Connect integration. These documents do not prove the release channel or field coverage of your installed app today. Do not join a beta or upgrade just to follow this guide.

If your existing version already offers Health Connect and the required records are visible there, the [Health Connect export guide](/health-connect-export/) explains a separate one-day preview and folder export.

<a class="button" href="https://play.google.com/store/apps/details?id=com.healthmd.android">Get Health.md for Android</a>

The iPhone CSV labels above are not an Android schema, and no universal history or strength-detail parity is promised. If the connection is absent or records are missing, use Strong's native CSV rather than installing another exporter to repair an upstream gap.

## Keep copies and destinations deliberate

Before combining exports, compare one known session's date, units, available values and source. Keep native CSVs and phone-store daily files in separate folders. Re-exports or multiple source recordings can describe the same workout; missing sessions are not zero-duration workouts.

Core folder export creates no Health.md health-data server copy by default. A synced folder, spreadsheet upload or shared migration file follows the destination's rules. Review the file before sharing and use the [local-only export workflow](/blog/export-health-data-without-the-cloud/) when a local destination is the right fit.
