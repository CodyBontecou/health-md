# Changelog

All notable changes to Health.md will be documented in this file.

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
