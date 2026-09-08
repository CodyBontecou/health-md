# Liquid Glass mobile workspace

Home is a feed of health trends over a selected date range with a compact active-profile selector.
Movement switches between steps, active energy, and exercise. Sleep combines a
stage-composition ring with stacked daily bars. Health signals pairs compact
sparklines with selectable resting heart rate, HRV, and respiratory trends.
The export activity chart counts saved runs. Home, Activity, and Connections remain the three tabs.
The Home toolbar opens the profile manager or **Edit export**.

Edit export follows the compact profile-detail layout: section headings and
label/value rows, with subdued chevrons. Filename and folder rows open their
editors directly. Metrics, data detail, ZIP, dictionary, write behavior, daily
notes, and individual entries each have a focused destination. Other saved
profiles also expose tappable facts; those editors work on isolated drafts and
commit through `ExportProfileCoordinator` only on Save.

The workspace binds to the existing `AdvancedExportSettings`, `VaultManager`,
and `ExportProfileCoordinator`. Active-profile changes retain immediate
persistence; filename/folder sheets and saved-profile drafts retain Save/Cancel.
Configuration protection continues to intercept mutations.

## Selecting and inspecting profiles

The Home profile strip labels the active profile and opens the selector when
tapped. Its separate Edit action opens the active export settings. In the
selector, tapping a profile applies it immediately and closes the sheet; the
checkmark, Active profile label, and outline identify the current choice. Each
row's separate Edit action opens its editable facts without activating it.
Profile names wrap, and the Edit action moves below the summary at accessibility
text sizes.

An inactive profile's detail has a persistent **Make active** action in the
bottom safe area, visible on arrival and while scrolling. Successful activation
closes the whole selector and updates the originating workspace. The existing
coordinator flushes outgoing edits and adopts the selected snapshot and
destination. Failed activation keeps the current view open with an explanation.
Configuration protection guards both activation controls; tapping the already
active choice simply closes the selector. Done also closes without changing it.

This is a native navigation refinement of the shared `export.profiles`
capability. Android's `ExportProfilesScreen` and `ExportProfilesViewModel.activate`
already expose selection and separate settings inspection using the same
activation outcome; their Material navigation is unchanged. Profile persistence,
schedule behavior, and public export contracts are unchanged.

## Native appearance

- On iOS 26 and later, native tabs and toolbars provide Liquid Glass. Primary and
  secondary actions use `glassProminent` and `glass` styles with capsule shapes.
- Earlier supported iOS versions use bordered system buttons and standard tabs.
- Content uses opaque system grouped surfaces. Glass is reserved for navigation
  and actions, following Apple's [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials).
- Mobile typography uses semantic system styles for Dynamic Type. Native glass
  responds to the system's transparency, contrast, and motion preferences.
- Controls retain the purple app accent. Charts use orange for steps, coral/pink
  for energy and heart rate, green for exercise, blue/cyan for sleep, and teal
  for HRV and exports. Every chart also has text labels and units. macOS retains
  the existing Geist tokens.

## Feature coverage

| Workspace entry | Existing implementation |
| --- | --- |
| Health data | Metric selection, detail policy, Health permission setup |
| Health files | Formats, ZIP, dictionary, metadata, grouping, range summaries |
| Names & folders | Subfolder, filename tokens, folder organization, format folders |
| Existing files | Update, Append, Overwrite; current format-specific semantics |
| Daily notes | Root-relative note location, missing notes, properties, sections, notes-only |
| Individual entries | Supported metrics, event files, category and filename configuration |
| Format & fields | Units, dates, property naming, Markdown templates and presentation |
| Destination | Local folder, connected Mac, API endpoint |
| Schedule | Existing global and per-profile schedule controls |
| Review export | Date range, real generated-file preview, existing export execution |
| Activity | Existing history, file operation details, retry and recovery |
| Connections | Existing Mac and direct CLI pairing; application settings |

The HTML design exploration used fictional examples. The native app's preview
uses its existing bounded HealthKit preview path and existing output planners;
no sample health records are added to normal app runs.

## Health and activity charts

The platform-neutral outcome is a bounded overview of available daily health
readings and recent export operations. Home reads only `steps`, `active_energy`,
`exercise_time`, `sleep_total`, `sleep_core`, `sleep_rem`, `sleep_deep`,
`resting_heart_rate`, `hrv`, and `respiratory_rate` through the existing summary
capture path. These trend
cards have their own fixed read selection and do not alter a profile's export
selection. Dates use the current local calendar, including DST.

- Steps and active energy use existing daily cumulative totals; exercise uses
  Apple Exercise Time, which is not interchangeable with workout duration.
- Sleep uses the existing noon-to-noon owner-day reducer, converted from seconds
  to hours. The date identifies the start of that window, including naps. Stage
  totals use existing deduplicated reducers. Unclassified sleep remains
  Unspecified. If stage totals exceed total sleep (overlapping sources), the
  composition is unavailable and only the total is shown. No invented timeline
  is reconstructed from duration totals.
- Resting heart rate shows the most recent reading within each day, not an average.
- HRV shows HealthKit daily-average SDNN in milliseconds. Respiratory rate shows
  the daily average in breaths/minute. Dashed lines are arithmetic means of the
  available daily values in the selected range, with missing days excluded and
  recorded zeros retained. They are not clinical baselines or normal ranges.
- The visual references are [Apple Health sleep](https://support.apple.com/en-us/108906)
  and [WHOOP trend views](https://support.whoop.com/s/article/Viewing-Trends):
  distinct metric colors, sleep-stage proportions, compact signals, and direct
  chart selection. The feed does not calculate WHOOP strain/recovery scores.
- Missing readings remain gaps; only recorded zero values appear as zero.
- Failed days retain their positions, and the UI explains a partial read.
- Readings stay in memory, with a five-minute reuse window and pull-to-refresh.
- Tapping a chart keeps its selected day's value and date visible.
- Export activity uses `ExportHistoryManager` timestamps and success state. It
  counts runs, not inferred file totals, and discloses the 50-entry retention limit.

## Visualization dates

One date control above the charts sets their shared inclusive local-day range.
The initial view follows the latest seven days. Users can choose 30 days, tap
Custom or the date label to edit start/end dates, or move by the current range's
length using the arrows. The next arrow is disabled at today; Back to latest
returns to a rolling range ending today. Presets preserve a historical end date
when changing duration. Custom ranges contain 1–90 days and cannot end in the
future. The editor uses native [DatePicker](https://developer.apple.com/documentation/swiftui/datepicker)
controls, with Apply/Cancel; invalid ranges cannot be applied.

This is read-only exploration and remains available under configuration
protection. It never changes export dates, profiles, schedules, or file output.
The selection survives navigation within Home, but is not persisted across app
launches. Returning from the background refreshes the local calendar context;
a rolling range advances at local midnight. Reads remain summary-only, show
progress by day, and use a five-minute cache keyed by range and calendar/time
zone. A new selection clears obsolete data; superseded or cancelled requests
cannot publish results. Each chart day has a unique date identity, with sparser
axis labels for longer ranges and accessibility text sizes. Chart selections
reset on a range change. Export activity uses the same dates while still
reflecting only the 50 retained runs.

Android's existing bounded range reader accepts a list of local dates. The
Mobile profile feed milestone explicitly includes these date-navigation
semantics before this prototype graduates to a shared release. No export,
protocol, metric mapping, or consumer schema is affected by chart navigation.

## Platform boundary

Export bytes, public metric identities, schemas, and device protocols are unchanged.
The new feed is staged in the capability inventory as `planned`: Apple has the
native prototype; Android's target is the Mobile profile feed milestone before
this redesign graduates from device testing to a shared release.

Android's `HealthConnectWidgetDataSource` and `fetchWidgetHealthDataRange` already
provide bounded local-day reads with explicit missing days. Steps use Health Connect
aggregation, resting heart rate uses `latestRestingHeartRate`, and sleep retains
its existing session/owner-day mapper. Those are the inspected adapter paths for
the Android feed. Its bounded active-calorie aggregate supplies the same energy
unit. ExerciseSession duration remains distinct from Apple Exercise Time; HRV
RMSSD remains distinct from HealthKit SDNN (and uses the Android reducer rather
than silently adopting the Apple average). Core and Light sleep retain their
platform names. Respiratory averages have an existing Health Connect path. The
staged Android target includes these additional charts with explicit platform
labels; no metric-equivalence claim or export remapping is introduced.

Charts use native [Swift Charts](https://developer.apple.com/documentation/charts),
including Apple's [chart selection](https://developer.apple.com/videos/play/wwdc2023/10037/)
interaction. Glass is reserved for controls, keeping chart backgrounds opaque.

## Device testing

Open `HealthMd.xcodeproj` from this worktree, choose scheme `HealthMd`, select the
iPhone, and Run with `Debug-iOS`. The build uses the existing app identifier and
signing team, so installing it updates the development copy of Health.md in place.
Do not uninstall the app to switch builds; reinstalling preserves its container.

Try changing a format and returning to the profile, saving a filename pattern,
opening daily-note and individual-entry settings, reviewing an export, and
checking its result under Activity. Also verify the Connections gear button,
configuration protection, Dark Mode, and larger accessibility text sizes.

Deterministic simulator journeys live in `LiquidGlassWorkspaceUITests`; bounded
reads, missingness, DST, and run counts are covered in `HealthInsightsModelTests`. Those
test launches use the repository's existing test injection hooks; phone launches
use normal HealthKit, destination, purchase, and export services.

## Local verification

Worktree: `/Users/codybontecou/dev/health-md-liquid-glass`  
Branch: `codex/ios-liquid-glass`

- Profile selector iteration: five focused UI journeys passed for direct
  selection, persistent detail activation, protection on both activation paths,
  saved-profile Save/Cancel, and copy-ID/activation/rename. Direct selection and
  the persistent action also passed in Dark Mode with accessibility-large text.
  The sheet-local lock notice sits below the navigation controls so Back and
  Done remain reachable. Signed device build and contract validation passed.

- Twelve `HealthInsightsModelTests` passed: bounded reads across DST, caching and
  refresh by range/time zone, historical run counts, midnight following, preserving
  chosen dates across time-zone changes, superseded reads, units/statistics,
  missing-data behavior, and sleep composition integrity.
- Date navigation passed five focused UI journeys: presets and previous/next/
  latest navigation under configuration protection; custom Apply/Cancel; all
  four charts following 30 days; individual chart-day selection; and metric/
  sleep-stage interactions. The three date-navigation journeys also passed in
  Dark Mode with accessibility-large text. Custom testing changes both dates,
  confirms a five-day chart and its latest reading, rejects a range over 90 days,
  and confirms Cancel retains the previously applied range. The range editor
  closes its owning sheet explicitly after the native calendar closes.
- Final date-range receipts: `build/InsightDates-Final-Unit.xcresult`,
  `build/InsightDates-UI.xcresult`, `build/InsightDates-Final-UI.xcresult`
  (preset/axis polish), `build/InsightDates-Accessibility.xcresult`
  (longer charts), `build/InsightDates-Accessibility-Final.xcresult`
  (preset navigation), and `build/InsightDates-Custom-Completion.xcresult`
  (custom date interaction after fixing sheet dismissal). The latter runs
  supersede the custom-date failures in earlier receipts. Signed iPhone build
  and contract validation passed. Previews are under
  `build/insight-dates-final-previews/` and `build/insight-dates-custom-final-previews/`.
- Nine focused UI journeys passed across the workspace and configuration-
  protection suites, covering profile navigation, formats, naming, daily notes,
  individual entries, real preview/export, saved-profile Save/Cancel, and chart day selection.
- The additional visualization journey passed in Light Mode and Dark Mode with
  accessibility-large text: metric switching, sleep-stage selection, day
  selection, HRV, and respiratory readings. The sleep ring and legend stack at
  accessibility sizes; charts reduce axis labels while retaining every daily
  point. The compact profile also stacks labels and values.
- The existing 59 profile/protection/preview regression tests passed earlier in
  this worktree. Contract inventory validation passed after recording Android's
  staged feed milestone; no schema fixtures or public export versions changed.

Simulator previews use explicit test data. Normal device launches query the
user's existing HealthKit store. Preview images are local build artifacts under
`build/liquid-glass-feed-final-previews/` (`home.png` and `profile.png`) for the
previous iteration, and `build/health-visualizations-final-previews/` for the
expanded charts. Dark accessibility previews are under
`build/health-visualizations-accessibility-v2-previews/`.
