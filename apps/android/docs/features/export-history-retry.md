# Export History & Retry

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** History
- **Source files:** `app/src/main/java/com/healthmd/presentation/history/HistoryScreen.kt`, `app/src/main/java/com/healthmd/data/history/` (Room database, DAO, repository)

## What it does

Every export — manual, scheduled, shortcut, or API — is recorded in a local history database. Each entry shows success/partial/failed status, source, date range, file counts, destination, and any failure details, and failed runs can be retried with one tap.

## Who it is for

- Verifying scheduled runs without checking the folder every morning
- Recovering from partial exports (rate limits, missing permissions) without redoing everything
- Not a log of file contents — entries record what ran, not your health data

## Where to find it

1. Open Health.md → **History** tab.
2. Tap an entry for the full detail sheet.
3. On a failed entry, tap **Retry Export**.

## Prerequisites

- None — history is always on, stored locally in a Room database on your device

## Setup

1. No setup. Run an export; the entry appears.
2. Use **Clear History** if you want to remove stored run records (confirmation dialog offered).

## Example output

List rows show status (✓ Success / Partial / Failed), timestamp, and destination. The detail sheet adds source, when, range, counts, destination type, target, files, failure reason, and warnings.

## Tips

- Retry uses the currently configured destination settings, so fix the underlying problem (permissions, folder access) before retrying.
- History entries for automation broadcasts appear with source `SHORTCUT`.
- Clear History only clears run records — exported files in your folder are untouched.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Failure says rate limit | Health Connect limited reads | Wait, retry a smaller range, or export remaining dates later |
| Failure says file write | Folder permission lapsed | Reselect the export folder, then retry |
| Failure says no data | Days had no readable Health Connect data | Confirm your tracker syncs to Health Connect; grant history access |
| Failure says unlock required | Scheduled run hit the paywall | Retry after unlocking, or use manual free exports |

## Video outline

- **Suggested title:** Know Exactly What Exported — and Fix What Didn't
- **Hook:** "Partial export? Two taps to finish it."
- **Demo flow:** open History → expand a partial entry → fix → retry.
- **Key screenshot/recording moments:** status chips, detail sheet, retry button state.
- **CTA / next video:** Scheduled Exports.

## Implementation notes

History persists in Room (`ExportHistoryDatabase` + `ExportHistoryDao`) via `ExportHistoryRepositoryImpl`. `HistoryScreen` maps `ExportHistoryEntry` into success/partial/failed (`isFullSuccess`/`isPartialSuccess`) and renders per-entry failure labels from `ExportFailureReason.localizedLabel()`. Retry re-enters `ExportOrchestrator` for the failed dates only. Guidance copy (`export_guidance_*` strings) pairs each failure reason with a concrete remedy. Entries are local-only and never synced.
