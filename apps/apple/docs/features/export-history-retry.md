# Export History Retry

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Schedule → Export History
- **Source files:** `HealthMd/iOS/Views/ScheduleSettingsView.swift`, `HealthMd/Shared/Models/ExportHistory.swift`, `HealthMd/iOS/ContentView.swift`

## What it does

Export History records recent manual, scheduled, Shortcut, and iPhone→Mac export attempts, including whether the run fully succeeded, partially succeeded, or failed. Failed rows name the cause and show the suggested next step directly in the history list. Details separate **Why it failed**, **What to do**, and any selectable **Technical details**, alongside the source, destination target, days attempted, files written, and failed dates. Failed local iPhone dates can be opened from the Schedule tab and retried without rebuilding the whole export setup.

This is the recovery path for real-world automation issues: locked phones, missing folder permissions, missing HealthKit data, file-write errors, and partial multi-day runs.

## Who it is for

- Users who rely on scheduled exports.
- Users backfilling multiple days at once.
- Users who want to see why an export did not create files.
- Users troubleshooting HealthKit, folder access, Mac destination, or locked-device failures.

## Where to find it

1. Open Health.md on iPhone.
2. Tap the **Schedule** tab.
3. Scroll to **Export History**.
4. Tap a history row to view details.
5. Use **Retry** for failed dates when available.

## Prerequisites

- At least one manual or scheduled export has run.
- HealthKit permission granted for retrying health data.
- A vault/folder selected and accessible for local retries. Mac-target history is informational; retry Mac exports from the Export tab after fixing Mac readiness.
- Free export quota remaining or Full Access unlocked.
- The iPhone should be unlocked when retrying.

## Setup

There is no separate setup. Export History is recorded automatically after export attempts.

1. Configure Health.md export settings.
2. Run a manual export or enable scheduled exports.
3. Return to **Schedule → Export History**.
4. Tap an entry to inspect its date range, source, target, files written, success count, and failed dates.
5. Retry failed local iPhone dates after fixing the underlying issue, or rerun Mac-target exports from the Export tab.

## Example status messages

```text
Exported 1 file(s)
Partial: 6 file(s), 2/3 days
Export failed: Device locked
Export failed: No vault selected
Export failed: Vault access denied
Export failed: No health data
Export failed: File write failed
Export failed: Task timed out
```

History keeps the newest entries first and stores up to 50 recent attempts.

## Tips

- Use history after every scheduled-export test to confirm the schedule actually wrote files.
- For multi-day exports, look for partial success instead of only success/failure.
- Open a failed entry and follow **What to do** before retrying.
- If a failure repeats, copy **Technical details** into the bug report after removing any private folder or server information.
- If the phone was locked, unlock it before retrying.
- If folder access changed in Files or iCloud Drive, re-select the vault before retrying.
- If a Mac-target export failed, fix the Mac Destination readiness issue first, then rerun from the iPhone Export tab.
- Use Export History retry after locked-device or folder-access issues so missed scheduled days can be written after you fix the cause.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| History says Device locked | iOS protected HealthKit data while the phone was locked | Unlock the phone, open Health.md, and retry. |
| History says No vault selected | Export folder has not been chosen | Select a vault/folder in Export or Settings. |
| History says Vault access denied | Security-scoped folder permission was lost | Re-select the folder in Health.md. |
| History says No health data | Apple Health has no samples for that date or permission is missing | Check Health permissions and Apple Health data for the date. |
| Retry fails again | Root issue was not fixed | Open the failed-date details and address the shown reason. |
| Mac export entry has no Retry button | Mac exports require an interactive connected Mac target | Open the Export tab, choose Connected Mac, and run the export again after fixing Mac readiness. |
| Old entry disappeared | History is capped | Newer entries replace older ones after the 50-entry limit. |

## Video outline

- **Suggested title:** Fix Failed Health.md Exports with Export History
- **Hook:** “If an automatic export fails, Health.md tells you which dates failed and lets you retry them.”
- **Demo flow:**
  1. Show a scheduled export history list.
  2. Open a failed or partial entry.
  3. Explain source, target, date range, files written, success count, and failure reason.
  4. Fix a common issue, such as unlocking the phone or re-selecting the folder.
  5. Tap Retry and show the new successful entry.
- **Key screenshot/recording moments:** history row, detail sheet, failed-date list, retry progress overlay, successful retry.
- **CTA / next video:** “Next, we’ll configure scheduled exports so fewer retries are needed.”

## Implementation notes

- `ExportHistoryEntry` stores source, optional target label, optional file count, success flag, date range, success count, total count, failure reason, and failed-date details.
- `ExportFailureReason` maps common failures to short explanations and actionable recovery suggestions.
- `ExportHistoryEntry` derives a display reason from legacy per-date failures and deduplicates stored error messages for the Technical details section.
- `ExportHistoryManager` persists history in `UserDefaults` under `exportHistory` and trims to 50 entries.
- `ScheduleSettingsView` presents `ExportHistoryDetailView` from a selected entry and routes retry work through the same export pipeline.
- Export sources include `manual`, `scheduled`, `shortcut`, and `macAgent` (`iPhone → Mac`).
