# Android Accessibility Audit

Last updated: 2026-08-02

## Pass covered

Primary TalkBack and large-font-risk areas were audited across onboarding, export setup, date/export controls, scheduled exports, history/settings navigation, format customization, frontmatter editing, and paywall actions.

## Fixes applied

- Custom glass buttons/cards now use Compose `clickable` semantics with `Role.Button` instead of pointer-only gesture handlers.
- Shared icon-only glass buttons now have 48 dp touch targets by default and accept content descriptions.
- Schedule increment/decrement controls and frontmatter add actions now expose TalkBack labels.
- Shared secondary buttons enforce a minimum 48 dp touch target.
- Export progress announces polite state updates while exports/previews advance.
- Decorative icons continue to use `contentDescription = null`; visible text remains the accessible label for card rows and navigation items.

## Known limitations

- Full automated TalkBack traversal still requires device/emulator validation because Compose unit tests cannot fully emulate Android's screen reader.
- Very large display/font combinations may still wrap dense metric rows; controls remain reachable and scrollable, but some cards can become tall.
- Health Connect's system permission screens are outside the app and inherit Android system accessibility behavior.

## Home-screen widgets

- Every widget keeps a visible text summary for charted values. Duplicate activity-ring artwork is decorative, while heart charts expose concise descriptions; color and artwork are never the only source of meaning.
- The widget root exposes a single predictable action that opens Health.md. Setup and management actions use the app’s 48 dp control tokens.
- Responsive compact, wide, medium, and tall-large compositions are tested separately because launcher padding and resize behavior vary by device. At larger font scales, compact cards switch to denser textual summaries and shorten step counts instead of clipping essential status copy.
- Missing, stale, permission-required, Health Connect unavailable, and before-first-unlock states use text rather than color alone.
- Synthetic picker previews contain readable labels and do not expose real measurements.
- Glance renders through `RemoteViews`, so launcher accessibility remains a physical-device gate. Pixel 7/API 37 QA confirmed whole-card TalkBack focus and activation, unclipped 1.3× font layouts, Arabic RTL mirroring, light/dark contrast, and compact-to-tall resizing.
