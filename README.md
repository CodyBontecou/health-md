# Health.md

[Download on the App Store](https://apps.apple.com/us/app/health-md/id6757763969)

Health.md is an iOS app that exports Apple Health data into an Obsidian vault as human‑readable Markdown (or structured JSON/CSV). This repository also includes an optional Obsidian plugin for rendering beautiful health dashboards and charts.

## What’s Included

- **iOS app (SwiftUI)**: Collects HealthKit metrics and exports them into your vault with configurable formats, filenames, and schedules.
- **Obsidian plugin**: Renders activity rings, sleep charts, vitals, and workout summaries from exported files.

## Features

### iOS App
- **HealthKit export** for sleep, activity, vitals, body measurements, and workouts.
- **Manual export** for a date range with progress and error handling.
- **Scheduled exports** (daily or weekly) using Background Tasks + HealthKit background delivery.
- **Export history** with retry support for failed dates.
- **Flexible formats**: Markdown, Obsidian Bases frontmatter, JSON, or CSV.
- **Custom filename templates** (e.g. `{date}`, `{year}`, `{month}`, `{weekday}`).
- **Vault folder picker** with optional `Health` subfolder.

### Obsidian Plugin
- Apple Health‑inspired charts (activity rings, sleep analysis, vitals, workouts).
- Works automatically with exported Markdown/JSON.
- Configurable goals and styling.

See [`obsidian-health-charts-plugin/README.md`](obsidian-health-charts-plugin/README.md) for plugin installation and usage, including iOS installation steps.

## Supported Data

- **Sleep**: total, deep, REM, core
- **Activity**: steps, active calories, exercise minutes, flights climbed, walking/running distance
- **Vitals**: resting heart rate, HRV, respiratory rate, blood oxygen
- **Body**: weight, body fat percentage
- **Workouts**: type, start time, duration, calories, distance

## Export Formats

- **Markdown** with optional frontmatter and grouped sections
- **Obsidian Bases** (frontmatter-only metrics for querying)
- **JSON** (structured output for analysis)
- **CSV** (one row per metric)

## Getting Started (iOS App)

### Requirements
- macOS with **Xcode**
- iOS device with Health data (HealthKit access is limited in the simulator)
- An Obsidian vault on device or iCloud Drive

### Run the App
1. Open `HealthMd.xcodeproj` in Xcode.
2. Select a real device, configure signing, and run.
3. On first launch, grant HealthKit permissions.
4. Choose your Obsidian vault folder.
5. Export manually or configure scheduled exports.

### Scheduling Notes
Scheduled exports rely on iOS background task scheduling. If the device is locked, HealthKit data may be protected; the app will send a notification prompting you to tap and retry.

## Project Structure

```
.
├── HealthMd/           # SwiftUI app source
├── HealthMd.xcodeproj/ # Xcode project
├── obsidian-health-charts-plugin/ # Obsidian charts plugin
```

## Privacy

All exports are written locally to your Obsidian vault. No health data is sent to external services.
