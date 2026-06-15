---
title: "macOS App"
description: "Native Mac companion for receiving iPhone-configured exports, writing files to desktop folders, checking readiness, reviewing history, and staying available from the menu bar."
---

<p>The Mac app is a local destination and desktop control surface. Apple Health remains on iPhone; the Mac receives export jobs from the iPhone and writes the resulting Markdown, JSON, CSV, or Obsidian Bases files to the destination folder you choose.</p>

## Panes
<div class="options">
<div class="option"><strong>Sync</strong><p>Shows whether the Mac is discoverable and ready for iPhone export jobs.</p></div>
<div class="option"><strong>Destination folder</strong><p>Stores a security-scoped folder bookmark so received files can be written without repeated prompts.</p></div>
<div class="option"><strong>Schedule</strong><p>Keeps Mac-side scheduling and readiness visible. The iPhone still needs to be available to provide HealthKit data.</p></div>
<div class="option"><strong>History</strong><p>Tracks export outcomes, errors, and retry context for desktop-written files.</p></div>
<div class="option"><strong>Settings</strong><p>Shows configuration and folder health for the Mac destination app.</p></div>
<div class="option"><strong>Menu bar</strong><p>Quick access for status, opening the app, opening settings, and staying available in the background.</p></div>
</div>

## Setup
<ol>
<li>Install and open Health.md on Mac.</li>
<li>Pick a destination folder in iCloud Drive, local disk, or an Obsidian vault.</li>
<li>On iPhone, enable Mac connectivity from the Sync tab.</li>
<li>On iPhone, choose Connected Mac in the Export tab and configure the export.</li>
<li>Tap Export. The iPhone reads HealthKit and the Mac writes the received files.</li>
</ol>

<div class="callout">
<strong>HealthKit limitation.</strong>
<p style="margin-top:6px;">The Mac app does not read Apple Health directly. Use the iPhone app as the HealthKit source and the Mac app as the local destination.</p>
</div>

## Related

<div class="related">
  <a href="/docs/sync/"><span>Setup</span>Mac Sync — pair iPhone and Mac.</a>
  <a href="/docs/scheduling/"><span>Workflow</span>Scheduling — automate recurring exports.</a>
</div>
