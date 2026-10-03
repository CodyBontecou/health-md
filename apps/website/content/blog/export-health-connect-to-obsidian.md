---
title: "How to export Health Connect data to Obsidian on Android."
description: "Turn Health Connect records into Markdown, Obsidian Bases, JSON, or CSV files in an Android-accessible Obsidian vault with Health.md."
lead: "Health.md for Android reads Health Connect on the device and writes plain files to a folder you choose—without a Health.md account or health-data cloud."
date: "2026-09-22T13:00:00.000Z"
updated: "2026-09-22T13:00:00.000Z"
category: "Workflow guide"
draft: false
tags:
  - healthmd
  - android
  - health-connect
  - obsidian
---

An Obsidian health journal does not have to start on an iPhone. Health.md for Android can read user-authorized Health Connect data and write it to an Obsidian vault as Markdown, Bases-ready notes, JSON, or CSV.

The read happens on the Android device. The files go to a folder selected through Android's Storage Access Framework. Health.md does not require an account or relay the export through a Health.md health-data cloud.

## Set up the source

1. Install Health.md from Google Play or F-Droid.
2. Open the Health Connect setup in Health.md.
3. Grant only the categories you want to export.
4. Confirm that the source apps or wearable services have already synchronized into Health Connect.

Health.md can only read what the installed Health Connect API exposes and what you authorize. A missing type is not evidence that the underlying event never happened.

## Choose the vault

In Health.md, open the folder picker and select a writable folder inside the Obsidian vault. Android may expose local storage, Obsidian-managed folders, Syncthing, Google Drive, OneDrive, or another document provider.

A simple layout is enough:

```text
Obsidian Vault/
  Health/
    2026-09-21.md
    2026-09-22.md
  Daily/
    2026-09-22.md
```

If the provider does not expose persistent write access through Android's picker, Health.md cannot safely bypass it. Export to a local folder and let your chosen sync tool move the files instead.

## Pick a format

- **Markdown** is readable and works well for one note per day.
- **Obsidian Bases** keeps useful values in typed frontmatter.
- **JSON** is appropriate for scripts and Health.md visualizations.
- **CSV** works well for spreadsheets and data notebooks.

You can enable more than one format. Start with a single day and a small metric set, inspect the result, and only then backfill a longer range.

## Keep platform semantics visible

Health Connect and Apple Health overlap, but they are not identical databases. Health.md shares public fields only where the meanings are proven equivalent. Provider-specific fields remain provider-specific, and unsupported data is reported rather than invented.

Sleep is assigned to the local date on which the session starts. On Tuesday morning, Monday night usually appears in Monday's file. Export **Yesterday**—or Monday and Tuesday together—when checking an overnight session.

## Automate carefully

Android schedules use an exact alarm when you grant Alarms & reminders access, with durable WorkManager work as a fallback. Without exact-alarm access, the chosen time is a target rather than a guarantee. Health.md records history and can recover missed dates.

Google Play includes 10 manual export actions before its one-time unlock. The F-Droid build includes unlimited Health Connect export and no billing or Health.md telemetry code. Both channels produce the same Health Connect export outcomes, but switching channels requires uninstalling because their signing keys differ.

After the first successful note, add more metrics, a schedule, or a second profile. Keep the initial workflow small enough that an empty permission, inaccessible folder, or late source sync is easy to diagnose.

<div class="cta-row">
<a class="button" href="/docs/android/">Read the Android guide</a>
<a class="button secondary" href="/docs/sleep-date-attribution/">Understand sleep dates</a>
</div>
