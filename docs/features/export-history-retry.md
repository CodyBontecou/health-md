# Export History Retry

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Schedule → Export History
- **Source files:** `HealthMd/iOS/Views/ScheduleSettingsView.swift`, `HealthMd/Shared/Models/ExportHistory.swift`, `HealthMd/iOS/ContentView.swift`

## What it does

Export History records recent manual and scheduled export attempts, including whether the run fully succeeded, partially succeeded, or failed. Failed date details can be opened from the Schedule tab and retried without rebuilding the whole export setup.

This is the recovery path for real-world automation issues: locked phones, missing folder permissions, missing HealthKit data, file-write errors, and partial multi-day runs.

## Who it is for

- Users who rely on scheduled exports.
- Users backfilling multiple days at once.
- Users who want to see why an export did not create files.
- Users troubleshooting HealthKit, folder access, or locked-device failures.

## Where to find it

1. Open Health.md on iPhone.
2. Tap the **Schedule** tab.
3. Scroll to **Export History**.
4. Tap a history row to view details.
5. Use **Retry** for failed dates when available.

## Prerequisites

- At least one manual or scheduled export has run.
- HealthKit permission granted for retrying health data.
- A vault/folder selected and accessible.
- Free export quota remaining or Full Access unlocked.
- The iPhone should be unlocked when retrying.

## Setup

There is no separate setup. Export History is recorded automatically after export attempts.

1. Configure Health.md export settings.
2. Run a manual export or enable scheduled exports.
3. Return to **Schedule → Export History**.
4. Tap an entry to inspect its date range, source, success count, and failed dates.
5. Retry failed dates after fixing the underlying issue.

## Example status messages

```text
Exported 1 file(s)
Partial: 2/3 files
Device locked
No vault selected
Vault access denied
No health data
File write failed
Task timed out
```

History keeps the newest entries first and stores up to 50 recent attempts.

## Tips

- Use history after every scheduled-export test to confirm the schedule actually wrote files.
- For multi-day exports, look for partial success instead of only success/failure.
- If the phone was locked, unlock it before retrying.
- If folder access changed in Files or iCloud Drive, re-select the vault before retrying.
- Pair scheduled exports with a wider lookback window so a later retry can catch missed days.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| History says Device locked | iOS protected HealthKit data while the phone was locked | Unlock the phone, open Health.md, and retry. |
| History says No vault selected | Export folder has not been chosen | Select a vault/folder in Export or Settings. |
| History says Vault access denied | Security-scoped folder permission was lost | Re-select the folder in Health.md. |
| History says No health data | Apple Health has no samples for that date or permission is missing | Check Health permissions and Apple Health data for the date. |
| Retry fails again | Root issue was not fixed | Open the failed-date details and address the shown reason. |
| Old entry disappeared | History is capped | Newer entries replace older ones after the 50-entry limit. |

## Video outline

- **Suggested title:** Fix Failed Health.md Exports with Export History
- **Hook:** “If an automatic export fails, Health.md tells you which dates failed and lets you retry them.”
- **Demo flow:**
  1. Show a scheduled export history list.
  2. Open a failed or partial entry.
  3. Explain source, date range, success count, and failure reason.
  4. Fix a common issue, such as unlocking the phone or re-selecting the folder.
  5. Tap Retry and show the new successful entry.
- **Key screenshot/recording moments:** history row, detail sheet, failed-date list, retry progress overlay, successful retry.
- **CTA / next video:** “Next, we’ll configure scheduled exports so fewer retries are needed.”

## Implementation notes

- `ExportHistoryEntry` stores source, success flag, date range, success count, total count, failure reason, and failed-date details.
- `ExportFailureReason` maps common failures to short and detailed user-facing messages.
- `ExportHistoryManager` persists history in `UserDefaults` under `exportHistory` and trims to 50 entries.
- `ScheduleSettingsView` presents `ExportHistoryDetailView` from a selected entry and routes retry work through the same export pipeline.
- Export sources are currently `manual` and `scheduled`.
