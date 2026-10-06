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
| 4 | Opening app after a missed schedule drains pending/catch-up work. | Not run locally, device-only. | Create a missed/locked scheduled occurrence, do not tap the notification, then open Health.md. Confirm pending scheduled work drains and catch-up exports any missed complete days; the drain presents through the scheduled-export activity banner, never a standalone result alert. |
| 5 | Shortcut export while locked returns pending dialog and does not hard-fail. | Not run locally, device-only. | Lock the iPhone, run a Health.md export Shortcut from Shortcuts/Siri, and confirm the dialog is pending rather than a hard failure. Confirm no quota is consumed for the locked attempt. |
| 6 | Shortcut pending notification tap exports exact Shortcut dates. | Not run locally, device-only. | After scenario 5, unlock and tap the Health.md notification. Confirm the exported dates match the Shortcut request exactly. |
| 7 | Duplicate silent/BG triggers do not duplicate notifications or exports. | Not run locally, device-only. | Force or wait for multiple triggers for the same scheduled occurrence. Confirm there is one pending request/notification for that fire date and one export run. Covered locally by duplicate pending request and in-flight drain tests. |
| 8 | Notification permissions denied path degrades gracefully. | Not run locally, device-only. | Deny Health.md notifications, trigger a locked scheduled/Shortcut export, then open Health.md after unlock. Expected: no visible notification, no crash, pending work remains recoverable via app-open drain; APNs registration may be skipped while permission is denied. |
| 9 | Cold-launch recovery notification tap presents one banner, no bare alert. | Not run locally, device-only. | Force-quit Health.md with a preserved pending scheduled request and its “Health Export Needs Attention” notification delivered, then tap the notification. Expected: one export run presented through the scheduled-export activity banner (the app-open drain may win the tap race and own the banner); no standalone “Export Failed” alert, and no second export run for the same request. |

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

## Profile-only schedule restoration diagnosis — 2026-10-05

This is a source-fix diagnosis receipt, not an App Store release or proof that every reported delivery failure has the same cause.

### Reproduced behavior and fix

With the legacy schedule disabled and one enabled profile schedule restored from storage, the app-active drain/catch-up sequence neither armed a local fallback before the first occurrence nor ran an unqueued due occurrence. The minimized first case failed twice with `opening a restored profile schedule must re-arm its local notification`.

`performCatchUpExportIfNeeded` now evaluates enabled profiles as well as the legacy schedule. Profile evaluation re-arms its next wake-up even when no occurrence is due. App launch uses the profile-aware automation refresh, restoring the HealthKit delivery callback, local fallback, and APNs bridge instead of enabling HealthKit only behind the legacy flag. Queued profile recovery is not retried a second time immediately after the app-active drain, and one profile's pending request cannot suppress legacy catch-up at the same fire time.

The platform-neutral outcome is restoring enabled automation after app launch without requiring another schedule edit or exporting future work. Android already reconciles both legacy and profile scheduling in `presentation/MainActivity.kt` and `data/scheduler/BootReceiver.kt`; no Android change is needed for this Apple lifecycle defect. Public health exports, direct protocols, API envelopes, shared-core, CLI, website and external-consumer contracts are unchanged. The frozen receipt-verifier worker was not modified or deployed.

### Verification and limitations

- New runtime regressions cover pre-occurrence fallback restoration, repeated re-arm identity, all scheduling disabled, due profile catch-up, retained drain recovery without a second attempt, and simultaneous legacy/profile recovery.
- Six focused suites passed twice on the iOS 26.5 simulator: `SchedulingManagerProfileSchedulingTests`, `SchedulingManagerPendingExportsTests`, `ScheduledExportCoordinatorTests`, `ExportNotificationSchedulerTests`, `ScheduledExportEntryStoreTests`, and `APNsSchedulingPreflightTests`: **112 tests, zero failures**.
- This was an **isolated diagnostic build** of the real scheduler: unrelated existing compilation errors required temporary adapters for `MetricSelectionState.enabledMetricIDs` and the unavailable HealthKit boundary API, plus an empty view in place of excluded `ContentView.swift`. Those adapters were removed after testing and must never be installed on a user's phone. This result is not a normal full-app build pass.
- A normal `build-for-testing` was rerun after removing the adapters and still fails in `iOS/AppIntents/RefreshMacContextIntent.swift:114` because `MetricSelectionState` has no `enabledMetricIDs`. The prior full-build attempts also found the unavailable `HKHealthStore.earliestAuthorizedSampleDate` API and unrelated `ContentView.swift` compilation/type errors. Resolve the full-build blockers and rerun `make -C apps/apple test-ios` before release or device installation.
- `make -C apps/apple check-apns-scheduling` passes, including new launch-restoration guards. This validates source/config wiring, not APNs delivery.
- Private local evidence is in `apps/apple/build/logs/scheduled-notifications-*.log` (ignored build artifacts), including red, guard-only probe, green, repeated regression, and normal-build-blocker logs.
- Argent reached the connected physical iPhone 17 Pro running iOS 27. Its read-only Settings inspection was blocked by a Face ID prompt before notification permission could be observed. No notification permissions or schedules were changed, no health export was initiated, and the patched app was not installed. The incomplete private flow under `/tmp/healthmd-notification-qa/` is diagnostic evidence, not a passing replay.

### Remaining physical-device checks

After the owner authenticates and a genuine signed app build is available, obtain permission to use a temporary test schedule/destination, preserve the existing configuration, and verify:

1. A profile-only schedule survives relaunch before its first fire time; no export starts early.
2. With notifications allowed, the fallback appears near fire time +60 seconds when background execution does not complete the export. Include locked-device and denied-permission cases; silent pushes remain best-effort.
3. Opening after a missed occurrence runs its frozen dates once; a failed drain preserves its recovery notification without an immediate second attempt.
4. Repeated app-open/re-arm and simultaneous profiles/legacy scheduling preserve pending identity and do not duplicate completed exports.
5. Restore the original test configuration and confirm unrelated schedules, history, destinations and credentials remain intact.

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
