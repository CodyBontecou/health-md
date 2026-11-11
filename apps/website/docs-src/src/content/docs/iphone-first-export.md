---
title: "First iPhone export"
description: "Authorize Apple Health, choose a Files destination, preview Health.md output, run a small first iPhone export, and verify the files that were written."
---

Use this procedure to export one day before you change metrics, formats, or automation. Health.md reads only the Apple Health categories that you authorize.

Health.md writes the files to the folder that you select.

<div class="availability available">
<strong>Available now · Health.md for iPhone</strong>
<p>Exports need an active trial, subscription, or Lifetime access. You can set up schedules and other automations later.</p>
</div>

## Before you start

Before you start, make sure that you have:

- [Health.md from the App Store](https://apps.apple.com/app/health-md/id6757763969), installed on an iPhone that contains Apple Health data
- Permission to read at least one Apple Health category
- A writable Files folder in iCloud Drive, On My iPhone, or an Obsidian vault.

Keep the default metrics and the Markdown format. Select **Yesterday** for a one-day range.

## 1. Finish iPhone setup

Health.md shows five setup steps. None of them blocks progress: Apple Health access and the folder can be skipped and repaired later.

On the first launch, tap **Connect Apple Health**. Authorize the health categories that you want. Review the sample output. Select a folder in Files. Continue to the last step.

After setup, the app opens on **Archive**. If Apple Health or the folder needs attention, the **Needs attention** card at the top says what to fix.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Open the onboarding screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Health.md setup screen at step 1 of 5 listing three steps, with the Connect Apple Health button." />
  </a>
  <figcaption>Setup explains what Health.md reads and where files go before it requests access.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-now.webp" target="_blank" rel="noopener" aria-label="Open the Export now screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/export-now.webp" width="1206" height="2622" loading="lazy" alt="Health.md Export now sheet with Yesterday selected, a Range summary only switch, a Will write summary for one file and one day, and an Export yesterday button." />
  </a>
  <figcaption>Export now shows what it will write before you start.</figcaption>
</figure>
</div>

## 2. Choose a small export

Tap the round **Export now** button next to the tab bar. Then:

1. Select **Yesterday**.
2. Leave **Range summary only** off.
3. Check that **Will write** names your folder and about one file for one day.

The default automation keeps the default metric selection and **Markdown**. To change them, open **Automations**, choose the automation, then **Metrics** or **Formats**. Add CSV, JSON, or Obsidian Bases after this export succeeds. A short range makes permission, empty-data, and folder problems easier to find.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Open the metric-selection screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Health.md Metrics page with the enabled metric count, Recommended, Select All and Deselect All buttons, a search field, and categories with enabled counts." />
  </a>
  <figcaption>Metric totals depend on the app version and permissions.</figcaption>
</figure>

## 3. Preview before writing

In **Export now**, tap **Preview**. Preview needs Apple Health access. It does not need a writable folder.

Use Preview to identify an Apple Health permission problem before you test the folder.

Make sure that the preview shows:

- The requested date
- The expected metric names and units
- Missing or unavailable values instead of false zero values
- The selected format and filename structure.

Close the preview and change the automation's settings if you must change metrics or formats.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Open the export-preview screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Health.md Export Preview showing the sleep window, a one-day Markdown estimate, the roll-up period, the destination folder, and the generated filename." />
  </a>
  <figcaption>This example uses sample health data.</figcaption>
</figure>

## 4. Export and verify

Tap **Export yesterday**. If setup is incomplete, Health.md identifies the missing Apple Health or folder requirement.

After the export completes:

1. Review the result for written, skipped, or failed files. The day appears on the **Archive** calendar.
2. Open the Files app and the selected folder.
3. Open one generated file. Make sure that its date, units, and frontmatter are correct.
4. Keep the result details if you must investigate a problem.

A covered day on the calendar is a summary; tap the day to see each automation's status for that date.

<div class="callout">
<strong>No data for the selected day?</strong>
<p style="margin-top:6px;">Select a day that has activity or sleep data. Then check Apple Health authorization and metric selection. An empty range is not a write failure.</p>
</div>

## Next steps

<div class="related">
  <a href="/docs/metrics/"><span>Choose data</span>Search metrics and change categories or permissions.</a>
  <a href="/docs/format/"><span>Shape output</span>Set formats, dates, units, frontmatter, templates, and filenames.</a>
  <a href="/docs/scheduling/"><span>Automate</span>Schedule exports after you verify a manual export.</a>
  <a href="/docs/folder-vault/"><span>Fix a destination</span>Review Files providers, folder access, and recovery.</a>
</div>
