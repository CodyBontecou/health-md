# iOS large-text and control accessibility audit

- Date: 2026-09-07 (UTC)
- Source revision: `a5fbf59f8f3cde73af12bafd6a09dde33db39b98`
- Status: **audit findings; no production fixes applied**

## Summary

The iPhone UI has useful native scrolling/navigation patterns, but it has similar reading and control problems to the Android UI. Its biggest defect is different: **all 19 shared typography entry points ignore Dynamic Type**. Some layouts look contained because their text never grows, while nearby native labels and symbols do grow.

The shared outcome remains: users can read essential labels, understand values and operate controls at their chosen text/display settings without reducing text size. Identical Swift/Kotlin layouts are not required.

| ID | Priority | Finding | Evidence |
| --- | --- | --- | --- |
| IOS-A1 | P1 | Shared typography does not enlarge | Simulator measurements and renders |
| IOS-A2 | P1 | Format selectors fragment labels and hide selected values | Hosted production-row renders; adjacent editor risks from source |
| IOS-A3 | P1 | Custom dialogs lack a short-window/keyboard scrolling strategy | Constrained production-card measurements and source |
| IOS-A4 | P2 | Enabled helper/status text uses insufficient light-theme contrast | Token contrast calculation and use sites |
| IOS-A5 | P2 | Several actions have 24–40 pt layouts, below a 44 pt target | Shared-control measurements plus source; hit expansion not tested |
| IOS-A6 | P2 | Metric and Settings rows restrict readable text width/content | Settings renders and metric source |
| IOS-A7 | P2 | Schedule/date/profile controls need adaptive layouts and clearer edit targets | Source risks; full flows not runtime-verified |
| IOS-A8 | P2 | Paywall/onboarding choices still use shrinking and dense horizontal layouts | Source |
| IOS-A9 | P2 | Existing journey tests do not establish large-text usability | Test-source inspection |

P1 means address before claiming large-text support. P2 means a meaningful follow-up, not a claim that every listed configuration has been reproduced on a physical device.

## Findings

### IOS-A1 — Shared fonts ignore the user's text size

[DesignSystem.swift:231–254](../../HealthMd/Shared/Theme/DesignSystem.swift#L231-L254) says SF fonts provide native Dynamic Type, but the implementation returns fixed `.system(size:weight:design:)` fonts. `bodyMono()` delegates to another fixed-size helper. The font family alone does not make explicit point sizes scale.

An isolated iOS 26.5 probe measured the unchanged production helpers at `.large`, `.xxxLarge`, `.accessibility1` and `.accessibility5`. **Every one of the 19 entry points retained identical text bounds across all four settings.** Five native semantic-font controls grew correctly, confirming the environment reached the renderer.

Example single-line **text-box heights**, not font point sizes:

| Font | Default `.large` | `.accessibility5` |
| --- | ---: | ---: |
| `Typography.body()` (14 pt base font) | 17 pt | 17 pt |
| `Typography.heading24()` | 29 pt | 29 pt |
| `Typography.caption()` | 16 pt | 16 pt |
| Native `.body` | 20.5 pt | 63.5 pt |

This affects page headers, onboarding explanations, metric names, legacy schedule copy, profile summaries and other shared-font users. Onboarding also sets fixed 16/14 pt action fonts directly at [OnboardingView.swift:1732–1773](../../HealthMd/iOS/Views/OnboardingView.swift#L1732-L1773). [StatusIndicator.swift:30–40](../../HealthMd/iOS/Components/StatusIndicator.swift#L30-L40) scales its decorative dot while keeping its status label at 12 pt.

**Recommendation:** make named tokens use appropriate semantic scaling or scaled metrics, retaining intentional base sizes, weights and monospaced figures. Then remeasure callers: enabling scaling will expose additional layout problems. Do not replace the problem with a Dynamic Type cap, `minimumScaleFactor`, or a global visual scale transform. These helpers also serve iPad/macOS; review those consumers rather than changing shared defaults blindly.

[Default versus largest accessibility rendering](accessibility-ios-2026-09-07/typography-comparison-light.png). These are synthetic component renders, not whole-app screenshots. The shared `PrimaryButton`/`IconButton` helpers included in the probe currently have no live call sites found; the typography result and the directly fixed onboarding buttons do not depend on those helpers being used.

### IOS-A2 — Format choices become difficult to read before any font repair

[FormatSelectionRow:998–1057](../../HealthMd/iOS/Views/FormatCustomizationView.swift#L998-L1057) puts a scalable label/description beside a menu in an unconditional `HStack`. The selected value has a one-line, middle-truncated label capped at 190 pt. The surrounding page/card remove another 80 pt of horizontal space.

Hosted, source-extracted production rows at a 320 pt content width show:

- At default text size, `ISO 8601 (2026-01-13)` is already abbreviated in the closed menu.
- At `.accessibility5`, “Date Format” breaks into fragments and the selected value becomes only an ellipsis beside large chevrons.
- The full value remains in accessibility metadata, but that does not make it readable visually.

Related **source-only** concerns in the same editor:

- [FormatTextFieldRow:1094–1129](../../HealthMd/iOS/Views/FormatCustomizationView.swift#L1094-L1129) keeps labels beside a field capped at 180 pt; the labels scale but the monospaced input does not.
- [FrontmatterFieldRow:718–765](../../HealthMd/iOS/Views/FormatCustomizationView.swift#L718-L765) puts a switch, middle-truncated original/renamed keys and a pencil in one row. Custom/placeholder keys and values are also line-limited at [553–618](../../HealthMd/iOS/Views/FormatCustomizationView.swift#L553-L618).
- [MarkdownTemplateView:867–900](../../HealthMd/iOS/Views/FormatCustomizationView.swift#L867-L900) requires a 220 pt `TextEditor` inside an outer scroll, without an explicit keyboard-dismiss/short-window arrangement. Native keyboard behavior needs a separate test; a nested scroll is not itself proof of a failure.

**Recommendation:** put full selected values and inputs below labels when crowded; allow identifiers to remain inspectable without changing stored text. Budget template-editor height for the remaining window and test nested scrolling/keyboard dismissal. Preserve key normalization, settings transformations, configuration guards and export bytes.

Evidence: [default](accessibility-ios-2026-09-07/rows-hosted-large-light.png), [largest accessibility/light](accessibility-ios-2026-09-07/rows-hosted-accessibility5-light.png), [largest accessibility/dark](accessibility-ios-2026-09-07/rows-hosted-accessibility5-dark.png).

### IOS-A3 — Custom dialogs cannot fit sufficiently short content areas

[GeistDialog.swift:195–224](../../HealthMd/Shared/Views/GeistDialog.swift#L195-L224) uses a non-scrolling `VStack`, fixed-size multiline title/message, 24 pt inner padding and a 280–420 pt width. The presenting overlay adds another 24 pt on each side at [110–124](../../HealthMd/Shared/Views/GeistDialog.swift#L110-L124). Fields have a fixed 40 pt height; one/two actions always share a horizontal row and action labels have a two-line limit ([271–308](../../HealthMd/Shared/Views/GeistDialog.swift#L271-L308)).

The actual production “Add Custom Field” card, with two synthetic fields, measured **280 × 277 pt** when offered a **320 × 200 pt host**. The card alone is 77 pt taller than the entire host; the nominal padded area is only 272 × 152 pt. This persisted at all four tested text categories, because the dialog fonts are fixed too. At a 320 × 280 host it only exceeds the *padded allowance*, not the entire host—those are different findings.

This establishes a constrained-layout failure, **not** a measured native-keyboard obstruction on a complete screen. Frontmatter Add/Placeholder/Rename use this component ([FormatCustomizationView.swift:280–346](../../HealthMd/iOS/Views/FormatCustomizationView.swift#L280-L346)); longer permission/help/error messages also need testing.

**Recommendation:** use a scrollable, bounded dialog/sheet with reachable dismissal/confirmation, adaptive action placement and growing labeled fields. Test focus and viewport resizing with the real keyboard. Both fields currently share one Boolean focus state, so verify initial focus and field traversal rather than assuming them. Preserve live protection guards and cancellation behavior.

### IOS-A4 — Muted/status colors are being used for readable content

[DesignSystem.swift:38–45](../../HealthMd/Shared/Theme/DesignSystem.swift#L38-L45) defines `textMuted` as `#8F8F8F`. Its sRGB contrast is **3.23:1 on white** and **3.10:1 on `#FAFAFA`**, below the design specs' 4.5:1 target for ordinary body/helper text. It is used for enabled explanations, not just disabled controls: [format subtitles:963–968](../../HealthMd/iOS/Views/FormatCustomizationView.swift#L963-L968), [metric permission explanation:193–195](../../HealthMd/iOS/Views/MetricSelectionView.swift#L193-L195), and [purchase disclosure:273–277](../../HealthMd/iOS/Views/PaywallView.swift#L273-L277).

`success` (`#28A948`) is also only **3.06:1 on white**, relevant to small enabled-count/status text; tinted pill backgrounds require their own calculation. This is not a claim that every green icon or large label fails. Dark `textMuted` on black is 6.49:1, so the light-theme problem must not be generalized to both themes.

**Recommendation:** reserve muted styling for truly disabled/decorative content; use suitable readable text tokens for explanations and state labels. Add contrast tests for actual foreground/background combinations in both themes. [Calculated values](accessibility-ios-2026-09-07/contrast.json).

### IOS-A5 — Small action layouts need explicit target checks

Measured shared `SecondaryButton`, `DestructiveButton` and default `IconButton` remain 40 pt tall at both default and largest accessibility text ([AnimatedButton.swift:94–96,157,211–213](../../HealthMd/iOS/Components/AnimatedButton.swift#L94-L96)). Secondary/destructive controls have active call sites in setup/storage and Sync. Additional source examples:

- Frontmatter delete/rename: 32 × 32 pt ([FormatCustomizationView.swift:576,608,756](../../HealthMd/iOS/Views/FormatCustomizationView.swift#L576)).
- Paywall dismissal: 36 × 36 pt; Restore Purchase: 40 pt minimum ([PaywallView.swift:115,258](../../HealthMd/iOS/Views/PaywallView.swift#L115)).
- Today Refresh info: 24 × 24 pt ([ScheduleSettingsView.swift:871–883](../../HealthMd/iOS/Views/ScheduleSettingsView.swift#L871-L883)).
- Onboarding repair actions: 36 pt minimum; secondary action: 40 pt minimum ([OnboardingView.swift:1704,1777](../../HealthMd/iOS/Views/OnboardingView.swift#L1704)).

**Recommendation:** establish at least 44 × 44 pt interactive regions and appropriate separation for iOS, while letting labels grow. Inspect real hit regions and edge taps: layout bounds alone do not prove whether the OS expands a target. Do not mechanically substitute Android's 48 dp measurements or count decorative frames as controls. The Apple design specs still describe generic 32/40 px component defaults without an iOS-specific target rule.

### IOS-A6 — Metric and Settings copy is squeezed or truncated

[MetricSelectionView.swift:379–405](../../HealthMd/iOS/Views/MetricSelectionView.swift#L379-L405) clamps category title/subtitle to one line beside an icon, status pill and chevron. [Metric rows:687–730](../../HealthMd/iOS/Views/MetricSelectionView.swift#L687-L730) add 48 pt of leading indentation beyond row/page padding, cap names at two lines, and put the visual label outside the switch. This limits reading width and does not make the whole named row a toggle. Actual VoiceOver grouping/duplication remains unverified.

[SettingsRow:3075–3108](../../HealthMd/iOS/ContentView.swift#L3075-L3108) reserves icon/status/chevron space and caps descriptions at two lines. The hosted Privacy Policy row is visibly abbreviated at default and largest text sizes. At the largest setting its symbols enlarge while its title/description remain small, illustrating IOS-A1 within an active production row.

**Recommendation:** use full-width descriptions and long names, reduce decorative indentation in crowded layouts, and expose one coherent labeled selection control. Keep category expansion distinct from selection. Do not change HealthKit-only permission/availability behavior to copy Android. The current category pill is a status display; the `categoryToggleButton` helper is not called from the rendered category header.

### IOS-A7 — Native schedule controls still need layout-specific review

Source risks include:

- Legacy frequency/Today Refresh/file-mode segmented pickers, 40 pt indents and the unconditional custom-cadence `HStack` with a fixed-size stepper ([ScheduleSettingsView.swift:505–576](../../HealthMd/iOS/Views/ScheduleSettingsView.swift#L505-L576), [813–864](../../HealthMd/iOS/Views/ScheduleSettingsView.swift#L813-L864)).
- Hour/minute/period menus remain in one indented row with no size-based reflow. Their parent combines accessibility children despite containing three independent menu actions ([637–660](../../HealthMd/iOS/Views/ScheduleSettingsView.swift#L637-L660)); actual VoiceOver traversal must be checked.
- Date presets always use two columns, with no minimum target or accessibility-size column fallback ([ExportTabView.swift:429–510](../../HealthMd/iOS/Views/ExportTabView.swift#L429-L510)). They do expose selection state and custom dates already stack vertically.
- Profile schedule rows use a whole-row tap gesture alongside a separate toggle, with no explicit named Edit button ([ProfileScheduleSection.swift:90–130](../../HealthMd/iOS/Views/ProfileScheduleSection.swift#L90-L130)). The editor itself has a native scrolling `Form`, menu/date controls and Save/Cancel toolbar, which is a better starting point.
- Sync's host/port rows retain fixed 82 pt port fields beside long hosts ([SyncSettingsView.swift:332–347](../../HealthMd/iOS/Views/SyncSettingsView.swift#L332-L347), [547–559](../../HealthMd/iOS/Views/SyncSettingsView.swift#L547-L559)).

**Recommendation:** measure these at accessibility sizes, long locales, narrow/short windows and keyboard-open states; reflow controls and use full selected labels where necessary. Preserve numeric limits and native actions. Apple cadence is bounded at 365, unlike Android's profile positive-Int range. Apple's current Clear History immediately performs the guarded deletion ([ScheduleSettingsView.swift:1012–1016](../../HealthMd/iOS/Views/ScheduleSettingsView.swift#L1012-L1016)); adding Android's confirmation would be a separate behavior decision, not a typography fix.

### IOS-A8 — Paywall/onboarding use shrink-to-fit and dense purchase rows

[PaywallView.swift:486–535](../../HealthMd/iOS/Views/PaywallView.swift#L486-L535) puts icon, title/badge, subtitle and price in one row. The subtitle is capped at two lines, while price/loading text permits shrinking to **75%**. Audience choices have a fixed 40 pt height ([416–431](../../HealthMd/iOS/Views/PaywallView.swift#L416-L431)). Onboarding's analogous choices are also 40 pt; its info chips allow 85% text scaling ([OnboardingView.swift:1191–1202](../../HealthMd/iOS/Views/OnboardingView.swift#L1191-L1202)).

Onboarding already scrolls explanations and retains meaningful primary actions, but its centered copy, 64 pt decoration and permanent header/footer need a reading-comfort pass once typography genuinely scales ([65–101](../../HealthMd/iOS/Views/OnboardingView.swift#L65-L101), [1038–1064](../../HealthMd/iOS/Views/OnboardingView.swift#L1038-L1064)). These are source findings, not a reproduced full paywall overflow.

**Recommendation:** let price/details/actions reflow rather than shrinking them; reduce decoration and center alignment where they constrain reading. Keep purchase state, pricing, restore behavior, permission/folder callbacks and onboarding analytics unchanged.

### IOS-A9 — Reachability tests are not large-text verification

[UITestLaunchHelper.swift](../../HealthMdUITests/UITestLaunchHelper.swift) configures deterministic state, but not a text-size matrix. The inspected journey tests mostly establish existence/hittability; [OnboardingJourneyUITests.swift:199–200](../../HealthMdUITests/OnboardingJourneyUITests.swift#L199-L200) accepts 40 pt controls. No Dynamic Type matrix, font-growth assertion or `performAccessibilityAudit` invocation was found in the inspected app test sources. Marketing locale captures do not fill that gap.

**Recommendation:** add a production-backed synthetic suite that checks actual font growth, full labels/values, visible/interactable targets and callbacks at default, largest standard and accessibility sizes. Include narrow portrait, short landscape, Display Zoom, German, Arabic/RTL, Japanese, both themes, keyboard-open fields, native menus/sheets and configuration protection. Keep screen-reader traversal and subjective reading comfort as separate human gates.

## Patterns worth preserving

- Main navigation uses native `TabView` ([ContentView.swift:137–200](../../HealthMd/iOS/ContentView.swift#L137-L200)).
- Onboarding separates scrolling explanation from meaningful setup actions; setup is not trapped behind a disabled Continue.
- Export uses a measured `safeAreaInset` for its footer and stacks actions at accessibility sizes ([ExportTabView.swift:105–111](../../HealthMd/iOS/Views/ExportTabView.swift#L105-L111), [1026–1035](../../HealthMd/iOS/Views/ExportTabView.swift#L1026-L1035)). Width-only/short-landscape behavior still needs testing.
- Profile scheduling uses a native scrolling editor and a live Save protection guard ([ProfileScheduleSection.swift:241–327](../../HealthMd/iOS/Views/ProfileScheduleSection.swift#L241-L327)).
- Settings keeps the main protection explanation outside its labeled toggle. Export status announces changes and has some adaptive actions.

These were useful references for Android, not proof that Apple's complete layouts or VoiceOver behavior were already verified.

## Evidence and limits

The probe ran on an isolated **iPhone SE (3rd generation) simulator, iOS 26.5 (23F77), Xcode 26.6**. It compiled unchanged copies of the production design system/buttons/dialog, with an append-only private-dialog access shim. Format/Settings layout blocks were extracted byte-for-byte; synthetic bindings and an unused no-persistence guard stand-in supplied their dependencies. It did not launch Health.md, invoke its services, open menus, save settings or perform real health/folder/billing/export actions. Only the newly created probe simulator was shut down and deleted afterward; existing simulators/installations and shared build caches were left untouched.

- **96 font observations:** 19 production entry points + 5 native controls × 4 categories.
- **16 control-layout observations:** 4 shared helpers × 4 categories. No pointer hit testing.
- **12 dialog observations:** 3 proposed host sizes × 4 categories. The short host models constrained content, not a real measured IME inset.
- **8 final renders:** typography and hosted rows, default/largest text, light/dark. English only. The 320 pt rows are embedded layout constraints, not a claim of actual system Display Zoom.
- These are **124 diagnostic observations, not 124 passed app tests**. They intentionally expose defects.

[Measurements](accessibility-ios-2026-09-07/measurements.json), [source provenance](accessibility-ios-2026-09-07/provenance.json), and selected PNG evidence are retained beside this report. Full local captures/logs are under `/tmp/healthmd-ios-accessibility-audit-20260907`; the small standalone probe is in the component-scoped build directory recorded in provenance. Initial `ImageRenderer` menu placeholders were capture limitations and are **not** retained as app-defect evidence; final row images use a hosted UIKit hierarchy, with safe-area inheritance disabled and layout remeasured after attachment.

No full-app XCTest run, actual VoiceOver traversal, physical-device Display Zoom/IME/magnification/reading-pace check, localization matrix, or app-wide certification was performed. iPad-specific navigation/window layouts, macOS, watchOS, widgets, OS permission/calendar windows and other unlisted screens require separate review. No production implementation, schema, protocol, metric identity/unit, settings default or export contract was changed by this audit.

## Suggested implementation order

1. Repair shared font scaling and native control/contrast rules; establish measurable regression checks before changing screen layouts.
2. Repair the shared dialog and format/frontmatter controls. Confirm both short-window and real keyboard behavior.
3. Reflow metric/Settings rows, schedule/date/profile controls, onboarding and purchase choices. Preserve the platform's existing callbacks, guards and numeric semantics.
4. Run the complete synthetic app matrix, inspect both-theme captures, then conduct actual VoiceOver and low-vision usability checks. Do not call the work complete merely because source checks or layout probes pass.
