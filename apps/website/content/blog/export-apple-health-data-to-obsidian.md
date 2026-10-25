---
title: "How to export Apple Health data to Obsidian."
description: "Export Apple Health to Obsidian with Health.md: choose a vault, preview one day, and merge health metrics into daily notes or query frontmatter in Bases."
lead: "Health.md writes selected Apple Health data into your Obsidian vault as Markdown or Bases-ready frontmatter. Choose a folder, preview one day, then export a separate health note or update an existing daily note."
date: "2026-06-13"
updated: "2026-10-25"
verified: "2026-10-25"
verified_by: "Codex (agent)"
verified_method: mixed
category: "Workflow guide"
draft: false
image: "/assets/blog/export-apple-health-data-to-obsidian/healthmd-export-configuration.png"
imageAlt: "Health.md export configuration screen"
showCover: false
tags:
  - healthmd
  - apple-health
  - obsidian
---
<figure class="phone-shot">
<img alt="Health.md export configuration screen showing Health, vault, export target, and date range controls" src="/assets/blog/export-apple-health-data-to-obsidian/healthmd-export-configuration.png"/>
<figcaption>Start with Health authorization, a vault destination, an export target, and the date range you want to write.</figcaption>
</figure>

Use Health.md when you want steps, sleep, heart metrics, or workouts beside your journal and training notes. You select the health data and destination; this Obsidian folder workflow does not create a Health.md server copy of your health data.

## Before you start

- Install [Health.md on your iPhone](https://apps.apple.com/us/app/health-md/id6757763969) and make sure Apple Health contains data for the day you want.
- Open your vault in Obsidian and identify its folder in Files. Health.md needs a writable folder inside that same vault.
- Authorize the Apple Health categories you want to read. Available metrics depend on the device, OS, source data, permissions, and app version.

This guide covers Apple Health on iPhone. For Android, follow [Health Connect to Obsidian](/blog/export-health-connect-to-obsidian/); the platforms do not expose identical metrics or export profiles. For current trial and purchase details, see [Health.md pricing](/about/#key-facts).

## The quick workflow

1. Install Health.md on the iPhone that has access to Apple Health.
2. Grant Health permissions for the metrics you want to export.
3. Pick an Obsidian vault folder or another folder available through Files.
4. Choose the export formats: Markdown, Obsidian Bases, JSON, CSV, or a mix.
5. Start with Yesterday or a custom one-day range, tap Preview, then Export Data. Review the result and open the file in Obsidian.
6. Optionally enable Daily Note Injection to merge metrics into existing daily notes.

## Choose an Obsidian destination

Health.md writes to folders you choose. That can be an Obsidian vault in iCloud Drive, an on-device folder, a file-provider location, or a Mac destination when you use the companion app. The iPhone remains the HealthKit source; the Mac workflow is only a local destination for files that are configured and prepared from the iPhone.

A common vault layout is simple:

```
Obsidian Vault/
  Health/
    2026-06-13.md
    2026-06-14.md
  Daily/
    2026-06-13.md
```

The `Health/` folder is useful for full daily exports. The `Daily/` folder is useful when you want selected metrics merged into notes you already write by hand.

## Pick the right export format

Health.md supports four daily export formats, and you can enable more than one.

| What you want | Choose | What it produces |
| --- | --- | --- |
| Read health summaries beside your journal | Markdown | A daily note with selected metrics and readable sections |
| Filter and compare notes in Obsidian Bases | Obsidian Bases | A generated note containing structured frontmatter properties |
| Process data in scripts | JSON | Structured daily data and optional canonical source records |
| Build charts in a spreadsheet | CSV | Metric rows with values and units; see the [CSV walkthrough](/apple-health-to-csv/) |

Updating a daily note you already write is a separate choice: use Daily Note Injection below. A Bases export creates a frontmatter file; it does not build a Bases view for you.

<figure class="phone-shot">
<img alt="Health.md export formats screen showing Markdown, Obsidian Bases, JSON, CSV, frontmatter, and category grouping options" loading="lazy" src="/assets/blog/export-apple-health-data-to-obsidian/healthmd-export-formats-and-daily-notes.png"/>
<figcaption>Enable Markdown for readable notes, Obsidian Bases for structured frontmatter, and JSON or CSV when you want machine-readable exports.</figcaption>
</figure>

The following is a **synthetic excerpt** of the [production-generated Apple v8 Markdown example](/docs/reference/generated/core/summary-day.md). It shows selected properties, not a complete export or a person's health data. Your enabled metrics and formatting settings determine the output.

```
---
date: 2026-03-15
type: health-data
resting_heart_rate: 58
sleep_total_hours: 7.75
steps: 12500
---
```

An Obsidian Bases export stores selected metrics as frontmatter properties. Fields such as `steps`, `sleep_total_hours`, and `resting_heart_rate` remain numeric so you can use them in Bases views.

In Obsidian, create a Bases view scoped to your health-note folder and add the properties you want as columns. Keep numbers numeric; the unit for `sleep_total_hours` is hours and `resting_heart_rate` is beats per minute. See the [format reference](/docs/reference/export-formats/) for units and omission rules before building calculations.

JSON exports include top-level fields such as `date`, `type`, and `units`, followed by category objects like `activity`, `sleep`, `heart`, `vitals`, and `workouts`. CSV exports use a stable `Date,Category,Metric,Value,Unit,Timestamp` header, with timestamps filled in for individual samples when available.

## Use Daily Note Injection for journal workflows

Daily Note Injection is for people who already live in daily notes. Instead of creating only separate health files, Health.md can merge selected metrics into the YAML frontmatter of an existing note such as `Daily/2026-06-13.md`.

### Set up one existing daily note

1. Back up your vault and choose one date for the first run.
2. In Daily Note Injection, set **Folder** to your vault-relative daily-note folder, such as `Daily`, and **Filename** to your existing naming pattern. Use `{date}` for `2026-06-13.md`; omit the extension in the setting.
3. Leave **Create note if missing** off if Obsidian or Templater creates your notes. Turn it on only if you want Health.md to create missing notes.
4. Choose the metrics in **Health Metrics** and review the frontmatter preview. Leave **Inject metric sections** off for a frontmatter-only update.
5. Export that one date. Open the matching note in Obsidian and verify that its health properties updated and your writing is still present.

The [Daily Note Injection reference](/docs/daily-notes/) lists filename placeholders and merge behavior.

<figure class="phone-shot">
<img alt="Health.md settings showing time-series data, format customization, daily note injection, and output options" loading="lazy" src="/assets/blog/export-apple-health-data-to-obsidian/healthmd-daily-note-options.png"/>
<figcaption>Daily Note Injection sits beside format customization and individual entry tracking so you can choose how deeply health data enters your vault.</figcaption>
</figure>

This **illustrative daily note** uses synthetic values. It combines your writing with health properties; it is not a complete schema fixture:

```
---
date: 2026-06-13
steps: 12642
sleep_total_hours: 7.31
resting_heart_rate: 58
---

# Saturday

Morning notes, workout reflections, meals, symptoms, or anything else you track.
```

If the daily note already has frontmatter, Health.md preserves your keys and updates the fields it owns. If you enable body sections, the app-managed health sections are replaced cleanly on each export so repeated exports remain idempotent.

## Decide which metrics belong in your vault

The production-generated Health.md catalog documents hundreds of summary and source-record definitions. Availability depends on the app build, operating system, permissions, and records actually returned. A registry entry is not a promise that every source is readable: current Apple App Store builds do not request historical clinical records. You can select a few properties or include sleep stages, heart-rate samples, workouts, vitals, nutrition, symptoms, and supported source archives; inspect capture status and warnings when completeness matters.

A good starting set for Obsidian is:

- **Activity:** steps, walking/running distance, active energy, exercise time.
- **Sleep:** total sleep, bedtime, wake time, deep sleep, REM sleep.
- **Heart:** resting heart rate, average heart rate, heart rate variability.
- **Workouts:** workout count, duration, distance, and workout details.
- **Mindfulness or symptoms:** useful if they already support your journal workflow.

## Keep it local-first

Health.md is designed around files you control. HealthKit reads happen on your Apple devices, and the exported Markdown, Bases, JSON, and CSV files land in the folder you choose. This Obsidian folder workflow does not require a Health.md cloud account or create a Health.md server copy. If you send exports to a Mac, the Mac acts as a local destination rather than a remote health-data service.

A separate, optional single-owner Health.md Cloud pilot retains API exports intentionally uploaded to it, subject to its quota. There is no public signup and no automatic device sync; this Obsidian folder workflow does not upload to it. The pilot is unbacked, retains accepted revisions without an age cutoff, and erases stored data asynchronously after account deletion disables access. See the [privacy policy](/privacy-policy.html#retention) for retention, deletion, and loss risks.

That local-first shape matters for health data. You can back up the vault, sync it with the provider you already trust, version it with your own tools, or delete the exported files without asking a service to remove your account.

## Troubleshooting notes

- If exports are empty, review Health.md’s Health permissions, selected categories, date range, and capture warnings. Empty output alone does not prove that the source contains no records.
- If last night's sleep is missing, export the day the sleep session started. A session from Monday night to Tuesday morning belongs to Monday. See [sleep-date attribution](/blog/why-sleep-is-in-yesterdays-note/).
- Check that your watch or source app has synchronized and that the selected day contains the metric. An absent value is not a measured zero.
- If Obsidian does not see the files, confirm the destination folder is inside the vault Obsidian is opening on that device.
- If you use scheduled exports, remember that iOS background refresh is opportunistic. Treat the scheduled time as a target, not a guarantee.
- If you need database-style views, enable Obsidian Bases or keep Markdown frontmatter enabled so properties are queryable.

## What to read next

For exact field names, examples, and app screens, start with the Export docs, Daily Note Injection docs, and the production-backed Export Reference.

<div class="cta-row">
<a class="button" href="/docs/export/">Read Export docs</a>
<a class="button secondary" href="/docs/daily-notes/">Daily Note Injection</a>
<a class="button secondary" href="/docs/reference/">Open Export Reference</a>
</div>
