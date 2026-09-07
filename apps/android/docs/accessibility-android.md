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

### Regression coverage

`LargeDisplayAccessibilityTest` uses real Compose measurements and pointer taps on synthetic screens, without granting health permissions, selecting real folders, making purchases, or changing device-wide settings. It traverses onboarding, checks both incomplete and connected setup actions without scrolling, verifies the reading width and unchanged font size/scale, exercises export and paywall actions, and checks that scroll content clears the measured navigation bar. Control bounds, label line widths/heights, and absence of ellipsized labels are checked.

Schedule coverage additionally checks 12/24-hour adjustments, localized five-digit input, minimum/empty-input commits, keyboard Done, date/unit menus, and lookback controls. Settings coverage checks full-width explanations, loading/on/off switch states, navigation taps, and protected/unprotected controls inside scrolling content. `ConfigurationProtectionTest` also covers the native notice action and a regression tapping real child coordinates inside an unbounded scroll column.

The matrix covers 411×720 dp at 100%, 320×480 dp at 130% and 200%, 320×640 dp at 100% (display scaling alone) and 200%, 568×280 and 640×280 dp landscape at 200%, plus German and Arabic/RTL at 200% in dark mode and Japanese at 200% for leading day-period placement. The constrained dp viewports model enlarged display settings independently of text scaling. These tests are included in the existing Android instrumentation CI job. Unit tests cover layout breakpoints and AA contrast for readable secondary copy in both themes.

Local validation on 2026-09-07: Pixel 7 (Android 17), 82/82 instrumentation checks passed (80 matrix checks plus 2 protection regressions); Play debug unit suite, 1,314 passed and 1 skipped; `:app:lintPlayDebug` passed.

Run on the local Pixel 7, optionally saving screenshots:

```sh
cd apps/android
ANDROID_SERIAL=2C061FDH200CJN scripts/run-accessibility-ui-tests.sh /tmp/healthmd-android-reading-layout
./gradlew :app:testPlayDebugUnitTest :app:lintPlayDebug
```

The local runner installs the debug app/test APKs and invokes instrumentation directly. Unlike connected-test cleanup, it does not uninstall the app or erase its data afterward. Screenshots are opt-in, capture production composables with synthetic state, and contain no health measurements. Native popup contents retain the anchor's unchanged density/direction, and tests verify their font scale too. Popup windows themselves use the physical device's window bounds rather than the embedded synthetic viewport; this is not a certification of every OEM/window configuration.

### Remaining usability opportunities

- **Remaining editors:** audit per-profile schedule dialogs, dense metric rows, date presets, and keyboard-open format/frontmatter editors. The legacy schedule card and Settings entry/lock cards above are covered; other screens are not implicitly certified.
- **Reading pace and discovery:** validate auto-advance timing, scroll discovery, and the text-only navigation arrangement with users who rely on magnification or TalkBack. The device matrix checks geometry and interaction, not subjective comfort.

## Known limitations

- Full automated TalkBack traversal still requires device/emulator validation because Compose unit tests cannot fully emulate Android's screen reader.
- Dense metric rows and other dialogs still require separate checks with OEM-specific font/display combinations; the layout regression matrix above is not a complete app-wide accessibility certification.
- Health Connect's system permission screens are outside the app and inherit Android system accessibility behavior.

## Home-screen widgets

- Every widget keeps a visible text summary for charted values. Duplicate activity-ring artwork is decorative, while heart charts expose concise descriptions; color and artwork are never the only source of meaning.
- The widget root exposes a single predictable action that opens Health.md. Setup and management actions use the app’s 48 dp control tokens.
- Responsive compact, wide, medium, and tall-large compositions are tested separately because launcher padding and resize behavior vary by device. At larger font scales, compact cards switch to denser textual summaries and shorten step counts instead of clipping essential status copy.
- Missing, stale, permission-required, Health Connect unavailable, and before-first-unlock states use text rather than color alone.
- Synthetic picker previews contain readable labels and do not expose real measurements.
- Glance renders through `RemoteViews`, so launcher accessibility remains a physical-device gate. Pixel 7/API 37 QA confirmed whole-card TalkBack focus and activation, unclipped 1.3× font layouts, Arabic RTL mirroring, light/dark contrast, and compact-to-tall resizing.
