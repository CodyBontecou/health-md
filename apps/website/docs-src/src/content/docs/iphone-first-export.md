---
title: "First iPhone export"
description: "Authorize Apple Health, choose a Files destination, preview Health.md output, run a small first iPhone export, and verify the files that were written."
---

Use this procedure to export one day before you change metrics, formats, or automation. Health.md reads only the Apple Health categories that you authorize.

Health.md writes the files to the folder that you select.

<div class="availability available">
<strong>Available now · Health.md for iPhone</strong>
<p>The first export uses the free allowance. You can configure schedules and paid features later.</p>
</div>

## Before you start

Before you start, make sure that you have:

- Health.md on an iPhone that contains Apple Health data
- Permission to read at least one Apple Health category
- A writable Files folder in iCloud Drive, On My iPhone, or an Obsidian vault.

Keep the default metrics and the Markdown format. Select **Yesterday** or a different one-day range.

## 1. Finish iPhone setup

Health.md shows seven onboarding screens.

On the first launch, tap **Start Setup**. Authorize the health categories that you want. Review the sample output. Select a folder in Files. Continue to **Ready**. At the unlock step, continue with the free allowance.

If setup is complete, open the **Export** tab. Make sure that Apple Health and the local folder are ready.

If the folder is missing or unavailable, use the folder control to select it again.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Open the onboarding screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Health.md onboarding welcome screen at step 1 of 7 with the Start Setup button." />
  </a>
  <figcaption>Start Setup explains local files, schedules, and folders before it requests access.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="Open the setup-required screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Health.md Export tab with Health disconnected, Choose Folder available, Local iPhone Folder selected, and date-range buttons." />
  </a>
  <figcaption>The badges show that Apple Health and folder setup are incomplete.</figcaption>
</figure>
</div>

## 2. Choose a small export

On the **Export** tab:

1. Select **Local iPhone Folder** as the target.
2. Select **Yesterday** or a custom one-day range.
3. Keep the default metric selection.
4. Keep **Markdown** selected.

Add CSV, JSON, or Obsidian Bases after this export succeeds. A short range makes permission, empty-data, and folder problems easier to find.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Open the metric-selection screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Current Health Metrics screen with an enabled metric count, standard metrics switch, search field, and expandable Sleep, Activity, and Heart categories." />
  </a>
  <figcaption>Metric totals depend on the app version and permissions. This example has two enabled metrics.</figcaption>
</figure>

## 3. Preview before writing

Tap **Preview**. Preview needs Apple Health access. It does not need a writable folder.

Use Preview to identify an Apple Health permission problem before you test the folder.

Make sure that the preview shows:

- The requested date
- The expected metric names and units
- Missing or unavailable values instead of false zero values
- The selected format and filename structure.

Return to the **Export** tab if you must change dates, metrics, or formats.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Open the export-preview screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Health.md Export Preview showing a one-day Markdown export estimate, roll-up periods, destination, and generated filename." />
  </a>
  <figcaption>This example uses sample health data. It shows that no vault is selected.</figcaption>
</figure>

## 4. Export and verify

Tap **Export Data**. If setup is incomplete, Health.md identifies the missing Apple Health or folder requirement.

After the export completes:

1. Review the result for written, skipped, or failed files.
2. Open the Files app and the selected folder.
3. Open one generated file. Make sure that its date, units, and frontmatter are correct.
4. Keep the result details if you must investigate a problem.

An idle export button does not show that an export succeeded.

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
