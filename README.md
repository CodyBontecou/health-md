# Health.md

[Download on the App Store](https://apps.apple.com/us/app/health-md/id6757763969)

Health.md exports Apple Health data to your filesystem as human-readable Markdown (or structured JSON/CSV). Your health data stays local and accessible in the Files app, Obsidian, or any markdown-compatible tool.

## What's Included

- **iOS app** — Reads HealthKit data and exports to your device. Configurable formats, filenames, and scheduled exports.
- **macOS app** — Companion destination app that receives export jobs from your iPhone over your local network (Wi‑Fi/Bluetooth) and writes them to a folder on your Mac. Configure formats, metrics, time-series data, filenames, and export actions on iPhone; choose only the destination folder on Mac.

## Documentation

- [Feature documentation index](docs/features/index.md) — canonical feature inventory, docs drafts, and video-series planning.
- [Video series roadmap](docs/features/video-series.md) — multi-part walkthrough plan for feature-focused videos.

## Documentation

- [Feature documentation index](docs/features/index.md) — canonical feature inventory, docs drafts, and video-series planning.
- [Video series roadmap](docs/features/video-series.md) — multi-part walkthrough plan for feature-focused videos.

## How It Works

### iPhone → Mac Destination

HealthKit data is **only available on iPhone** — macOS cannot read the Health store. Health.md solves this by making iPhone the control plane and Mac a local filesystem destination:

1. **iPhone** reads your health data from HealthKit.
2. **iPhone** applies your selected dates, metrics, formats, filename/folder templates, write mode, and time-series settings.
3. **Mac** advertises destination readiness: connected, compatible, folder selected, and folder access healthy.
4. iPhone sends a complete export job directly to Mac — **no cloud, no servers**.
5. Mac writes the received Markdown/Bases/JSON/CSV files to the selected folder.

Both devices must be on the same Wi‑Fi network or within Bluetooth range. Mac Destination is optional — the iOS app works fully standalone.

## Features

### iOS
- **HealthKit export** for sleep, activity, vitals, body measurements, nutrition, mindfulness, mobility, hearing, and workouts.
- **Manual export** for a date range with progress and error handling.
- **Scheduled exports** (daily or weekly) — server-driven via silent APNs push so they fire on the exact minute, not on `BGTaskScheduler`'s loose timing.
- **Apple Shortcuts integration** — `AppIntents` for `Export Yesterday`, `Export Specific Date`, `Export Date Range`, `Export Last N Days`, plus `Get Health Summary` (structured output for downstream shortcuts) and `Get Last Export Status`.
- **Mac destination target** — optionally send iPhone-configured export jobs to Health.md for Mac over the local network.
- **Export history** with retry support for failed dates.
- **Multi-format export** — pick any combination of Markdown, JSON, CSV, or Obsidian Bases YAML; one export action writes one file per format per date.
- **Custom filename templates** (e.g. `{date}`, `{year}`, `{month}`, `{weekday}`).
- **Folder picker** with optional subfolder organization (`{year}` / `{month}` / `{quarter}` / `{week}` placeholders supported in folder paths).

### macOS
- **Mac Destination screen** — shows connection, destination-folder access, readiness, active export progress, last result/failure, and recent activity.
- **Destination folder selection** — choose where received iPhone exports should be written; security-scoped access is validated before each export.
- **iPhone-configured exports** — Mac uses the iOS-provided settings snapshot and shared exporter, so Markdown, Obsidian Bases, JSON, CSV, time-series data, daily note injection, and individual entry tracking match iPhone-local exports.
- **Menu bar widget** — persistent menu bar extra with destination status, activity, quick open, and settings.
- **Legacy cache cleanup** — old iPhone→Mac cached health records are preserved if present and can be deleted explicitly.
- **Settings window** (⌘,) — focused on destination/status/feedback preferences.
- **Native appearance** — respects system light/dark mode, uses standard macOS forms and controls.

## Supported Data

| Category | Metrics |
|---|---|
| **Sleep** | Total, deep, REM, core sleep duration |
| **Activity** | Steps, active/basal calories, exercise minutes, flights climbed, walking/running/cycling/swimming distance |
| **Heart** | Resting heart rate, walking HR average, HRV, heart rate |
| **Vitals** | Respiratory rate, blood oxygen, body temperature, blood pressure, blood glucose |
| **Body** | Weight, height, BMI, body fat %, lean body mass, waist circumference |
| **Nutrition** | Calories, protein, carbs, fat, fiber, sugar, sodium, cholesterol, water, caffeine |
| **Mindfulness** | Mindful sessions, State of Mind (iOS 18+) |
| **Mobility** | Walking speed, step length, double support %, asymmetry, stair speed, 6-min walk |
| **Hearing** | Headphone audio exposure, environmental sound levels |
| **Workouts** | Type, duration, calories, distance (50+ workout types) |

## Export Formats

- **Markdown** with optional frontmatter and grouped sections
- **Obsidian Bases** (frontmatter-only for database queries)
- **JSON** (structured output for analysis)
- **CSV** (one row per metric)

## Individual Entry Tracking

In addition to daily summaries, Health.md can create **individual timestamped files** for specific metrics:

- **Mood tracking**: Each mood entry gets its own file with valence, labels, and associations
- **Workouts**: Each workout saved as a separate file with duration, calories, distance
- **Vitals**: Blood pressure, glucose readings as individual entries

### File Structure

```
vault/
├── Health/
│   └── 2026-02-05.md              # Daily summary
└── entries/
    ├── mindfulness/
    │   ├── 2026_02_05_1030_daily_mood.md
    │   └── 2026_02_05_1545_momentary_emotions.md
    ├── workouts/
    │   └── 2026_02_05_0700_workouts.md
    └── vitals/
        └── 2026_02_05_0900_blood_pressure.md
```

## Getting Started

### iOS

**Requirements:** iPhone with Health data, iOS 17+

1. Open `HealthMd.xcodeproj` in Xcode.
2. Select a real device, configure signing, and run.
3. Grant HealthKit permissions on first launch.
4. Choose your export folder (Files app, iCloud Drive, or any location).
5. Export manually or configure scheduled exports.

**Optional — Use your Mac as the export destination:**
1. Open Health.md on your Mac.
2. On iPhone, go to **Mac Destination** and enable the destination toggle.
3. Choose a destination folder on Mac.
4. In the iPhone **Export** tab, select **Connected Mac** and tap **Export**.

**Build from CLI:**
```bash
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd -destination 'generic/platform=iOS' build
```

**AppsFlyer (affiliate attribution):**
- Disabled automatically in `Debug` builds.
- Non-Debug builds require a dev key and will fail fast if missing.
- Set once in your macOS Keychain (then forget it):
```bash
bash scripts/set-appsflyer-dev-key.sh "<APPS_FLYER_DEV_KEY>"
```

### macOS

**Requirements:**
- **macOS 14 (Sonoma) or later**
- **iPhone running Health.md** with Mac Destination enabled

1. Open `HealthMd.xcodeproj` in Xcode.
2. Select the **HealthMd-macOS** scheme.
3. Configure signing and build.
4. On first launch, the Mac Destination screen searches for nearby iPhones.
5. On your iPhone, enable **Mac Destination**.
6. Choose a destination folder on Mac (for example, your Obsidian vault in `~/Documents`).
7. On iPhone, configure the Export tab, choose **Connected Mac**, and tap **Export**.

**Build from CLI:**
```bash
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd-macOS -destination 'platform=macOS' build
```

### macOS Menu Bar

Health.md lives in your menu bar for quick destination status:

- Click the heart icon in the menu bar to see connection/readiness and recent Mac export activity.
- Use **Open Mac Destination** to choose or re-select the destination folder.
- The app stays running in the menu bar even when you close the main window, so it can receive iPhone-initiated export jobs.
- Scheduled exports and Shortcuts run from iPhone and write to the selected iPhone folder; Mac-target exports are started manually from the iPhone Export tab.

### macOS Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘0 | Open Mac Destination |
| ⌘, | Open settings |
| ⌘Q | Quit |

## Project Structure

```
HealthMd/
├── Shared/              # Cross-platform code
│   ├── Models/          # Data models (HealthData, HealthMetrics, settings)
│   ├── Managers/        # HealthKitManager, VaultManager, ExportOrchestrator
│   ├── Export/          # Markdown, JSON, CSV, Obsidian Bases exporters
│   ├── Sync/            # SyncService (Multipeer Connectivity), SyncPayload
│   └── Theme/           # DesignSystem with per-platform color mapping
├── iOS/                 # iOS-only (ContentView, SchedulingManager, Components)
├── macOS/               # macOS-only (Views, SchedulingManager, HealthDataStore)
├── Assets.xcassets/     # Shared assets
└── *.entitlements       # Per-platform entitlements
```

The codebase uses `#if os(iOS)` / `#if os(macOS)` guards where platform behavior differs. All export logic, data models, and formatting code is fully shared.

## Architecture Notes

### Why not HealthKit on macOS?

Apple's documentation states: *"The HealthKit framework is available on macOS 13 and later, but your app can't read or write HealthKit data. Calls to `isHealthDataAvailable()` return `false`."* The framework compiles but does nothing. Health.md works around this with device-to-device sync via Multipeer Connectivity.

### Sync Protocol

The current sync protocol includes legacy health-data messages plus v2 Mac export-job messages:
- `capabilities` / `macStatus` — devices publish platform/version/readiness and Mac destination folder state.
- `macExportRequest(job)` — iPhone sends a complete export job with iOS-provided settings and per-date records.
- `macExportAccepted`, `macExportProgress`, `macExportResult`, `macExportFailed`, `macExportCancel` — Mac reports lifecycle and result state.
- `ping` / `pong` — connection keepalive.

Data is serialized as JSON and sent via `MCSession`. Payloads over 100KB can use MC resource transfers for reliability.

### macOS Data Flow

```
iPhone (HealthKit + export settings) → Multipeer Connectivity → macOS (MacExportJobExecutor) → selected Mac folder
```

The Mac export path no longer depends on a local health-data cache. If an older cache exists in `~/Library/Application Support/Health.md/`, the Mac app shows it as legacy data and lets the user delete it explicitly.

## Scheduling Notes

Scheduled exports on both platforms are driven by a small Cloudflare Worker (`worker/` in the repo) that holds two D1 tables — `devices` (APNs token + Keychain-derived UUID) and `schedules` (cadence + timezone + next-fire-at) — and a 1-minute cron that joins them and sends silent APNs pushes (`apns-push-type: background`, `aps.content-available: 1`, custom `type: scheduled-export`). The phone or Mac wakes on the push, runs the export against on-device data, writes to disk, and goes back to sleep.

What the worker stores: APNs token, schedule cadence, timezone string. What it doesn't: any health data — that stays on the device and is read fresh on each push. Worker source is in the repo if you want to audit it. If you don't enable scheduled exports, the app makes zero network requests outside of optional iPhone↔Mac Multipeer sync.

**iOS:** HealthKit data is encrypted while the device is locked, so a silent push that lands on a locked phone bounces through a `.deviceLocked` failure path → reminder notification → user-tap retry. The worker only fixes timing precision; it can't bypass that fundamental iOS restriction. Scheduled exports write to the selected iPhone folder.

**macOS:** The Mac app is not a scheduler or HealthKit reader in the current model. It must be open and ready only when the user manually selects **Connected Mac** on iPhone and starts an export.

## Privacy

Health data stays on the device. The iOS app reads HealthKit on-device, formats on-device, and writes exports to a folder you pick — Files / iCloud Drive / Obsidian vault. No analytics SDK, no crash SDK, no third-party trackers.

iPhone→Mac destination exports, when enabled, run over your local network via Apple's Multipeer Connectivity framework — no cloud relay. The Mac receives the export job and writes files to the folder you selected on Mac; it does not read HealthKit or require a Mac health-data cache for new exports.

The one server-side touchpoint is the **scheduling worker** described in [Scheduling Notes](#scheduling-notes), and it's opt-in. The worker stores APNs tokens + schedule cadence + timezone so it can issue silent pushes at the right time; health data does not flow through it. Disable scheduled exports and the app makes no network requests outside of Multipeer sync.

## License

[GNU AGPL-3.0](LICENSE). Derivative works — including hosted services — must ship their source.
