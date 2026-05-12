# Scheduled Exports

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Schedule
- **Source files:** `HealthMd/iOS/Views/ScheduleSettingsView.swift`, `HealthMd/iOS/SchedulingManager.swift`, `HealthMd/Shared/Models/ExportSchedule.swift`, `HealthMd/Shared/Managers/PushRegistrationManager.swift`, worker in `../worker/`

## What it does

Scheduled Exports let Health.md automatically export recent Apple Health data on a daily or weekly schedule. The user chooses a frequency, time of day, and how many past days each run should include. Health.md then writes the selected export formats to the chosen vault/folder using the same export settings as a manual export.

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
4. Choose frequency, time, and lookback window.

## Prerequisites

- HealthKit permission granted.
- A vault/folder selected.
- At least one export format selected.
- Notification permission granted when prompted.
- The iPhone should be unlocked at the scheduled time for HealthKit reads to succeed.

## Setup

1. Go to **Schedule**.
2. Enable **Scheduled Exports**.
3. Accept notification permissions.
4. Choose **Daily** or **Weekly**.
5. Choose the time using the hour, minute, and AM/PM controls.
6. Set **Export past days** to the number of days each run should include.
7. Confirm the **Next export** message in the Schedule tab.

## What gets exported

Scheduled exports use the same configuration as manual exports:

- selected metrics from **Export → Health Metrics**;
- selected formats: Markdown, Obsidian Bases, JSON, CSV;
- filename and folder templates;
- write mode: overwrite, append, or update;
- daily note injection, if enabled;
- individual entry tracking, if enabled;
- time-series data, if enabled.

The scheduled run exports the configured lookback window ending with yesterday. Today is excluded because the day is still incomplete.

Examples:

| Frequency | Export past days | Scheduled run writes |
|---|---:|---|
| Daily | 1 | Yesterday |
| Daily | 3 | The previous 3 complete days |
| Weekly | 7 | The previous 7 complete days |
| Weekly | 14 | The previous 14 complete days |

## Locked-device behavior

iOS protects HealthKit data while the phone is locked. If a scheduled export fires while the iPhone is locked, Health.md cannot read Apple Health data at that moment.

Expected behavior:

1. The scheduled trigger arrives.
2. Health.md attempts the export.
3. If the device is locked, the export fails through the device-locked path.
4. Health.md sends a notification.
5. The user taps the notification after unlocking the phone.
6. Health.md retries the full scheduled export window.

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

- Start with **Daily + Export past days: 1** for a simple daily note workflow.
- Use **Daily + Export past days: 3–7** if you want automatic backfill when your phone is sometimes locked.
- Use **Weekly + Export past days: 7** if you only review health data once per week.
- Keep the iPhone charging and unlocked near the scheduled time for the most reliable automation.
- Pair scheduled exports with **Daily Note Injection** or **Obsidian Bases** for the strongest Obsidian workflows.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Scheduled export did not write files | iPhone was locked, no vault access, or no HealthKit data | Unlock the phone and tap the retry notification or retry from Export History. |
| No notification appeared | Notification permission denied | Enable notifications for Health.md in iOS Settings. |
| Export ran but missed some days | Some dates had no data or failed individually | Open Export History and inspect/retry the failed entry. |
| Files went to the wrong folder | Export folder/template settings are shared with manual exports | Check Export tab path preview, subfolder, filename, and folder organization. |
| Schedule time feels unreliable | iOS background execution and silent push delivery are not absolute guarantees | Use a wider lookback window and verify Export History. |
| Free export limit blocks schedule | Full Access not unlocked and free exports exhausted | Unlock Health.md or run fewer test exports before relying on schedule. |

## Video outline

- **Suggested title:** Automate Apple Health Exports to Obsidian with Health.md
- **Hook:** “You shouldn’t have to remember to export yesterday’s Apple Health data every morning.”
- **Demo flow:**
  1. Show an Obsidian vault before automation.
  2. Open Health.md → Schedule.
  3. Enable scheduled exports and accept notification permission.
  4. Configure Daily, a specific time, and a lookback window.
  5. Show that it uses the same metrics/formats/folder settings from the Export tab.
  6. Explain locked-device behavior with a simple diagram.
  7. Show Export History and retry.
- **Key screenshot/recording moments:** Schedule toggle, time picker, Export past days stepper, Next export text, Export History row.
- **CTA / next video:** “Next, we’ll trigger the same export from Apple Shortcuts.”

## Implementation notes

- `ExportSchedule` stores `isEnabled`, `frequency`, `preferredHour`, `preferredMinute`, `weekday`, `lookbackDays`, and `lastExportDate` on current `origin/main`.
- `ScheduleSettingsView` binds directly to `SchedulingManager.schedule`, so edits persist as they happen.
- `SchedulingManager.schedule.didSet` saves the schedule, registers background work, sets up HealthKit background delivery, registers remote notifications, and mirrors the schedule to the worker.
- `PushRegistrationManager.syncSchedule(...)` sends schedule state to the worker.
- Worker cron runs every minute and sends silent APNs pushes for due schedules.
- Silent-push handling eventually calls the same export pipeline as manual exports through `ExportOrchestrator` and `VaultManager`.
