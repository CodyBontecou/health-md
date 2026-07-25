---
title: "Scheduling"
description: "Run exports automatically — daily or weekly, at a time you pick. Uses iOS background tasks plus a scheduled local notification as a fallback when the device is locked."
---

## The Schedule tab
<p>A status screen, not a settings panel. It tells you in one glance:</p>
<ul>
<li>Whether the schedule is on or off</li>
<li>The next scheduled run, if any</li>
<li>The last run's outcome</li>
</ul>
<p>One button — <em>Set Up Schedule</em> (or <em>Manage Schedule</em>) — opens the detail view.</p>

## Schedule settings
<div class="options">
<div class="option"><strong>Enable Scheduled Exports</strong><p>Master toggle at the top. When off, no background runs and no notifications.</p></div>
<div class="option"><strong>Frequency</strong><p>Daily, Weekly, or Monthly. Daily exports cover yesterday; weekly covers the previous 7 days; monthly covers the previous 30.</p></div>
<div class="option"><strong>Time</strong><p>Hour and minute. iOS treats this as a hint, not a guarantee — see the limitations callout below.</p></div>
</div>

## Export history
<p>The list at the bottom of the Schedule screen records every scheduled run with its outcome. Tap a row to see details. Failed runs include a <em>Retry</em> button that re-runs that specific date range.</p>

## How iOS scheduling actually works
<div class="doc-diagram">
  <div class="flow-steps" aria-label="Scheduled export fallback flow">
    <span><strong>1. Target time</strong>Health.md asks iOS to wake the app around your chosen time.</span>
    <span><strong>2. Background attempt</strong>If the device is available, iOS runs a background refresh task.</span>
    <span><strong>3. Locked fallback</strong>If HealthKit is unavailable, Health.md posts a notification.</span>
    <span><strong>4. Tap to finish</strong>Opening the notification lets the app read HealthKit and export.</span>
  </div>
</div>

<div class="callout">
<strong>iOS limitations you should know.</strong>
<p style="margin-top:6px;">HealthKit data isn't readable while the device is locked. Scheduled exports run via <code>BGAppRefreshTask</code>, which iOS opportunistically schedules based on usage patterns — your time setting is a target, not a contract. As a fallback, the app posts a local notification at the scheduled time if the device is locked; tap it to run the export.</p>
</div>
<ul>
<li>The scheduled time is approximate. iOS may run the task earlier, later, or skip it if the device is dead/disconnected.</li>
<li>Scheduled exports work best when your phone is regularly plugged in and unlocked at roughly the same time each day.</li>
<li>If the export fails because the device was locked, tap the notification — that runs the export with HealthKit access.</li>
</ul>

## Programmatic control
<p>You can turn the schedule on/off from Shortcuts using the <em>Turn Scheduled Export On or Off</em> intent. <a href="/docs/shortcuts/">See Shortcuts</a> for examples.</p>

## Related

<div class="related">
  <a href="/docs/export/"><span>Manual</span>Export — for one-off date ranges.</a>
  <a href="/docs/shortcuts/"><span>Automate</span>Shortcuts — toggle the schedule from automations.</a>
  <a href="/docs/sync/"><span>Cross-device</span>Mac Sync — schedule on Mac too.</a>
</div>
