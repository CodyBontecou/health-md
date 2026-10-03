# Watch App and Watch Widgets

## Status

- **Docs status:** draft
- **Video priority:** low
- **Primary screen:** watchOS app + watch complications
- **Source files:** `HealthMdWatch/`, `HealthMdWatchWidgets/`, `HealthMdWatchShared/`

## What it does

A lightweight watchOS dashboard puts today's health metrics on your wrist, and ten watch widgets (complications) put individual metrics — steps, rings, sleep, heart, HRV, blood oxygen — into watch faces and the Smart Stack. The watch reads directly from watchOS HealthKit; nothing syncs from the phone app.

## Who it is for

- Apple Watch owners who want a one-tap wrist dashboard instead of the rings app.
- Anyone who wants a single metric (HRV, resting HR, sleep) as a permanent complication.

## Where to find it

1. Install Health.md on Apple Watch from Watch app → Available Apps (or automatically with the iPhone app).
2. Open Health.md on the watch and tap **Connect Health** to grant watch-side HealthKit access.
3. Long-press your watch face → **Edit** → add a Health.md complication, or pin one in the Smart Stack.

## Available metrics

| Surface | Metrics |
|---|---|
| Watch app dashboard | Today's snapshot: activity, steps, sleep, heart, HRV, blood oxygen |
| Watch widgets (10) | Daily Activity, Recovery, Steps, Move Energy, Exercise Minutes, Stand Hours, Sleep, Resting Heart Rate, Heart Rate Variability, Blood Oxygen |

## Prerequisites

- Apple Watch running a supported watchOS version.
- Watch-side HealthKit authorization — the dashboard's **Connect Health** button walks through this; watch Health data is separate from iPhone permissions.

## Setup

1. Install the watch app.
2. Open it once and connect Health.
3. Add widgets to faces or Smart Stack.

## Example output

Dashboard: steps 8,432 · move 420 kcal · sleep 7h 12m · RHR 58 · HRV 42 ms · SpO₂ 98%.

## Tips

- "Health Unavailable" means watch HealthKit data is missing or denied — re-check via Connect Health.
- Widgets refresh on the watch's timeline budget; opening the dashboard forces a fresh read.
- iPhone export settings play no role here — this is a standalone watch surface.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Dashboard shows placeholder | Authorization not completed on watch | Tap Connect Health on the watch |
| Complication empty | Metric has no data today on the watch | Grant/verify the health type on watchOS |
| App missing on watch | Not installed for this watch | Watch app → Available Apps → Install |

## Video outline

- **Suggested title:** Health.md on Your Wrist
- **Hook:** "Your HRV, one glance."
- **Demo flow:** 1. Open dashboard. 2. Connect Health. 3. Add HRV complication to a face.
- **Key screenshot/recording moments:** dashboard scroll, complication picker.
- **CTA / next video:** iPhone widgets.

## Implementation notes

`HealthMdWatch/WatchDashboardView.swift` renders a `WatchHealthSnapshot` (shared model + store in `HealthMdWatchShared/`) with an explicit `WatchHealthAccessState` machine (unknown → needsAuthorization → requested → connected/unavailable). `WatchHealthWidgets/WatchHealthWidgets.swift` defines ten `StaticConfiguration` widgets over one `WatchHealthTimelineProvider`, all restricted to `WatchHealthWidgetFamilies.supported` (accessory families). Android Wear OS equivalents: `apps/android/wear` (tiles + complications), documented in `apps/android/docs/features/wear-os-implementation.md`.
