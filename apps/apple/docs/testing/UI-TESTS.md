# UI Tests

The iOS UI test target uses the `HealthMd-UITests-iOS` scheme and launches the app with `--uitesting`.

## Export Preview HealthKit Fixtures

Export Preview tests can opt into deterministic HealthKit-like data without reading simulator Health data:

```swift
let app = UITestLaunchHelper.configuredApp(
    healthAuthorized: true,
    vaultSelected: true,
    purchaseUnlocked: true,
    useHealthKitExportPreviewFixtures: true
)
```

This sets `UITEST_HEALTHKIT_EXPORT_PREVIEW_FIXTURES=true`. In Debug UI-test mode, the app routes `ExportPreviewView` through `UITestHealthKitFixtures.exportPreviewHealthData(...)`, which returns representative sleep, activity, heart, vitals, body, nutrition, mindfulness, mobility, hearing, workout, and granular time-series samples.

Focused command:

```bash
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-UITests-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:HealthMdUITests/ExportJourneyUITests/testExportPreview_rendersHealthKitFixtureValues
```

## Pull-request UI coverage

Apple CI runs 15 selected phone cases in two batches (9 + 6) from one qualified generic simulator build. The protected-profile creation journey was removed at the owner's request after its “New profile” hittability assertion failed in hosted CI; earlier runs had passed. Remaining UI assertions, warning gates and timeout allowances are unchanged.

Protected-profile creation and its toast-to-setting route require manual QA: enable “Prevent Accidental Changes,” open Settings → Export Profiles, and tap the New profile (+) action. Confirm that the profile editor does not open, a protection toast appears, and tapping the toast opens the enabled “Prevent Accidental Changes” setting.
