---
title: "Export"
description: "The Export tab is the main canvas. It shows whether HealthKit and your vault are connected, lets you choose a destination, and runs one-off exports for the date range you choose."
---

<p>The Export tab is organized as three small decisions: confirm readiness, choose a destination, then pick the date range before previewing or exporting.</p>

## Read the status badges
<div class="options">
<div class="option"><strong>Health badge</strong><p>Green dot = HealthKit authorized. Red = not granted. Tap to retry the iOS permission sheet (only works the first time per install — after that, iOS silently does nothing and you have to fix it in Settings → Privacy &amp; Security → Health).</p></div>
<div class="option"><strong>Vault badge</strong><p>Green dot = a vault folder is selected. Tap to re-pick or change the vault. The label shows the folder name.</p></div>
</div>
<p>The <em>Export</em> action stays disabled until HealthKit, output format, and the selected destination are ready. This prevents the most common failure mode: trying to export with no destination.</p>

## Choose an export target
<p>The Export Target card decides where data goes:</p>

<div class="options">
<div class="option"><strong>Local iPhone Folder</strong><p>Writes directly into the folder or Obsidian vault you picked on this device.</p></div>
<div class="option"><strong>Connected Mac</strong><p>Sends the export job to the nearby Mac app. The iPhone still reads HealthKit; the Mac writes the received files.</p></div>
<div class="option"><strong>API Endpoint</strong><p>POSTs a JSON envelope directly from iPhone to a user-configured HTTP(S) endpoint. <a href="/docs/api-endpoint/">See API Endpoint</a>.</p></div>
</div>

## Pick a date range
<p>Date presets cover the common paths:</p>

<div class="options">
<div class="option"><strong>Today</strong><p>Export the current day. Useful for testing output formatting.</p></div>
<div class="option"><strong>Yesterday</strong><p>The safest daily-export choice because the day is complete.</p></div>
<div class="option"><strong>All Time</strong><p>Backfill from the earliest HealthKit data Health.md can find.</p></div>
<div class="option"><strong>Custom</strong><p>Pick start and end dates for a specific range.</p></div>
</div>

## Preview or Export
<div class="options">
<div class="option"><strong>Preview</strong><p>Shows the files and contents that will be generated before anything is written.</p></div>
<div class="option"><strong>Export</strong><p>Runs the export, shows progress on the main screen, and records the outcome in history.</p></div>
</div>

## What "exporting" actually does
<ol>
<li>For each day in the range, query HealthKit for every metric you've enabled.</li>
<li>Apply your chosen format (Markdown, Bases, JSON, or CSV) and template.</li>
<li>Write one file per day into <code>{vault}/{subfolder}/</code>, send the job to the connected Mac, or POST JSON to your API endpoint.</li>
<li>If <em>Individual Tracking</em> is on, also write one file per timestamped entry into the entries folder for file-based targets.</li>
<li>If <em>Daily Note Injection</em> is on, also merge metrics into your daily notes' frontmatter.</li>
</ol>

## Tab bar

<p>The four tabs at the bottom of the screen — Export, Schedule, Sync, Settings — cover the entire app surface area. Everything else lives one or two layers deep inside Settings.</p>

<div class="callout">
<strong>Unlock behavior.</strong>
<p style="margin-top:6px;">Full Access unlocks unlimited export runs, scheduled exports, Mac destinations, and Shortcuts. <a href="/docs/paywall/">See the Paywall page</a> for details.</p>
</div>

## Related

<div class="related">
  <a href="/docs/scheduling/"><span>Daily use</span>Scheduling — automate this so you never tap Export again.</a>
  <a href="/docs/api-endpoint/"><span>Integrate</span>API Endpoint — send selected JSON directly to your own service.</a>
  <a href="/docs/format/"><span>Customize</span>Format Customization — change what each file looks like.</a>
  <a href="/docs/shortcuts/"><span>Power</span>Shortcuts — trigger exports from Siri, automations, or other apps.</a>
</div>
