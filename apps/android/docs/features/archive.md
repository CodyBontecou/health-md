# Archive coverage calendar

## Purpose and evidence

- **Audience and task:** People who export on a schedule and want to see, at a glance, which health dates are already in their archive and which need a backfill.
- **Canonical location:** This guide owns the Android Archive. The shared capability is `export.coverage-calendar` in [product-capabilities.json](../../../../packages/contracts/product-capabilities.json); the Apple Archive lands with the Liquid Glass experience.
- **Source and tests:** `app/src/main/java/com/healthmd/presentation/archive/` (`ArchiveCoverage.kt` rules, `ArchiveViewModel.kt`, `ArchiveScreen.kt`, and the day page in `DayPageScreen.kt`/`DayPageViewModel.kt`) and `widget/glance/ArchiveGlanceWidget.kt`; `ArchiveCoverageTest.kt` and `ArchiveWidgetSummaryTest.kt`. On-device rendering has not been verified by automated UI tests.

## What it does

The Archive is the first tab. It shows one month as a calendar of health dates — the dates your exports covered, not the times they ran — built from the local export history. Each day has one state:

| State | Meaning on Android |
| --- | --- |
| Complete | A run wrote this date. |
| Partial | Health Connect had no data for the date, or a partial run did not record which dates failed. |
| Missing | Every run that covered the date failed for it. Backfill opens Export now set to that date. |
| Not exported | Nothing in history covered the date, or it is in the future. |
| Today | An export may still update today. |

Each export profile is its own lane; runs without a profile form the **Current settings** lane. **All** combines the lanes with the same rule as the Apple Archive: among lanes that covered a date, missing beats partial beats complete. In **All**, days with trouble show one dot per affected lane (filled for partial, hollow for missing). The stats card counts days archived (complete + partial) and gaps, and the streak runs back from yesterday, skipping dates with nothing exported, until the first gap.

## Setup and use

1. Export once from **Export now**, or let an automation run. The calendar fills from export history.
2. Tap a day to see each lane's state and its last export time. **Backfill** a missing lane or **Re-export** a partial one.
3. Tap a lane to open the day page: the file Health.md writes for that date, line by line, with **Share file** and **Re-export**. It is a dry run with the current export settings, the same one Export now previews, so it reflects today's Health Connect data and writes nothing. Raw snapshot mode has no single day file.
4. Use the chips to focus one profile, and **Show first gap** to jump to the earliest missing date in the month.
5. Open **History** from the Archive for the full run log and retries ([Export history and retry](./export-history-retry.md)).

On tablets and unfolded foldables the calendar fills the main pane, with the chips and month controls inside it; the stats, the selected day, an **Automations** summary and History sit in a side column.

The **Archive** home-screen widget shows the same coverage at a glance; see [Home-screen widgets](./widgets.md).

## Limitations and troubleshooting

- Coverage merges outcomes so a later failure never hides a file an earlier run wrote. It does not inspect the folder: a file you deleted by hand still shows as complete.
- Android has no paused-schedule ledger, so the Archive has no paused state; a paused automation's dates show as not exported.
- Clearing export history clears the calendar.
- The day page does not read the written file back from the folder (history does not record file paths); it regenerates the file from current data and settings, so it can differ from what an earlier run wrote or from a profile's own settings.

## Maintainer rationale

Statuses are enums resolved to strings in the screen, so the rules stay testable and localized. Keep `ArchiveCoverage` aligned with Apple's `ArchiveAggregation` (aggregate, issue dots, on-track counts and stats); record any intentional difference in the capability ledger.
