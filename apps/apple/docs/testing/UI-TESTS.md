# iOS UI tests

Run from `apps/apple` using the `HealthMd-UITests-iOS` scheme. UI tests use synthetic
launch state, not simulator Health data or production purchases.

## Choose an existing recipe

| Work | Reference |
| --- | --- |
| Deterministic launch environment and accessibility IDs | [`UITestLaunchHelper.swift`](../../HealthMdUITests/UITestLaunchHelper.swift) |
| Onboarding, first preview, post-onboarding paywall, and shared setup | [`OnboardingJourneyUITests.swift`](../../HealthMdUITests/OnboardingJourneyUITests.swift) |
| Quota/paywall anchors and swipe-down dismissal | [`PaywallJourneyUITests.swift`](../../HealthMdUITests/PaywallJourneyUITests.swift) |
| Export preview, result, and cancellation | [`ExportJourneyUITests.swift`](../../HealthMdUITests/ExportJourneyUITests.swift) |
| Launch-state reset | `configureTestMode()` in [`HealthMdApp.swift`](../../HealthMd/iOS/HealthMdApp.swift) |
| Broader test/coverage gates | [CI quality gates](CI-QUALITY-GATES.md) |

## Configure repeatable state

Use `UITestLaunchHelper.configuredApp(...)` rather than constructing launch flags in each test.
The helper sets `--uitesting` and explicit scenario values. The app's `configureTestMode()`
resets persisted onboarding/profile state at launch; an installed app is reused between methods.
For a new UserDefaults-backed feature, establish/reset its requested state there as well.
Test both alone and after another journey to expose inherited-state failures.

For onboarding, set `showOnboarding: true`. For the post-onboarding paywall, also set
`showsPostOnboardingPaywall: true`; close the first preview before expecting the paywall.
Use `analyticsTransport: "offline"` for deterministic analytics isolation. The representative
journey tests show these configurations and the expected navigation sequence.

Export preview tests can use deterministic HealthKit-like fixtures:

```swift
let app = UITestLaunchHelper.configuredApp(
    healthAuthorized: true,
    vaultSelected: true,
    purchaseUnlocked: true,
    useHealthKitExportPreviewFixtures: true
)
```

This sets `UITEST_HEALTHKIT_EXPORT_PREVIEW_FIXTURES=true`. In Debug UI-test mode,
`ExportPreviewView` uses `UITestHealthKitFixtures.exportPreviewHealthData(...)` instead of
reading simulator Health data.

## Run a focused journey

Choose an available simulator with `xcrun simctl list devices available`. Use an unused result
bundle path for each run so earlier failure evidence remains available.

```bash
mkdir -p build/ui-tests
xcodebuild test \
  -project HealthMd.xcodeproj \
  -scheme HealthMd-UITests-iOS \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -resultBundlePath build/ui-tests/onboarding.xcresult \
  -only-testing:HealthMdUITests/OnboardingJourneyUITests/testPostOnboardingPaywallAppearsAfterFirstPreviewCloses
```

For the preview fixture recipe, select
`HealthMdUITests/ExportJourneyUITests/testExportPreview_rendersHealthKitFixtureValues` instead.
Run the surrounding journey class next, then the affected broader suite.

## Inspect failures before changing presentation

1. Export the screenshots and accessibility attachments:

   ```bash
   xcrun xcresulttool export attachments \
     --path build/ui-tests/onboarding.xcresult \
     --output-path build/ui-tests/onboarding-attachments \
     --only-failures
   ```

2. Inspect the screenshot, hierarchy, and attachment manifest. Distinguish a missing sheet
   from a query that matches multiple elements or the wrong accessibility container.
3. Wait on a stable content anchor, such as `UITestLaunchHelper.Paywall.title`, rather than
   treating `paywall.view` as proof of presentation. The latter has been ambiguous in this hierarchy.
4. Use the existing swipe-down dismissal and coordinate fallback in the paywall journey tests
   when the small dismiss control is not reliably exposed. Assert the destination after dismissal.
5. Recheck explicit launch state before diagnosing routing races. Rerun the test twice and
   alongside another journey; a lone pass does not establish state isolation.

Attachments must come from synthetic scenarios. Keep real health values, credentials, and user
vault content out of test logs and reports. [Local TODO plans](TODO-INDEX.md) are session planning
artifacts, not the testing runbook or fresh-checkout prerequisites.
