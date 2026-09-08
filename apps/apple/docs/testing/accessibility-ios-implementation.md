# iOS accessibility implementation status

2026-09-08. **In progress; all five repair lanes merged, component gates passed, full screen/journey matrix pending.** The [September 7 audit](accessibility-ios-audit.md) remains unchanged historical evidence. Android's separately blocked 402-case device gate is not an Apple pass.

The shared outcome is full readable essential labels, explanations and values with operable native controls at the user's chosen text size. This repairs existing UI presentation; no settings/defaults, HealthKit semantics, contracts, schemas, metric identities/units, export bytes or Android implementation change.

## Verified foundation

- All 19 `Typography` entry points now use public SwiftUI relative-font resolution on iOS, with bundled OFL-licensed Geist faces. Base sizes/weights and mono figures are retained. This deliberately replaces fixed SF fonts; iOS 17 support does not rely on private SF names or the iOS-26-only `Font.scaled(by:)` API. Tests reject missing registered faces and prove view-scoped and live text-size growth.
- Active secondary/destructive button labels grow/wrap with at least 44pt minimum targets. Status labels and their symbols grow together. Full export filenames/messages wrap; status actions retain individual callbacks. Primary/Icon helpers are covered too, but they have no current app call sites and do not stand in for onboarding's separate buttons.
- Enabled status text uses readable named tokens. `successText` uses light green1000/dark green900; `errorText` uses red900; pending/disconnected text uses existing `textSecondary`. Semantic fills are unchanged. Both-theme tests include actual 10% tinted status surfaces and pressed/selected backgrounds.
- Shared macOS source retains native SF/SF Mono base sizes and desktop defaults. Hostless component tests avoid starting the production app's stores, cleanup and runtime services.

### Executed evidence

The separate [production-backed test host](../../AccessibilityTests/README.md) executed **7 iOS unit/component tests + 4 native UI tests + 2 isolated macOS tests**, all passing, zero skips. These include 96 font observations (19 production fonts + 5 semantic positive controls × 4 sizes), 16 button measurements, 20 status/symbol measurements and 84 both-theme contrast pairs. Counts of observations are not additional XCTest cases. Real UI edge taps verify secondary/destructive callbacks, disabled/loading semantics and independent status actions.

The shipping iOS app and entire unit-test target compiled with `HealthMd-Tests-iOS`/`Debug-iOS`; its target dependency graph also compiled the Mac app. This was **build-for-testing, not execution of the full hosted suites**. Actual app `UIAppFonts` and all five packaged resources were checked. Core source stamp and the centrally copied XCFramework hashes/slices/symbols matched. Package resolution used pinned Notelet 1.1.0 with owned component caches; locks were unchanged. Targeted compiler-warning and TDD guards passed (no local testing TODOs to inspect).

[Source hashes, native result counts and capture provenance](accessibility-ios-2026-09-08-foundation/provenance.json) identify the exact pre-commit implementation bytes; the listed HEAD is the audit base, not a claim that it contains the repairs. [Font measurements](accessibility-ios-2026-09-08-foundation/font-measurements.txt). Selected native simulator captures: [default/light](accessibility-ios-2026-09-08-foundation/foundation-large-light.png), [AX5/light](accessibility-ios-2026-09-08-foundation/foundation-accessibility5-light.png), [AX5/dark](accessibility-ios-2026-09-08-foundation/foundation-accessibility5-dark.png), [scrolled AX5 actions with verified callbacks](accessibility-ios-2026-09-08-foundation/production-buttons-accessibility5-dark.png). Captures show a scroll viewport of synthetic content, not whole-app certification.

Local command/log/result receipts: `/tmp/health-md-ios-a11y-fleet-loop/cycle-1`, with component-owned results under `apps/apple/build/ios-a11y-c1`. NEW owned simulator: `BD07FC16-9F6F-43A5-A42A-59949A553A20`, iPhone SE (3rd generation), iOS 26.5 (23F77), Xcode 26.6 (17F113). No existing simulator/app or real health/folder/purchase/settings data was used.

Failures were investigated before accepting results: palette green900 and warning text failed on tinted pressed/selected surfaces; text tokens were corrected without changing fills or reducing the 4.5:1 threshold. UI tests initially compared localized synthetic counters against ungrouped integers and checked window rather than scroll bounds; diagnostics now use verbatim counters and stricter viewport reachability. Initial standalone dependency/module wiring failures were corrected. One failed-run diagnostic collection exceeded the harness timeout; that incomplete bundle is not green evidence. The final native result bundles confirm complete, nonzero successful runs.

## Integrated repairs and central diagnostics

All five source-only lanes were merged serially after clean-head, ancestry and ownership checks. The integrated changes cover dialogs; format/frontmatter/template editing; metric/Settings/Sync reading; scheduling/export/profile controls; and onboarding/paywall. Their actual production components are registered in the isolated host. No lane's static checks were counted as runtime tests.

Central execution found issues that source parsing could not establish:

- A padded native switch label was not a physical row target. The production `A11ySwitchToggleStyle` now supplies one actual full-row action with native switch accessibility. Label-edge/thumb-side dispatch, unavailable state and the real isolated configuration-protection manager's block/unlock paths passed native UI tests.
- Compact date openers measured 34.5pt and did not respond to a padded-edge tap. The affected date/time controls now use native wheels with the original bindings/ranges, full wrapping readback and horizontal scrolling for narrow columns. Native wheel targets and value-preserving adjustments passed; page scrolling uses the outer gutter, not the wheel.
- UIKit Menu options measured 42pt and ignored minimum frames on SwiftUI action labels. `A11ySelectionMenu` retains native popover presentation but owns growing, scrolling >=44pt option Buttons. Native tests passed full date/time/unit choices, repeated current-option dispatch and independent hour/minute/period callbacks.
- The iOS dialog now has a real UIKit modal/escape boundary containing the production SwiftUI content and its complete live environment. Unit and native UI tests passed Escape dispatch, first-secondary cancellation before dismissal, initial field focus and Next/Done progression. This does not certify physical VoiceOver gestures.
- Test assumptions were corrected rather than reducing text or thresholds: native single-line newline rendering is compared against an actual native control while raw binding values remain unchanged; deliberately long fixtures exceed the 44pt minimum-height plateau; tight AX glyph bounds are not confused with allocated reading width; keyboard/wheel overscan is excluded from visible target measurements. One zero-test UI run was rejected, followed by explicit test enumeration and actual execution.

Current component result `integrated-components-current-1.xcresult`: **52 passed, 0 failed/skipped**. Actual-source hostless Mac result `integrated-mac-components-1.xcresult`: **5 passed, 0 failed/skipped**, including bounded shared dialogs, desktop 40pt action sizing, native font metrics and desktop dispatch policy. Shipping result `integrated-app-build-2.xcresult` compiled the iOS app, full unit-test target and Mac dependency graph; it is **not hosted-suite execution**. Targeted native UI passes are recorded separately under `integrated-switches-1`, `integrated-popovers-1`, `integrated-date-native-1`, `integrated-components-and-native-1`, `integrated-native-controls-1` and `integrated-lane-smoke-1`; some of those exploratory bundles also contain earlier failing cases and are not whole-suite green evidence. Commands, logs, source manifests, raw result summaries and failure history remain under the local cycle directory.

See the [integrated native-control contract](../../AccessibilityTests/README.md#integrated-native-control-details). These are component and targeted native-dispatch results, not whole-app completion.

## Remaining before delivery

| Findings | Status |
| --- | --- |
| IOS-A1 | Shared typography and caller component reflow passed; full screen matrix pending |
| IOS-A2/A3 | Format/frontmatter/dialog repairs merged; broad editor/dialog journeys pending |
| IOS-A4/A5 | Readable tokens and real target fixes tested; remaining screen target matrix pending |
| IOS-A6/A7/A8 | All corresponding lanes merged; full metric/settings/scheduling/onboarding journeys pending |
| IOS-A9 | 52 iOS + 5 Mac component tests passed; integrated UI matrix not yet complete |

Remaining integration work includes the complete native popover/dialog, keyboard, protected shipping-host and screen matrix: short landscape/narrow width, German/Arabic RTL/Japanese, both themes, runtime Reduce Motion, and date/selection/domain preservation. Targeted passes above do not replace those remaining gates. The full macOS host is unsafe to launch under this run's data boundaries; build plus isolated actual-source equivalents must remain explicitly distinct from that unavailable full-host gate. Actual VoiceOver traversal, physical Display Zoom/IME/magnification and reading comfort remain separate human gates. No platform or app-wide accessibility certification is claimed.
