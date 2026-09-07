# Android manual accessibility QA

**Status: checklist, not an executed result.** The selector/editor implementation builds, but its expanded Pixel matrix and the manual checks below remain pending. See [the audit and validation inventory](accessibility-android.md).

## Prepare safely

- Start with the designated Pixel 7 (`2C061FDH200CJN`), then record independently tested OEM/device combinations. Record OS, app revision, theme, locale, font/display settings, keyboard and TalkBack version.
- Use real production composables with the in-memory synthetic fixtures in `app/src/androidTest/java/com/healthmd/presentation/accessibility/`. Do not grant real health permissions, select folders, purchase, persist settings, schedule exports or clear actual history.
- A manual host must keep the fixture alive and allow accessibility services. Normal instrumentation may suppress TalkBack and controls its own timing; do not interrupt an assertion sequence and count that exploration as an automated pass. An interactive manual session is a separate gate, not a mode currently supplied by the safe runner.
- Only an authorized human operator should choose or change system accessibility settings. Record previous settings and restore them afterward. Agents must not change device-wide settings on the user's behalf without approval.
- Capture only synthetic app content. Do not capture the full device display, notifications, real values or personalized keyboard suggestions.

Run the independent automated gate first when the Pixel is available:

```sh
cd apps/android
ANDROID_SERIAL=2C061FDH200CJN scripts/run-accessibility-ui-tests.sh /tmp/healthmd-android-accessibility-complete
./gradlew :app:testPlayDebugUnitTest :app:lintPlayDebug --console=plain
scripts/test-accessibility-ui-runner.sh
```

The expected UI inventory is 402 cases, not a nonzero partial count. Never substitute `connectedPlayDebugAndroidTest`, uninstall the app or clear its data. The host runner self-test uses fake binaries and is not a device test.

## TalkBack traversal and activation

| Surface | Check |
| --- | --- |
| Metric selection | Back and Search are discoverable; search results remain reachable. Category expansion and selection are independent, with full/partial/off and expanded/collapsed announcements. Each metric has one label/unit/state and one activation. Collapsing a group leaves focus somewhere predictable. |
| Profile schedules | Names and summaries are readable before distinct Edit Schedule, Delete and enable targets. Spoken actions identify the profile. Menus announce their current value; returning from a menu retains useful focus. |
| Profile dialogs | Full title and every field can be read. Save/Cancel remain discoverable when they join the scroll in short windows. Cancel/dismiss does not save. Enabling protection after opening rejects confirmation but permits cancellation. |
| Format options | One radio/switch action per choice, with selected state, complete descriptions and no duplicate indicator focus. Frontmatter navigation and Back have meaningful labels. |
| Frontmatter | Field/group context distinguishes repeated labels, Add and Delete. Disabled output keys are readable but cannot be edited. Long original/custom values remain available without requiring activation of Delete. Check verbosity and repeated reading of long-value previews. |
| Dates/history | Four mutually exclusive presets announce selection; custom-date actions announce label and value. Clear History is separate from its heading, blocked while protected and requests confirmation rather than deleting immediately. |

Also verify real containing-route navigation separately: a stateless fixture recording a Back callback is not proof of navigation focus restoration. The export-profile editor's containing metric overlay and native calendar picker windows were not repaired/certified by the bounded selector/date-row work.

## Keyboard and short windows

Use portrait and actual short landscape, with both a soft keyboard and a hardware keyboard where available:

1. Focus first and last numeric/key/template fields. Keep the label, caret and current value discoverable while scrolling; test selection, cursor movement and multilingual composition.
2. Reach Add, Reset, preview, Save, Cancel and Back without reducing type size. Check both inner template scrolling and outer form scrolling.
3. Enter valid, empty and invalid numeric drafts. Preserve profile hour/minute/lookback limits and its positive-Int cadence range; do not impose the legacy schedule's five-digit limit on profiles.
4. Confirm focus/state survive reflow. Distinguish Back hiding the IME from Back dismissing a dialog. Verify cancellation leaves original values unchanged.
5. Check actual system bars, cutouts, IME/extract-mode resizing and popup placement. The embedded dp matrix and the format test's remaining-height budget are not equivalent to every native window geometry.

## Magnification, reading and discovery

- At enlarged text **and** display size, locate lower fields/actions without being told where to scroll. Check both themes and long German, Arabic/RTL and Japanese labels.
- Read a long metric name, profile name, key/value, explanation and template reference. Record fragmented wrapping or excessive action/title height even when every glyph is technically reachable.
- Assess onboarding explanation/primary-action discovery, setup auto-advance timing and reading pace with people who use these accommodations. Geometry and pointer checks cannot establish subjective comfort.
- Check text-only navigation labels, selected state, traversal order and content clearance under magnification.

## Record evidence

For each check, record **passed / failed / not tested**, exact setup, expected versus observed announcements/focus/geometry, and a reproducible synthetic case. Keep automated counts, visual inspection and human observations separate. Do not mark TalkBack, Apple/VoiceOver, OEM compatibility or app-wide accessibility verified from Compose semantics alone.
