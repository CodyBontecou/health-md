# Agents

## Cross-platform feature and export policy

Apple and Android should expose the same capability, terminology, settings semantics, and public data meaning whenever Health Connect and HealthKit permit it. Before changing a mobile feature, health metric, provider integration, exporter, API/automation behavior, or public terminology, read `../../docs/architecture/cross-platform-unification-policy.md` and inspect the Apple implementation and contract.

- Define the common user/consumer outcome first; do not treat the current Apple shape as automatically correct.
- Prefer shared semantic IDs, canonical units, reducers, completeness states, and unified-contract fixtures when semantics are equivalent.
- Keep Health Connect-only data in an explicit Android capability/platform section. Unsupported Apple data must not receive fabricated placeholders.
- If an otherwise shared feature lands on Android first, mark Apple `planned` with a concrete target or document the OS/API blocker in `packages/contracts/product-capabilities.json`.
- Preserve distinct meanings such as Health Connect HRV RMSSD versus HealthKit HRV SDNN, Android sleep-journal behavior, exact source timestamps, and provider merge provenance.
- Never change frozen Android v4 or analytical v5 bytes in place to create parity; use a new reviewed profile/common contract.
- Run affected Android, Apple, shared-core, contract, CLI, website, API/automation, and external Obsidian consumer tests.

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
