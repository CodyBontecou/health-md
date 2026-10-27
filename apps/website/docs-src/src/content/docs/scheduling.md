---
title: "Schedule Apple Health exports and troubleshoot missed runs"
description: "Verify a scheduled export, understand completed-day lookback, and recover pending dates. iPhone background timing is best-effort; history Retry uses current settings."
---

This page describes iPhone scheduling. Android has different background permissions and purchase requirements; see [Android automation](/docs/android/).

## Verify the first scheduled export

1. Activate the intended profile. Check its metrics, formats, Data Detail, write behavior and destination. Run one completed day manually and inspect the saved file or endpoint result before enabling automation.
2. Open Schedule, then Set Up Schedule or Manage Schedule. Enable the schedule, choose Daily, Weekly or Custom, set the time, and start with a one-day completed-day lookback. Allow notifications if you want local recovery reminders.
3. Check whether scheduling is enabled, the next occurrence and the last result. After an attempt, inspect its history details and the actual destination; a next-run label or notification is not proof that data was written.
4. Check the exported dates, units, coverage and missing data. A saved file does not by itself prove complete source capture.

On Apple, a scheduled request that exports at least one date shares the five free export actions with manual and other counted exports. Full Access removes that shared limit. See [unlock and paywall](/docs/paywall/).

## Understand the completed-day window

Daily, Weekly and Custom schedules can have a lookback. Custom cadence repeats every N days, weeks or months from its start date. Each new occurrence re-exports the entire configured completed-day window, including dates exported before. A three-day lookback covers yesterday and the two preceding days; delayed execution keeps the window anchored to the scheduled fire day.

Today Refresh is separate current-day work, not a replacement for the completed-day window. Inspect paths and write behavior before overlapping exports; do not add repeated daily snapshots together as new measurements.

## Choose the correct recovery path

- **Pending scheduled recovery:** unlock the iPhone, open Health.md and inspect the pending attempt. It retains its exact unresolved dates, saved settings and destination. Completed dates remain completed; recovery does not expand into a new lookback.
- **Retry from history:** this starts a new run for that range using the currently configured settings and destination and records a new history row. Check the active configuration before pressing Retry. It is not the same as resuming a frozen pending attempt.
- **Changed or unavailable destination:** restore access or inspect the pending profile before trying again. An old iPhone API recovery must not silently adopt a changed endpoint or credential. Do not repeatedly start new retries while the original attempt is unresolved.

Review pending recovery, profile identity and destination rules in [Export profiles](/docs/export-profiles/).

## What iOS does and does not guarantee

The selected time is a target, not a guaranteed completion time. iOS controls background runtime, and locked-device protection can prevent HealthKit reads. Background requests and silent wake notifications do not bypass that protection.

Local recovery notifications require notification permission and are not a guarantee of delivery at the target time. If you receive one, unlock the device and open it to let Health.md attempt recovery. If no notification arrives, open Health.md and check pending work and history. Verify the result rather than assuming that an alert or elapsed time means success.

## Programmatic control
<p>You can turn the schedule on/off from Shortcuts using the <em>Turn Scheduled Export On or Off</em> intent. <a href="/docs/shortcuts/">See Shortcuts</a> for examples.</p>

## Profile schedules and cancellation

- Every profile can keep its own schedule, including a custom cadence. Switching the active profile does not retarget another profile's schedule.
- A collision warning appears when profiles could write the same rendered paths at the same destination. Review it before enabling competing schedules. Health.md does not silently change either profile.
- Stop or Cancel ends only the current attempt. Completed dates stay completed, unresolved dates remain retryable, and the schedule stays enabled.
- Each history row remains pinned to the run-time profile and the privacy-safe destination label actually used.

Manage the frozen settings and per-profile destination in [Export profiles](/docs/export-profiles/).

## Related

<div class="related">
  <a href="/docs/export-profiles/"><span>Multiple workflows</span>Export Profiles, give each saved setup its own destination and cadence.</a>
  <a href="/docs/export/"><span>Manual</span>Export, for one-off date ranges.</a>
  <a href="/docs/shortcuts/"><span>Automate</span>Shortcuts, toggle the schedule from automations.</a>
  <a href="/docs/sync/"><span>Cross-device</span>Mac Sync, schedule on Mac too.</a>
</div>
