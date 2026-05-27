# APNs Scheduling Preflight

Health.md scheduled exports depend on production APNs silent pushes. ISO-154 adds a repo-level guard so iOS releases fail before App Store submission if the APNs entitlement or scheduling bridge is misconfigured.

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
- `HealthMd/iOS/SchedulingManager.swift` still registers for remote notifications and calls `PushRegistrationManager.shared.syncSchedule(schedule)` when the schedule changes.
- `HealthMd/iOS/HealthMdApp.swift` still forwards APNs tokens and handles `scheduled-export` silent push payloads.
- `HealthMd/Shared/Managers/PushRegistrationManager.swift` still posts device registrations to `/devices/register` and schedule upserts to `/schedules/upsert` with the worker payload fields (`userId`, `platform`, `apnsToken`, `bundleId`, `timezone`, `isEnabled`, `frequency`, `hour`, `minute`, `weekday`).

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
