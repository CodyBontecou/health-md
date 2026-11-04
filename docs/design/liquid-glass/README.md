# Liquid Glass redesign — design source

The approved design for the next Health.md experience on iPhone, iPhone Duo, iPad, Mac, Apple Watch and widgets.

- Live canvas (owner access): https://claude.ai/artifact/XTx2RFXpjT7Gxgs6SZrAxg
- Readable Archive (Archive B week strip and the DayPage file view): https://claude.ai/artifact/LB6GSB2VpwsCQbrG1oUaJP
- Signal carousel paywall (iOS boards Signal, SigIOS2, SigIOS3, SigIOSFam): https://claude.ai/artifact/1bxjTi3o7yiN9PnBC5XSsk
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

## Accepted differences from the boards

The shipping app follows every board except where the board would need data the app does not have, would break a policy, or shows a placeholder. Keep these unless the underlying reason changes:

- **PaywallG:** Weekly is listed and selected first (owner decision); subscription subtitles keep an auto-renew and cancel-anytime note.
- **ExportNowG:** the "Will write" count starts with "About", because days without data, roll-ups and the data dictionary make the file count an estimate.
- **NotificationsG:** the Direct CLI wake push says "Your CLI is waiting. Open Health.md to continue on [computer]". The payload must not name the request kind (`apps/wake` privacy test), so "finish the export" is not used.
- **HistoryWarnG:** says "older dates" because the unfinished history check has no cutoff date.
- **AttentionG:** names a denied metric only for Medications. HealthKit does not reveal other read denials.
- **AutomationDetailG:** "Use in Shortcuts" names the app's real App Intent.
- **ClinicianReportG:** no Heart rate variability row. The report's 11-metric set is a cross-platform contract (`apps/apple/docs/features/clinician-report-v1.md`).
- **ClinicAccessG** and the paywall's "Clinic invitation?": built, local-only, and shown only when `PracticeFeaturePolicy` is enabled, which it is not in production.
- **ReviewG:** shows a real published review without a storefront label.
- **iPadArchiveG / DuoInnerArchiveG:** the header keeps previous/next month chevrons. They are the only month navigation on those layouts, and coverage history spans several months.
- **iPhone Duo boards:** "unfolded" is detected as a regular-width phone window with a short side of at least 500 pt; the outer-screen hint appears only after that state has been seen.
- **AutomationsGlass / AS_iPhone_7:** the Agent feed refreshes Today every 3 hours. Today Refresh offers 30 minutes, 1, 3, 6 and 12 hours (`ExportSchedule.todayRefreshMinuteOptions`), so the board's "Every 2 hours" is not a real setting.
- **App Store boards:** produced by `apps/apple/scripts/app-store-screenshots/compose.swift` from real captures (runbook: `apps/apple/screenshots/macos/README.md`). Duo slides need a real device; the AS_iPhone_7 widget insert is a manual crop.
- Rows that exist in the app but not on a board stay where `CoverageMap.dc.html` places their capability, so no capability is lost. Three entry rows have no board home and stay where they are: Clinician report (Settings › Data), Clear export history (App & support › Configuration) and Help us grow (App & support › Help, opens ReviewG).
- **Archive B (iPhone):** the week strip and readable day are the iPhone default; Month switches to the ArchiveGlass month calendar and is remembered. The automation chips stay above the strip when there is more than one automation, so the per-automation filter keeps its place. Metric tiles come only from the written file's frontmatter (no file, no tiles), and the sentence card stays below the day. Other automations' lines open DayPage on their tab.
- **DayPage:** shows the file as written. The "Added on re-export" and "Value changed" marks are not shown, because Health.md keeps no earlier copy of a file to compare. The primary button opens the full file viewer ("Open file"); the app has no Obsidian or Files deep link for a single file. Endpoints and Mac folders show their status and a note instead of a file, since their output is not readable on the iPhone.
- **Signal paywall:** D5 says "Cancel anytime" instead of "A heads-up": Health.md does not send a trial-ending reminder. The review card shows a verified App Store excerpt (`AppStoreReview.verifiedExcerpts`) instead of the placeholder.
