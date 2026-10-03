# Wear OS companion

## Status

- **Docs status:** needs QA — page written from source; the companion itself is implemented and emulator-verified but **not yet released**. Per the completion audit ([`wear-os-completion-audit.md`](./wear-os-completion-audit.md)), physical paired-device battery/OEM QA, exact-release Play screenshots, and the Play Wear form-factor upload are still pending gates, so it cannot be installed from Google Play yet. No screenshots exist for this page.
- **Video priority:** low
- **Primary screen:** Wear OS (watch launcher app, tile carousel, watch-face complications) + phone **Settings → Wear OS** card
- **Source files:** [`wear/src/main/java/com/healthmd/wear/`](../../wear/src/main/java/com/healthmd/wear/) — `MainActivity.kt` (dashboard), `surface/HealthTiles.kt` (2 tiles), `surface/HealthComplications.kt` (10 complications), `sync/WearDataLayerService.kt`, `sync/WearRefreshClient.kt`, `sync/WearSnapshotRepository.kt`; contract [`WearHealthSnapshot.kt`](../../wearable-contract/src/main/kotlin/com/healthmd/wearable/contract/WearHealthSnapshot.kt); phone side [`app/src/play/java/com/healthmd/wear/WearSettingsCard.kt`](../../app/src/play/java/com/healthmd/wear/WearSettingsCard.kt)

## What it does

Puts glanceable daily health summaries on a paired Wear OS watch: a dashboard app, two watch-face tiles (Daily Activity and Recovery), and ten watch-face complications. Your phone stays the **only** health authority — the watch performs no Health Connect reads and no on-watch sensing. The phone pushes a bounded daily-aggregate snapshot over the Wear OS data layer, and every watch surface renders only that cached snapshot, always footed with "Last phone sync; not real-time" (or the snapshot's age once it is 4–24 hours old).

## Who it is for

- Users who want today's steps, activity, sleep, HRV RMSSD, heart rates, and blood oxygen at a glance without opening the phone app.
- Users comfortable with the phone being authoritative: the watch never *senses* health data, it only *displays* what the phone synced.
- Not for: watch-sourced measurements (none exist here), or F-Droid phone installs — Wear sync settings, services, and data-layer code ship only in the Google Play distribution channel.

## Where to find it

On the watch:

1. Watch launcher → **Health.md** — a round-scrolling dashboard of today's metrics with a **Sync Health Data** button.
2. Swipe to the watch's tile carousel and add the **Daily Activity** or **Recovery** tile (both appear in the tile picker with previews).
3. Long-press your watch face → **Customize** → complications → pick one of ten: **Daily Activity, Recovery, Steps, Move Energy, Exercise Minutes, Sleep, Resting Heart Rate, Average Heart Rate, HRV RMSSD, Blood Oxygen**. Short-text, long-text, and ranged-value complication slots are supported; picker previews are placeholders only ("Preview; no health value").

On the phone:

4. Open Health.md → **Settings** and scroll to the **Wear OS** card ("Sync minimized daily activity, sleep, heart, HRV RMSSD, and blood oxygen aggregates to a paired watch. Health.md does not sense health data on the watch.") — it holds **Sync Watch** and **Clear Watch Data** buttons plus live source/delivery/acknowledgement status. This card is Play-distribution only.

Tapping a tile or complication opens the watch dashboard.

## Prerequisites

- The **Google Play channel** phone app installed on a paired Android phone (the card and Wear services are absent from the F-Droid variant).
- A Wear OS 3 or newer watch (the `:wear` module sets `minSdk 30`), paired to that phone.
- Health Connect permissions granted **on the phone** for the categories you want to see: Steps, Active Calories, Exercise, Sleep, Heart Rate, Resting Heart Rate, HRV RMSSD, Oxygen Saturation. Partial grants produce partial snapshots — missing metrics are simply omitted.
- Phone and watch running the same Health.md version; a skew shows "Update Health.md on your phone and watch." and hides measurements.
- **Availability:** the companion has not shipped to Google Play yet (see Status). The watch app installs from the watch's Play Store or the phone listing's watch section once released; it is the same `com.healthmd.android` package and Play listing as the phone app.

## Setup

1. Once released, install Health.md on the watch from the Play Store on the watch (or the watch section of the phone's Play Store listing).
2. Open the phone app once so the first snapshot syncs. After that, an eligible phone syncs automatically about every 30 minutes (platform-inexact), or you can press **Sync Watch** in Settings, or **Sync Health Data** in the watch app.
3. Add tiles from the watch's tile carousel and complications from the watch-face editor (see *Where to find it*).

## What the surfaces show

| Surface | Content | Day rule |
|---|---|---|
| Daily Activity tile | Today's steps and exercise minutes ("8,432 steps · 30 min"); "No activity data" when empty | Today only (phone's captured timezone) |
| Recovery tile | Latest sleep hours and HRV RMSSD ("7 hr sleep · 48 ms RMSSD"); "No sleep or HRV data" when empty | Today or yesterday's overnight values, independently |
| Steps / Move Energy / Exercise complications | Steps; kcal; minutes | Today only |
| Recovery / Sleep / HRV complications | Sleep hr; sleep hr; HRV RMSSD ms | Today or yesterday |
| Resting Heart Rate / Average Heart Rate / Blood Oxygen complications | bpm; bpm; % | Today only |
| Dashboard app | All of the above for today (sleep/HRV via the today-or-yesterday recovery rule) | Same rules as the matching complications |

Complication values render as short text ("7 hr", "48 ms", "98%"), long text ("Sleep 7 hr · Last phone sync; not real-time"), or a ranged-value progress bar against a fixed maximum (e.g. steps out of 10,000; exercise out of 180 min). Every surface is followed by its freshness: current snapshots show "Last phone sync; not real-time"; 4–24-hour-old snapshots show the age ("Updated 3 hours ago"); anything older than 24 hours is hidden and replaced by "Data is more than 24 hours old. Sync to show measurements." (complications go blank instead).

## Example output

Daily Activity tile (title / value / footer):

```text
Daily Activity
8,432 steps · 30 min
Last phone sync; not real-time
```

Recovery tile after a stale sync:

```text
Recovery
7 hr sleep · 48 ms RMSSD
Updated 5 hours ago
```

## Tips

- Offline is by design: tiles and complications read only the watch's local cache, so the phone can be off or out of range and yesterday's snapshot still renders with an honest age label.
- The watch's **Sync Health Data** button only reports success when a *newer* snapshot actually arrives (30-second window); otherwise it keeps the last-good data and shows "Phone is currently unreachable. Last saved data remains available."
- **Clear Watch Data** in phone Settings is durable: the deletion survives app restarts and process death, offline watches are cleared on reconnect, and a delayed older sync can never restore deleted data.
- Sleep and HRV in the Recovery surfaces can come from different days — one present value never hides the other.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Tile shows "Open Health.md on your phone to finish setup." | No snapshot has ever reached the watch | Open the phone app once; press Sync Watch |
| "Health Connect access is needed on your phone." / "Health Connect is unavailable…" | Phone permission revoked / Health Connect missing | Re-grant the category in Health Connect on the phone |
| "Data is more than 24 hours old. Sync to show measurements." / blank complication | Snapshot expired (>24 h) | Bring phone in range and sync |
| "Update Health.md on your phone and watch." | Phone/watch version skew | Update Health.md on both devices |
| "Phone is currently unreachable…" after tapping Sync | Phone off, out of range, or no newer data within 30 s | Last-good data stays; retry when paired |
| Complication shows "--" | No-data state (no snapshot/day/value for that slot) | Sync from the phone; check the day rule for that metric |
| No Wear OS card in phone Settings | F-Droid build, or Play distribution flag off | Wear sync requires the Google Play channel build |

## Video outline

- **Suggested title:** Your Health Data on the Wrist — Health.md for Wear OS
- **Hook:** "Tiles and complications straight from your phone's Health Connect data — no watch sensing, no cloud."
- **Demo flow:**
  1. Install on a paired watch and sync from phone Settings.
  2. Add the Daily Activity and Recovery tiles to the carousel.
  3. Add Steps / Sleep / HRV complications from the watch-face editor; tap one to open the dashboard.
- **Key screenshot/recording moments:** tile carousel, complication picker list (10 metrics), stale-age label turning honest, Clear Watch Data in phone Settings.
- **CTA / next video:** Home-screen widgets (./widgets.md) — same glanceable idea on the phone.

## Implementation notes

Maintainer-only ground truth: `HealthTiles.kt` builds both ProtoLayout tiles with a one-hour host freshness interval plus **local timeline entries** so stale-age labels, 24-hour expiry, and captured-zone midnight transitions re-render without the phone; Recovery reselects today-or-yesterday overnight values at midnight while Activity stays today-only. `HealthComplications.kt` declares exactly ten `Metric` services (push-only, `UPDATE_PERIOD_SECONDS 0`) with native validity ranges and the same midnight/stale timeline policy; picker previews are placeholders and never invented measurements. `WearDataLayerService.kt` + the private `:wearable-contract` module define the bounded phone→watch protocol: a versioned `WearHealthSnapshot` (schema v1, ≤ 14 daily aggregate rows, ≤ 64 KiB, 5-minute clock-skew window) that carries **aggregates only** — no samples, sub-day timestamps, source apps, record IDs, metadata, routes, or identity — plus ordered sequences, acknowledgements, and delete tombstones. Watch storage is an atomic file in `noBackupFilesDir` with backups disabled; corrupt or out-of-order payloads fail closed (measurements hidden). The phone side lives in `app/src/play/java/com/healthmd/wear/` (`WearSettingsCard.kt`, `WearPhoneSync.kt`) and reads only granted Health Connect categories. A DUMP-permission diagnostics provider exposes cache presence/size/hash only, never health values. Release state and the remaining hardware/Play gates are tracked in [`wear-os-implementation.md`](./wear-os-implementation.md) and [`wear-os-completion-audit.md`](./wear-os-completion-audit.md) — that audit is the ceiling for any availability claim on this page. The user-facing website guide is [`guides/wear-os`](../../../website/docs-src/src/content/docs/guides/wear-os.md) (canonical English). Deliberate differences from Apple's [`watch-app.md`](../../../apple/docs/features/watch-app.md): watchOS ships an app + 10 widgets with watch-authoritative HealthKit sensing, while Wear OS ships tiles/complications fed exclusively by the phone — parity stays `platform-distinct`, and the watch's HRV RMSSD is never conflated with HealthKit SDNN.
