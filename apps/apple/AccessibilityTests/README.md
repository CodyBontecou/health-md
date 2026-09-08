# Isolated native accessibility components

This separate test app has no Health.md app bootstrap, HealthKit, StoreKit, vault, scheduler, analytics or transport dependencies. It is not a fake implementation: the generator compiles production sources directly, and generates only the status-prefix/identifier excerpts from current production bytes with source spans and SHA-256 provenance. No configuration-protection stand-in is provided.

```sh
# From the repository root; XcodeGen must be installed.
python3 apps/apple/scripts/generate-a11y-test-project.py apps/apple/build/a11y-owned
# Create/record a NEW simulator; substitute its explicit UDID below. Never use booted.
xcodebuild test -project apps/apple/build/a11y-owned/HealthMdA11y.xcodeproj \
  -scheme HealthMd-A11y-iOS -destination 'platform=iOS Simulator,id=<OWNED_UDID>' \
  -derivedDataPath apps/apple/build/a11y-owned/dd \
  -resultBundlePath apps/apple/build/a11y-owned/result.xcresult \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM=''
```

The macOS scheme `HealthMd-A11y-macOS` runs hostless XCTest against a framework compiled from the actual shared design-system file. It does not start the production Mac host, which initializes destination stores, cleanup and runtime services. Use a separate derived-data/result path. This is an isolated equivalent, not a full-host macOS test pass.

## Component and lane contract

- Existing `Typography` signatures remain. On iOS they use bundled registered Geist faces and native `Font.custom(_:size:relativeTo:)`; no private SF names, fixed point-size resolution or process-global UIFontMetrics. `Typography.scaled(size:weight:relativeTo:monospaced:)` is available for existing bespoke base sizes. On macOS it keeps the existing native system sizes/weights/design.
- Readable tokens: `Color.textSecondary` for enabled helper copy; `Color.successText` is light green1000/dark green900 and `Color.errorText` is red900. Existing success/error fills are unchanged. Pending/disconnected pill text uses `textSecondary`. `textMuted` is not an enabled-copy token.
- `HealthMdTests/Support/A11yHosting.swift`: `@MainActor A11yHosting(view, size:)`, `measured(proposal:)`, `update(view)`, `capture()`, `close()`. It hosts real views in UIKit, disables inherited safe areas for embedded probes, and remeasures/layouts after attachment. Always close hosts. Do not use ImageRenderer to infer native-menu failures.
- `AccessibilityTests/UITests/A11yUITestSupport.swift`: inherit `A11yUITestCase`; `launchScenario(_:size:theme:locale:width:height:)` launches this synthetic app, not the shipping app. Supported sizes: `large`, `xxxLarge`, `accessibility1`, `accessibility5`. `reveal(_:in:)`, `tapEdge(_:in:)`, `saveScreenshot(_:name:)` are available. The scroll helper checks actual scroll viewport bounds, not just window bounds. Native modal/keyboard tests must use their own real owner/window geometry where appropriate.
- `A11yScenarioContainer` applies the requested text environment, theme, locale/RTL, and optional constrained viewport. Constraints are synthetic remaining space, not physical Display Zoom or every IME. The OS keyboard still requires a real focus/type/dismiss test.
- New scenarios belong in uniquely named `AccessibilityTests/Scenarios/<Lane>A11yScenario.swift`, assembling production components with synthetic state/callback counters only. Coordinator registers scenario routing and generator sources centrally. Unit tests can go in uniquely named `HealthMdTests/Views/<Lane>A11yTests.swift` with `#if os(iOS)` and `@testable import HealthMd`; these synchronized test groups need no lane pbxproj edit. Native isolated UI tests go in `AccessibilityTests/UITests/<Lane>A11yUITests.swift`.
- Private production components may be extracted into uniquely named, correctly platform-guarded production files and used by BOTH real views and tests. Never hand-copy an implementation into tests, replace real guards with stubs, or call synthetic counters proof of purchases/HealthKit/storage.

Foundation coverage includes all 19 entry points plus five native positive controls at four text sizes, base metrics/registered faces/weights, live environment changes, monospacing, production status/symbol growth, minimum targets and actual edge callbacks, both-theme/tinted contrast, and eight native simulator renders. Screens, native menus/dialogs/keyboard and live protection are separate integration gates. Human VoiceOver, physical Display Zoom/IME and reading pace remain manual gates.
