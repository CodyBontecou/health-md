---
title: "Shortcuts & App Intents"
description: "Eight App Intents let you trigger exports, fetch summaries, and toggle the schedule from Siri, the Shortcuts app, Focus filters, automations, and any other AppIntent-aware host."
---

## Available intents
<div class="options">
<div class="option"><strong>Export Yesterday's Health Data</strong><p>Zero-parameter shortcut. The fast path for &quot;just export yesterday's data and shut up about it.&quot; Same engine as the manual export.</p></div>
<div class="option"><strong>Export Health Data for a Date</strong><p>Single <em>Date</em> parameter. Time-of-day is ignored. Useful in calendar-driven automations.</p></div>
<div class="option"><strong>Export Health Data for Date Range</strong><p><em>Start Date</em> and <em>End Date</em> parameters, inclusive on both ends. Use for backfills.</p></div>
<div class="option"><strong>Export Last N Days of Health Data</strong><p><em>Number of Days</em> parameter (1–366). Ends yesterday. Default 7. Good for &quot;every Sunday, export last 7 days&quot; automations.</p></div>
<div class="option"><strong>Get Health Summary for a Date</strong><p>Returns a structured snapshot — steps, active calories, sleep, heart rate — without writing anything to the vault. Use this in Shortcuts to feed values into other apps.</p></div>
<div class="option"><strong>Get Last Export Status</strong><p>Returns the timestamp, success state, day count, and any failure reason from the most recent recorded export. A locked-device request remains pending until retried, so it is not returned as the current status while pending.</p></div>
<div class="option"><strong>Turn Scheduled Export On or Off</strong><p>Boolean parameter. Use to suspend the schedule (e.g. on vacation Focus) and resume it later.</p></div>
<div class="option"><strong>Export Health Data</strong><p>Generic export — uses the date range from the in-app Export modal's last state. Less common; the date-range variants are usually clearer.</p></div>
</div>

## Where to find them
<p>Open the Shortcuts app on iOS or macOS. Tap the <em>+</em> button to create a new shortcut, search for &quot;Health.md&quot; or any of the intent titles above. They live under the <em>Health</em> category.</p>
<p>Most intents have <code>openAppWhenRun = false</code>, so they execute headlessly — no app launch, no UI flash. They work from automations, Focus filters, the Hey Siri handoff, and the Action Button.</p>

<div class="callout">
<strong>Running while locked does not unlock HealthKit.</strong>
<p style="margin-top:6px;">Apple protects HealthKit data while the iPhone is locked and <a href="https://support.apple.com/guide/security/protecting-access-to-users-health-data-sec88be9900f/web">relinquishes app access about ten minutes after locking</a>. <em>Allow Running When Locked</em> lets Shortcuts start the action, but it does not override HealthKit data protection. The Health.md app-content permission in Shortcuts does not override it either.</p>
<p>If HealthKit is unavailable, Health.md preserves the requested dates as pending and posts a <em>Health Export Needs Attention</em> notification. Unlock the iPhone, then tap the notification or open Health.md to retry. A fully unattended export cannot be guaranteed while the phone remains locked.</p>
</div>

<a id="recipe-nightly-export-with-confirmation"></a>
## Recipe: daily export with confirmation
<ol>
<li><strong>Personal Automation</strong> → <em>Time of Day</em> → choose a time when you normally use your unlocked iPhone, such as 8:00 AM.</li>
<li><em>Export Yesterday's Health Data</em> intent.</li>
<li><em>Get Last Export Status</em> intent.</li>
<li><em>Show Notification</em> with the result.</li>
</ol>
<p><strong>Pending-status note:</strong> <em>Get Last Export Status</em> reads the most recent recorded export-history entry. If this run encountered locked HealthKit data, it may still show the previous export until you retry the pending request. Health.md's own recovery notification is the authoritative signal for pending work.</p>

## Recipe: backfill on a one-off
<ol>
<li>Create a shortcut.</li>
<li><em>Export Health Data for Date Range</em> with start = 2024-01-01, end = 2024-12-31.</li>
<li>Run from Shortcuts. Walks the year, writes one file per day. May take a few minutes for full years.</li>
</ol>

## Recipe: pause schedule on vacation
<ol>
<li><strong>Focus filter</strong>: when <em>Vacation</em> Focus turns on, run <em>Turn Scheduled Export On or Off</em> with Enabled = false.</li>
<li>When Focus turns off, run again with Enabled = true.</li>
</ol>

<div class="callout">
<strong>Authorization required.</strong>
<p style="margin-top:6px;">Intents inherit your in-app HealthKit permission and vault selection. They will fail with a clear error if the app hasn't been opened-and-set-up at least once on this device.</p>
</div>

## Related

<div class="related">
  <a href="/docs/scheduling/"><span>Source</span>Scheduling — the in-app equivalent of the toggle intent.</a>
  <a href="/docs/export/"><span>Source</span>Export — the in-app equivalent of the date-range intents.</a>
</div>
