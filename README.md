# Health.md

[Download on the App Store](https://apps.apple.com/us/app/health-md/id6757763969)

Health.md exports Apple Health data to your filesystem as human-readable Markdown (or structured JSON/CSV). Your health data stays local and accessible in the Files app, Obsidian, or any markdown-compatible tool.

## What's Included

- **iOS app** — Reads HealthKit data and exports to your device. Configurable formats, filenames, and scheduled exports.
- **macOS app** — Companion app that receives health data from your iPhone over your local network (WiFi/Bluetooth), then exports to your Obsidian vault with the same engine. Includes a menu bar widget, scheduled exports, and keyboard shortcuts.

## How It Works

### iPhone → Mac Sync

HealthKit data is **only available on iPhone** — macOS cannot read the Health store. Health.md solves this with **device-to-device sync** using Apple's Multipeer Connectivity framework:

1. **iPhone** reads your health data from HealthKit
2. **Mac** discovers your iPhone on the local network
3. iPhone sends health data directly to Mac — **no cloud, no servers**
4. Mac caches the data locally and exports to your Obsidian vault

Both devices must be on the same WiFi network or within Bluetooth range. Sync is optional — the iOS app works fully standalone.

## Features

### iOS
- **HealthKit export** for sleep, activity, vitals, body measurements, nutrition, mindfulness, mobility, hearing, and workouts.
- **Manual export** for a date range with progress and error handling.
- **Scheduled exports** (daily or weekly) using Background Tasks + HealthKit background delivery.
- **Mac sync** — optional companion sync sends health data to your Mac over the local network.
- **Export history** with retry support for failed dates.
- **Flexible formats**: Markdown, frontmatter-based Markdown, JSON, or CSV.
- **Custom filename templates** (e.g. `{date}`, `{year}`, `{month}`, `{weekday}`).
- **Folder picker** with optional subfolder organization.

### macOS
- **iPhone companion sync** — discovers your iPhone and receives health data via Multipeer Connectivity.
- **Local data cache** — health records stored as JSON in `~/Library/Application Support/Health.md/`.
- **Same export engine** — all data categories, formats, and settings are shared with iOS.
- **NavigationSplitView UI** — sidebar with Sync, Export, Schedule, History, and Settings sections.
- **Menu bar widget** — persistent menu bar extra with sync status, "Export Yesterday" one-click button, and quick access to settings.
- **Scheduled exports** — timer-based scheduling with Login Item support for automatic background exports (reads from local cache).
- **Keyboard shortcuts** — ⌘E (export), ⌘, (settings), ⌘Q (quit).
- **Settings window** (⌘,) — tabbed settings with General, Format, Data, and Schedule tabs.
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

**Optional — Enable Mac Sync:**
1. Go to Settings → Mac Sync.
2. Toggle "Sync to Mac" on.
3. Open Health.md on your Mac — it will discover your iPhone automatically.

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
- **iPhone running Health.md** with sync enabled (for health data)

1. Open `HealthMd.xcodeproj` in Xcode.
2. Select the **HealthMd-macOS** scheme.
3. Configure signing and build.
4. On first launch, the Sync tab shows "Searching for nearby iPhones…"
5. On your iPhone, enable sync in Settings → Mac Sync.
6. The Mac will auto-connect and you can request health data.
7. Choose an export folder (e.g. your Obsidian vault in `~/Documents`).

**Build from CLI:**
```bash
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd-macOS -destination 'platform=macOS' build
```

### macOS Menu Bar & Scheduling

Health.md lives in your menu bar for quick access:

- Click the heart icon in the menu bar to see sync status and export yesterday's data with one click.
- Enable **scheduled exports** in the Schedule section (daily or weekly at your preferred time).
- Enable **Launch at Login** so exports happen automatically when your Mac starts.
- The app stays running in the menu bar even when you close the main window.
- Scheduled exports read from the local data cache — sync your iPhone regularly for fresh data.

### macOS Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| ⌘E | Export now |
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

The sync protocol uses four message types:
- `requestData(dates:)` — Mac requests specific dates from iPhone
- `healthData(payload)` — iPhone sends health records to Mac
- `ping` / `pong` — Connection keepalive

Data is serialized as JSON and sent via `MCSession`. Payloads over 100KB use MC resource transfers for reliability.

### macOS Data Flow

```
iPhone (HealthKit) → Multipeer Connectivity → macOS (HealthDataStore) → Export (VaultManager)
```

Health data is cached locally as one JSON file per date in `~/Library/Application Support/Health.md/`. The export engine reads from this cache — it never touches HealthKit directly on macOS.

## Scheduling Notes

**iOS:** Scheduled exports use `BGTaskScheduler` + HealthKit background delivery. If the device is locked, health data may be protected; the app sends a notification prompting you to unlock and retry. Auto-sync to Mac happens after each export if enabled.

**macOS:** Scheduled exports use an in-app timer (30-minute check interval). The app must be running (in the menu bar) for scheduled exports to work. Enable "Launch at Login" for reliability. Exports read from the local data cache — make sure to sync from your iPhone regularly.

## Privacy

All data transfer happens over your local network using Multipeer Connectivity (WiFi + Bluetooth). No health data is sent to external services or cloud storage. Exports are written locally to your chosen folder.

## License

[GNU AGPL-3.0](LICENSE). Derivative works — including hosted services — must ship their source.
