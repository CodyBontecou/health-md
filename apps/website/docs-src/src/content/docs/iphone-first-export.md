---
title: "First iPhone export"
description: "Authorize Apple Health, choose a Files destination, preview Health.md output, run a small first iPhone export, and verify the files that were written."
---

Use this walkthrough to produce a small, verifiable export before changing metrics, formatting, or automation. Health.md reads only the Apple Health categories iOS authorizes and writes generated files into the folder you choose.

<div class="availability available">
<strong>Available now · Health.md for iPhone</strong>
<p>The first export works with the free allowance. Scheduling and other paid capabilities can be configured later.</p>
</div>

## Before you start

You need:

- Health.md installed on an iPhone that contains Apple Health data;
- permission to read at least one Apple Health category;
- a writable Files destination such as iCloud Drive, On My iPhone, or an Obsidian vault.

For the shortest first run, keep the default metrics and Markdown output. Start with **Yesterday** or another one-day range instead of all available history.

## 1. Finish iPhone setup

On first launch, tap **Start Setup** and complete the seven onboarding steps. Authorize the health categories you want, review the sample output, choose a folder in Files, and continue through **Ready**. You can continue with the free allowance when the unlock step appears.

If you already finished onboarding, open the **Export** tab and confirm that Apple Health and the local folder are ready. Use the folder control to replace a missing or inaccessible destination.

<div class="docs-screenshot-grid">
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/onboarding-start.webp" target="_blank" rel="noopener" aria-label="Open the onboarding screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/onboarding-start.webp" width="1206" height="2622" loading="lazy" alt="Health.md onboarding welcome screen at step 1 of 7 with the Start Setup button." />
  </a>
  <figcaption>Start Setup introduces the local archive, scheduled notes, and folder model before requesting access.</figcaption>
</figure>
<figure class="docs-screenshot">
  <a href="/docs/assets/docs/iphone-first-export/export-setup-required.webp" target="_blank" rel="noopener" aria-label="Open the setup-required screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/export-setup-required.webp" width="1206" height="2622" loading="lazy" alt="Health.md Export tab with Health disconnected, Choose Folder available, Local iPhone Folder selected, and date-range buttons." />
  </a>
  <figcaption>The readiness badges make missing Health and folder setup explicit. This simulator capture intentionally shows both requirements incomplete.</figcaption>
</figure>
</div>

## 2. Choose a small export

On the Export tab:

1. Select **Local iPhone Folder** as the target.
2. Choose **Yesterday** or a one-day custom range.
3. Keep the default metric selection for the first run.
4. Keep **Markdown** selected. You can add CSV, JSON, or Obsidian Bases after the basic path succeeds.

A short range makes permissions, empty categories, and destination problems easier to understand. It also avoids treating a long-running first request as a failed export.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/iphone-first-export/metric-selection.webp" target="_blank" rel="noopener" aria-label="Open the metric-selection screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/metric-selection.webp" width="1206" height="2622" loading="lazy" alt="Current Health Metrics screen with an enabled metric count, standard metrics switch, search field, and expandable Sleep, Activity, and Heart categories." />
  </a>
  <figcaption>Metric totals depend on the installed app version and permissions. This controlled simulator state keeps only two metrics enabled so the category controls remain easy to see.</figcaption>
</figure>

## 3. Preview before writing

Tap **Preview**. Preview requires Apple Health access but does not need a writable local folder, so it is useful for separating a read-permission problem from a Files problem.

Check that the preview shows:

- the requested date;
- expected metric names and units;
- explicit missing or unavailable values rather than invented zeroes;
- the selected format and filename structure.

Return to the Export tab if you need to adjust dates, metrics, or formatting.

<figure class="docs-screenshot docs-screenshot-single">
  <a href="/docs/assets/docs/iphone-first-export/export-preview.webp" target="_blank" rel="noopener" aria-label="Open the export-preview screenshot at full size">
    <img src="/docs/assets/docs/iphone-first-export/export-preview.webp" width="1206" height="2622" loading="lazy" alt="Health.md Export Preview showing a one-day Markdown export estimate, the range summary state, destination, and generated filename." />
  </a>
  <figcaption>Preview separates output inspection from writing. This deterministic documentation capture uses sample Health data and explicitly shows that no vault is selected.</figcaption>
</figure>

## 4. Export and verify

Tap **Export Data**. If setup is incomplete, Health.md identifies the missing Health or folder requirement instead of silently starting a partial write.

After completion:

1. Review the in-app result for files written, skipped, or failed.
2. Open the Files app and navigate to the folder you selected.
3. Open one generated file and confirm its date, units, and frontmatter.
4. Keep the result details when troubleshooting; do not infer success from the button returning to idle.

<div class="callout">
<strong>No data for the selected day?</strong>
<p style="margin-top:6px;">Try a day you know contains activity or sleep data, then review Health authorization and metric selection. An empty authorized range is different from a transport or write failure.</p>
</div>

## Next steps

<div class="related">
  <a href="/docs/metrics/"><span>Choose data</span>Search Apple Health metrics and adjust categories or special permissions.</a>
  <a href="/docs/format/"><span>Shape output</span>Configure formats, dates, units, frontmatter, templates, and filenames.</a>
  <a href="/docs/scheduling/"><span>Automate</span>Schedule repeat exports after one manual run is verified.</a>
  <a href="/docs/folder-vault/"><span>Fix a destination</span>Understand Files providers, folder access, and recovery.</a>
</div>
