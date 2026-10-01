# Scheduled Exports

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Schedule
- **Source files:** `app/src/main/java/com/healthmd/data/scheduler/ExportScheduler.kt`, `app/src/main/java/com/healthmd/data/scheduler/ExportWorker.kt`, `app/src/main/java/com/healthmd/data/scheduler/ScheduledExportRecoveryManager.kt`, `app/src/main/java/com/healthmd/presentation/schedule/ScheduleScreen.kt`

## What it does

Scheduled exports run your compatibility export (or Raw API Snapshot) automatically at a chosen time and frequency, and can also refresh the current day's partial file during the day so a daytime run captures last night's sleep alongside yesterday. Results arrive as Android notifications — **Export Complete**, **Export Partial**, or **Export Failed** — and every run lands in export history where you can retry it.

Scheduling offers three date windows on the single schedule, plus a Today Refresh option on each export-profile schedule (matching iOS):

- **Past complete days** — the trailing N complete days ending yesterday.
- **Past complete days + today** — the same trailing window plus today's partial file. Pair it with an hourly frequency (e.g. every 6 hours) and both files stay fresh all day; tomorrow's run re-exports today as a complete day, so nothing is lost after the last refresh of the day. Use Overwrite or Update write mode.
- **Today** — only the run day's partial file.
- **Today Refresh (profiles)** — a profile schedule exports its completed-day window at the preferred time and refreshes today's partial file every 3, 6, or 12 hours after it. The refresh runs are best-effort like iOS; a failed refresh waits for its next slot (or tomorrow's completed-day run) instead of creating a missed-date recovery entry.

Profile schedules re-export the **full configured completed-day lookback on every new occurrence**, including dates exported by previous runs. A daily 08:00 profile with a 14-day lookback exports all 14 completed days each morning. The window ends the day before the scheduled boundary, even if execution is delayed; duplicate wake-ups after success do not resend that occurrence. Today Refresh stays independent: it can join a due completed-day run or export only today afterward. Failed/cancelled attempts retry their exact frozen residual dates rather than expanding the lookback again. Those residuals take priority over new occurrences, including Today Refresh; changing lookback/time or toggling a profile schedule does not discard them.

To abandon obsolete recovery without recreating the profile, open **Schedule → Profiles → Discard Pending Recovery** on the affected row and confirm. The action is shown only when that profile has pending recovery. It stops that profile's scheduled retry, clears its frozen pending dates/settings, and re-arms its next ordinary occurrence using the current profile and schedule. It does not export immediately, reset completed-day/refresh progress, delete the profile, clear API credentials, or erase export history. A disabled schedule stays disabled. Already uploaded data or written files cannot be undone by this action.

**API recovery authority:** pending profile snapshots freeze the endpoint URL, and prepared compatibility journals validate the credential/header destination fingerprint. Matching iPhone's new per-pending-request credential evidence *before* compatibility journal preparation, including Raw API Snapshot retries, is planned for the next Android scheduler-hardening change (`automation.api-recovery-authority`). That follow-up must persist private evidence, pass it to both runners, and test credential rotation, legacy queues and pre-journal failures before capture/upload; no additional parity is claimed here and export contracts stay unchanged.

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

1. Enable Automatic export and set Frequency + Time (or pick a date window such as "Past complete days + today").
2. Pick the target: a folder ("Target folder ready") or the API endpoint.
3. Grant Alarms & reminders access when asked for exact timing.

## Example output

A notification per run with a day count (e.g. "Raw snapshot range ending …"), plus a history entry with full per-date diagnostics.

## Tips

- **Exact timing vs fallback:** with Alarms & reminders access, each occurrence runs from a one-shot exact alarm with a durable WorkManager backup; without it, WorkManager becomes primary and the time is a target, not a guarantee.
- Occurrences carry their intended local date, so a delayed start after midnight still exports the correct day.
- **Today stays out of missed-date recovery:** the "Past complete days + today" window and profile Today Refresh re-export the current day on every occurrence, so a failed same-day write is retried by the next occurrence rather than a recovery prompt.
- **Legacy migration:** when the single schedule migrates into the Default profile's entry, a window that included today ("Today" or "Past complete days + today") maps onto Today Refresh; an hourly cadence maps to the nearest 3/6/12-hour refresh interval.
- Missed dates are recoverable: if the phone was locked after reboot, background access was missing, or Health Connect was unavailable, the Schedule screen offers to retry those exact dates while the app is open and unlocked.
- **Active-run cancellation:** Tap **Cancel Export** in the foreground scheduled-export notification to stop only that in-progress attempt. Health.md leaves the schedule enabled, keeps completed owner dates completed, and freezes exact unresolved dates plus their destination/settings identity for a later retry. Cancellation itself is not recorded as a failed export. On Android 13 and later, allow Health.md notifications so this drawer action is visible.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Scheduled exports need Health Connect background access" | Background permission missing | Schedule tab → enable background access |
| Runs late or skipped | Exact-alarm access denied or OEM battery management | Grant Alarms & reminders; exempt Health.md from battery optimization |
| Missed dates after reboot | Phone locked after restart (Health Connect gated) | Use the pending-dates retry prompt; unlock once after reboot |
| No completion notification | Notifications off | Enable notifications; runs still recorded in History |
| Old dates repeat after changing the profile schedule | Frozen pending recovery takes priority | Discard Pending Recovery on that profile's Schedule row; confirm only if those retries are no longer wanted |
| Manual raw succeeds but a profile schedule reports “API rejected export” | Older profile workers sent compatibility envelopes instead of raw artifacts | Update to a build containing the profile raw-routing fix, then discard obsolete recovery if needed; the destination must support Raw API Snapshot |

## Video outline

- **Suggested title:** Automate Your Health Journal While You Sleep
- **Hook:** "Yesterday's health, in your vault before breakfast."
- **Demo flow:** enable schedule → set time + folder → show notification → show history.
- **Key screenshot/recording moments:** exact-timing prompt, background-access grant, recovery banner.
- **CTA / next video:** Export History & Retry.

## Implementation notes

The shared `export.scheduled-today-refresh` capability refreshes the internal registry identity and its generated Apple/Android adapters and website reference. Registry-bound semantic/render test inputs carry the new identity; their synthetic health facts and expected public export bytes are unchanged. Byte-frozen Shared Setup v2 fixtures retain their historical source-registry identity. No public export schema, API envelope, or direct-protocol version changes.

Profile runs branch on the **frozen export mode** for both destinations: `RAW_SNAPSHOT` uses `RawSnapshotService.exportRange`, while compatibility mode keeps the existing API/folder runners and journals. Scheduled raw runs never request interactive route consent or resume compatibility API journals. Raw success counts describe provider artifacts, not completed dates: a partial/cancelled raw action retries every completed day in its attempted range, and only a fully successful raw action satisfies Today Refresh. Today's partial day remains outside frozen recovery.

The discard is profile-scoped and fail-closed on malformed persistence. DataStore atomically clears residuals and advances `recoveryGeneration` before the scheduler cancels that profile's alarm, fallback, and export work. Workers carry the admitted generation, recheck it before export, and fence all progress writes; an old coroutine cannot restore discarded recovery or advance the new generation's frontiers. New durable operation IDs include a nonzero generation so a fresh occurrence cannot resume a discarded compatibility journal. Stale editor drafts preserve the stored generation and queue. Discard does not remove destination artifacts or journals that may still be in use.

The shared user outcome is abandoning stale recovery while preserving the profile. Apple already drops pending requests from a previous enabled period in `SchedulingManager.shouldAttemptPendingScheduledExport`; Android keeps toggle-preserved residuals until the explicit confirmed discard. This is a native recovery-control difference, not a new export product or schema: Apple v8, Android v4/v5, raw-snapshot v1, API envelopes, shared-core/CLI/website/Obsidian consumer bytes and fixtures are unchanged.

`ExportScheduler` reconciles persisted settings with exactly one alarm-or-fallback delivery and durably admits one export per occurrence; the state write is the transition invariant that makes stale work inert. `BootReceiver` reschedules after reboot/app-update/clock changes. `ScheduledExportRecoveryManager.inspectPendingRecovery` reports blockers (`NO_PENDING_DATES`, `ALREADY_RUNNING`, `PAYWALL_REQUIRED`, …) before offering retries. `ExportWorker` posts foreground info (`dataSync` type) and result notifications on the scheduled-exports channel. Profile-based scheduling (`ScheduledProfile*Worker`) runs profile-scoped exports alongside the default schedule; each entry's `ScheduledProfileOccurrenceMath` merges a due Today Refresh slot into a new completed-day occurrence (or runs it alone when that occurrence is already satisfied) and arms whichever boundary comes first. The `PAST_COMPLETE_DAYS_THROUGH_TODAY` single-schedule window appends the run day to the trailing window inside `ScheduledExportPendingRequests.scheduledRunDates`, which also keeps today out of pending-retry claiming.
