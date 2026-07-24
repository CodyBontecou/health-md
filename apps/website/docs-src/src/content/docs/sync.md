---
title: "Mac Sync"
description: "Use the macOS companion as a local destination. Your iPhone captures HealthKit data and settings, then the Mac renders and writes the requested files."
---

## What it is
<p>Mac Sync lets your Mac produce exports without becoming a HealthKit reader. The iPhone remains the source of truth for Apple Health data: it captures the selected daily data and exact settings snapshot, then transfers that job to the Mac. The Mac uses the shared exporters to plan paths, render the requested formats, and write the resulting files into the destination folder you chose.</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Mac Sync export flow">
    <span><strong>iPhone</strong>Captures HealthKit data and snapshots the effective settings.</span>
    <span><strong>Local network</strong>Transfers the versioned job to the nearby Mac app.</span>
    <span><strong>Mac</strong>Renders the selected formats and writes them to the chosen folder.</span>
    <span><strong>Vault</strong>Obsidian, iCloud Drive, or any local folder gets the final export.</span>
  </div>
</div>

## How to enable
<ol>
<li>Install and open the macOS app.</li>
<li>On Mac, choose a destination folder so Health.md has write access.</li>
<li>On iPhone, open the Sync tab and enable Mac connectivity.</li>
<li>Return to the iPhone Export tab, choose <em>Connected Mac</em>, configure the export, and tap Export.</li>
</ol>

## What's transferred
<ul>
<li>A versioned export request describing the date range and effective settings</li>
<li>Progress and capability messages while the iPhone captures HealthKit data</li>
<li>Bounded, checksum-validated frames carrying captured daily data and the exact settings snapshot for file-writing jobs</li>
<li>A structured completion, partial, failure, rejection, or unavailable result</li>
</ul>
<p>No account or remote health-data cloud is required. Nearby sync uses encrypted Multipeer Connectivity; Manual IP/Tailscale uses paired encrypted Network.framework transport. Both devices must be able to reach each other, and the iPhone remains the HealthKit reader.</p>

## When to use it
<div class="options">
<div class="option"><strong>Desktop-only vaults</strong><p>If your Obsidian vault lives only on the Mac, this is the clean path from iPhone HealthKit to Mac files.</p></div>
<div class="option"><strong>Large backfills</strong><p>Keep final files on a desktop disk while the iPhone handles the HealthKit read and export configuration.</p></div>
<div class="option"><strong>Local archive workflows</strong><p>Write directly into folders that are backed up, versioned, or indexed on macOS.</p></div>
</div>

<div class="callout">
<strong>Local network required.</strong>
<p style="margin-top:6px;">Both devices must be nearby and allowed to use local networking. Cellular-only iPhones cannot discover a Mac destination. If readiness says the Mac needs attention, reopen the Mac app and reselect the destination folder.</p>
</div>

## Mac sync and Direct CLI Access are separate

Mac Sync pairs the iPhone with the Health.md Mac app for destination exports and encrypted agent context. Direct CLI Access pairs the iPhone with a command-line installation through a separate trust domain. Direct mode can export raw data or generated files without the Mac app, but it cannot use the Mac encrypted query index or MCP.

See [Direct iPhone CLI](/docs/cli-direct/) before enabling the separate iPhone setting.

## Related

<div class="related">
  <a href="/docs/macos/"><span>Desktop</span>macOS App — Export, Schedule, History on the Mac.</a>
  <a href="/docs/scheduling/"><span>Workflow</span>Scheduling — automate recurring exports.</a>
  <a href="/docs/cli-direct/"><span>Separate trust</span>Direct iPhone CLI — pair a CLI without routing work through the Mac app.</a>
  <a href="/docs/reference/connected-mac-iphone-protocol/"><span>Protocol</span>Connected Mac–iPhone Reference — capabilities, requests, bounded transfer, and results.</a>
</div>
