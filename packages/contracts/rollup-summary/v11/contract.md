# `healthmd.rollup_summary` v11 — Apple Morning ends

Status: owner-authorized, production-gated successor implementation. This contract does not qualify a product release.

The range window and coverage grammar follows v9: immutable requested civil start/end dates in the captured IANA timezone; at most 10,000 inclusive days; failed bounds do not shrink the range; successful empty days count toward capture coverage. Metric days count only days with that metric, and averages exclude missing values.

The successor declares `schema_version: 11`, `schema_profile: apple-rollup-v11`, `source_schema: healthmd.health_data`, `source_schema_version: 11`, `source_schema_profile: apple-v11`, and `rollup_rules_version: 11`. Its `time_context` is atomic: captured `calendar_timezone`, UTC `timestamp_timezone`, `sleep_day_attribution: morning_ends`, `sleep_owner_day_rule: session_end_date`, and `sleep_interval_clipping: none`. Top-level `calendar_timezone` must agree with `time_context.calendar_timezone`.

Sleep quantities are already whole-session wake-date daily reductions. Range aggregation uses the successor metric registry's declared reductions; it never clips sessions again, subtracts wall clocks, or rewrites source ownership. Apple Core remains native Core. Unsupported or absent statistics stay absent. Metric rules marked `none` remain excluded from summary output.

JSON uses the supplied schema; Markdown and Bases carry equivalent frontmatter. CSV keeps the v9 leading column grammar and adds six trailing authority columns: Schema Profile, Source Schema Profile, Timestamp Timezone, Sleep Day Attribution, Sleep Owner Day Rule, Sleep Interval Clipping. Every row carries the same authority. This independently versioned grammar does not alter historical v8 calendar or v9 range bytes.

Revision 2 of the semantic capability enables only the requested range for Apple v11. Historical calendar periods remain readable in their original contracts. Android has no existing period-summary writer to silently repurpose; its Light identity and daily v6 remain separate.

The four fixtures are actual shared-core artifacts from `sleep_range_summary.rs`, generated from synthetic SDK aggregate inputs through real semantic/render sessions with independently asserted range, coverage, quantity and attribution outcomes. They are core controls, not native public-writer goldens. AppleWakeDateExportPlannerTests additionally exercises the actual native local-range planner and packaged Rust with synthetic sleep capture inputs, emitting four deterministic artifacts for external reader qualification. Those native artifacts remain separate from these core-only fixtures. Physical-provider and complete execution qualification remain required before production enablement.

Regenerate with an explicit task-owned `HEALTHMD_WAKE_DATE_RANGE_FIXTURE_DIR` and `cargo test -p healthmd-core --test sleep_range_summary --locked`, then copy artifact bytes verbatim and review the manifest hashes. Do not regenerate historical fixtures.
