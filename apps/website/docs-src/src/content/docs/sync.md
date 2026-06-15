---
title: "Mac Sync"
description: "Use the macOS companion app as a local destination for iPhone-configured exports. Your iPhone reads HealthKit, applies your selected settings, then sends the export job to the Mac over nearby-device connectivity."
---

## What it is
<p>Mac Sync lets your Mac receive exports without becoming a HealthKit reader. The iPhone remains the source of truth for Apple Health data, builds the export using your selected metrics, formats, date range, filenames, and write mode, then sends the job to the Mac. The Mac writes the received files into the destination folder you chose.</p>

<div class="doc-diagram">
  <div class="flow-steps" aria-label="Mac Sync export flow">
    <span><strong>iPhone</strong>Reads HealthKit and applies your export settings.</span>
    <span><strong>Local network</strong>Sends the export job to the nearby Mac app.</span>
    <span><strong>Mac</strong>Receives the files and writes them to the chosen folder.</span>
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
<li>The exported files or export job payload for the date range you selected on iPhone</li>
<li>Your metric selection, formats, filenames, folder structure, and write mode</li>
<li>Status and readiness messages from the Mac destination</li>
</ul>
<p>No account or remote health-data cloud is required. Both devices need local-network access and must be able to discover each other.</p>

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

## Related

<div class="related">
  <a href="/docs/macos/"><span>Desktop</span>macOS App — Export, Schedule, History on the Mac.</a>
  <a href="/docs/scheduling/"><span>Workflow</span>Scheduling — automate recurring exports.</a>
</div>
