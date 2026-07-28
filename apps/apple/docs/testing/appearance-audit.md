# Appearance Audit

## Summary

Health.md should follow the user's system Light/Dark appearance on iOS, iPadOS, and macOS. Production SwiftUI must not apply app-wide `.preferredColorScheme(.dark)`, `.environment(\.colorScheme, .dark)`, or `.colorScheme(.dark)` overrides.

The shared design tokens in `HealthMd/Shared/Theme/DesignSystem.swift` use adaptive light/dark colors, so custom backgrounds, borders, and text colors can respond to system appearance without a global override.

## Dark-only Scope

No production UI currently forces a dark color scheme.

No preview, marketing capture, or isolated visual treatment currently requires a dark-only appearance override. If a future capture or preview intentionally needs one, keep it outside production view composition, document the file here, and exclude only that scoped debug/preview path from `AppearanceRegressionTests`.

## Manual Check Matrix

- Onboarding: check Light and Dark appearance for welcome, permission, sample export preview, Obsidian plugin visualization, optional folder, unlock, and completion screens.
- Export: check Light and Dark appearance for main export, advanced export sheets, progress, and confirmation.
- Settings: check Light and Dark appearance for vault, format, tracking, purchase, and support sections.
- Schedule: check Light and Dark appearance for enablement, frequency, time/day controls, and notifications.
- Sync: check Light and Dark appearance for disconnected, connecting, connected, and transfer states.
- Paywall: check Light and Dark appearance for product loading, purchase, restore, and error states.
- iPad split view: check Light and Dark appearance for sidebar selection, export, settings, schedule, sync, and history panes.
