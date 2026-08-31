---
title: "Export profiles"
description: "Save export settings and a destination together, then run or schedule that setup from iPhone, Android, Shortcuts, the CLI, Tasker, or adb."
---

Export profiles keep a repeatable export setup together. Manage them in Health.md on iPhone or Android. On Apple platforms, the current management workflow is documented and tested on iPhone only; no iPad or Mac management surface is claimed.

## Manage and edit profiles

Open **Settings → Export Profiles**. The list marks the active profile and lets you create, rename, duplicate, delete, activate, or inspect profiles. Open a profile's detail view to copy its stable ID. The last remaining profile cannot be deleted.

The Export tab edits the active profile. Activate another profile before changing export settings if you do not want to update the current one.

Each profile freezes the choices needed to reproduce a run:

- selected metrics, Data Detail, formats, templates, filenames, units, and write behavior;
- its own folder destination and subfolder, API endpoint, or Connected Mac target where that platform supports it;
- daily-note, individual-entry, roll-up, and other output choices supported by that platform.

A schedule is bound separately to the profile's stable identity. Switching the active profile does not retarget that schedule. A profile run uses the saved snapshot instead of borrowing changed settings from another profile.

## Run and schedule safely

- A profile can have its own recurring schedule, including the custom cadence offered by the app.
- Platform entitlement still applies: Apple's free allowance can include scheduled actions, while Android scheduling requires the lifetime unlock.
- Health.md warns when profiles could write the same rendered paths at the same destination. The warning does not silently change either profile or schedule.
- Stopping or cancelling affects only the current attempt. Dates already completed stay completed, unresolved dates remain retryable, and the recurring schedule stays enabled.
- If a referenced profile is missing, Health.md fails closed. It never falls back to the active profile or another destination.

## Names, stable IDs, and automation

A display name is for people and may change. A profile's stable ID is for rename-safe automation. Copy it from **Settings → Export Profiles → Profile ID**.

- Apple Shortcuts select a profile by display name; an empty profile parameter uses the active profile.
- Android Tasker and adb broadcasts can supply the `PROFILE` extra with a stable ID or name. Prefer the ID for workflows that must survive renames.
- The direct CLI accepts `--profile PROFILE_ID` for supported generated-file jobs. The profile supplies its frozen output settings; the required `--destination` still selects the existing folder on the computer.

Review the platform automation guide before enabling an unattended workflow.

## History, recovery, and privacy

Profile-aware scheduled and automation history rows record the run-time profile. History also retains a privacy-safe label for the destination actually used. A manual Export-tab run may not attach a profile name even though it uses the active profile's settings. Later renaming a profile, changing its destination, or selecting another profile does not rewrite existing history.

A retry started from export history uses the currently configured settings and destination, then records a new row with what it actually used. It does not pretend the original profile governed the retry. By contrast, recovery or resume of an unresolved scheduled attempt retains that attempt's exact dates, settings, and destination.

Profiles and schedules are device-local settings. They do not sync between iPhone, iPad, Mac, and Android. Recreate the intended setup on each device and verify its destination before enabling automation.

## Related

<div class="related">
  <a href="/docs/export/"><span>Export</span>Choose Data Detail, preview output, and run a date range.</a>
  <a href="/docs/scheduling/"><span>Scheduling</span>Understand profile cadences, recovery, and platform timing limits.</a>
  <a href="/docs/shortcuts/"><span>Shortcuts</span>Select a saved profile in Apple automations.</a>
  <a href="/docs/android/"><span>Android automation</span>Use profile-aware Tasker and adb actions.</a>
  <a href="/docs/cli-direct/"><span>Direct CLI</span>Run a profile's saved output settings into an explicit computer folder.</a>
</div>
