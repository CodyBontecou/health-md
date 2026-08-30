# Home-Screen Widgets and Live Activity

## Status

- **Docs status:** draft
- **Video priority:** low
- **Primary screen:** iPhone home screen / lock screen (widget targets, not in-app)
- **Source files:** `HealthMdWidgets/HealthWidgets.swift`, `HealthMdWidgets/CLIExportLiveActivityWidget.swift`, `HealthMdWidgets/HealthWidgetSnapshot.swift`

## What it does

Four home-screen widgets put today's health at a glance — a full health summary, activity rings, heart-rate range, and last night's sleep — plus a Live Activity that shows real-time progress while a CLI export runs on your iPhone. Widgets read directly from HealthKit on a timeline refresh; the Live Activity is driven by the export engine.

## Who it is for

- Anyone who wants steps, activity, heart, or sleep visible without opening an app.
- CLI/MCP users watching a long-running export from the lock screen or Dynamic Island.

## Where to find it

1. Long-press the iPhone home screen → **Edit → Add Widget** → search **Health.md**.
2. Pick a widget and size, or add it from the lock screen / StandBy for accessories.
3. The Live Activity appears automatically when a CLI export runs (Direct CLI enabled in the Sync tab).

## Widget families

| Widget | Sizes | Shows |
|---|---|---|
| Health Summary | Small, Medium, Large, Inline, Rectangular | Steps, active energy, exercise, stand hours, sleep, resting HR, avg HR, HRV, blood oxygen |
| Activity Rings | Small, Medium, Circular, Inline, Rectangular | Move/exercise/stand rings; circular accessory ring |
| Heart Range | Medium, Large, Inline, Rectangular | Average, min, and max heart rate for the day |
| Sleep Summary | Small, Medium, Large, Inline, Rectangular | Sleep duration with start/end times |

## Prerequisites

- HealthKit read permission for the metrics shown (each widget reads only what it displays).
- No export configuration or vault needed — widgets never touch exported files.

## Setup

1. Grant Health.md the health types you want surfaced (see [HealthKit permissions](./healthkit-permissions.md)).
2. Add the widget to your home screen or accessories.
3. For the Live Activity: enable Direct CLI access in the Sync tab and start an export from the `healthmd` CLI.

## Example output

```
Today            ♥ 62–121 bpm (avg 78)
Steps 8,432      ───────────────
Sleep 7h 12m     22:41 → 5:53
```

## Tips

- Lock-screen values are privacy-redacted automatically; sensitive numbers blur until unlock.
- An empty widget means Health.md has no data for the metrics you granted — check permissions.
- Accessories (Inline/Rectangular/Circular) work on Apple Watch-equipped setups and StandBy.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Widget shows placeholder/empty | HealthKit permission missing or no data today | Re-check permissions in Apple Health settings |
| Widget not refreshing | System timeline budgeting | Widgets refresh on iOS's schedule; open the app to force a snapshot |
| No Live Activity during export | Direct CLI disabled or Live Activities off system-wide | Enable Direct CLI in Sync tab; Settings → Face ID & Passcode → Live Activities |

## Video outline

- **Suggested title:** Your Health Day at a Glance: Health.md Widgets
- **Hook:** "Check your sleep and rings without unlocking."
- **Demo flow:** 1. Add Health Summary large. 2. Add circular ring accessory. 3. Start a CLI export, show the Live Activity.
- **Key screenshot/recording moments:** widget picker, redacted lock-screen values, Dynamic Island export progress.
- **CTA / next video:** Direct iPhone CLI access.

## Implementation notes

`HealthWidgetTimelineProvider` reads a `HealthWidgetSnapshot` (per-day optional values; `hasAnyData` gating) from HealthKit on timeline refresh — no Health.md servers, no export store involvement. Values use `.privacySensitive()` for lock-screen redaction. `CLIExportLiveActivityWidget` is an `ActivityConfiguration` over `CLIExportActivityAttributes` with lock-screen, progress-bar, and compact presentations. Watch-side equivalents are separate targets (`HealthMdWatchWidgets`). Android's Glance widgets are documented in `apps/android/docs/features/widgets.md`.
