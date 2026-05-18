# Scheduled Exports

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Schedule
- **Source files:** `HealthMd/iOS/Views/ScheduleSettingsView.swift`, `HealthMd/iOS/SchedulingManager.swift`, `HealthMd/iOS/HealthMdApp.swift`, `HealthMd/iOS/AppIntents/ExportIntentRunner.swift`, `HealthMd/Shared/Models/ExportSchedule.swift`, `HealthMd/Shared/Models/PendingExportRequest.swift`, `HealthMd/Shared/Managers/ScheduledExportCoordinator.swift`, `HealthMd/Shared/Managers/PushRegistrationManager.swift`, `HealthMd/Shared/Notifications/ExportNotificationScheduler.swift`, worker in `../worker/`

## What it does

Scheduled Exports let Health.md automatically export recent Apple Health data on a daily or weekly schedule. The user chooses a frequency, time of day, and lookback window. Health.md then writes the selected export formats to the chosen iPhone vault/folder using the same export settings as a manual iPhone-folder export.

Connected Mac is a manual export target only. Scheduled exports do not wake the Mac or send Mac-target jobs; use the iPhone Export tab and choose **Connected Mac** when you want files written to the Mac destination folder.

The schedule is designed for low-touch Obsidian health journaling. iOS can still delay background work, and HealthKit data is unavailable while the phone is locked, so Health.md also persists pending export work and offers recovery paths when a scheduled run cannot finish immediately.

## Who it is for

- Users who want daily health notes without remembering to tap Export.
- Users who want a weekly catch-up export.
- Users who export to Obsidian Bases and want fresh database rows.
- Users who combine scheduled exports with daily note injection.

Do not rely on this for emergency or medical-grade monitoring. It is an automation convenience built on iOS background execution rules.

## Where to find it

1. Open Health.md.
2. Tap the **Schedule** tab.
3. Turn on **Enable Scheduled Exports**.
4. Choose frequency and time.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected on iPhone.
- At least one export format selected.
- Full Access unlocked for scheduled exports.
- Notification permission granted when prompted for the best recovery experience.
- The iPhone should be unlocked at the scheduled time for the most reliable HealthKit reads.

## Setup

1. Go to **Schedule**.
2. Enable **Scheduled Exports**.
3. Accept notification permissions.
4. Choose **Daily** or **Weekly**.
5. Choose the time using the hour, minute, and AM/PM controls.
6. Choose how many past days to export.
7. Confirm the **Next export** message in the Schedule tab.

## What gets exported

Scheduled exports use the same iPhone configuration as manual exports:

- selected metrics from **Export → Health Metrics**;
- selected formats: Markdown, Obsidian Bases, JSON, CSV;
- filename and folder templates;
- write mode: overwrite, append, or update;
- daily note injection, if enabled;
- individual entry tracking, if enabled;
- time-series data, if enabled.

The scheduled run exports the configured lookback window ending with yesterday. Today is excluded because the day is still incomplete. The destination is always the selected iPhone folder, even if the manual Export tab is currently set to **Connected Mac**.

Examples:

| Frequency | Scheduled run writes |
|---|---|
| Daily default | Yesterday |
| Weekly default | The previous 7 complete days |
| Custom lookback | 1-30 complete days ending yesterday |

## Pending export recovery

Before a scheduled occurrence runs, Health.md creates a persisted pending export request for the exact dates that should be written. That pending request includes:

- the normalized dates to export;
- whether the source is scheduled export or Shortcut export;
- the scheduled fire date for scheduled exports;
- notification payload metadata that points back to the same pending request.

The pending request stays on device in app storage. It is not uploaded to the worker.

When the export succeeds, Health.md clears the pending request and removes the matching recovery notification. If the export cannot read HealthKit because the device is locked, Health.md keeps the same pending request and sends an actionable notification. Tapping that notification after unlocking the phone retries the stored dates instead of recalculating a new window.

Opening the app also drains pending work. Scheduled pending requests drain while scheduling is still enabled. Shortcut pending requests drain even if the scheduled-export toggle is off, because they came from an explicit Shortcut run.

## Locked-device behavior

iOS protects HealthKit data while the phone is locked. If a scheduled export fires while the iPhone is locked, Health.md cannot read Apple Health data at that moment.

Expected behavior:

1. The scheduled trigger arrives.
2. Health.md persists the exact scheduled export dates as pending work.
3. Health.md attempts the export.
4. If the device is locked, the export fails through the device-locked path.
5. Health.md keeps the pending request and sends a recovery notification when notifications are allowed.
6. The user unlocks the phone and taps the notification, or simply opens Health.md.
7. Health.md retries the exact pending dates.

This is an iOS privacy/security constraint, not a Health.md bug.

If notification permission is denied, Health.md cannot show the visible tap-to-retry notification and may skip APNs registration for server silent pushes. The pending request still remains on device, and opening the app can drain it once HealthKit data is readable again.

## Scheduling architecture

Health.md uses two scheduling layers:

1. **On-device background support** via iOS background tasks, HealthKit background delivery, and app-open catch-up.
2. **Server-driven silent push** via the Health.md worker so schedules have an additional timing signal near the selected minute.

The worker stores scheduling metadata, not health data.

The worker may store:

- APNs token;
- app/user installation identifier;
- platform;
- schedule frequency;
- hour/minute/weekday;
- timezone;
- next fire time.

The worker does **not** store:

- HealthKit samples;
- exported Markdown/JSON/CSV files;
- Obsidian vault contents;
- personal health metrics.

Silent push is best-effort. It can help Health.md wake closer to the chosen schedule time, but it does not guarantee delivery, does not guarantee iOS will grant enough background runtime, does not show a visible lock-screen alert by itself, and cannot bypass protected HealthKit data while the device is locked. Local pending requests, recovery notifications, and app-open drain are the recovery layer when a silent push, background task, or HealthKit background delivery cannot complete the export.

Duplicate triggers for the same scheduled occurrence reuse the same pending request. Health.md also tracks in-flight pending request IDs so a notification tap and app-open drain do not run the same pending export twice at the same time.

## Shortcuts and pending exports

Health.md Shortcuts use the same iPhone-folder export pipeline as manual iPhone exports. If a Shortcut export hits the device-locked HealthKit path, the Shortcut does not hard-fail the user-requested dates. Instead, Health.md:

1. persists a pending Shortcut export request for the exact requested dates;
2. sends the same actionable pending export notification when possible;
3. returns a pending dialog telling the user to unlock the phone and tap the Health.md notification;
4. avoids consuming export quota, updating scheduled export bookkeeping, or recording a failed export history row for that locked attempt.

Tapping the pending notification retries the exact Shortcut dates. Opening Health.md also drains pending Shortcut work.

## Export history and retry

The Schedule tab also shows recent export history. Tapping a history entry opens details and supports retrying failed dates.

Use this when:

- the phone was locked at the scheduled time;
- HealthKit had no data for a date;
- the vault/folder was unavailable;
- a multi-day export partially succeeded.

## Tips

- Start with **Daily** for a simple daily note workflow.
- Use **Weekly** if you only review health data once per week.
- Keep the iPhone charging and unlocked near the scheduled time for the most reliable automation.
- Pair scheduled exports with **Daily Note Injection** or **Obsidian Bases** for the strongest Obsidian workflows.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Scheduled export did not write files | iPhone was locked, iOS delayed background work, no vault access, or no HealthKit data | Unlock the phone and tap the recovery notification, open Health.md to drain pending work, or retry from Export History. |
| No notification appeared | Notification permission denied, iOS suppressed background notification delivery, or the schedule did not reach a runnable background window | Enable notifications for Health.md in iOS Settings and open Health.md to drain pending/catch-up work. |
| Export ran but missed some days | Some dates had no data or failed individually | Open Export History and inspect/retry the failed entry. |
| Files went to the wrong folder | Scheduled exports always write to the selected iPhone folder using Export tab templates | Check Export tab path preview, subfolder, filename, and folder organization. Use manual Connected Mac export for Mac destination writes. |
| Schedule time feels unreliable | iOS background execution and silent push delivery are not absolute guarantees | Verify Export History, open the app to run catch-up, and retry pending dates when prompted. |
| Free export limit blocks schedule | Full Access not unlocked and free exports exhausted | Unlock Health.md or run fewer test exports before relying on schedule. |
| Shortcut says pending | The Shortcut ran while HealthKit was protected by device lock | Unlock the phone and tap the Health.md notification, or open Health.md to drain the pending Shortcut export. |

## Video outline

- **Suggested title:** Automate Apple Health Exports to Obsidian with Health.md
- **Hook:** “You shouldn’t have to remember to export yesterday’s Apple Health data every morning.”
- **Demo flow:**
  1. Show an Obsidian vault before automation.
  2. Open Health.md → Schedule.
  3. Enable scheduled exports and accept notification permission.
  4. Configure Daily and a specific time.
  5. Show that it uses the same metrics/formats/folder settings from the Export tab.
  6. Call out that Connected Mac is manual-only and schedules write to the iPhone folder.
  7. Explain pending export recovery and locked-device behavior with a simple diagram.
  8. Show notification-tap recovery and app-open catch-up.
  9. Show Export History and retry.
- **Key screenshot/recording moments:** Schedule toggle, time picker, Next export text, Export History row.
- **CTA / next video:** “Next, we’ll trigger the same export from Apple Shortcuts.”

## Implementation notes

- `ExportSchedule` stores `isEnabled`, `frequency`, `preferredHour`, `preferredMinute`, `weekday`, and `lastExportDate`.
- `ExportSchedule.lookbackDays` stores the number of complete past days to export, clamped to 1-30.
- `ScheduleSettingsView` binds directly to `SchedulingManager.schedule`, so edits persist as they happen.
- `SchedulingManager.schedule.didSet` saves the schedule, registers background work, sets up HealthKit background delivery, registers remote notifications, and mirrors the schedule to the worker.
- `PushRegistrationManager.syncSchedule(...)` sends schedule state to the worker.
- Worker cron runs every minute and sends silent APNs pushes for due schedules.
- `ScheduledExportCoordinator` creates and completes persisted `PendingExportRequest` records for scheduled occurrences.
- `ExportNotificationScheduler` uses deterministic `healthmd.pending-export.<request-id>` notification identifiers so pending notifications can be replaced or cancelled.
- `HealthMdApp` drains pending exports when the app becomes active and routes pending export notification taps back to `SchedulingManager`.
- Silent-push handling eventually calls the same local iPhone export pipeline through `ExportOrchestrator` and `VaultManager`; it does not send Mac export jobs.
