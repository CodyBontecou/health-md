# APNs Scheduling Preflight

Health.md scheduled exports use APNs silent pushes routed to the registered device's signing environment. App Store and TestFlight builds use production APNs; development-signed device builds use sandbox APNs. ISO-154 adds a repo-level guard so iOS releases fail before App Store submission if the APNs entitlement or scheduling bridge is misconfigured.

`PushRegistrationManager` sends `apnsEnvironment: "development" | "production"` with every `/devices/register` request. It reads `aps-environment` from the installed iOS provisioning profile rather than assuming Debug means sandbox and Release means production. An absent profile means App Store production distribution. A present but unreadable/unsupported profile skips registration rather than guessing a host. On macOS, the public `SecTask` API reads the signed APNs entitlement directly. The iOS profile parser uses only Foundation; Apple's provisioning profile format may change, so profile decode failures require investigation when updating signing/toolchains. See [Apple's APS Environment entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment) and [TN3125: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles).

The scheduled-export outcome remains shared with Android. This registration field is an Apple transport detail: Android uses `AlarmManager`/`WorkManager` through `apps/android/app/src/main/java/com/healthmd/data/scheduler/ExportScheduler.kt`, not APNs, and has no producer or consumer of this registration payload. No health export schema or scheduling setting changes.

## Local commands

Run the release guard directly:

```bash
scripts/check-apns-scheduling-preflight.sh
```

Run it through the Makefile:

```bash
make check-apns-scheduling
```

Run the focused XCTest source/config guard:

```bash
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-macOS \
  -destination 'platform=macOS,arch=$(uname -m)' \
  -only-testing:HealthMdTests/APNsSchedulingPreflightTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER=""
```

## What the guard checks

- `HealthMd/HealthMd.entitlements` keeps `aps-environment` set to `production`.
- `HealthMd/Info.plist` keeps `UIBackgroundModes` configured with `remote-notification` for silent pushes.
- `HealthMd/Info.plist` keeps `BGTaskSchedulerPermittedIdentifiers` aligned with `SchedulingManager.backgroundTaskIdentifier`.
- `HealthMd/iOS/HealthMdApp.swift` restores scheduling on launch through `isSchedulingActive` and `refreshScheduledAutomation()`, including profile-only scheduling after the legacy schedule has been disabled by migration. Launch restoration re-arms local fallbacks and restores the HealthKit delivery callback and APNs bridge; enabling HealthKit alone is insufficient.
- `HealthMd/iOS/SchedulingManager.swift` still registers for remote notifications, calls `PushRegistrationManager.shared.syncSchedule(schedule)` when the schedule changes, and rejects custom completed-day pushes that lack a parseable fire date.
- `HealthMd/iOS/HealthMdApp.swift` still forwards APNs tokens and handles `scheduled-export` silent push payloads.
- `HealthMd/Shared/Managers/PushRegistrationManager.swift` still posts device registrations to `/devices/register` and schedule upserts to `/schedules/upsert` with the worker payload fields (`userId`, `platform`, `apnsToken`, `bundleId`, `apnsEnvironment`, `timezone`, `isEnabled`, `frequency`, `hour`, `minute`, `weekday`), including the explicit custom-to-daily wake-up fallback. With export profiles (phase 3), `SchedulingManager.refreshScheduledAutomation` mirrors the **coalesced** worker record through `syncSchedules(_:legacy:)` — the earliest preferred time among enabled scheduled entries and the legacy schedule — using the same single-record worker contract.

## Fixture and mock strategy

No network calls are made. The preflight is a deterministic source/config check over plist and Swift source files.

For negative fixtures, point the script at temporary files with environment overrides:

```bash
cp HealthMd/HealthMd.entitlements /tmp/HealthMd.bad.entitlements
/usr/libexec/PlistBuddy -c 'Set :aps-environment development' /tmp/HealthMd.bad.entitlements
APNS_IOS_ENTITLEMENTS=/tmp/HealthMd.bad.entitlements scripts/check-apns-scheduling-preflight.sh
```

The command above should fail before any release upload or App Store Connect submission.

## Release wiring

`.github/workflows/release-ios.yml` runs `scripts/check-apns-scheduling-preflight.sh` before archiving and before `asc review submit`, so GitHub Release-triggered iOS deployments are blocked if the repo configuration regresses.
