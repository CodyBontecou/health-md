---
title: "Export"
description: "Export Apple Health data now or on a schedule. Check readiness on the Archive, choose a date range in Export now, and set each automation's destination."
---

<p>On iPhone, Health.md has three tabs, <strong>Archive</strong>, <strong>Automations</strong>, and <strong>Settings</strong>, plus a round <strong>Export now</strong> button. On iPad the tabs move to a sidebar.</p>

## Check readiness on the Archive
<p>The <strong>Archive</strong> calendar shows which health dates each automation has covered. When something blocks exports, a <strong>Needs attention</strong> card at the top names it:</p>
<div class="options">
<div class="option"><strong>Apple Health</strong><p>Health.md shows the app's setup state, not confirmed read access to every category. HealthKit does not reveal denied read permissions. Review categories in Apple Health. Empty results can mean withheld access or no matching data. <a href="/docs/troubleshooting/">Troubleshoot missing data</a>.</p></div>
<div class="option"><strong>Folder</strong><p>Choose or re-pick the folder in <strong>Settings → Folder</strong>. If iOS loses access after a folder moves, Health.md asks you to choose it again; nothing is deleted.</p></div>
</div>

## Choose where an automation exports
<p>Each automation has its own destination. Open <strong>Automations</strong>, choose the automation, then <strong>Output</strong>:</p>

<div class="options">
<div class="option"><strong>Local Folder</strong><p>Writes directly into the folder or Obsidian vault you picked on this device.</p></div>
<div class="option"><strong>Connected Mac</strong><p>Sends captured daily data and an exact settings snapshot to the nearby Mac app. The iPhone reads HealthKit. The Mac renders the selected formats and writes the files.</p></div>
<div class="option"><strong>API Endpoint</strong><p>POSTs a JSON envelope directly from iPhone to a user-configured HTTP(S) endpoint. <a href="/docs/api-endpoint/">See API Endpoint</a>.</p></div>
<div class="option"><strong>Agent Data gateway</strong><p>Uploads each exported file unchanged to your gateway's ingestion endpoint.</p></div>
</div>

## Pick a date range in Export now
<p>Tap <strong>Export now</strong>, choose the automation if you have several, then a range:</p>

<div class="options">
<div class="option"><strong>Yesterday</strong><p>The safest daily-export choice because the day is complete.</p></div>
<div class="option"><strong>7 days / 30 days</strong><p>The last week or month, ending yesterday. Ranges of 30 days or more ask you to confirm first.</p></div>
<div class="option"><strong>Custom</strong><p>Pick start and end dates for a specific range.</p></div>
</div>
<p><strong>Will write</strong> shows the destination and roughly how many files and days the export covers. <strong>Range summary only</strong> writes one roll-up file instead of daily files. Today and All Time remain available in <strong>Automations → All export settings</strong>.</p>

## Preview or Export
<div class="options">
<div class="option"><strong>Preview</strong><p>Shows the files and contents that will be generated before anything is written.</p></div>
<div class="option"><strong>Export</strong><p>Runs the export, shows progress above the tab bar with a Cancel button, and records the outcome in history and on the Archive calendar.</p></div>
</div>

## Choose the Data Detail level

<div class="options">
<div class="option"><strong>Summary</strong><p>Compact daily totals and roll-ups for reading, notes, and dashboards.</p></div>
<div class="option"><strong>Detailed Time-Series</strong><p>Selected timestamped samples and intervals. This level is available on both Apple and Android when the chosen metric exposes suitable detail.</p></div>
<div class="option"><strong>Lossless Health Records</strong><p>The canonical HealthKit source-record archive. This level is Apple-only. Android does not turn Health Connect records into a HealthKit archive.</p></div>
</div>

## What "exporting" actually does
<ol>
<li>For each day in the range, capture selected summary projections. Add compatible samples for Detailed Time-Series. And, for Lossless Health Records, add canonical source records and query diagnostics.</li>
<li>Apply your chosen format (Markdown, Bases, JSON, or CSV) and template.</li>
<li>Write one file per day into <code>{vault}/{subfolder}/</code>, transfer files through the connected Mac workflow, or POST a versioned JSON envelope to your API endpoint.</li>
<li>If <em>Individual Tracking</em> is on, derive selected per-entry Markdown files from the canonical archive for file-based targets.</li>
<li>If <em>Daily Note Injection</em> is on, merge selected summary fields into your daily notes.</li>
</ol>

<p>JSON and CSV can preserve canonical records. Markdown and Bases stay readable and expose compact capture diagnostics rather than embedding the archive. See the <a href="/docs/reference/">complete export reference</a> for exact schemas and omission rules.</p>

## Stop, cancel, and retry

Stopping or cancelling ends only the current attempt. Files and dates already completed stay completed, while unresolved dates remain available to retry. Cancelling a scheduled attempt does not disable its recurring schedule.

## Profiles and trustworthy history

A saved profile freezes its settings and destination for the run. Profile-aware scheduled and automation history rows keep the run-time profile, while history retains a privacy-safe label for the destination actually used. A manual export row may omit the profile name. Later renames and destination changes do not rewrite existing history. If a referenced profile is missing, the operation fails without substituting other settings. See [Export profiles](/docs/export-profiles/).

<div class="callout">
<strong>Unlock behavior.</strong>
<p style="margin-top:6px;">The subscription-enabled iPhone/iPad and Google Play phone releases require active trial, subscription, Lifetime, or preserved permanent access for exports and scheduling. No local free-export allowance remains. The Mac companion and F-Droid included-access build retain their documented exceptions. <a href="/docs/paywall/">See the Paywall page</a> for Apple purchase details.</p>
</div>

## Related

<div class="related">
  <a href="/docs/export-profiles/"><span>Repeatable setups</span>Export Profiles, save independent settings, destinations, schedules, and stable automation IDs.</a>
  <a href="/docs/scheduling/"><span>Daily use</span>Scheduling, automate this so you never tap Export again.</a>
  <a href="/docs/api-endpoint/"><span>Integrate</span>API Endpoint, send selected JSON directly to your own service.</a>
  <a href="/docs/format/"><span>Customize</span>Format Customization, change what each file looks like.</a>
  <a href="/docs/shortcuts/"><span>Power</span>Shortcuts, trigger exports from Siri, automations, or other apps.</a>
  <a href="/docs/reference/"><span>Reference</span>Export Reference, schemas, canonical records, diagnostics, and generated examples.</a>
</div>
