# Range summary roll-up

Health.md generates one range summary per export, covering exactly the user's selected export dates — first day through last day. The [data dictionary and roll-up reference](../reference/data-dictionary-and-rollups.md) includes every rule family and complete generated JSON, CSV, Markdown, and Bases examples.

## User promise

When the range summary is enabled, Health.md writes one derived summary file per selected export format:

```text
Health/
  Rollups/
    Range/2026-03-10_to_2026-03-15.md
    Range/2026-03-10_to_2026-03-15.json
    Range/2026-03-10_to_2026-03-15.csv
    Range/2026-03-10_to_2026-03-15-bases.md
```

If **Organize by File Type** is enabled, roll-ups are grouped before the period folder:

```text
Health/
  Rollups/
    Markdown/Range/2026-03-10_to_2026-03-15.md
    Bases/Range/2026-03-10_to_2026-03-15.md
    JSON/Range/2026-03-10_to_2026-03-15.json
    CSV/Range/2026-03-10_to_2026-03-15.csv
```

These files are derived artifacts generated from HealthKit daily summary snapshots using the same rules documented in `_healthmd_data_dictionary.json`. They do not require the sidecar file to be written and do not embed canonical `healthkit_record_archive` records; lossless source data remains in daily JSON/CSV exports.

Because the file is anchored to the requested range instead of a shared calendar period, re-exporting the same range is deterministic and different ranges never overwrite each other's summaries.

## Settings

The range summary is an explicit opt-in setting and defaults to off for existing and new users:

- Range summary
- Summary files only

Roll-up files are aggregate derived artifacts, not daily records. Daily Markdown/Bases/JSON/CSV files continue to use `healthmd.health_data`; the range summary identifies itself separately as `healthmd.rollup_summary`.

When **Summary files only** is enabled together with the range summary, Health.md skips per-day aggregate files and export side effects such as Daily Note Injection and Individual Entry Tracking. It still fetches HealthKit daily aggregate snapshots for every selected day so the summary is complete.

Users who previously enabled weekly/monthly/yearly roll-ups are migrated automatically: any enabled period toggle opts in to the range summary. Historical weekly/monthly/yearly files remain valid v7 roll-ups and are not rewritten; regenerate summaries from the new export instead.

## What gets generated

For each export, exactly one summary covers the requested range:

- `period_id` is `<start>_to_<end>`, for example `2026-03-10_to_2026-03-15`
- `start_date` and `end_date` are the first and last selected days
- `days_expected` is the inclusive day span of the range
- `days_counted` is the number of daily snapshots retained

Each Markdown summary includes:

- schema/frontmatter identifying the file as `healthmd.rollup_summary`
- `schema_version: 8`
- `rollup_period: range`, `period_id`, `start_date`, and `end_date`
- `days_expected`, `days_counted`, and `coverage_percent`
- `source_dates`
- a `units:` map for all summarized keys
- category tables for every metric that had data in that range
- per-metric statistics in collapsible details sections

JSON exports expose the same metadata plus structured `metrics` and `categories` objects. CSV exports write one primary row and statistic rows for each metric. Obsidian Bases exports write a Markdown file focused on YAML frontmatter under `rollup_metrics`.

## Aggregation rules

The range summary uses the rules that `_healthmd_data_dictionary.json` documents when **Write Data Dictionary** is enabled:

| Daily rule | Range behavior |
|---|---|
| `sum`, `duration_sum`, `count` | Sum daily values, also report daily average/min/max. |
| `average` | Average exported daily aggregate values. |
| `weighted_average` | Use workout duration when available, otherwise fall back to daily averages. |
| `minimum` | Range minimum of daily minima. |
| `maximum` | Range maximum of daily maxima. |
| `latest` | Latest daily value with trend context when numeric. Applies to `vo2_max`, even when the latest value is below an earlier value. |
| `list` | Union values and count occurrences. |
| `category_latest` | Latest value plus value counts. |
| `first_time` / `last_time` | Earliest, latest, and average clock time. |

`days_counted` and `source_dates` reflect the daily aggregate snapshots Health.md fetched for the range, even when a day has no value for a selected metric. Missing metric values are ignored for that metric's calculation and surfaced through the per-metric days-counted column. Coverage drops below 100% only when a daily snapshot could not be fetched. There are no future-date expectations: the denominator is the requested range, not a calendar period.

## Preview support

Export Preview shows a **Range summary** section before the daily files when the range summary is enabled. It renders one preview row per export format.

## Limitations

- The range summary queries HealthKit only for the selected days; it does not depend on existing vault files.
- The range summary summarizes compatibility projections and compact lossless diagnostics, not source objects. Record counts do not prove every query was complete; preserve capture-status/warning provenance.
- Summary-only changes which files are written, not the summary schema. Daily `healthmd.health_data` files are skipped.
- Weighted workout summaries use exported daily workout duration as the weight. Deeper recomputation from canonical records is outside the current roll-up contract.
- Keep schema-v5, v6, and v7 roll-ups as historical files; regenerate under v8 rather than relabeling them. V7 and earlier files used weekly/monthly/yearly calendar periods, so their `days_expected` reflects full calendar periods rather than a requested range.

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
- `HealthMdTests/ExportEngine/AppleLooseDailyExportPlannerTests.swift`
- `HealthMdUITests/ExportJourneyUITests.swift`
