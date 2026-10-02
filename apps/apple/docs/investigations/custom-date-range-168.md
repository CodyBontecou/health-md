# Custom date-range reentry investigation (#168)

Refs https://github.com/CodyBontecou/health-md/issues/168

## Status and scope

**Not reproduced; no production fix claimed.** The report describes Health.md
3.4.2 (202609171600), iOS 26.7: complete a Custom week, reopen the selector,
find Custom unavailable, then recover by selecting Today. The exact screen and
meaning of “complete” remain unknown. This investigation adds behavioral tests
for persistence and reachable preset reentry, not a speculative calendar fix.
No local simulator/device tests were run in the source-only issue lane.

The platform-neutral expected outcome is repeated custom ranges, earlier or
later, without resetting to Today. Only Apple tests/documentation change here;
there is no new staged capability, Android behavior change, or export/protocol
schema change. Existing saved selection offsets and local files are untouched.
Rust, CLI, website and the Obsidian consumer have no changed public boundary.

## Reachable screens and distinctions

- `HealthMd/iOS/ContentView.swift` binds `startDate`, `endDate`, and
  `dateRangePreset` directly into the Export tab. Its normal launch restores
  persisted dates; UI tests deliberately start with the default selection and
  do not persist it.
- `HealthMd/iOS/Views/ExportTabView.swift`, `dateRangeSection`, has inline
  preset buttons. Custom shows two native date pickers, not an app-owned
  range-selector sheet with a completion action. `selectDateRangePreset(.custom)`
  retains both dates. `SchedulingDatePresets` in
  `iOS/Components/SchedulingA11yComponents.swift` dispatches even when selected;
  selected styling/AX “Selected” is not a disable condition.
- The start picker accepts `...endDate`; the end picker accepts
  `startDate...Date()`. Thus a retained week restricts individual calendar days.
  To move the whole week earlier without crossing bounds, edit **start first,
  then end**; to move it later, edit **end first, then start** (not beyond today).
  This is a source-derived interaction plan, **not runtime evidence** and not a
  confirmed explanation of the reported gray Custom button.
- “Prevent Accidental Changes” uses `performConfigurationChange` and protected
  bindings. It can reject edits without disabling Custom because it is selected.
  Record its state during reproduction; do not bypass the guard or reset saved
  dates as a purported fix.
- `iOS/ClinicianReport/ClinicianReportView.swift` is another Custom/date-picker
  surface with retained bounds. It has report presets rather than Today. Confirm
  the screen before attributing the report to this surface.
- `iOS/Components/ExportModal.swift` has graphical pickers but no `ExportModal(`
  instantiation was found in current Apple Swift sources. Do not claim that
  testing or patching this legacy component verifies the reachable Export tab.
- `macOS/Views/MacContentView.swift` routes Home, CLI and Settings; the Mac is a
  destination agent, not the initiating date-range screen. Legacy `MacExportView`
  is not evidence of current macOS applicability. If feedback concerns a Mac
  screen, obtain navigation/video before proposing a Mac fix.

Apple's [public DatePicker documentation](https://developer.apple.com/documentation/swiftui/datepicker)
was read during this investigation. It documents the native calendar
presentation/dismissal and the `in:` selection restrictions. Those API contracts
do not prove how iOS 26.7 renders or behaves in the reported runtime.

Android's `presentation/export/ExportDateControls.kt` retains tappable Custom
presets; `ExportScreen.kt` presents separate Material date dialogs with explicit
confirmation and resets only their presentation booleans on dismissal. It
preserves current dates on Custom reselection. These are different native UI
flows, not evidence of an Android lockout or a reason to change Android now.
The existing shared export capability in
`packages/contracts/product-capabilities.json` is unchanged.

## Added regression evidence and its limits

| Criterion | Concrete evidence | Remaining verification |
| --- | --- | --- |
| Identify exact screen / reproduce or explain mismatch | Reachable route and picker/preset analysis above; retained production blob identities below | Reporter navigation and video; native calendar dismissal may be what “complete” means |
| Consecutive earlier/later Custom ranges without Today | `ExportDateRangePresetTests.testConsecutiveCustomWeeksCanBeSavedAndReopenedEarlierAndLaterWithoutToday`: May 8–14 → May 1–7 → May 15–21; each resolved, saved, read by a fresh store and reselected | Model/persistence only; native date selection still required |
| Preserve existing local selection semantics | `testSecondCustomWeekReplacesRollingOffsetsOnNextLaunch` checks that the second week's offsets, not the first's, roll forward on the next day | No migration or production store changes |
| Distinguish disabled preset from disabled calendar days | `ExportJourneyUITests.testDateRangePresets_selectedCustomRemainsEnabledAfterLeavingAndReopeningExport` taps already-selected Custom on Export reentry, asserts selected/enabled preset and enabled pickers, retains a screenshot | Does not open/dismiss a native calendar or edit a week; verify bounds and guard state on the reported OS |
| Completion, reopening, second Custom selection | Persistence test covers completed saves/reopens; UI test covers selected preset reentry without Today | **Exact native completion/reopening/two-week UI regression is still missing** pending confirmed screen and runtime AX hierarchy |
| macOS applicability | Current destination-agent routes, not legacy UI | No macOS selector verification claimed |
| Merged-source / release provenance for a fix | Base/tag comparison below and draft PR/CI receipts in lane report | No fix merged or shipped; owner must record merge SHA and eventual release tag/build if a fix follows |

Both new model tests are in the existing synchronized `HealthMdTests` target,
run by Apple CI's iOS and macOS unit-test schemes. The new UI test is in the
existing synchronized `HealthMdUITests` target and explicitly selected by
`.github/workflows/apple-ci.yml`'s iOS smoke invocation. These are behavioral
XCTest tests, not source-string assertions. Cloud run receipts belong to the PR
and issue-lane report; a queued run or a registered test is not a passing result.

## Required runtime evidence / bounded next step

Obtain a short recording beginning at app launch that shows the tab/navigation,
Custom selection, selected dates, completion/dismissal action, reopening, gray
control, and Today recovery. Record device model, exact OS/app version/build,
locale, time zone, text size, and Prevent Accidental Changes state. A screenshot
must distinguish the **Custom preset pill** from **calendar day cells**. Do not
collect health values or export file contents.

On the confirmed screen, run these cases on the reported OS and a current
supported OS, with protection off, then repeat with protection on to identify
expected guard rejection:

1. Select an inclusive seven-day range in the past, dismiss/complete the native
   picker, reopen and select Custom again without Today. Verify enabled preset,
   date readback, and no unintended reset.
2. Move to an earlier non-overlapping week (start then end); dismiss/reopen each
   native picker. Verify both dates, selected Custom and retained enabled state.
3. Move to a later non-overlapping week still in the past (end then start), with
   the same dismissal/reentry assertions.
4. Deliberately attempt start-after-end and end-before-start; distinguish native
   bounded day cells from a disabled preset. Record actual behavior rather than
   inferring it from tint alone.
5. Repeat across month/year boundaries and large text; background/foreground the
   app separately from picker dismissal. Preserve existing saved-range behavior.

Capture the native accessibility hierarchy in an authorized simulator run and
turn the confirmed completion interaction into a registered UI regression. If
the report cannot be reproduced, keep the issue open with OS/build and attempted
cases. Do not reset user data, disable range bounds, or assert a guessed cause.

## Source / release ledger

Live issue and all-state PR searches for `168`, `custom date`, and `date range`
were refreshed before editing. No covering implementation PR was found.
PR [#72](https://github.com/CodyBontecou/health-md/pull/72) merged persistence
as `a302409dc7833e1a5a24a0eb4b5f5c7d1375ba6d`; it is not a reentry fix.

At investigation time remote main and this lane's base were
`b8fd904f4d299f5af4a22111d2fdccf829705ea7`. Tag v3.4.2 points to
`837687662aa2853d1872724c72a97e1526519bbc`; that source declares marketing
version `3.4.2` and build `202609171600`. `git ls-tree` shows identical blobs
at the tag and base for:

- ExportTabView: `d0b1efcf58b6ddef28adcced1caedd187bc72632`
- SchedulingA11yComponents: `c375821c3243d0849e85808651a1786e723070c4`
- Original ExportDateRangePresetTests: `6ca49139742ed9a4b4c627c0f3fef79b7fb1f1b5`
- Original ExportJourneyUITests: `3cf494772c32c8677e2ce5bd67a54f8b697beb8f`

This establishes source identity, not proof of the installed binary or runtime
reproduction. No ASC, merge, release, deployment, or automatic issue closing was
performed. Any eventual production fix needs its exact merge SHA, qualified CI
SHA, release tag/version/build, and runtime QA receipt recorded by the owner.
