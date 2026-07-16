---
title: "macOS App"
description: "Native Mac companion for rendering iPhone-captured export jobs, writing files to desktop folders, checking readiness, and reviewing history."
---

<p>The Mac app is a local destination and desktop control surface. Apple Health remains on iPhone; the Mac receives captured daily data plus the exact iPhone settings snapshot, renders Markdown, JSON, CSV, Obsidian Bases, and related outputs with the shared exporters, then writes them to the destination folder you choose.</p>

## Panes
<div class="options">
<div class="option"><strong>Sync</strong><p>Shows whether the Mac is discoverable and ready for iPhone export jobs.</p></div>
<div class="option"><strong>Destination folder</strong><p>Stores a security-scoped folder bookmark so Mac-rendered outputs can be written without repeated prompts.</p></div>
<div class="option"><strong>Schedule</strong><p>Keeps Mac-side scheduling and readiness visible. The iPhone still needs to be available to provide HealthKit data.</p></div>
<div class="option"><strong>History</strong><p>Tracks export outcomes, errors, and retry context for desktop-written files.</p></div>
<div class="option"><strong>Settings</strong><p>Shows configuration and folder health for the Mac destination app.</p></div>
<div class="option"><strong>Menu bar</strong><p>Quick access for status, opening the app, opening settings, and staying available in the background.</p></div>
<div class="option"><strong>CLI</strong><p>Install the bundled <code>healthmd</code> command, copy agent setup prompts, check readiness, and trigger iPhone exports from Terminal.</p></div>
</div>

## Setup
<ol>
<li>Install and open Health.md on Mac.</li>
<li>Pick a destination folder in iCloud Drive, local disk, or an Obsidian vault.</li>
<li>On iPhone, enable Mac connectivity from the Sync tab.</li>
<li>On iPhone, choose Connected Mac in the Export tab and configure the export.</li>
<li>Tap Export. The iPhone captures HealthKit data; the Mac renders and writes the requested files.</li>
</ol>

<div class="callout">
<strong>HealthKit limitation.</strong>
<p style="margin-top:6px;">The Mac app does not read Apple Health directly. Use the iPhone app as the HealthKit source and the Mac app as the local destination.</p>
</div>

## Related

<div class="related">
  <a href="/docs/sync/"><span>Setup</span>Mac Sync — pair iPhone and Mac.</a>
  <a href="/docs/cli/"><span>Terminal</span>CLI Setup — install <code>healthmd</code> and run exports from Terminal.</a>
  <a href="/docs/scheduling/"><span>Workflow</span>Scheduling — automate recurring exports.</a>
</div>
