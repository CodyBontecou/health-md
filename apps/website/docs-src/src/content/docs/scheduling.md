---
title: "Scheduling"
description: "Run exports automatically on daily, weekly, or custom calendar cadences. iOS uses background tasks plus a local recovery notification when protected data is unavailable."
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
<div class="option"><strong>Frequency</strong><p>Daily, Weekly, or Custom. Custom schedules repeat every N days, weeks, or months from a chosen start date. The lookback controls how many completed days each run covers.</p></div>
<div class="option"><strong>Time</strong><p>Hour and minute. iOS treats this as a hint, not a guarantee — see the limitations callout below.</p></div>
</div>

## Export history
<p>The list at the bottom of the Schedule screen records every scheduled run with its outcome. Tap a row to see details. Failed runs include a <em>Retry</em> button that re-runs that date range with the currently configured settings and destination, then records a new history row.</p>

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

## Profile schedules and cancellation

- Every profile can keep its own schedule, including a custom cadence; switching the active profile does not retarget another profile's schedule.
- A collision warning appears when profiles could write the same rendered paths at the same destination. Review it before enabling competing schedules; Health.md does not silently change either profile.
- Stop or Cancel ends only the current attempt. Completed dates stay completed, unresolved dates remain retryable, and the schedule stays enabled.
- Each history row remains pinned to the run-time profile and the privacy-safe destination label actually used.

Manage the frozen settings and per-profile destination in [Export profiles](/docs/export-profiles/).

## Related

<div class="related">
  <a href="/docs/export-profiles/"><span>Multiple workflows</span>Export Profiles — give each saved setup its own destination and cadence.</a>
  <a href="/docs/export/"><span>Manual</span>Export — for one-off date ranges.</a>
  <a href="/docs/shortcuts/"><span>Automate</span>Shortcuts — toggle the schedule from automations.</a>
  <a href="/docs/sync/"><span>Cross-device</span>Mac Sync — schedule on Mac too.</a>
</div>
