# Health.md

[Download on the App Store](https://apps.apple.com/us/app/health-md/id6757763969)

Health.md exports Apple Health data to your filesystem as human-readable Markdown (or structured JSON/CSV). Your health data stays local and accessible in the Files app, Obsidian, or any markdown-compatible tool.

## What's Included

- **iOS app** — Collects HealthKit metrics and exports to your device with configurable formats, filenames, and schedules.
- **macOS app** — Same export engine running natively on Mac. Includes a menu bar widget, scheduled exports, and keyboard shortcuts. Health data syncs automatically via iCloud.

## Features

### iOS
- **HealthKit export** for sleep, activity, vitals, body measurements, nutrition, mindfulness, mobility, hearing, and workouts.
- **Manual export** for a date range with progress and error handling.
- **Scheduled exports** (daily or weekly) using Background Tasks + HealthKit background delivery.
- **Export history** with retry support for failed dates.
- **Flexible formats**: Markdown, frontmatter-based Markdown, JSON, or CSV.
- **Custom filename templates** (e.g. `{date}`, `{year}`, `{month}`, `{weekday}`).
- **Folder picker** with optional subfolder organization.

### macOS
- **Same export engine** — all data categories, formats, and settings are shared with iOS.
- **NavigationSplitView UI** — sidebar with Export, Schedule, History, and Settings sections.
- **Menu bar widget** — persistent menu bar extra with status, "Export Yesterday" one-click button, and quick access to settings.
- **Scheduled exports** — timer-based scheduling with Login Item support for automatic background exports.
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
| **Mindfulness** | Mindful sessions, State of Mind (iOS 18+ / macOS 15+) |
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

**Build from CLI:**
```bash
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd -destination 'generic/platform=iOS' build
```

### macOS

**Requirements:**
- **Apple Silicon Mac** (M1 or later) — HealthKit is not available on Intel Macs
- **macOS 14 (Sonoma) or later**
- **iCloud Health sync enabled** — Health data syncs from your iPhone/Apple Watch via iCloud
- **Health app set up** on your Mac (launched at least once)

1. Open `HealthMd.xcodeproj` in Xcode.
2. Select the **HealthMd-macOS** scheme.
3. Configure signing (requires HealthKit entitlement).
4. Build and run.
5. Grant HealthKit permissions when prompted.
6. Choose an export folder (e.g. your Obsidian vault in `~/Documents`).

**Build from CLI:**
```bash
xcodebuild -project HealthMd.xcodeproj -scheme HealthMd-macOS -destination 'generic/platform=macOS' build -allowProvisioningUpdates
```

### macOS Menu Bar & Scheduling

Health.md lives in your menu bar for quick access:

- Click the heart icon in the menu bar to see status and export yesterday's data with one click.
- Enable **scheduled exports** in the Schedule section (daily or weekly at your preferred time).
- Enable **Launch at Login** so exports happen automatically when your Mac starts.
- The app stays running in the menu bar even when you close the main window.

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
│   └── Theme/           # DesignSystem with per-platform color mapping
├── iOS/                 # iOS-only (ContentView, SchedulingManager, Components)
├── macOS/               # macOS-only (Views, SchedulingManager, FolderPicker)
├── Assets.xcassets/     # Shared assets
└── *.entitlements       # Per-platform entitlements
```

The codebase uses `#if os(iOS)` / `#if os(macOS)` guards where platform behavior differs (HealthKit background delivery, security-scoped bookmarks, scheduling). All export logic, data models, and formatting code is fully shared.

## macOS-Specific Notes

- **iCloud Health sync** must be enabled in System Settings → Apple ID → iCloud for health data to appear on your Mac. If you've never opened the Health app on your Mac, do so once to trigger the initial sync.
- **Sync delay**: Health data recorded on iPhone/Apple Watch may take minutes to ~1 hour to appear on Mac via iCloud. Yesterday's data is typically fully synced by morning.
- **Apple Silicon only**: HealthKit requires an Apple Silicon Mac (M1, M2, M3, etc.). Intel Macs will show a "HealthKit Not Available" message.
- **Login Item**: When "Launch at Login" is enabled, Health.md registers as a Login Item via `SMAppService`. It launches silently in the menu bar on startup.
- **Sandbox**: The macOS app runs in the App Sandbox. Export folders are accessed via security-scoped bookmarks that persist across app restarts.

## Scheduling Notes

**iOS:** Scheduled exports use `BGTaskScheduler` + HealthKit background delivery. If the device is locked, health data may be protected; the app sends a notification prompting you to unlock and retry.

**macOS:** Scheduled exports use an in-app timer (30-minute check interval) combined with HealthKit observer queries. The app must be running (in the menu bar) for scheduled exports to work. Enable "Launch at Login" for reliability.

## Privacy

All exports are written locally to your chosen folder. No health data is sent to external services.
