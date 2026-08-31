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
<div class="option"><strong>Connected Mac</strong><p>Sends captured daily data and an exact settings snapshot to the nearby Mac app. The iPhone reads HealthKit; the Mac renders the selected formats and writes the files.</p></div>
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

## Choose the Data Detail level

<div class="options">
<div class="option"><strong>Summary</strong><p>Compact daily totals and roll-ups for reading, notes, and dashboards.</p></div>
<div class="option"><strong>Detailed Time-Series</strong><p>Selected timestamped samples and intervals. This level is available on both Apple and Android when the chosen metric exposes suitable detail.</p></div>
<div class="option"><strong>Lossless Health Records</strong><p>The canonical HealthKit source-record archive. This level is Apple-only; Android does not turn Health Connect records into a HealthKit archive.</p></div>
</div>

## What "exporting" actually does
<ol>
<li>For each day in the range, capture selected summary projections; add compatible samples for Detailed Time-Series; and, for Lossless Health Records, add canonical source records and query diagnostics.</li>
<li>Apply your chosen format (Markdown, Bases, JSON, or CSV) and template.</li>
<li>Write one file per day into <code>{vault}/{subfolder}/</code>, transfer files through the connected Mac workflow, or POST a versioned JSON envelope to your API endpoint.</li>
<li>If <em>Individual Tracking</em> is on, derive selected per-entry Markdown files from the canonical archive for file-based targets.</li>
<li>If <em>Daily Note Injection</em> is on, merge selected summary fields into your daily notes.</li>
</ol>

<p>JSON and CSV can preserve canonical records. Markdown and Bases stay readable and expose compact capture diagnostics rather than embedding the archive. See the <a href="/docs/reference/">complete export reference</a> for exact schemas and omission rules.</p>

## Stop, cancel, and retry

Stopping or cancelling ends only the current attempt. Files and dates already completed stay completed, while unresolved dates remain available to retry. Cancelling a scheduled attempt does not disable its recurring schedule.

## Profiles and trustworthy history

A saved profile freezes its settings and destination for the run. Profile-aware scheduled and automation history rows keep the run-time profile, while history retains a privacy-safe label for the destination actually used. A manual Export-tab row may omit the profile name. Later renames and destination changes do not rewrite existing history. Missing profile references fail closed instead of falling back. See [Export profiles](/docs/export-profiles/).

## Tab bar

<p>The four tabs at the bottom of the screen — Export, Schedule, Sync, Settings — cover the entire app surface area. Everything else lives one or two layers deep inside Settings.</p>

<div class="callout">
<strong>Unlock behavior.</strong>
<p style="margin-top:6px;">On Apple platforms, the free allowance covers 10 manual or scheduled export actions. Full Access removes that limit and unlocks Mac destination workflows and Shortcuts. Android instead offers 10 free manual actions and requires its lifetime unlock for scheduling. <a href="/docs/paywall/">See the Paywall page</a> for Apple purchase details.</p>
</div>

## Related

<div class="related">
  <a href="/docs/export-profiles/"><span>Repeatable setups</span>Export Profiles — save independent settings, destinations, schedules, and stable automation IDs.</a>
  <a href="/docs/scheduling/"><span>Daily use</span>Scheduling — automate this so you never tap Export again.</a>
  <a href="/docs/api-endpoint/"><span>Integrate</span>API Endpoint — send selected JSON directly to your own service.</a>
  <a href="/docs/format/"><span>Customize</span>Format Customization — change what each file looks like.</a>
  <a href="/docs/shortcuts/"><span>Power</span>Shortcuts — trigger exports from Siri, automations, or other apps.</a>
  <a href="/docs/reference/"><span>Reference</span>Export Reference — schemas, canonical records, diagnostics, and generated examples.</a>
</div>
