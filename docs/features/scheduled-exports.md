# Scheduled Exports

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Schedule
- **Source files:** `HealthMd/iOS/Views/ScheduleSettingsView.swift`, `HealthMd/iOS/SchedulingManager.swift`, `HealthMd/Shared/Models/ExportSchedule.swift`, `HealthMd/Shared/Managers/PushRegistrationManager.swift`, worker in `../worker/`

## What it does

Scheduled Exports let Health.md automatically export recent Apple Health data on a daily or weekly schedule. The user chooses a frequency and time of day. Health.md then writes the selected export formats to the chosen iPhone vault/folder using the same export settings as a manual iPhone-folder export.

Connected Mac is a manual export target only. Scheduled exports do not wake the Mac or send Mac-target jobs; use the iPhone Export tab and choose **Connected Mac** when you want files written to the Mac destination folder.

The schedule is designed for “set it and forget it” Obsidian health journaling: wake up, open your vault, and yesterday’s health data is already there.

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
- Notification permission granted when prompted.
- The iPhone should be unlocked at the scheduled time for HealthKit reads to succeed.

## Setup

1. Go to **Schedule**.
2. Enable **Scheduled Exports**.
3. Accept notification permissions.
4. Choose **Daily** or **Weekly**.
5. Choose the time using the hour, minute, and AM/PM controls.
6. Confirm the **Next export** message in the Schedule tab.

## What gets exported

Scheduled exports use the same iPhone configuration as manual exports:

- selected metrics from **Export → Health Metrics**;
- selected formats: Markdown, Obsidian Bases, JSON, CSV;
- filename and folder templates;
- write mode: overwrite, append, or update;
- daily note injection, if enabled;
- individual entry tracking, if enabled;
- time-series data, if enabled.

The scheduled run exports the configured window ending with yesterday. Today is excluded because the day is still incomplete. The destination is always the selected iPhone folder, even if the manual Export tab is currently set to **Connected Mac**.

Examples:

| Frequency | Scheduled run writes |
|---|---|
| Daily | Yesterday |
| Weekly | The previous 7 complete days |

## Locked-device behavior

iOS protects HealthKit data while the phone is locked. If a scheduled export fires while the iPhone is locked, Health.md cannot read Apple Health data at that moment.

Expected behavior:

1. The scheduled trigger arrives.
2. Health.md attempts the export.
3. If the device is locked, the export fails through the device-locked path.
4. Health.md sends a notification.
5. The user taps the notification after unlocking the phone.
6. Health.md retries the full scheduled export window (yesterday for daily, the previous 7 complete days for weekly).

This is an iOS privacy/security constraint, not a Health.md bug.

## Scheduling architecture

Health.md uses two scheduling layers:

1. **On-device background support** via iOS background tasks and HealthKit background delivery.
2. **Server-driven silent push** via the Health.md worker so schedules can be triggered at the selected minute.

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
| Scheduled export did not write files | iPhone was locked, no vault access, or no HealthKit data | Unlock the phone and tap the retry notification or retry from Export History. |
| No notification appeared | Notification permission denied | Enable notifications for Health.md in iOS Settings. |
| Export ran but missed some days | Some dates had no data or failed individually | Open Export History and inspect/retry the failed entry. |
| Files went to the wrong folder | Scheduled exports always write to the selected iPhone folder using Export tab templates | Check Export tab path preview, subfolder, filename, and folder organization. Use manual Connected Mac export for Mac destination writes. |
| Schedule time feels unreliable | iOS background execution and silent push delivery are not absolute guarantees | Verify Export History and retry failed dates when prompted. |
| Free export limit blocks schedule | Full Access not unlocked and free exports exhausted | Unlock Health.md or run fewer test exports before relying on schedule. |

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
  7. Explain locked-device behavior with a simple diagram.
  8. Show Export History and retry.
- **Key screenshot/recording moments:** Schedule toggle, time picker, Next export text, Export History row.
- **CTA / next video:** “Next, we’ll trigger the same export from Apple Shortcuts.”

## Implementation notes

- `ExportSchedule` stores `isEnabled`, `frequency`, `preferredHour`, `preferredMinute`, `weekday`, and `lastExportDate`.
- `ScheduleSettingsView` binds directly to `SchedulingManager.schedule`, so edits persist as they happen.
- `SchedulingManager.schedule.didSet` saves the schedule, registers background work, sets up HealthKit background delivery, registers remote notifications, and mirrors the schedule to the worker.
- `PushRegistrationManager.syncSchedule(...)` sends schedule state to the worker.
- Worker cron runs every minute and sends silent APNs pushes for due schedules.
- Silent-push handling eventually calls the same local iPhone export pipeline through `ExportOrchestrator` and `VaultManager`; it does not send Mac export jobs.
