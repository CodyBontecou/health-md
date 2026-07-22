# Changelog

All notable changes to Health.md will be documented in this file.

## [Unreleased]

### Added
- Added the `{YR}` filename placeholder for two-digit years, enabling daily-note names such as `10-07-26` across export filenames, folder templates, and Daily Note Injection.
- Added unlimited Health Context Profiles, registered local-agent access, encrypted on-Mac health context storage, authenticated query/evidence APIs and CLI commands, and a signed sandboxed `healthmd-mcp` helper.
- Added profile-scoped, resumable iPhone context acquisition for exact ranges and all available Apple Health history without creating export files or consuming file-export quota.

### Changed
- WHOOP, Strava, and agent result traversal now continues through provider cursors/pages instead of fixed total-result limits, while preserving units, source provenance, coverage, missingness, and capture diagnostics.

### Privacy and Security
- Agent credentials are issued once and stored in Keychain; profile grants, exact adapter surfaces, owner-scoped jobs, stable authenticated cursors, PHI-minimized activity, and AES-GCM context retention controls fail closed.

## [3.0.1] - 2026-07-21

### Added
- Added trusted manual IP reconnects so a paired iPhone and Mac can reconnect securely without entering a new pairing code each time.

### Changed
- Made large and multi-year connected iPhone-to-Mac exports durable and resumable, with incremental file writing to reduce memory pressure.
- Improved connected Mac handling for Daily Notes Only, custom schedules, interrupted jobs, and preserved export dates.

### Fixed
- Improved recovery details and retry behavior for failed or interrupted connected exports.

## [3.0] - 2026-07-20

### Added
- On iPhone and iPad, added custom scheduled export cadences with configurable day, week, or month intervals and a start date, supporting schedules such as every other day or monthly.
- On iPhone and iPad, added **Daily Notes Only** for filesystem exports, allowing Health.md to update or create Obsidian daily notes without generating aggregate files, ZIPs, roll-ups, individual entries, provider sidecars, or a data dictionary. The mode works for local, scheduled, Shortcut, CLI-triggered, and Connected Mac exports with explicit mixed-version safety.
- Added live export schema v6 with an authoritative `healthmd.healthkit_records` v1 archive in JSON and matching canonical JSON rows in CSV. Existing daily summaries remain available.
- Added complete public source capture for ordinary quantities/categories, blood-pressure and food correlations, workouts/routes/events/activities/statistics/associations/effort/WorkoutKit plans, specialized records, State of Mind, medications, Activity summaries, characteristics, clinical/FHIR/CDA/verifiable/vision records, and exact attachments.
- Added explicit capture/query outcomes, ownership, metric attribution, relationships, warnings, and partial-failure diagnostics so incomplete capture cannot appear complete.
- Added strict `canonical_source_records_v1` CLI output with per-day/capture summaries and opt-in `--allow-partial` exit behavior.

### Changed
- Limited Full Access purchases to the approved one-time Individual Lifetime, Family Lifetime, and Family Upgrade options for this release.
- Renamed the user-facing Time-Series Data setting to **Lossless Health Records**. It defaults on for new installs; existing explicit off choices are preserved and remain summary-only. The internal compatibility key remains `includeGranularData`.
- JSON is the complete source representation. CSV carries the same canonical records; Markdown and Obsidian Bases intentionally remain readable summaries with capture counts and diagnostics.
- Individual Entry Tracking now derives entries from canonical source UUIDs whenever an archive exists instead of substituting daily aggregates for failed or empty source queries.
- Canonical records use strict source-start day ownership in the captured timezone and never clip raw timestamps. Sleep summaries retain their established noon-to-noon compatibility behavior.
- Schema-v5 and schema-v6 exports and their signature fixtures remain historical. Consumers should branch on version; re-export v5 dates for lossless source completeness and v6 files when corrected v7 summary semantics matter.

### Fixed
- On iPhone and iPad, Export History now makes failed runs explicit, explains the likely cause, suggests the next recovery step, and preserves selectable technical details for clearer bug reports.
- On iPhone and iPad, weekly local scheduling now honors its configured weekday, and delayed scheduled runs retain the logical occurrence date so catch-up does not skip unexported days.
- Added schema v7 to correct `vo2_max` dictionary and period roll-ups, populate canonical units in extended CSV summary categories, and render roll-up dates in the calendar timezone used to form each period. VO2 Max now uses the latest daily measurement as its headline while retaining period min/max/average context; ISO weekly labels now agree with Monday-through-Sunday period IDs.
- Preserved exact quantity statistics/series, category raw values, source revision/OS/device provenance, recursive typed metadata, binary values, relationships, and unknown future values without lossy coercion.
- Corrected VO2 Max carry-forward provenance, Stand Time versus Stand Hours semantics, vitamin/mineral units, and blood-pressure pairing without inferred sessions or averages.
- Deduplication now merges only repeated views of the same UUID or documented external identity; similar-looking distinct records remain separate.
- UUID-free public values no longer receive fabricated UUID/source/device provenance, and clinical records expose stable FHIR content identity separately from unstable HealthKit UUIDs.

### Privacy and Security
- Added encrypted, checksum-validated, size-bounded iPhone/Mac transfers for current file jobs and strict raw CLI results; strict raw no longer falls back to an unbounded whole payload.
- Exact available attachment bytes are base64 encoded with SHA-256 checksums. Source URLs are preserved but never fetched.
- Hardened special authorization/capability reporting and clinical failure logging so unsupported/skipped/cancelled access remains explicit without leaking PHI-bearing error details.
- Documented public-API, HealthKit read-privacy, snapshot/deletion-history, file-size, and final-serialization memory limits.

## [2.9.3] - 2026-07-14

### Changed
- General maintenance and reliability improvements.

## [2.9.2] - 2026-07-13

### Added
- Added versioned export schema v4 with lossless HealthKit workout activity identity across Markdown, Obsidian Bases, JSON, and CSV.
- Added explicit calendar timezone context while keeping complete machine-readable timestamps in UTC.

### Changed
- Recognizes every workout activity in the current HealthKit SDK and preserves readable names, stable sport values, HealthKit cases, and original raw values, including future unknown activities.
- Existing export files remain readable and compatible; re-export dates for the new fields.
- Update the Health.md Obsidian plugin before enabling roll-up summaries or format folders in a mixed-schema vault.

## [2.8] - 2026-07-06

### Fixed
- Fixed weekly, monthly, and yearly roll-up summaries inside archived and zipped exports.
- Improved Mac export handling so roll-up settings are preserved more consistently when iPhone prepares the data.
- Hardened roll-up Markdown escaping for metric names, metadata, and summary tables.

## [2.6] - 2026-06-29

### Added
- Added a Mac CLI surface for installing `healthmd`, checking readiness, and triggering iPhone Apple Health exports from Terminal or automation.
- Added Mac-to-iPhone export requests for yesterday, recent-day, and custom-date-range exports when the iPhone app is open and connected.
- Embedded the Health.md CLI operator guide in the Mac app so users can copy supported commands and troubleshooting steps.

### Fixed
- Fixed archived and zipped roll-up exports so weekly, monthly, and yearly summaries are written consistently on iPhone, iPad, and Mac.
- Improved Mac roll-up sync compatibility with the iPhone export pipeline.
- Hardened Markdown and roll-up escaping so metric names, metadata, and generated summaries remain readable in Obsidian and other Markdown tools.

## [2.1.10] - 2026-06-13

### Fixed
- Sleep exports now align with daily journaling expectations: an exported date includes the sleep session that starts that evening and ends the following morning.

## [1.6.2] - 2026-03-21

### Fixed
- HRV export now uses the daily average of all SDNN measurements, matching Apple Health's displayed value

## [1.6.1] - 2026-03-13

### Added
- Full VoiceOver support with proper labels, hints, and values for all interactive controls
- Dynamic Type support so text scales with system accessibility settings
- VoiceOver announcements for schedule changes, sync status, and connection events
- YAML-only mode for Obsidian Bases exports (frontmatter properties only)
- Quarter date placeholder (`{quarter}`) for folder path organization

### Fixed
- Individual Entry Tracking now warns when enabled without selected metrics
- Daily note metadata is preserved when using the Obsidian Bases update method
- Decorative UI elements are hidden from screen readers for cleaner VoiceOver navigation

## [1.6.0] - 2026-03-12

### Added
- New Liquid Glass UI design system
- Improved visual aesthetics with modern macOS 26 styling

### Changed
- Updated to macOS 26 SDK
- Refined user interface components

### Fixed
- Various bug fixes and performance improvements

## [1.5.1] - 2026-02-27

### Fixed
- Fixed Gatekeeper blocking: App is now properly code-signed and notarized by Apple
- macOS users can now install and run the app without security warnings

## [1.5.0] - 2026-02-25

### Added
- First macOS build distributed via isolated.tech
- Sparkle auto-update support
