# Changelog

All notable changes to Health.md will be documented in this file.

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
