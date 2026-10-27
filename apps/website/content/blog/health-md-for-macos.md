---
title: "Export Apple Health data to Mac: CSV, JSON and Obsidian"
description: "Send selected Apple Health data from iPhone to your Mac with Health.md. Set up a destination folder, export one day, and verify CSV, JSON or Obsidian notes."
lead: "Open Health.md on your iPhone and Mac, choose a destination folder on the Mac, then send a small Apple Health export from the iPhone. The iPhone reads HealthKit; the Mac renders and saves your files."
date: "2026-06-12"
updated: "2026-10-27"
verified: "2026-10-27"
verified_by: "Codex (agent)"
verified_method: traced
category: "Workflow guide"
related:
  - export-apple-health-data-to-obsidian
  - local-first-health-data-architecture
  - export-health-data-without-the-cloud
draft: false
image: "/assets/screenshots/optimized/macos-sync-with-iphone-1200.webp"
imageAlt: "Health.md Mac sync with iPhone"
showCover: false
tags:
  - healthmd
  - macos
  - apple-health
---

Use the Mac destination when your spreadsheet, archive, or Obsidian vault lives on a Mac. You configure the selected health metrics, formats, and dates on iPhone; Health.md transfers the captured data and settings to the Mac, which writes the requested files to its selected folder.

This is a direct iPhone workflow. It does not import an existing Apple `export.xml` archive, and the Mac app cannot read Apple Health on its own. If you already have Apple's archive, start with the [Apple Health XML guide](/blog/apple-health-xml-export/).

<div id="section-why-use-the-mac-destination"></div>

## What you need

- [Health.md from the App Store](https://apps.apple.com/us/app/health-md/id6757763969) installed on a compatible iPhone and Mac. Check the store for current OS requirements.
- Apple Health records on the iPhone for the day you want, with access authorized for your selected categories.
- Both Health.md apps open and able to connect. Start with nearby devices and local network access; a cellular connection alone cannot discover a nearby Mac.
- A writable destination folder on the Mac. This can be a local folder or a folder inside your Obsidian vault.

Health.md offers free export actions followed by a lifetime unlock. Check the installed app's purchase screen for its current allowance and local price; [purchase and restore documentation](/docs/paywall/) explains access. No Health.md account is required for this core export workflow.

<figure>
<img alt="Health.md Mac sync with iPhone" decoding="async" height="750" src="/assets/screenshots/optimized/macos-sync-with-iphone-1200.webp" width="1200"/>
<figcaption>The Mac companion shows connection and destination readiness. Labels can vary by installed version.</figcaption>
</figure>

## Connect your iPhone and choose the Mac folder

1. Open Health.md on the Mac and choose a destination folder. Grant access to that folder when macOS asks.
2. On iPhone, open **Sync**, select **Mac Destination**, and enable the Mac destination connection.
3. Allow local network access when requested. Keep both apps open while they connect.
4. Check that the destination is ready. If the Mac needs attention, reopen the Mac app and check its folder access before starting an export.

The folder selected on the Mac owns the final files. Selecting a similarly named folder on iPhone does not select the Mac's destination. The [Mac Sync setup guide](/docs/sync/) describes the connection, and the [macOS app guide](/docs/macos/) explains destination readiness and history.

<figure>
<img alt="Health.md Mac export destination" decoding="async" height="750" loading="lazy" src="/assets/screenshots/optimized/macos-export-health-data-1200.webp" width="1200"/>
<figcaption>Choose a writable folder on the Mac, then configure the export on iPhone.</figcaption>
</figure>

## Export one day before a larger backfill

On the iPhone's **Export** tab:

1. Choose **Connected Mac** as the export target.
2. Select **Yesterday** or a custom completed day that contains known data.
3. Select a small metric set, such as Steps, and choose CSV or Markdown as a first format.
4. Use **Preview** to check the selected date, metric, and unit.
5. Tap **Export Data** and review the completion result. On the Mac, open the selected destination folder and inspect the saved file.

The iPhone captures Apple Health data and a snapshot of the effective export settings. The Mac uses that job to render and write the requested formats; it does not independently fetch HealthKit data. Review written, skipped, and failed outcomes rather than treating an idle button as proof of success.

For authorization and metric selection, see the [first iPhone export walkthrough](/docs/iphone-first-export/). Its local folder example is a separate target; keep **Connected Mac** selected for this guide.

## Choose CSV, JSON, Markdown or Obsidian Bases

| Your next step on the Mac | Format | What to check |
| --- | --- | --- |
| Open data in Excel or another spreadsheet | CSV | Filter the category, metric, and unit before numeric analysis. Value can contain nonnumeric rows. |
| Process the daily export with a script | JSON | Keep dates, units, coverage, and the chosen export detail together. |
| Read health summaries beside a journal | Markdown | Open the generated note and confirm its date and selected metrics. |
| Query note properties in Obsidian Bases | Obsidian Bases | Save inside the vault and configure a Bases view; exported frontmatter does not create the view for you. |

You can enable multiple formats. The [synthetic daily CSV sample](/docs/reference/generated/core/summary-day.csv) and [JSON sample](/docs/reference/generated/core/summary-day.json) contain fictional data for inspecting output before sharing your own records.

Follow the [Excel import guide](/blog/apple-health-to-excel/) for spreadsheet steps, or [Apple Health to Obsidian](/blog/export-apple-health-data-to-obsidian/) for notes, Bases, and the free starter vault. Importing files into a hosted spreadsheet or another provider shares them with that provider.

## Check dates, units and the destination

Open one exported file on the Mac and compare a selected metric with the source day in Apple Health. Confirm the format, date, unit, and folder before exporting a longer range.

For overnight sleep, choose the date the session **started**. Monday night normally belongs to Monday's note, even when you export on Tuesday morning. See [sleep dates and daily notes](/docs/sleep-date-attribution/).

A missing value is not zero. Check authorization, metric selection, the requested day, and whether the original data source has synchronized into Apple Health. Daily summaries and detailed source records are different representations; do not add them together as extra measurements. See [export formats and detail](/docs/format/).

## If the Mac is unavailable or no file appears

| What you see | First check |
| --- | --- |
| No nearby Mac appears | Open both apps, enable the Mac destination on iPhone, and check local network access and device reachability. |
| The Mac needs attention | Check the selected folder in the Mac app and reselect it if write access is unavailable. |
| Preview has data but the Mac folder is empty | Confirm the active iPhone target is Connected Mac, inspect the Mac's actual destination and subfolder, then review written, skipped, or failed results. |
| A file exists but a selected value is absent | Check the source day, selected metrics, authorization, and source synchronization before retrying a larger range. |

Start with the [export troubleshooting checklist](/docs/troubleshooting/) and [folder access guide](/docs/folder-vault/). Keep the result details when investigating a failed run. Increasing the date range cannot repair an unavailable connection or folder.

<div id="section-what-stays-private"></div>

## Keep the destination under your control

This Mac destination workflow creates no Health.md server copy of your health records. The files go to the folder you select. iCloud Drive, another sync provider, backups, and any app that opens or uploads the files have their own data handling rules. The separate optional Health.md Cloud pilot has different retention boundaries; see the [privacy policy](/privacy-policy.html#retention).

For a destination without folder sync, use the [local export checklist](/blog/export-health-data-without-the-cloud/) and review backup settings separately.

The Mac app's bundled CLI and MCP features are optional. The [standalone direct iPhone CLI preview](/blog/healthmd-cli-direct-iphone-mcp/) uses a separate setup and trust path; it is not required for this Mac folder export.

<div id="section-what-to-read-next"></div>

<div class="cta-row download-cta">
<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone and Mac</a>
<a class="button secondary" href="/docs/sync/">Review Mac Sync setup</a>
</div>
