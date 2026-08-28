# Scheduled Exports

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Schedule
- **Source files:** `app/src/main/java/com/healthmd/data/scheduler/ExportScheduler.kt`, `app/src/main/java/com/healthmd/data/scheduler/ExportWorker.kt`, `app/src/main/java/com/healthmd/data/scheduler/ScheduledExportRecoveryManager.kt`, `app/src/main/java/com/healthmd/presentation/schedule/ScheduleScreen.kt`

## What it does

Scheduled exports run your compatibility export (or Raw API Snapshot) automatically at a chosen time and frequency. Results arrive as Android notifications — **Export Complete**, **Export Partial**, or **Export Failed** — and every run lands in export history where you can retry it.

## Who it is for

- Set-and-forget journaling: yesterday's health lands in the vault every morning
- Anyone whose vault syncs automatically and wants fresh files without opening the app
- Requires the lifetime unlock (scheduling is a paid capability)

## Where to find it

1. Open Health.md → **Schedule** tab.
2. Enable **Automatic export**, set **Frequency** and **Time**.
3. Choose the destination (folder or API endpoint) and grant the prompts shown.

## Prerequisites

- Lifetime unlock (free plan: manual exports only)
- Health Connect **background access** — grant it when prompted; scheduled reads need it
- Notifications enabled to see results; exports still run with notifications off

## Setup

1. Enable Automatic export and set Frequency + Time.
2. Pick the target: a folder ("Target folder ready") or the API endpoint.
3. Grant Alarms & reminders access when asked for exact timing.

## Example output

A notification per run with a day count (e.g. "Raw snapshot range ending …"), plus a history entry with full per-date diagnostics.

## Tips

- **Exact timing vs fallback:** with Alarms & reminders access, each occurrence runs from a one-shot exact alarm with a durable WorkManager backup; without it, WorkManager becomes primary and the time is a target, not a guarantee.
- Occurrences carry their intended local date, so a delayed start after midnight still exports the correct day.
- Missed dates are recoverable: if the phone was locked after reboot, background access was missing, or Health Connect was unavailable, the Schedule screen offers to retry those exact dates while the app is open and unlocked.
- **Active-run cancellation:** Tap **Cancel Export** in the foreground scheduled-export notification to stop only that in-progress attempt. Health.md leaves the schedule enabled, keeps completed owner dates completed, and freezes exact unresolved dates plus their destination/settings identity for a later retry. Cancellation itself is not recorded as a failed export. On Android 13 and later, allow Health.md notifications so this drawer action is visible.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Scheduled exports need Health Connect background access" | Background permission missing | Schedule tab → enable background access |
| Runs late or skipped | Exact-alarm access denied or OEM battery management | Grant Alarms & reminders; exempt Health.md from battery optimization |
| Missed dates after reboot | Phone locked after restart (Health Connect gated) | Use the pending-dates retry prompt; unlock once after reboot |
| No completion notification | Notifications off | Enable notifications; runs still recorded in History |

## Video outline

- **Suggested title:** Automate Your Health Journal While You Sleep
- **Hook:** "Yesterday's health, in your vault before breakfast."
- **Demo flow:** enable schedule → set time + folder → show notification → show history.
- **Key screenshot/recording moments:** exact-timing prompt, background-access grant, recovery banner.
- **CTA / next video:** Export History & Retry.

## Implementation notes

`ExportScheduler` reconciles persisted settings with exactly one alarm-or-fallback delivery and durably admits one export per occurrence; the state write is the transition invariant that makes stale work inert. `BootReceiver` reschedules after reboot/app-update/clock changes. `ScheduledExportRecoveryManager.inspectPendingRecovery` reports blockers (`NO_PENDING_DATES`, `ALREADY_RUNNING`, `PAYWALL_REQUIRED`, …) before offering retries. `ExportWorker` posts foreground info (`dataSync` type) and result notifications on the scheduled-exports channel. Profile-based scheduling (`ScheduledProfile*Worker`) runs profile-scoped exports alongside the default schedule.
