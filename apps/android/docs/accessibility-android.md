# Android Accessibility Audit

Last updated: 2026-09-07

## Pass covered

Primary TalkBack and large-font-risk areas were audited across onboarding, export setup, date/export controls, scheduled exports, history/settings navigation, format customization, frontmatter editing, and paywall actions.

## Fixes applied

- Custom glass buttons/cards now use Compose `clickable` semantics with `Role.Button` instead of pointer-only gesture handlers.
- Shared icon-only glass buttons now have 48 dp touch targets by default and accept content descriptions.
- Schedule increment/decrement controls and frontmatter add actions now expose TalkBack labels.
- Shared secondary buttons enforce a minimum 48 dp touch target.
- Export progress announces polite state updates while exports/previews advance.
- Decorative icons continue to use `contentDescription = null`; visible text remains the accessible label for card rows and navigation items.

## Large text and display scaling

The shared user outcome is that increasing system text or display size does not prevent setup or navigation. Text keeps the user's chosen size; content scrolls and controls grow or wrap instead of being hidden.

The Android onboarding bodies previously used bounded, centered columns without scrolling. Taller text could push Grant Access, Select Folder, Use a Shared Setup, and Get Started outside the pager. A nested Back/Skip/Continue row could also squeeze its final action out of view. The main navigation used fixed-height tabs and a guessed 88 dp content inset.

### Reading comfort improvements

- Setup has one persistent primary action. Connect Health Data and Select Folder replace the previously disabled Continue; after setup succeeds, Continue becomes the primary action. Start Exporting is also visible without scrolling. Back and optional Skip live in a compact header. Permission requests, folder selection, completion, and skip/analytics behavior are unchanged.
- Explanations remain scrollable. At 1.3× text or a constrained viewport, onboarding and paywalls omit decorative hero illustrations, use start-aligned copy, drop forced title line breaks, and give informational cards more text width. No explanatory copy or selected-folder text is removed or truncated, and the `sp` type sizes and user font scale are unchanged.
- Helper text and enabled secondary actions use the readable secondary token, not the disabled-control color. Selected folders use a readable card instead of a long pill.
- Export and Preview stack primary-first when the available width is too narrow for comfortable labels. Wider landscape windows keep the pair side by side so the actions do not consume all available height.
- Main navigation uses two columns of full-width text labels when four narrow tabs would fragment the words. A measured Scaffold reserves the actual bar height; the navigation rail scrolls in short landscape windows. System-bar and display-cutout insets apply to all routes.

Apple inspection: `apps/apple/HealthMd/iOS/Views/OnboardingView.swift` already separates scrolling explanations from meaningful setup actions in `footerControls`; `apps/apple/HealthMd/iOS/Views/ExportTabView.swift` stacks floating export actions for accessibility Dynamic Type; `apps/apple/HealthMd/iOS/ContentView.swift` uses native `TabView` navigation. This pass adapts Android's custom Compose layouts, not a new platform capability. No health APIs, settings semantics, export schemas, direct protocols, shared-core, CLI, website, or external-consumer contracts change.

### Schedule and settings control pass

The shared outcome is that users can read and edit a schedule at their chosen text/display size without aiming at tiny arrows, losing digits, or narrowing explanations beside a switch. This is a bounded pass over the legacy scheduled-export card and Settings navigation/lock cards, not the per-profile schedule dialogs.

- Schedule labels now sit above their fields. Frequency value/unit controls reflow, numeric fields size for all five supported localized digits, and date menus wrap full labels. The existing 15-minute minimum, five-digit limit, date-window choices, hour/minute deltas, and persistence callbacks remain unchanged.
- Time and lookback adjustments have separate 48 dp minus/plus targets with 8 dp gaps, button roles, localized action labels, and current-value semantics. AM/PM has one clearly labeled whole-button action rather than duplicate arrows. Locale period placement and the existing 12/24-hour behavior are retained. Numeric type remains 20 sp; the new `label-20-mono` token adds readable line height and tabular figures.
- Numeric fields keep their padding inside the focus/touch target, grow vertically, have a visible themed cursor/focus border, and commit on keyboard Done or focus loss. The schedule scroll container accommodates the IME.
- Settings entry cards omit decorative leading icons when crowded and give descriptions their full inner width. The lock explanation is below the switch row, with readable secondary contrast. The switch's whole labeled row is one target and remains disabled while its value is loading.
- Device tests exposed an existing lock-overlay sizing bug: `fillMaxSize` could produce a zero-height interceptor in an unbounded scrolling column. The protected region now uses `matchParentSize` to cover its measured content. Both blocked and allowed pointer actions are verified; configuration guards and storage policy are unchanged.

Apple inspection: `apps/apple/HealthMd/iOS/Views/ScheduleSettingsView.swift` uses whole-menu time controls and native steppers, not separately tappable tiny arrows; `apps/apple/HealthMd/iOS/ContentView.swift` puts the configuration-protection explanation outside its native labeled toggle. This pass changes Android native presentation, not schedule meaning, settings defaults, or any producer/consumer wire contract. Apple large-text geometry has not been certified by these Android tests.

### Selector, editor and secondary-control implementation

The remaining targeted Android layouts are implemented locally. **The expanded physical-device matrix and new screenshots are still pending:** the Pixel 7 was disconnected when verification was attempted. This is not an app-wide accessibility certification.

- Metric selection scrolls its title, search, bulk actions and individual rows beneath compact Back/Search navigation. Category expansion and tri-state selection are separate actions; each metric has one labeled checkbox target. Crowded names get full width, with units/indicators below. Search matching, category scope, counts and caller-owned selection remain unchanged.
- Profile names/summaries have full width and independent edit, delete and enabled controls. Native editor/delete dialogs retain live protection guards. Fields and menus reflow; roomy dialogs keep fixed chrome, while short/IME windows and oversized titles scroll the entire composition so Save/Cancel remain reachable. Defaults, parsing, hour/minute/lookback bounds and the profile-specific positive-Int cadence range are preserved.
- Format choices/options use one labeled radio/switch action instead of duplicate row/indicator callbacks. Unit descriptions and frontmatter navigation get more reading width. The custom-template editor allocates visible lines from the available height rather than demanding eight lines; all text, examples, help, reset and the existing bounded preview remain available. Customization transformations, including the Android-native-fields/profile implication, are unchanged.
- Frontmatter inputs use wrapping external labels, reflowing key/value fields, contextual Add/Delete actions and single labeled switches. Long values also have a wrapping reading surface, including disabled fields. Normalization, trimming, sorting, duplicate handling, raw edits and key-style behavior are unchanged. Back joins the scroll surface rather than reserving scarce keyboard height.
- Date presets grow/stack with explicit selected semantics; custom-date labels sit above full-width values. Schedule's Clear History is a readable 48 dp button that reflows with its heading and still requests the existing protected confirmation. Date mappings, formatting and deletion policy are unchanged.

Apple evidence: `MetricSelectionView.swift` separates scrolling content/native navigation and labels metric actions; `ProfileScheduleSection.swift` has labeled toggles and a native scrolling editor; `FormatCustomizationView.swift` contains native format/frontmatter selections, toggles and editors; `ExportTabView.swift` exposes selected preset state and adaptive actions; `ScheduleSettingsView.swift` has a labeled guarded history action. Android retains its existing search behavior, numeric limits, reset scope, confirmation flow and guards rather than copying different Apple behavior. Apple geometry and VoiceOver remain independently unverified. No exporter, domain/data logic, capability, metric/unit, schema/protocol, shared-core, CLI, website or external-consumer contract changed.

### Regression coverage

`LargeDisplayAccessibilityTest` uses real Compose measurements and pointer taps on synthetic screens, without granting health permissions, selecting real folders, making purchases, or changing device-wide settings. It traverses onboarding, checks both incomplete and connected setup actions without scrolling, verifies the reading width and unchanged font size/scale, exercises export and paywall actions, and checks that scroll content clears the measured navigation bar. Control bounds, label line widths/heights, and absence of ellipsized labels are checked.

Schedule coverage additionally checks 12/24-hour adjustments, localized five-digit input, minimum/empty-input commits, keyboard Done, date/unit menus, and lookback controls. Settings coverage checks full-width explanations, loading/on/off switch states, navigation taps, and protected/unprotected controls inside scrolling content. `ConfigurationProtectionTest` also covers the native notice action and a regression tapping real child coordinates inside an unbounded scroll column.

The matrix covers 411×720 dp at 100%, 320×480 dp at 130% and 200%, 320×640 dp at 100% (display scaling alone) and 200%, 568×280 and 640×280 dp landscape at 200%, plus German and Arabic/RTL at 200% in dark mode and Japanese at 200% for leading day-period placement. The constrained dp viewports model enlarged display settings independently of text scaling. These tests are included in the existing Android instrumentation CI job. Unit tests cover layout breakpoints and AA contrast for readable secondary copy in both themes.

Earlier validation on 2026-09-07, **before the selector/editor integration**: Pixel 7 (Android 17), 82/82 instrumentation checks passed (80 matrix checks plus 2 protection regressions); Play debug unit suite, 1,314 passed and 1 skipped; lint passed. Those device results are not a pass for the newer layouts.

The shared `AccessibilityTestHarness` supports five additional production-composable suites. The compiled inventory is:

| Suite | Methods × displays | Declared cases |
| --- | --- | --- |
| `LargeDisplayAccessibilityTest` | 8 × 10 | 80 |
| `MetricSelectionAccessibilityTest` | 6 × 10 | 60 |
| `ProfileScheduleAccessibilityTest` | 9 × 10 | 90 |
| `FormatCustomizationAccessibilityTest` | 7 × 10 | 70 |
| `FrontmatterCustomizationAccessibilityTest` | 6 × 10 | 60 |
| `SecondaryControlsAccessibilityTest` | 4 × 10 | 40 |
| `ConfigurationProtectionTest` | Non-parameterized | 2 |
| **Total** | | **402** |

New checks cover full labels/scale, bounded targets, selection roles/state, exact callbacks, caller rejection, search, editing, menus, save/cancel and live protection guards. **These are declared/compiled cases, not 402 executed passes.** Native dialogs use their own owner bounds. The fitted metric/frontmatter fixtures intercept the platform IME so a physical portrait inset cannot double-shrink a synthetic landscape viewport; their focus and IME-action checks still run, while actual keyboard resizing remains a manual gate. The format IME test separately combines real focus/keyboard visibility with an explicitly constrained remaining-height host; it does not reproduce every physical keyboard/window inset.

Current integration validation on 2026-09-07: Play debug app and instrumentation APKs assembled; 188 unit suites, **1,314 passed / 1 skipped**, no failures/errors; `:app:lintPlayDebug` passed. The safe runner's **9 host-only mocked cases** passed. Its real Pixel invocation stopped at device preflight, before installation/instrumentation; no new screenshots were generated. Compilation fixes retained the assertions; the obsolete generic Add resource was removed after contextual actions replaced its last uses, without lint suppression or fixture weakening.

Local receipts: `/tmp/health-md-fleet-loop/cycle-1/integrated-build-unit-lint.log`, `runner-safety.log` and `device-validation.log`. These temporary files are operator receipts, not permanent CI artifacts.

Run on the local Pixel 7, optionally saving screenshots:

```sh
cd apps/android
ANDROID_SERIAL=2C061FDH200CJN scripts/run-accessibility-ui-tests.sh /tmp/healthmd-android-reading-layout
./gradlew :app:testPlayDebugUnitTest :app:lintPlayDebug
```

The local runner verifies the selected device before building, assembles app/test APKs, and installs both explicitly with `adb -s <serial> install -r`. It invokes all seven classes and requires the complete 402-case success summary, rejecting failures, empty filters and partial/stale selections. Unlike connected-test cleanup, it does not uninstall the app or erase its data afterward. `scripts/test-accessibility-ui-runner.sh` tests targeting, failure/selection guards and screenshot transport with disposable fake Gradle/ADB binaries, without real device calls. Screenshots are opt-in, capture production composables with synthetic state, and contain no health measurements. Native popup contents retain the anchor's unchanged density/direction, and tests verify their font scale too. Popup windows themselves use the physical device's window bounds rather than the embedded synthetic viewport; this is not a certification of every OEM/window configuration.

### Remaining usability opportunities

- **Device gate:** reconnect the Pixel, run the complete compiled 402-case matrix, investigate failures, and inspect new synthetic 200% captures in both themes before accepting the new layouts.
- **Screen reader and keyboard:** follow the [manual QA checklist](accessibility-manual-qa.md) for actual TalkBack traversal, focus, native IME resizing and magnification. Automated semantics/geometry is not a substitute.
- **Reading pace and discovery:** validate auto-advance timing, scroll discovery and text-only navigation with users. No subjective comfort or reading-pace result is claimed.

## Known limitations

- Full automated TalkBack traversal still requires device/emulator validation because Compose unit tests cannot fully emulate Android's screen reader.
- New selector/editor geometry remains device-unverified. Native calendar picker windows, the export-profile editor's containing metric overlay, other app surfaces and OEM-specific font/display combinations need independently scoped checks; the matrix is not complete app-wide certification.
- Health Connect's system permission screens are outside the app and inherit Android system accessibility behavior.

## Home-screen widgets

- Every widget keeps a visible text summary for charted values. Duplicate activity-ring artwork is decorative, while heart charts expose concise descriptions; color and artwork are never the only source of meaning.
- The widget root exposes a single predictable action that opens Health.md. Setup and management actions use the app’s 48 dp control tokens.
- Responsive compact, wide, medium, and tall-large compositions are tested separately because launcher padding and resize behavior vary by device. At larger font scales, compact cards switch to denser textual summaries and shorten step counts instead of clipping essential status copy.
- Missing, stale, permission-required, Health Connect unavailable, and before-first-unlock states use text rather than color alone.
- Synthetic picker previews contain readable labels and do not expose real measurements.
- Glance renders through `RemoteViews`, so launcher accessibility remains a physical-device gate. Pixel 7/API 37 QA confirmed whole-card TalkBack focus and activation, unclipped 1.3× font layouts, Arabic RTL mirroring, light/dark contrast, and compact-to-tall resizing.
