# Agents

## Design System — Required

`DESIGN.md` and `DESIGN.dark.md` are the governing visual specifications for this app. They preserve Vercel’s Geist light and dark systems with the documented Health.md brand accent layer.

- Use named Compose tokens from `presentation/theme`; do not add ad hoc colors, spacing, type sizes, radii, shadows, or motion values.
- Support both documented themes and follow the system appearance. Do not use Material dynamic color.
- Use bundled Geist Sans for UI/copy and Geist Mono for code, paths, dates, and tabular data.
- Update the governing documents first before intentionally deviating from a token.

## Local Build & Deploy

When building locally, always target the Pixel 7 device:

- **Device serial:** `2C061FDH200CJN`
- **ADB path:** `~/Library/Android/sdk/platform-tools/adb`

Use `./gradlew installDebug` and pass the serial to install on the physical device.
