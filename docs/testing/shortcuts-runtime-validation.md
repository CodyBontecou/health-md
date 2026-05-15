# Shortcuts Runtime Validation

This document tracks the runtime validation path for Health.md App Intents, starting with Linear issue ISO-153.

## Export Last N Days

The `Export Last N Days` shortcut is implemented by `ExportLastNDaysIntent`. It exports a clamped `1...366` day window ending yesterday; today is intentionally excluded because the health data for the current day is incomplete.

### Automated Coverage

Run the focused iOS unit coverage with:

```sh
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-Tests-iOS \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro,arch=$(uname -m)" \
  -configuration Debug-iOS \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  -only-testing:HealthMdTests/ExportLastNDaysIntentTests
```

This is the StoreKit-safe fixture path: it does not call StoreKit, HealthKit, Shortcuts UI, or the file system. The test directly covers the date window used by the App Intent runtime:

- default `7` days ends yesterday and excludes today
- values below `1` clamp to a single-day export
- values above `366` clamp to the maximum supported window
- the Shortcut initializer clamps the stored parameter before runtime

Validation result on 2026-05-11:

```text
Test Suite 'ExportLastNDaysIntentTests' passed.
Executed 4 tests, with 0 failures (0 unexpected).
```

### Manual Runtime Fixture

Use this path when validating the Shortcut action itself in the Shortcuts app on a real device or a booted simulator.

1. Install a Debug-iOS build of Health.md.
2. For simulator validation, keep purchase state StoreKit-safe by using the debug legacy unlock fixture instead of a live transaction:

   ```sh
   xcrun simctl spawn booted defaults write com.codybontecou.obsidianhealth debugOriginalAppVersion "1.6.0"
   xcrun simctl spawn booted defaults write com.codybontecou.obsidianhealth debugOriginalPurchaseDate -float 1767225600
   ```

   `1767225600` is `2026-01-01T00:00:00Z`, before `PurchaseManager.grandfatherCutoffDate`, so `refreshStatus()` unlocks exports without StoreKit network or purchase calls.

3. Launch Health.md once and grant Health access.
4. Select an export folder in the app. The runtime path requires a real security-scoped vault bookmark; UI-test `--uitesting` vault injection is intentionally not used by Shortcuts.
5. Open Shortcuts, add the Health.md action `Export Last N Days`, set `Number of Days` to `7`, and run it.
6. Expected result:
   - Shortcuts returns a success dialog such as `Exported 7 days of health data.`
   - exported files are present in the selected folder for the expected date range ending yesterday
   - `Get Last Export Status` reports a successful shortcut/scheduled export entry for the same range

If there is no HealthKit fixture data for one or more days, the acceptable runtime result is a partial or failure dialog that names the primary reason. The Shortcut is still considered runtime-valid when the App Intent launches without StoreKit prompts, computes the correct clamped date range, respects the vault requirement, records export history, and returns the expected success/partial/failure dialog.

### ISO-153 Linear Metadata

Verified with:

```sh
linear issue view ISO-153 --json
```

As of 2026-05-11, ISO-153 is attached to parent `ISO-142`, project `Health.md`, and project milestone `P0 — Gates & Release Blockers`.
