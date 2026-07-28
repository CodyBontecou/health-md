# Scheduled Exports

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Schedule
- **Source files:** `HealthMd/iOS/SchedulingManager.swift`, `HealthMd/Shared/Managers/ScheduledExportCoordinator.swift`, `HealthMd/Shared/Models/PendingExportRequest.swift`, `HealthMd/Shared/Notifications/ExportNotificationScheduler.swift`

## What it does

Scheduled Exports run recent Apple Health exports daily, weekly, or on a custom calendar cadence using the same iPhone settings as Manual Export, including formats, metrics, paths, write mode, and **Lossless Health Records**. Custom schedules can repeat every N days, weeks, or months, covering patterns such as every other day or monthly. Targets are iPhone Folder, API Endpoint, or an already-open/connected Mac.

Lossless Health Records is on by default for new installs. Existing explicit summary-only choices remain off. Scheduled lossless exports can be large; start with a short lookback.

## Setup

1. Open **Schedule** and enable Scheduled Exports.
2. Grant notification permission for recovery.
3. Choose Daily, Weekly, or Custom; then set the time, lookback, and destination. Custom schedules also have an interval unit and start date that establishes the repeating phase.
4. Configure metrics, formats, and Lossless Health Records on Export.
5. Optional: enable Today Refresh every 3/6/12 hours.

Completed-day runs end yesterday. Today Refresh re-fetches the current day when iOS permits. File targets use Update/Overwrite to replace the daily JSON snapshot; API Endpoint targets resend the complete snapshot so the receiver can replace or upsert that date.

## What gets exported

- selected summary metrics;
- canonical source archive in JSON/CSV when lossless capture is on;
- summary + diagnostic Markdown/Bases;
- daily-note injection and individual entries for file targets, if enabled;
- roll-ups, if explicitly enabled.

Canonical records use strict source-start day ownership. Sleep summary keeps its established noon-to-noon night attribution, so the next completed-day pass remains the final compatibility summary for yesterday.

## Completeness

Scheduled file/upload completion and source-capture completeness are separate. Review `raw_capture_status` in each v7 daily record:

- `complete` can include successful empty queries;
- `partial` retains successful data but records incomplete branches;
- `not_requested` means the setting was off;
- `legacy_unavailable` means an older source could not provide it.

A downstream automation should not equate a written file with a complete canonical archive.

## Pending recovery

Before a scheduled occurrence, Health.md persists exact requested dates, source, schedule kind, destination snapshot, fire date, and notification routing metadata. It does not store HealthKit samples in the worker.

If HealthKit is protected while locked, the unresolved dates remain pending. Partial runs remove exact terminal dates (successfully written/uploaded days and iPhone HealthKit no-data outcomes) and keep only retryable dates, preventing append-mode duplicates. Missing Mac cache data remains retryable because a later iPhone sync may populate it. The immediate “Health Export Needs Attention” notification carries the stable pending request ID; Health.md does not announce an incomplete run as completed. Open Health.md and tap to retry. Duplicate triggers reuse pending identity and in-flight IDs prevent concurrent duplicate runs or re-expansion of completed dates.

## Scheduling/privacy architecture

Health.md combines on-device background tasks/HealthKit delivery/app-open catch-up with best-effort silent APNs. The worker may store APNs/install/platform/schedule/timezone metadata. It does not store HealthKit samples, export files, vault contents, API URLs, or API secrets.

Custom cadence details stay on device. Until the worker supports calendar intervals directly, Health.md registers custom schedules as daily wake-ups and rejects off-cadence pushes locally using the saved interval, unit, and start date.

Silent push cannot guarantee runtime or bypass locked-device protection. User-visible recovery stays local to avoid server/local notification races.

## Server-visible APNs fallback decision

Decision: no server-visible APNs alert. Health.md uses the client pending request plus local notification fallback for visible recovery. This keeps health/routing state on device and helps avoid duplicate notifications when silent push, app-open catch-up, and a notification tap overlap. A future server-visible alert would require explicit completion acknowledgement before it could be safe.

## Connected Mac behavior

Connected Mac schedules require an open, compatible, ready Mac to begin; they do not wake it. Current peers use peer-bound durable checksum-validated sessions. A disconnect, scheduler wait timeout, or iPhone app suspension pauses rather than cancels the persisted job; reopening Health.md and reconnecting the same Mac resumes from its acknowledged partition frontier until the fixed seven-day expiry. The scheduler invocation may stop waiting while the job continues. Peers without bounded per-date completion capability remain ineligible. Large one-day HealthKit capture/final serialization can still use substantial memory even though aggregate resume storage and frames are bounded.

## Practical guidance

- Begin with a one-day lookback.
- Use Update/Overwrite for repeated dates.
- Split route/ECG/clinical/attachment-heavy history into manual backfills.
- Review Export History and per-file lossless diagnostics.
- HealthKit denied read access can look successfully empty; Health.md cannot bypass that privacy behavior.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Schedule did not complete | iOS delay, lock protection, target unavailable | Unlock/tap notification or open app to drain pending work. |
| File exists but archive is partial | One source branch failed/cancelled/skipped/unsupported | Inspect manifest/diagnostics; retry if recoverable. |
| No archive | Lossless off or legacy peer | Review Export setting and update peers. |
| Mac schedule fails | Mac closed/not ready/incompatible | Open/update Mac, select folder, retry pending/history. |
| API 413 or high memory use | Receiver limit is below the bounded batch, or one lossless day is too large | Select fewer metrics, use summary-only, or raise the receiver's request limit. |
| No visible notification | Permission denied/iOS suppressed it | Enable notifications and open Health.md for catch-up. |

## Video outline

- **Suggested title:** Automate Lossless Apple Health Exports Safely
- **Hook:** “Schedule exact records, then verify capture completeness instead of trusting file presence alone.”
- **Demo flow:** configure one-day schedule, show pending lock recovery, inspect status/manifest, and explain API/Mac size limits.

## Implementation notes

- `ExportSchedule` stores frequency, custom interval/unit/start date, time, lookback, and target.
- `ScheduledExportCoordinator` persists exact `PendingExportRequest` values.
- `SchedulingManager` runs local/API/bounded Connected Mac pipelines with current settings.
- `ExportNotificationScheduler` uses deterministic pending identifiers.
- Worker silent pushes carry routing/schedule metadata only.
