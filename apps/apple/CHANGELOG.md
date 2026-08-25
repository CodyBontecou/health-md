# Changelog

All notable changes to Health.md will be documented in this file.

## [Unreleased]

### Fixed
- The iPhone export-completion toast no longer shows a successful local export in error red. Success was inferred by checking whether the status text started with "Exported"/"Updated", which the generated-file/data-day success summary never does (and which localization breaks entirely); full-success statuses now carry an explicit recorded outcome, restoring the success styling along with the persistent toast and its Preview/Browse actions.
- Selecting the iCloud Drive root (or other file-provider roots) no longer displays the raw provider identifier `com~apple~CloudDocs` — whose tildes render like strikethroughs around "apple" — as the vault name. Destination names now prefer the localized name Files shows ("iCloud Drive").
- Export folders on cloud file providers (iCloud Drive, Dropbox, and similar) no longer lose their saved selection on cold starts. Bookmarks for folders whose volume never reports persistent file identifiers now rebind to the provider's current path and refresh the saved metadata when resolution succeeds with security-scoped access, instead of demanding manual re-selection on every launch — which had broken automatic exports and Shortcuts until the folder was re-picked. A confirmed persistent-identity mismatch is still blocked outright, identity evidence appearing on only one side of a move still requires review, and newly selected folders now store their trusted path through the same bookmark round-trip that later verifies it, eliminating save/verify normalization mismatches.

## [3.1] - 2026-08-22

### Added
- Export profiles can now be fully edited in one place: a new profile editor (pencil button on a profile's detail, or the same form for creation) edits name, target, destination folder or endpoint, output formats, write mode, filename/folder templates, format folders, zip, data dictionary, lossless records, summary-only, roll-ups, Daily Note injection, and individual-entry settings, with the full Health Metrics picker one tap away — no need to activate the profile and hunt through the Export tab. The destination section includes a true system folder picker ("Choose New Folder…") and an inline "Add Endpoint…" form for new API endpoints (URL + Keychain-stored bearer token), so destinations can be created right in the editor instead of choosing only among previously used ones; picking a folder or endpoint doesn't disturb the live Export-tab destination until the edited profile is saved and active. Editing the active profile keeps the Export tab in sync immediately; editing other profiles never touches live state. The live overlapping-export warning tracks every in-flight change.
- Creating a new export profile now opens a small setup form (name, target, destination folder) before anything is saved, with a live warning when the chosen destination and the current output templates would write the same files as another profile — since profile names never appear in file paths, the later run would silently overwrite the earlier one. The warning updates as you change the folder, and the profile's detail page keeps a standing overlap notice naming the other profiles until their folders or templates diverge. Connected Mac profiles are compared against the shared Mac destination; API endpoint profiles never trigger it.

### Fixed
- Persisted export-history file counts now share one cross-category budget instead of being clamped per category, so absurd per-category counts can no longer inflate the persisted generated-file total beyond the supported bound. Breakdowns whose counts were reduced by the budget are marked with an explicit truncated flag so readers can tell exact totals from budget-limited ones. Older aggregate-over-budget history is migrated conservatively instead of making the full saved history unreadable, and mixed-version readers no longer treat capped counts as exact.
- Preserved scheduled-export retries (device-locked or partial runs) are no longer destroyed moments after being advertised. A post-run re-arm, a schedule edit, or disabling automation now cancels only fallback notifications that have not fired yet; a preserved retry and its recovery notification survive until satisfied or the schedule is re-enabled fresh — including retries preserved seconds earlier, and even if the app is interrupted mid-run. The armed 60-second fallback is also defused the moment its retry starts, so it can no longer surface mid-run. Two profiles (or a profile and the legacy schedule) firing at the same minute no longer overwrite each other's stored retry, which previously turned one profile's recovery notification into a dead tap.
- An enabled legacy single schedule and enabled export-profile schedules now both run automatically. Background wake-ups, HealthKit delivery, and the worker's silent push run due profile occurrences and the legacy schedule's due occurrence together, instead of the legacy schedule only being able to fire notifications that required a manual tap.
- A profile's preserved retry from before its schedule was re-enabled is discarded instead of silently exporting a stale date window (and consuming an export action) on the next app open.
- Two profiles' retries at the same fire minute no longer block each other's in-flight dedupe.
- Tapping a scheduled-export notification no longer fails with "Scheduling is disabled" when scheduling runs through export profiles. The recovery fallback notification armed for a profile occurrence now carries that profile's identity, dates, and destination, so a tap retries the profile's exact export instead of a legacy request that could never run. Stale pre-profile recovery requests are discarded cleanly (a tap runs due profile work), the worker's silent push now wakes profile schedules instead of being ignored, and the "Scheduling is disabled" message only appears when all scheduling is genuinely off.
- Editing an export profile's schedule (time, cadence, lookback) now updates the next scheduled export immediately — the Schedule tab's next-export status, the background-task wake-up time, and the worker silent-push mirror all re-read the just-saved entry instead of serving a stale cached snapshot until an unrelated refresh.
- Tapping a scheduled-export recovery notification on a cold launch no longer surfaces an unexpected bare "Export Failed" alert (or silently does nothing). Every drained pending export — whether triggered by the notification tap, an app-active catch-up, or a Connected Mac handshake resume — now presents through the in-app scheduled-export activity banner, including live progress, and the tap can no longer double-run the same request.
- Workouts whose attached WorkoutKit plan cannot be decoded by the device (surfacing as an opaque `WorkoutKit.ImportError error N` partial-export warning) now explain in plain language that the workout and all of its samples exported successfully and only the optional structured plan was omitted, with the likely cause. Partial-export warnings in iPhone, iPad, and Mac export history now wrap fully and can be selected and copied for bug reports.

## [3.0.5] - 2026-08-09

### Added
- Added private, on-device clinician reports on iPhone and iPad with inclusive 7-, 30-, 90-day, and custom date ranges; 11 focused health metrics; previewable summaries and readings; an optional display name; and accessible Letter or A4 PDF output.
- Added an in-app Direct CLI QR scanner with camera-permission recovery, strict private-LAN/Tailscale payload validation, and automatic pairing after a valid scan.

### Changed
- Scanning a Direct CLI or MCP pairing QR from **Sync → Direct CLI Access → Scan Pairing QR** now starts the authenticated connection immediately, with no second **Pair** tap. External custom-URL opens no longer authorize pairing.
- The Mac app is now fully localized in every supported language, with a clearer dashboard and layouts that preserve longer localized labels and status details.

### Fixed
- New Direct CLI trust remains provisional until a valid peer hello; incomplete, cancelled, duplicated, expired, or interrupted QR handoffs restore previous trust and endpoint settings.

### Privacy and Security
- Clinician report generation stays on-device. Temporary report files remain private until an explicit share or save action, and missing or partial readings are labeled instead of inferred.

## [3.0.4] - 2026-08-03

### Added
- Added complete app localization for German, Spanish, French, Italian, Japanese, Korean, Dutch, Brazilian Portuguese, and Simplified Chinese, including export, scheduling, formatting, preview, tracking, and Mac-destination flows.
- Added localized nine-slide iPhone App Store screenshot sets for every supported non-English locale.
- Added a default-on **Write Data Dictionary** export setting on iPhone, iPad, and Mac. Turning it off keeps ordinary Markdown and other selected exports while omitting `_healthmd_data_dictionary.json`, including from ZIP archives and Connected Mac jobs. Older connected peers must be updated before they can honor suppression.
- Added transparent **Privacy & Analytics** disclosures on iPhone, iPad, Mac, and onboarding for automatically collected, pseudonymous product events and their strict health-data exclusions.
- Added privacy-safe onboarding skip milestones, purchase-source attribution, paywall CTA tracking, and coarse Mac onboarding/destination-setup milestones without collecting health values, export contents, or paths.

### Changed
- New installs now default **Lossless Health Records** off so the first export uses the faster summary-only path. Existing explicit on or off choices remain unchanged, and lossless canonical source capture remains available as an opt-in.
- Onboarding now prioritizes Apple Health and folder setup while keeping explicit skip actions, presents the free allowance as a full-width secondary choice, offers Ready-screen repair actions, and opens a preconfigured first-export preview on completion.
- Manual and scheduled exports now share the same free-export allowance.
- Removed retired hosted-account and remote-MCP surfaces so the product remains focused on local files and direct device connections.

### Fixed
- Enabled exports to start directly from mobile preview flows.
- Restored API endpoint preview and export events in first-party activation analytics.
- Restored the visible Preview and Export Data actions on iPad; the actions had been placed in a navigation toolbar that the iPad export screen hides.
- Replaced the generic export error shown for an empty Apple Health store with a guided **No Health Data Found** state on iPhone and iPad, including date-range, permission, and Apple Health guidance.

## [3.0.3] - 2026-07-31

### Changed
- New installs now default **Lossless Health Records** off so the first export uses the faster summary-only path. Existing explicit on or off choices remain unchanged, and lossless canonical source capture remains available as an opt-in.
- Temporarily removed Clinical Health Records access from App Store builds, including its managed entitlements, permission prompt, selectable metrics, and direct-query catalog. Ordinary Apple Health metrics and lossless source-sample exports remain available.

### Fixed
- Restored the visible Preview and Export Data actions on iPad; the actions had been placed in a navigation toolbar that the iPad export screen hides.
- Replaced the generic export error shown for an empty Apple Health store with a guided **No Health Data Found** state on iPhone and iPad, including date-range, permission, and Apple Health guidance.
- The iOS exported-file success view now stays hidden during multi-file exports and appears after the complete export finishes.
- Stopped the Mac app from accessing Keychain during ordinary launch. Retired local-agent cleanup now removes only legacy files, and encrypted context status loads only after an explicit request in Mac settings.
- Corrected weekly, monthly, and yearly roll-up output estimates to account for format-specific file sizes, the full data dictionary, and complete calendar windows. Summary-only exports now show their expanded source-day workload and report progress across those source days.
- Prevented Connected Mac file exports from failing when the separate encrypted query-context cache is unavailable. Small summary records now spool off the iOS main actor and flush in bounded batches to reduce UI stutters during large roll-up preparation.

## [3.0.2] - 2026-07-23

### Added
- Added the `{YR}` filename placeholder for two-digit years, enabling daily-note names such as `10-07-26` across export filenames, folder templates, and Daily Note Injection.
- Added a loopback-only local query/evidence API, encrypted on-Mac health context storage, CLI commands, and a sandboxed `healthmd-mcp` helper. Requests carry their metric, source, date, detail, and operation scope directly without profiles, registrations, grants, or credentials.
- Added directly scoped, resumable iPhone context acquisition for exact ranges and all available Apple Health history without creating export files or consuming file-export quota.
- Added `healthmd metrics` and high-level `healthmd query` commands that can acquire and query exact Apple Health metrics without changing saved iPhone export settings or requiring credential setup.
- Added `healthmd extract` as the canonical-data happy path for users and shell agents: date/metric/category/source/detail selection is pushed to iPhone before HealthKit reads, optional object/JSON-Pointer projection is applied afterward, and results preserve ordinary `healthmd.health_data` v7 objects plus explicit protocol receipts rather than exposing the durable transport envelope.
- Added `healthmd doctor`, the local `/v1/agent/readiness` route, and the `healthmd_doctor` MCP tool for actionable encrypted-cache and iPhone readiness without exposing health values.
- Added high-level workout, metric-coverage, explicit period-comparison, and factual training-evidence commands plus dedicated typed MCP tools backed by the existing bounded query contracts.
- Added first-class sleep-session queries with stable IDs, local timezone and cross-midnight dates, nap/overnight classification, fixed session-relative windows, stage completeness, observed/untracked duration, adjacent-day physiology coverage, explicit exclusions, and matching CLI/MCP surfaces.
- Added deterministic workout-to-preceding/following-sleep alignment with stable IDs, timing gaps, fixed sleep windows, physiology sample counts, coverage/exclusions, and explicit non-causal safety wording across query, CLI, and MCP surfaces.
- Added `healthmd.requested_scope_completion` v1 plus separate `requested_scope_status`, `corpus_status`, and aggregated `unrelated_skips`, preventing unrelated capture branches from falsely downgrading complete scoped queries.
- Added high-level `--all-pages`, `healthmd.cli_query_receipt` v1, stderr JSONL progress, opt-in table output, safe summary-only `--reuse-covered`, metric-aware coverage, and MCP `all_pages` traversal with receipts.

### Changed
- WHOOP, Strava, and local query result traversal now continues through provider cursors/pages instead of fixed total-result limits, while preserving units, source provenance, coverage, missingness, and capture diagnostics.
- `healthmd.health_data` is now documented and enforced as the single public health-data source of truth; raw/job/query envelopes are protocol metadata and typed query outputs are derived compatibility views over a disposable index.
- Fresh local acquisition uses the metrics, sources, dates, and detail supplied by each request, and HealthKit permission readiness is checked only for the requested ordinary types.
- Sleep-session/alignment commands now acquire lossless canonical stage intervals by default, de-duplicate overlapping stage sources for asleep totals, and report aggregate-only cache without claiming interval coverage.
- Automatic CLI/MCP page traversal now enforces aggregate memory ceilings; table output labels itself lossy and retains completion, coverage, source, limitation, and skip diagnostics.

### Privacy and Security
- Local query routes accept only canonical HTTP loopback URLs and validated loopback peers. Loopback is the complete access boundary; there are no query credentials or saved access profiles. Stable integrity-protected cursors, strict direct-scope validation, bounded pages, and AES-GCM context retention fail closed.
- Sleep/comparison technical date ranges are included explicitly before adjacent blobs are decrypted, and fresh scope completion requires every requested metric/source/day cell to come from blobs mutated by that refresh so stale cache or another provider cannot mask failures.
- Existing installations remove retired Agent Access/Profile files and their dedicated Keychain service once without touching encrypted query context, connected-provider credentials, or manual-IP secrets.

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
