# Roll-up summaries

Health.md can generate weekly, monthly, and yearly summary files for the full roll-up periods touched by the user's selected export dates.

## User promise

When one or more roll-up periods are enabled, Health.md writes period-level derived files for every selected export format:

```text
Health/
  Rollups/
    Weekly/2026-W11.md
    Weekly/2026-W11.json
    Weekly/2026-W11.csv
    Weekly/2026-W11-bases.md
    Monthly/2026-03.md
    Yearly/2026.md
```

If **Organize by File Type** is enabled, roll-ups are grouped before the period folder:

```text
Health/
  Rollups/
    Markdown/Weekly/2026-W11.md
    Bases/Weekly/2026-W11.md
    JSON/Weekly/2026-W11.json
    CSV/Weekly/2026-W11.csv
```

These files are derived artifacts generated from HealthKit daily aggregate snapshots and `_healthmd_data_dictionary.json`.

## Settings

Roll-ups are explicit opt-in settings and default to off for existing and new users:

- Weekly summaries
- Monthly summaries
- Yearly summaries
- Summary files only

Roll-up files are aggregate derived artifacts, not daily records. Daily Markdown/Bases/JSON/CSV files continue to use `healthmd.health_data`; roll-up summary files identify themselves separately as `healthmd.rollup_summary`.

When **Summary files only** is enabled with at least one roll-up period, Health.md skips per-day aggregate files and export side effects such as Daily Note Injection, Individual Entry Tracking, and provider sidecars. It still fetches HealthKit daily aggregate snapshots for the full touched week/month/year windows so the summary files are complete.

## What gets generated

For each selected export range, Health.md expands the enabled roll-up windows and groups daily snapshots into:

- weekly summaries using ISO week IDs like `2026-W11`
- monthly summaries like `2026-03`
- yearly summaries like `2026`

Each Markdown roll-up includes:

- schema/frontmatter identifying the file as `healthmd.rollup_summary`
- `schema_version: 2`
- `rollup_period`, `period_id`, `start_date`, and `end_date`
- `days_expected`, `days_counted`, and `coverage_percent`
- `source_dates`
- a `units:` map for all summarized keys
- category tables for every metric that had data in that period
- per-metric statistics in collapsible details sections

JSON exports expose the same metadata plus structured `metrics` and `categories` objects. CSV exports write one primary row and statistic rows for each metric. Obsidian Bases exports write a Markdown file focused on YAML frontmatter under `rollup_metrics`.

## Aggregation rules

Roll-ups use the rules documented in `_healthmd_data_dictionary.json`:

| Daily rule | Period behavior |
|---|---|
| `sum`, `duration_sum`, `count` | Sum daily values, also report daily average/min/max. |
| `average` | Average exported daily aggregate values. |
| `weighted_average` | Use workout duration when available, otherwise fall back to daily averages. |
| `minimum` | Period minimum of daily minima. |
| `maximum` | Period maximum of daily maxima. |
| `latest` | Latest daily value with trend context when numeric. |
| `list` | Union values and count occurrences. |
| `category_latest` | Latest value plus value counts. |
| `first_time` / `last_time` | Earliest, latest, and average clock time. |

`days_counted` and `source_dates` reflect the daily aggregate snapshots Health.md fetched for the roll-up window, even when a day has no value for a selected metric. Missing metric values are ignored for that metric's calculation and surfaced through the per-metric days-counted column. Coverage drops below 100% only when a daily snapshot could not be fetched or the window includes future dates. For current week/month/year windows, future dates are not queried, but they still remain part of the period's `days_expected` count.

## Preview support

Export Preview shows a **Roll-up summaries** section before the daily files when roll-up periods are enabled. It renders one preview row per selected period and export format.

## Limitations

- Roll-ups query HealthKit for the full weekly/monthly/yearly windows touched by the selected export dates; they do not read or depend on previously generated files in the user's vault.
- Summary-only mode changes which files are written, not the roll-up schema. It does not change `healthmd.health_data` daily records because those records are skipped.
- Weighted workout roll-ups use exported daily workout duration as the weight. Deeper recomputation from individual workout entries can be added later.

## Implementation notes

Primary source files:

- `HealthMd/Shared/Export/HealthRollupModels.swift`
- `HealthMd/Shared/Export/HealthRollupGenerator.swift`
- `HealthMd/Shared/Export/HealthRollupExporter.swift`
- `HealthMd/Shared/Export/RollupMarkdownExporter.swift`
- `HealthMd/Shared/Export/RollupObsidianBasesExporter.swift`
- `HealthMd/Shared/Export/RollupJSONExporter.swift`
- `HealthMd/Shared/Export/RollupCSVExporter.swift`
- `HealthMd/Shared/Managers/ExportOrchestrator.swift`
- `HealthMd/Shared/Managers/VaultManager.swift`
- `HealthMd/Shared/Views/ExportPreviewView.swift`
- `HealthMd/Shared/Export/HealthMetricsDictionary.swift`

Tests:

- `HealthMdTests/Export/HealthRollupExporterTests.swift`
- `HealthMdTests/Managers/ExportOrchestratorTests.swift`
- `HealthMdTests/macOS/MacExportJobExecutorTests.swift`
- `HealthMdUITests/ExportJourneyUITests.swift`
