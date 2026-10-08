# Appearance Audit

## Summary

Health.md should follow the user's system Light/Dark appearance on iOS, iPadOS, and macOS. Production SwiftUI must not apply app-wide `.preferredColorScheme(.dark)`, `.environment(\.colorScheme, .dark)`, or `.colorScheme(.dark)` overrides.

The shared design tokens in `HealthMd/Shared/Theme/DesignSystem.swift` use adaptive light/dark colors, so custom backgrounds, borders, and text colors can respond to system appearance without a global override.

The CLI export Live Activity uses the system background material and action colors, keeping its semantic primary and secondary text readable in both appearances. Home Screen widgets use semantic system backgrounds and text. Apple Watch follows its native system presentation.

Android's Compose screens use `isSystemInDarkTheme()` and the documented Geist palettes. Native launch/window resources use `values` and `values-night` themes, with matching backgrounds, text, accents, and system-bar icon contrast. Automatic Force Dark is disabled because both palettes are explicitly supplied.

## Dark-only Scope

No production UI currently forces a dark color scheme.

No preview, marketing capture, or isolated visual treatment currently requires a dark-only appearance override. If a future capture or preview intentionally needs one, keep it outside production view composition, document the file here, and exclude only that scoped debug/preview path from `AppearanceRegressionTests`.

The macOS marketing capture conditionally selects light appearance only while `MacMarketingCapture.isActive`; ordinary app use inherits system appearance. The App Store QR code retains a white quiet zone for scanner readability. Camera overlays and the Dynamic Island retain their native dark surfaces.

## Manual Check Matrix

- Onboarding: check Light and Dark appearance for welcome, permission, sample export preview, Obsidian plugin visualization, optional folder, unlock, and completion screens.
- Export: check Light and Dark appearance for main export, advanced export sheets, progress, and confirmation.
- Settings: check Light and Dark appearance for vault, format, tracking, purchase, and support sections.
- Schedule: check Light and Dark appearance for enablement, frequency, time/day controls, and notifications.
- Sync: check Light and Dark appearance for disconnected, connecting, connected, and transfer states.
- Paywall: check Light and Dark appearance for product loading, purchase, restore, and error states.
- iPad split view: check Light and Dark appearance for sidebar selection, export, settings, schedule, sync, and history panes.
- Live Activity: check CLI export progress and terminal states on the Lock Screen in both appearances.
- Android: check cold launch, onboarding, export, settings, and widget setup in both appearances. Toggle the system setting while the app is open; screens and system-bar icons should update together.
