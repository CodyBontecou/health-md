---
title: Feature Overview by Platform
description: What Health.md does on iPhone, iPad, Mac, Android, Wear OS, and the CLI — shared capabilities and the honest platform differences.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Platform overview</p>
  <p>What Health.md does on iPhone, iPad, Mac, Android, Wear OS, and the CLI — shared wherever the platforms allow, honest where they differ.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://apps.apple.com/us/app/health-md/id6757763969" target="_blank" rel="noopener">iPhone & Mac</a>
    <a class="docs-button-secondary" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Android</a>
  </div>
</div>

Legend: ✓ available · ◐ available with platform differences named in the row · △ planned or in QA · ? availability not claimed · — not available on that platform.

The CLI is not a separate health-data platform column: CLI capabilities appear in the automation rows and retain the semantics of their iPhone or Android source.

## Setup and permissions

| Capability | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Health-data permissions (choose exactly what to read) | ✓ Apple Health types | ◐ reads through paired iPhone / Mac destination | ✓ Health Connect categories | — |
| Choose export destination | ✓ Obsidian vault, iCloud Drive, Files | ✓ local folders | ✓ any Android folder provider (Drive, OneDrive, Syncthing, Obsidian Sync…) | — |
| Onboarding with sample preview | ✓ | ✓ | ✓ | — |
| Share My Setup (move preferences between devices) | △ in QA | △ in QA | △ in QA | — |

## Reading and exporting

| Capability | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Daily exports to Markdown, Obsidian Bases, JSON, CSV | ✓ | ✓ (files arrive from iPhone) | ✓ | — |
| 225+ Apple Health metrics / 106 Health Connect metrics | ✓ | ✓ | ✓ | — |
| Preview before writing | ✓ | ✓ | ✓ | — |
| Saved export profiles with independent settings | ✓ manage on iPhone; ? iPad management not claimed | ? management not claimed | ✓ manage on Android | — |
| Weekly / monthly / yearly roll-up summaries | ✓ | ✓ | △ planned; requires a separately reviewed Android schema profile (current v4/v5 remain unchanged) | — |
| Export history and retry | ✓ | ✓ | ✓ | — |
| Stop or cancel the active run without disabling its schedule | ✓ completed dates preserved; unresolved dates retryable | ✓ | ✓ completed dates preserved; unresolved dates retryable | — |
| One-run ZIP archive | ✓ | ✓ | — | — |
| Summary Data Detail | ✓ | ✓ | ✓ | — |
| Detailed Time-Series for selected metrics | ✓ | ✓ | ✓ | — |
| Lossless Health Records canonical source archive | ✓ `healthmd.healthkit_records` | ✓ | — Apple-only; see Raw snapshots instead | — |
| Raw API snapshot export (immutable JSON/NDJSON) | — | — | ✓ Health Connect + Fitbit, Oura, WHOOP, Withings | — |

## Advanced data

| Capability | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Individual entry tracking (workouts, sleep stages, vitals) | ✓ | ✓ | ✓ | — |
| Workout details with full graphs and routes where offered | ✓ | ✓ | ✓ | — |
| Mood / State of Mind export | ✓ | ✓ | — (no Health Connect equivalent) | — |
| Medication dose events | ✓ | ✓ | — (no Health Connect equivalent) | — |
| Blood pressure, glucose, oxygen, temperature readings | ✓ | ✓ | ✓ | — |
| Third-party provider data | ◐ WHOOP section in export (beta) | ◐ | ✓ provider-native raw snapshots | — |

Some data is deliberately **not treated as equivalent** across platforms: heart-rate variability is SDNN on Apple and RMSSD on Android and WHOOP — Health.md keeps them as distinct metrics instead of blending them. Apple Watch wrist temperature and Health Connect skin temperature are also kept separate.

## Automate and integrate

| Capability | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Scheduled recurring exports | ✓ notifications + APNs fallback | ✓ | ✓ WorkManager (+ optional exact alarm), boot recovery | — |
| System automation | ✓ Shortcuts / Siri / App Intents | — | ✓ Tasker, adb, explicit broadcast intents | — |
| Send exports to your own HTTP(S) API endpoint | ✓ | — | ✓ with encrypted header storage | — |
| Standalone CLI (`healthmd`) pairing | ✓ foreground direct service | ✓ bundled + standalone | ✓ 20-digit code pairing | — |
| MCP server for AI agents | ◐ bundled through Mac; typed portable direct MCP is iPhone-only | ✓ bundled `healthmd-mcp` | — typed direct MCP unsupported | — |

## Devices and glanceable surfaces

| Capability | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Home-screen widgets | ✓ summary, activity rings, heart range, sleep | — | ✓ summary, activity, heart range, sleep (steps replaces stand hours) | — |
| Live Activity export progress | ✓ | — | — | — |
| Watch surfaces | ✓ watch app + 10 complications | — | — | ✓ tiles + 10 complications |
| Mac as export destination (encrypted local transfer) | ✓ iPhone sends | ✓ receives | — | — |

## Purchase and privacy

| Capability | iPhone / iPad | Mac | Android | Wear OS |
|---|---|---|---|---|
| Free tier | ✓ 10 manual or scheduled export actions | — | ✓ 10 manual export actions | — |
| Unlock | ✓ one-time lifetime (individual / family) | ◐ same Apple unlock | ✓ one-time lifetime purchase, including scheduling | — |
| Local-first privacy | ✓ no Health.md health-data cloud | ✓ | ✓ | ✓ |
| Clinician report (one PDF for appointments) | ✓ | — | ✓ | — |

Health.md does not operate a health-data cloud. Health data can exist in destinations you choose, encrypted local context, and bounded private transfer state. Every folder, Mac, API endpoint, or CLI destination is configured explicitly. Profiles and schedules stay local to the device where they were created. See [Export profiles](/docs/export-profiles/), the [Android guide](/docs/android/), and the [iPhone export guide](/docs/export/) for each platform's workflow.
