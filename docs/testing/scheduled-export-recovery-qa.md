# Scheduled Export Recovery QA

## Scope

- Linear: ISO-307
- GitHub: https://github.com/CodyBontecou/health-md/issues/46
- Version/build under test: 2.0.2 (202605131859)
- Date: 2026-05-18

This checklist covers the reliable scheduled export recovery work: persisted pending export requests, lock-screen recovery notifications, notification-tap retry, app-open drain, Shortcut pending behavior, and duplicate trigger protection.

## Manual QA Checklist

These scenarios require a physical iPhone with a passcode, real HealthKit data, a selected iPhone vault/folder, Full Access unlocked, and real iOS notification/background execution behavior. They were not run locally in this workspace because the simulator and Mac test host cannot faithfully reproduce protected HealthKit reads while locked, APNs silent push delivery, or lock-screen notification interaction.

| # | Scenario | Local status | Notes / device script |
|---|---|---|---|
| 1 | Daily scheduled export while unlocked succeeds and clears pending notification. | Not run locally, device-only. | On iPhone, enable Daily schedule for the next minute with notifications allowed, keep the phone unlocked, wait for the run, then confirm files are written, export history records success, and no `Health Export Needs Attention` notification remains. |
| 2 | Daily scheduled export while locked creates/keeps pending work and shows actionable notification. | Not run locally, device-only. | Enable Daily schedule for the next minute, lock the iPhone before the fire time, wait for the recovery notification, then confirm it says to unlock/tap to retry. |
| 3 | Tapping notification after unlock exports exact pending dates. | Not run locally, device-only. | After scenario 2, unlock and tap the notification. Confirm the exported file dates match the pending occurrence's lookback window ending yesterday, not a recalculated later window. |
| 4 | Opening app after a missed schedule drains pending/catch-up work. | Not run locally, device-only. | Create a missed/locked scheduled occurrence, do not tap the notification, then open Health.md. Confirm pending scheduled work drains and catch-up exports any missed complete days. |
| 5 | Shortcut export while locked returns pending dialog and does not hard-fail. | Not run locally, device-only. | Lock the iPhone, run a Health.md export Shortcut from Shortcuts/Siri, and confirm the dialog is pending rather than a hard failure. Confirm no quota is consumed for the locked attempt. |
| 6 | Shortcut pending notification tap exports exact Shortcut dates. | Not run locally, device-only. | After scenario 5, unlock and tap the Health.md notification. Confirm the exported dates match the Shortcut request exactly. |
| 7 | Duplicate silent/BG triggers do not duplicate notifications or exports. | Not run locally, device-only. | Force or wait for multiple triggers for the same scheduled occurrence. Confirm there is one pending request/notification for that fire date and one export run. Covered locally by duplicate pending request and in-flight drain tests. |
| 8 | Notification permissions denied path degrades gracefully. | Not run locally, device-only. | Deny Health.md notifications, trigger a locked scheduled/Shortcut export, then open Health.md after unlock. Expected: no visible notification, no crash, pending work remains recoverable via app-open drain; APNs registration may be skipped while permission is denied. |

## Automated Checks

Initial attempt:

```sh
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,arch=arm64' \
  -configuration Debug-iOS \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  -only-testing:HealthMdTests/PendingExportRequestTests \
  -only-testing:HealthMdTests/ScheduledExportCoordinatorTests \
  -only-testing:HealthMdTests/SchedulingManagerPendingExportsTests \
  -only-testing:HealthMdTests/ExportIntentRunnerTests \
  -only-testing:HealthMdTests/ExportNotificationSchedulerTests \
  -only-testing:HealthMdTests/ScheduleDateMathTests
```

Result: did not start tests. `xcodebuild` exited 70 because this machine does not have a unique matching `iPhone 16 Pro` simulator destination. The focused run was rerun against the concrete available `iPhone 17 Pro` simulator ID below.

Focused regression command:

```sh
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-iOS \
  -destination 'platform=iOS Simulator,id=0335EECF-93B3-4F95-9D5E-DC339BC055DB' \
  -configuration Debug-iOS \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  -only-testing:HealthMdTests/PendingExportRequestTests \
  -only-testing:HealthMdTests/ScheduledExportCoordinatorTests \
  -only-testing:HealthMdTests/SchedulingManagerPendingExportsTests \
  -only-testing:HealthMdTests/ExportIntentRunnerTests \
  -only-testing:HealthMdTests/ExportNotificationSchedulerTests \
  -only-testing:HealthMdTests/ScheduleDateMathTests
```

Result: passed on 2026-05-18. `Executed 39 tests, with 0 failures (0 unexpected)`.

Purpose: focused regression coverage for pending request persistence, scheduled export completion behavior, exact-date notification retry, app-active drain, Shortcut pending behavior, deterministic notification identifiers, duplicate trigger handling, and schedule date math.

Broader iOS unit command:

```sh
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-iOS \
  -destination 'platform=iOS Simulator,id=0335EECF-93B3-4F95-9D5E-DC339BC055DB' \
  -configuration Debug-iOS \
  -quiet \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

Result: passed on 2026-05-18. `xcresulttool` summary reported `result: Passed`, `totalTestCount: 893`, `passedTests: 890`, `skippedTests: 3`, and `failedTests: 0`.

Worker tests were not run for ISO-307 because this ticket did not change worker code.

## GitHub Issue Response Checklist

Posted response: https://github.com/CodyBontecou/health-md/issues/46#issuecomment-4479081773

The GitHub issue response should summarize:

- scheduled and Shortcut exports now persist pending exact-date work when HealthKit is unavailable while locked;
- tapping the Health.md recovery notification or opening the app after unlock drains pending work;
- server silent push improves timing but remains best-effort and cannot bypass iOS HealthKit protection;
- notification permission denial removes the visible tap path, but pending work remains on device for app-open recovery;
- version/build: 2.0.2 (202605131859), where available;
- automated command results from this QA note;
- no implicit follow-up remains, or any follow-up has a separate Linear issue.
