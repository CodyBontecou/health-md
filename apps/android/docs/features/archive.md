# Archive coverage calendar

## Purpose and evidence

- **Audience and task:** People who export on a schedule and want to see, at a glance, which health dates are already in their archive and which need a backfill.
- **Canonical location:** This guide owns the Android Archive. The shared capability is `export.coverage-calendar` in [product-capabilities.json](../../../../packages/contracts/product-capabilities.json); the Apple Archive lands with the Liquid Glass experience.
- **Source and tests:** `app/src/main/java/com/healthmd/presentation/archive/` (`ArchiveCoverage.kt` rules, `ArchiveViewModel.kt`, `ArchiveScreen.kt`) and `widget/glance/ArchiveGlanceWidget.kt`; `ArchiveCoverageTest.kt` and `ArchiveWidgetSummaryTest.kt`. On-device rendering has not been verified by automated UI tests.

## What it does

The Archive is the first tab. It shows one month as a calendar of health dates — the dates your exports covered, not the times they ran — built from the local export history. Each day has one state:

| State | Meaning on Android |
| --- | --- |
| Complete | A run wrote this date. |
| Partial | Health Connect had no data for the date, or a partial run did not record which dates failed. |
| Missing | Every run that covered the date failed for it. Backfill opens Export now. |
| Not exported | Nothing in history covered the date, or it is in the future. |
| Today | An export may still update today. |

Each export profile is its own lane; runs without a profile form the **Current settings** lane. **All** combines the lanes with the same rule as the Apple Archive: among lanes that covered a date, missing beats partial beats complete. In **All**, days with trouble show one dot per affected lane (filled for partial, hollow for missing). The stats card counts days archived (complete + partial) and gaps, and the streak runs back from yesterday, skipping dates with nothing exported, until the first gap.

## Setup and use

1. Export once from **Export now**, or let an automation run. The calendar fills from export history.
2. Tap a day to see each lane's state and its last export time.
3. Use the chips to focus one profile, and **Show first gap** to jump to the earliest missing date in the month.
4. Open **History** from the Archive for the full run log and retries ([Export history and retry](./export-history-retry.md)).

The **Archive** home-screen widget shows the same coverage at a glance; see [Home-screen widgets](./widgets.md).

## Limitations and troubleshooting

- Coverage merges outcomes so a later failure never hides a file an earlier run wrote. It does not inspect the folder: a file you deleted by hand still shows as complete.
- Android has no paused-schedule ledger, so the Archive has no paused state; a paused automation's dates show as not exported.
- Clearing export history clears the calendar.

## Maintainer rationale

Statuses are enums resolved to strings in the screen, so the rules stay testable and localized. Keep `ArchiveCoverage` aligned with Apple's `ArchiveAggregation` (aggregate, issue dots, on-track counts and stats); record any intentional difference in the capability ledger.
