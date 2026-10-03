# Workout Details and Metadata presentation

## Outcome and settings

Keep readable per-workout summaries while optionally omitting the **Details** and
**Metadata** tables from generated Markdown bytes. This is presentation suppression,
not a collapsed heading and not a source-data filter.

- iPhone/iPad: **Export Settings → Format Customization → Markdown Template →
  Markdown Options → Workout Details and Metadata**.
- Mac: **Settings → Export → Markdown Template → Workout Details and Metadata**
  (with Markdown selected or daily-note body injection configured).
- Default: **on**, preserving existing exports and migrated settings.
- Off: numbered workout headings and time, duration, distance, calories, and
  available physiology bullets remain. Laps, splits, heart-rate zones, and sample
  counts are separate presentation blocks and remain unchanged.
- Daily-note injection uses the same preference; keep **Workouts** selected and
  **Inject Metric Sections** on. **Include Summary** controls the document overview,
  not the per-workout summaries. Custom `{{workout_list}}` and
  `{{workouts_metrics}}` tokens honor the same table preference.

The value is persisted as `markdownTemplate.includeWorkoutDetailsAndMetadata`,
carried in profile/export snapshots, and reconstructed for Connected Mac jobs.
Update both peers to a version supporting this preference for Connected Mac exports;
older apps cannot honor a setting they do not know. Legacy snapshots without the key decode as on. On is omitted from encoded settings
so existing default-on durable fingerprints remain stable; off is encoded explicitly.
The deferred **Share My Setup v2** portable file is a separate allowlisted contract:
it does not carry this newly staged preference. Its native-field coverage ledger
marks the field `local_only`; setup-file imports retain the enabled default, so
configure suppression locally after importing. Native profile persistence and frozen
Mac jobs do carry it. Portable adoption requires Android convergence and contract review.

## Existing notes and capture scope

Re-export with daily-note body injection enabled replaces the managed Workouts
section, removing previously generated Details/Metadata tables. User preambles,
unrelated frontmatter, and user sections outside the managed Workouts section are
preserved. As before, do not place personal prose inside an app-managed section.
Frontmatter-only injection does not modify the existing body. Append-mode ordinary
exports retain old output by design; use Update or Overwrite to replace it.

The switch does **not** change Workouts selection, HealthKit queries, Data Detail,
source-archive policy, Markdown/Bases frontmatter (including `workout_details`),
JSON, CSV, individual event files, or provider sidecars. Choose those controls
separately when deciding what to capture or retain. Hiding tables is not redaction.

## Platform and version decision

The neutral outcome is readable summaries without duplicated detail/metadata
presentation. Apple stages a new optional presentation setting. Android's existing
`workoutsMarkdown` renderer already produces summary bullets, not Apple-style
Details/Metadata tables. There is no Health Connect API blocker: Android parity is
**planned** for the first unified-v9 Markdown presentation-settings/profile writer,
with the same identity and enabled default; frozen Android v4/v5 bytes remain intact.
The repository product-capability inventory records this distinction under
`export.completed-workouts`, whose source-capture outcome remains shared. Exact
setting classifications and the Android target live in the independently versioned
[workout presentation parity record](./workout-presentation-parity-v1.json)
(`export.workout-table-presentation`, classification `planned`). This keeps presentation
staging separate from the metric registry identity and frozen semantic fixtures.

No public schema/version bump: no public keys, types, units, reductions, source
capture, or machine-readable meaning change. Apple daily v8, Android v4/v5, direct
protocol, source archive, shared semantic/render envelopes, and Rust core are
unchanged. The new setting only omits optional readable body blocks when explicitly
requested. Default-on examples and schema signatures must remain byte-compatible.

Affected consumers: Apple ordinary exports, daily-note injection, profile/Mac
snapshots, and native-authoritative render-input Markdown documents. The pure-Rust
production authority admission currently accepts range-summary-only operations,
not daily workout rendering. Android, CLI, shared core, website, API JSON envelopes,
and the external Obsidian parser consume unchanged structured records; none should
interpret absence of a body table as absence of captured workouts.

## Regression and manual verification

Apple CI runs the synchronized `HealthMdTests` target on iOS and macOS, including:

- `WorkoutGranularMarkdownTests`: on/off table bytes for all template styles,
  metadata-bearing, sparse, minimal, and multiple workouts; summary preservation;
  unchanged JSON/CSV/Bases/frontmatter.
- `CanonicalHealthKitArchiveExportTests`: source-archive-bearing JSON/CSV remain
  byte-identical when the presentation preference changes.
- `DailyNoteInjectorTests`: rich → suppressed → repeated suppressed → rich injection,
  preserving user preamble, Journal, and unrelated properties.
- `ExportSettingsSnapshotTests`: legacy default/canonical encoding, frozen snapshot
  JSON round trip/Mac reconstruction, both persisted states/settings reload.

Still required on physical hardware: follow issue #167's day-with-metadata workflow,
check reachability and relaunch on iPhone/iPad, export the same frozen profile to a
paired Mac, and inspect note bytes in an actual vault. Check VoiceOver, Dynamic Type,
and translated Mac copy. No App Store binary or hardware QA is asserted here.
