# Automation Intents

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export (no dedicated screen — driven externally)
- **Source files:** `app/src/main/java/com/healthmd/automation/AutomationReceiver.kt`, `docs/android-automation-intents.md`

## What it does

Tasker, adb, MacroDroid, and other automation tools can trigger Health.md exports through an explicit broadcast receiver: export yesterday, the last N days, one date, or an inclusive range — and read back the last export status as an ordered-broadcast result. The app also ships launcher shortcuts for Export, Schedule, and History.

## Who it is for

- Tasker/MacroDroid users wiring exports into phone routines
- adb/script-driven flows from a computer
- Not for scheduling — use [Scheduled Exports](./scheduled-exports.md) for time-based runs

## Where to find it

1. No in-app screen. Address the receiver explicitly from your automation tool:
   `com.healthmd.android/com.healthmd.automation.AutomationReceiver`
2. Launcher shortcuts: long-press the app icon.

## Prerequisites

- Android 9 / API 28+
- Current export settings, folder, and metric selection — automation reuses exactly what the app is configured to do

## Setup

1. Configure your export destination and metrics once in the app.
2. In Tasker/adb, send an explicit broadcast (component + action).
3. Use `GET_LAST_STATUS` as an ordered broadcast to read the result.

## Example output

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7
```

Actions: `EXPORT_YESTERDAY`, `EXPORT_LAST_DAYS` (+`DAYS` int), `EXPORT_DATE` (+`DATE` ISO), `EXPORT_RANGE` (+`START_DATE`/`END_DATE`), `GET_LAST_STATUS`.

## Tips

- The receiver is exported but has **no intent-filter** — only explicit component addressing works, so no implicit broadcast can trigger exports.
- Automation runs count against the same paywall/free-export accounting as manual exports, and land in history with source `SHORTCUT`.
- Every export is an explicit, user-configured action; the receiver never self-triggers.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Broadcast does nothing | Implicit send or wrong component | Address the component explicitly with the exact action string |
| Export blocked | Paywall/free limit reached | Check History or unlock |
| Range exports partially | Health Connect rate limits on large ranges | Retry smaller ranges from History |

## Video outline

- **Suggested title:** Trigger Health Exports from Tasker
- **Hook:** "One broadcast, yesterday's health in your vault."
- **Demo flow:** Tasker task → broadcast EXPORT_YESTERDAY → history entry appears.
- **Key screenshot/recording moments:** explicit-intent config, result read-back.
- **CTA / next video:** Scheduled Exports.

## Implementation notes

`AutomationReceiver` routes actions into `ExportOrchestrator` with the current `ExportSettings`, profile resolution (`ExportProfileRules`, `ProfileFolderAdoptionScope`), `ExportAwakeCoordinator` for run duration, and `ExportAccountingPolicy` — identical side effects to a manual run, recorded via `ExportHistoryEntry` with `ExportSource.SHORTCUT`. Complete action/extras table and security model: [Android automation intents](../android-automation-intents.md) (canonical reference).
