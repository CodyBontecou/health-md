# Liquid Glass redesign — design source

The approved design for the next Health.md experience on iPhone, iPhone Duo, iPad, Mac, Apple Watch and widgets.

- Live canvas (owner access): https://claude.ai/artifact/XTx2RFXpjT7Gxgs6SZrAxg
- Superseded explorations, kept for history only (do not implement; on the original design account): https://claude.ai/artifact/NcL9X49rtDVqaQWE9JnK1X

## What is here

| Path | Contents |
| --- | --- |
| `screens/*.dc.html` | One file per screen. Self-contained HTML; open in a browser for a static look, or read as source. |
| `screens/AS_*.dc.html` | App Store screenshot boards for iPhone, iPad, iPhone Duo and Mac. They embed the product screens with `<dc-import>`. |
| `screens/CoverageMap.dc.html` | Every `product-capabilities.json` capability and every current Apple view mapped to the screen that carries it. The zero-regression checklist. |
| `canvas.json` | Canvas layout: which screens sit in which row (`notes` are the row titles). |
| `tokens.json` | Colours (dark, light, Reduce Transparency), radii, spacing, type, control sizes, calendar day states. |
| `assets/` | App icon, crystal heart and App Store hero image used by the screens. |

## How to read a screen file

- Inline `style="…"` values are the exact design values (colours, sizes, spacing, radii).
- The `<script type="text/x-dc">` block holds behaviour: `renderVals()` computes state such as calendar day status, profile aggregation, streak and gap counts, and the export-sheet summary. Treat it as the reference logic, not production code.
- `{{ name }}` holes are values from `renderVals()`; `<sc-for>` repeats and `<sc-if>` branches.
- Values in `[brackets]` and the health numbers are placeholders or sample data, never real copy.
- `support.js` is the canvas runtime and is not included; files render statically without it.

## Screen rows (from `canvas.json`)

1. Core: Archive (All, light), Composer, Automations, Settings, Export moment, archive widgets
2. Archive per profile: Weekly CSV, Agent feed, paused profile
3. Export now: sheet, preview, large-export confirm, history warning, partial result
4. Automation settings: metrics, formats & data detail, output, format customisation, daily notes, entries, schedule
5. Destinations & automation detail: folder, Mac, CLI, API endpoint, Agent Data gateway, automation hub
6. States: empty archive, needs attention, notifications
7. Account, support & tools: paywall, onboarding, connected apps, clinician report, clinic access, diagnostics, app & support
8. More account · accessibility · localisation: myself.md claim, review, file viewer, Reduce Transparency, largest text, German sentence
9. Coverage map
10. Gaps closed: report fallback, import setup review, formats help, QR scanner, What's New
11. Widgets, Live Activity, Watch
12. iPad Archive
13. Mac: destination, history, CLI & MCP, menu bar
14. iPad Automations & Settings, Mac Settings
15. iPhone Duo: outer, inner Archive, inner composer, Split View
16. App Store · iPhone 6.9″ (440×956, exported @3×)
17. App Store · iPad 13″ landscape (1376×1032, exported @2×)
18. App Store · iPhone Duo inner (951×669) and outer (466×678), exported @3×
19. App Store · Mac (1440×900, exported @2×)
