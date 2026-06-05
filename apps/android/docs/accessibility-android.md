# Android Accessibility Audit

Last updated: 2026-06-05

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
