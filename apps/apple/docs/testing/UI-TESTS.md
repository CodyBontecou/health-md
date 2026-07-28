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
