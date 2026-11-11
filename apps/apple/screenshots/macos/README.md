# App Store screenshots

This is the runbook for every App Store slide: iPhone, iPad, iPhone Duo and Mac. The slides come from the App Store boards in [`docs/design/liquid-glass/screens/AS_*.dc.html`](../../../../docs/design/liquid-glass/screens) (sizes in the design [README](../../../../docs/design/liquid-glass/README.md), rows 16–19), filled with real captures of the app. (The file lives here because this folder was the original Mac runbook and `.gitignore` already tracks it.)

Two steps produce a slide:

1. **Capture** the real app screens with deterministic fixture state.
2. **Compose** each board with `scripts/app-store-screenshots/compose.swift`. It renders the board's own HTML with WebKit, so background, artwork, device frames, rotation, positions and type come from the board's inline styles. It swaps each `<dc-import>` screen for a capture and the headline and caption for the requested locale's copy, then writes an sRGB PNG with no alpha at exactly board size × export scale.

Nothing here uploads to App Store Connect.

## Boards, captures and outputs

| Board | Size × scale = pixels | Copy | Captures | Output |
| --- | --- | --- | --- | --- |
| `AS_iPhone_1…9` | 440 × 956 × 3 = 1320 × 2868 (`IPHONE_69`) | `scripts/app-store-screenshots/iphone.json` | `iphone-*.png` from `AppStoreScreenshotUITests` on iPhone | `fastlane/screenshots/<locale>/appstore-ios-slide-N.png` |
| `AS_iPad_1…3` | 1376 × 1032 × 2 = 2752 × 2064 (`IPAD_PRO_3GEN_129`) | `scripts/app-store-screenshots/ipad.json` | `ipad-*.png` from `AppStoreScreenshotUITests` on iPad | `fastlane/screenshots/<locale>/appstore-ipad-slide-N.png` |
| `AS_Duo_1…3` | 951 × 669 × 3 and 466 × 678 × 3 (no App Store type) | `scripts/app-store-screenshots/duo.json` | `duo-*.png` from a real device | `screenshots/app-store/duo/<locale>/` (not fastlane) |
| `AS_Mac_1…2` | 1440 × 900 × 2 = 2880 × 1800 (`DESKTOP`) | `screenshots/macos/copy.json` | `sync.png`, `cli.png` from `capture-macos-app-store-screenshots.sh` | `fastlane/screenshots-macos/<locale>/` |

Each JSON maps a board's `<dc-import>` names to capture files and holds per-locale copy. A headline is one string per line, and `{…}` marks the accent-coloured run. The en-US copy is the board's text verbatim. The compositor refuses to render if en-US no longer matches the board, if a board is missing from the JSON (or the reverse), or if the pixel size is not one App Store Connect accepts for the display type. Run the drift check after any board or copy edit:

```bash
cd apps/apple
for copy in scripts/app-store-screenshots/{iphone,ipad,duo}.json screenshots/macos/copy.json; do
  swift scripts/app-store-screenshots/compose.swift --copy "$copy" --check
done
```

Every JSON (iPhone, iPad, Duo and Mac) has copy for all 10 locales: en-US, de-DE, es-ES, fr-FR, it, ja, ko, nl-NL, pt-BR and zh-Hans, and lists them in `supportedLocales`. en-US is checked verbatim against the boards; the other locales are translations whose rendered line fit must be reviewed on the composed slides.

Copy is ahead of the committed slides. Until a capture run is composed and applied, `fastlane/` still holds the earlier sets: the iPhone slides are the previous designs with glass captures swapped in (en-US only), the iPad set is the previous four slides, and every Mac locale has the previous five-slide light set (`01_sync_with_iphone.png` … `05_configure_your_app.png`). Applying the boards replaces them, as described under each platform below. Decorative board text (sample cards, chips, the terminal block) is part of the board and stays in English. The compositor drops web fonts and uses the system font that leads every board's font stack, so output does not depend on the network.

## iPhone and iPad

Simulator runs need the user's explicit approval under the root [verification policy](../../../../AGENTS.md#verification-policy).

`AppStoreScreenshotUITests` runs only when `APPSTORE_SCREENSHOT_DIR` is set. Every board shows the dark glass UI, so set the simulator to dark appearance first (`xcrun simctl ui <device> appearance dark`, in the loop below); `XCUIDevice.appearance` does not take effect on every runtime. On iPad it also rotates to landscape. It launches with `UITestLaunchHelper` fixtures, the four automations of the boards (Daily, Weekly CSV, the API automation Agent feed with Today Refresh, and the paused Mac archive; `UITEST_APPSTORE_FIXTURE_PROFILES`), and in-memory seeded coverage (`UITEST_SEED_COVERAGE`). Every automation uses the build's default metric selection, so Default metrics shows the real default count. Settings and the CLI captures show a paired computer, `Studio Mac`, paired by QR earlier today, with Direct CLI access on (`UITEST_APPSTORE_PAIRED_CLI`; display only: no Keychain trust, no network). The boards also show Connected apps · WHOOP; that row exists only in builds with `CONNECTED_APPS_WHOOP_ENABLED=YES`, where `UITEST_APPSTORE_CONNECTED_WHOOP` lists a WHOOP connection without a token. Pass `CONNECTED_APPS_WHOOP_ENABLED=YES` to `xcodebuild test` only when the release being captured ships WHOOP; otherwise the row is truthfully absent. The coverage pattern (`CoverageScreenshotFixture`) is keyed to day numbers of the month before the current one: Daily is missing on the 19th and 20th and partial on the 12th and 26th, Agent feed sends no refresh on the 15th and some on the 7th, 19th and 23rd, and Mac archive is paused from the 22nd. Every Archive capture opens that month and selects the board's day (the 19th, or the 15th for Agent feed), so captures look the same on any date. The month and weekday labels are the real ones for that month, not the boards' October 2026. Files are named `<device>-<screen>.png`, where `<device>` is `iphone` or `ipad` from the idiom, or `APPSTORE_DEVICE` if set.

- iPhone uses the **iPhone 17 Pro Max** (6.9″). The boards frame a 390 × 844 pt screen, so the 440 × 956 pt capture is cover-fitted from the top. The steps for AS_iPhone_1…9 are `archive`, `automation` (the Daily automation's composer), `archive-profile`, `metrics`, `formats`, `export-now`, `automations`, `settings` and `cli`; `export-now` selects 7 days, as on ExportNowG (the dates are the real last seven days). The test also captures the screens used outside the boards.
- iPad uses the **iPad Air 11-inch (M3)** in landscape. The boards frame an 1180 × 820 pt window, which matches it exactly. The steps for AS_iPad_1…3 are `archive`, `automations` (list beside the composer) and `settings-cli` (Settings with the CLI detail).

```bash
cd apps/apple
CAPTURES="$PWD/screenshots/app-store/captures/en-US"   # git-ignored
mkdir -p "$CAPTURES"

for DEVICE in "iPhone 17 Pro Max" "iPad Air 11-inch (M3)"; do
  xcrun simctl boot "$DEVICE" 2>/dev/null || true
  xcrun simctl ui "$DEVICE" appearance dark
  # iOS 26 simulators apply the appearance after a restart.
  xcrun simctl shutdown "$DEVICE"; xcrun simctl boot "$DEVICE"; xcrun simctl bootstatus "$DEVICE" -b
  xcrun simctl status_bar "$DEVICE" override --time 9:41 --dataNetwork wifi --wifiBars 3 \
    --cellularBars 4 --batteryState charged --batteryLevel 100
  TEST_RUNNER_APPSTORE_SCREENSHOT_DIR="$CAPTURES" xcodebuild test \
    -project HealthMd.xcodeproj -scheme HealthMd-UITests-iOS \
    -destination "platform=iOS Simulator,name=$DEVICE" \
    -only-testing:HealthMdUITests/AppStoreScreenshotUITests
done
```

`TEST_RUNNER_`-prefixed variables reach the UI test runner as `APPSTORE_SCREENSHOT_DIR`.

The test finds every element by accessibility identifier (and automations by their fixture names, which are the same in every language), so it runs unchanged under any simulator language. The fixture automations match the boards: Daily writes Markdown + Bases with daily notes on, Weekly CSV writes to its own `Files/Exports` folder in the app container, and Agent feed refreshes Today every 3 hours (the closest real option to the board's 2 hours).

**AS_iPhone_7 widget insert.** The board inserts the small Health Summary widget (`WidgetSummaryG`). XCUITest cannot place or render a Home Screen widget deterministically, so this capture is manual. Add the small Health Summary widget to the iPhone simulator's Home Screen. Its values come from the simulator's Health data, so add sample data in the Health app first; otherwise it shows its empty state. Take `xcrun simctl io booted screenshot home.png`, then crop the widget to a 510 × 510 px square named `iphone-widget-summary.png` in the captures folder (`sips -c 510 510 --cropOffset <y> <x> home.png --out …`). Without this file the compositor leaves the insert out and says so; it never draws a stand-in.

Compose:

```bash
for ENTRY in iphone:IPHONE_69 ipad:IPAD_PRO_3GEN_129; do
  PLATFORM="${ENTRY%%:*}"; TYPE="${ENTRY#*:}"
  swift scripts/app-store-screenshots/compose.swift \
    --copy scripts/app-store-screenshots/$PLATFORM.json --locale en-US \
    --captures "$CAPTURES" --output build/app-store-slides/$PLATFORM
  asc screenshots validate --path build/app-store-slides/$PLATFORM --device-type "$TYPE" --output table
done
cp build/app-store-slides/iphone/*.png build/app-store-slides/ipad/*.png fastlane/screenshots/en-US/
```

The board set has three iPad slides. When you apply it, delete the old `appstore-ipad-slide-4.png`, which has no board, and review the diff before committing. For another locale, capture with that simulator language and pass `--locale` to the compositor, writing into `fastlane/screenshots/<locale>/`.

## iPhone Duo

No simulator models the iPhone Duo inner (951 × 669 pt) or outer (466 × 678 pt) display. App Store Connect also has no display type at those sizes (`asc screenshots sizes --all`). An iPad or a landscape iPhone would show a different layout (`GlassWindowClass`), so neither stands in honestly. The Duo slides therefore need captures from a real device:

- `duo-outer.png`: Archive on the outer display.
- `duo-inner-archive.png`: Archive unfolded.
- `duo-inner-automation.png`: an automation's composer unfolded.

`AppStoreScreenshotUITests` writes these names when `APPSTORE_DEVICE=duo`. It reads the display it runs on from the window's short side, so run it twice on the device, once folded and once unfolded. The launch sets `glass.hasSeenUnfoldedLayout` in the argument domain (nothing is persisted), so the folded capture shows DuoOuterG's unfold invitation in either order. The status bar cannot be overridden on a device; set the clock and battery by hand or retake. Device runs need the same explicit approval as simulator runs.

```bash
# Folded, then again unfolded (DEVICE_ID from `xcrun xctrace list devices`).
TEST_RUNNER_APPSTORE_SCREENSHOT_DIR="$CAPTURES" TEST_RUNNER_APPSTORE_DEVICE=duo xcodebuild test \
  -project HealthMd.xcodeproj -scheme HealthMd-UITests-iOS \
  -destination "platform=iOS,id=$DEVICE_ID" \
  -only-testing:HealthMdUITests/AppStoreScreenshotUITests
```

Compose them for review outside fastlane:

```bash
swift scripts/app-store-screenshots/compose.swift --copy scripts/app-store-screenshots/duo.json \
  --captures "$CAPTURES" --output screenshots/app-store/duo/en-US
```

## Mac

`capture-macos-app-store-screenshots.sh` builds `HealthMd-macOS` (Debug) under the dedicated bundle identifier `com.codybontecou.obsidianhealth.screenshot`. That way capture never closes, reads from or changes a development or production copy of Health.md. `MacMarketingCapture` and its fixture hooks compile only under `DEBUG && os(macOS)`. They:

- use dark appearance by default, matching the boards. `MAC_SCREENSHOT_APPEARANCE=light` reproduces the earlier light set; the switch is scoped to the capture path, and production UI keeps following the system;
- use the neutral peer name `Demo iPhone`, display `~/Health.md Demo/Exports` while writing only to an isolated temporary folder, and use a fixed storage capacity and three export events relative to the capture date (today 11:02 PM, yesterday and nine days ago, one file each), matching the "Last export" value;
- disable real browsing and persisted activity-history writes;
- show a fixed "Last export" (today 11:02 PM, 1 file) without reading or writing export history, and show manual IP connections as on, with fixed addresses `192.168.1.24 · 100.64.0.12` and code 4821, never the capturing Mac's real interfaces (the manual IP server is not started);
- show an encrypted query context status of 30 days with both delete rows, without opening the Keychain-backed store;
- select the sidebar destination for each screen: `sync` is the home pane (MacHomeG), `cli` the CLI & MCP pane (MacCLIG);
- size the window to 1100 × 720 pt including the title bar, and capture it at 2× (2200 × 1440).

Capture mode starts the real localhost control server before capturing, so the CLI pane reports "Running on localhost" as on the board. Quit any other running Health.md first; if its port is taken, the pane truthfully shows "Not running" and the capture should be retaken.

Capture and compose in one step (the default screens are `sync cli`; override with `MAC_SCREENSHOT_SCREENS`):

```bash
./scripts/generate-macos-app-store-screenshots.sh en-US
# or recompose existing captures:
MAC_SCREENSHOT_SKIP_CAPTURE=1 ./scripts/generate-macos-app-store-screenshots.sh en-US
```

The script composes into a temporary folder. It checks each slide is 2880 × 1800 sRGB, then deletes every PNG in `fastlane/screenshots-macos/<locale>/` (the old five-slide set included), copies in the board slides and records `asc screenshots validate` output in `screenshots/macos/review/<locale>/asc-validation.json`. Board copy exists for all 10 locales, so run it once per locale; a locale not yet run keeps its old five slides, which must not ship beside the new ones.

Observed toolchain: macOS on a Retina display, Xcode 26.6+ with Swift 6, `asc` 3.7+. Only Xcode and macOS frameworks are used.

## Review

Before committing, review every slide at 100% and at thumbnail size (about 20%). Check for clipping, contrast, stale claims, personal data, and agreement between the copy and the app. `git diff --check` and `asc screenshots validate` must pass.
