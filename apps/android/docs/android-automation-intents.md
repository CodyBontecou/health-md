# Android Automation Intents

Health.md exposes an explicit-only broadcast receiver for Tasker/adb/other automation tools.

## Security model

The receiver is exported but has **no manifest intent-filter**. External callers must address the component explicitly. This prevents arbitrary implicit broadcasts from triggering health-data exports.

Component:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

## Actions

| Action | Extras | Behavior |
|---|---|---|
| `com.healthmd.android.action.EXPORT_YESTERDAY` | Optional `com.healthmd.android.extra.PROFILE` ID or name | Exports yesterday. |
| `com.healthmd.android.action.EXPORT_LAST_DAYS` | `com.healthmd.android.extra.DAYS` int; optional `PROFILE` | Exports the last N complete days ending yesterday. |
| `com.healthmd.android.action.EXPORT_DATE` | `com.healthmd.android.extra.DATE` ISO date; optional `PROFILE` | Exports one date. Defaults to yesterday if omitted. |
| `com.healthmd.android.action.EXPORT_RANGE` | `START_DATE`, `END_DATE` ISO dates; optional `PROFILE` | Exports an inclusive date range. |
| `com.healthmd.android.action.GET_LAST_STATUS` | — | Returns latest export-history status when called as an ordered broadcast. |

## Examples

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7 \
  --es com.healthmd.android.extra.PROFILE "Weekly Archive"

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

## Behavior parity

Automation exports use current settings when no profiles exist. Once profiles exist, omitting `PROFILE` uses the active profile; an explicit value resolves first by stable profile ID and then by trimmed, case-insensitive name. An unknown explicit profile or an invalid frozen profile snapshot fails closed without exporting. Folder profiles adopt their saved folder for the run, while API profiles use their saved endpoint. History entries use source `SHORTCUT` and retain the resolved profile name plus a privacy-safe destination label.

The launcher also includes static shortcuts for opening Export, Schedule, and History. Direct export shortcuts can be layered on top of the explicit broadcast API by Android automation tools.
