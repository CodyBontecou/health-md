# `healthmd.rollup_summary` v10

Status: canonical Apple profile. Source daily schema: `healthmd.health_data` v10. Reduction rules version: 8.

New range summaries retain [v9's immutable range authority and coverage rules](../v9/contract.md), but identify `schema_version: 10` and `source_schema_version: 10`. This avoids claiming that new v10 captures came from daily v8. `rollup_rules_version: 8` is deliberate: primary reductions have not changed. WHOOP values, including physiological-cycle steps, have no roll-up rule and are excluded.

Range JSON, Markdown, Bases and CSV identify `healthmd.rollup_summary`, v10, source `healthmd.health_data` v10, rules v8, and the captured `calendar_timezone`. Bounds/period ID/timezone are frozen before capture; failed or empty boundary days do not shorten the request. Inclusive bounds are limited to 10,000 days; successful empty days count toward coverage, query failures do not.

Legacy calendar presentation functions can also render v10 JSON/Markdown/Bases with the same weekly/monthly/yearly identity and reduction semantics as before. Calendar timezone remains optional on these compatibility presentations. Legacy calendar CSV remains structural/unversioned; range CSV carries the versioned leading metadata columns. Current app UI and new scheduling intent remain range-only.

Historical calendar v8 and range v9 artifacts/fixtures are not relabeled or regenerated. Readers accept their original source/rule identities and reject v10 incorrectly claiming source daily v8. Unified daily v9 is a different, still-deferred namespace/contract.
