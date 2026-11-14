---
version: beta
name: Health.md Material 3
description: Health.md’s Material 3 design system for Android, Light theme (the Dark theme is documented at /design.dark.md).
colors:
  primary: "#1d1b20"
  secondary: "#49454f"
  tertiary: "#6a3fe0"
  neutral: "#f2ecf4"
  # Health.md brand tonal palette, seeded from the faceted purple app icon.
  brand-primary: "#6a3fe0"
  brand-hover: "#4f2fa8"
  brand-subtle: "#e9ddff"
  brand-border: "#cdb6ff"
  brand-on-primary: "#ffffff"
  brand-on-subtle: "#23005c"
  # Tonal neutral surfaces. background-* are surfaces; gray-* are containers, outlines and text.
  background-100: "#fef7ff"
  background-200: "#f8f1fa"
  gray-100: "#f2ecf4"
  gray-200: "#ece6ee"
  gray-300: "#e6e0e9"
  gray-400: "#e0dae2"
  gray-500: "#cac4d0"
  gray-600: "#aea9b4"
  gray-700: "#7a757f"
  gray-800: "#605d66"
  gray-900: "#49454f"
  gray-1000: "#1d1b20"
  # Material roles without a gray step, and Archive coverage day states.
  secondary-container: "#e8def8"
  on-secondary-container: "#1d192b"
  # Tertiary container: offers and cautions that are not errors (Best value, large export).
  tertiary-container: "#ffdbcf"
  on-tertiary-container: "#5c1a00"
  coverage-complete: "#dccffa"
  on-coverage-complete: "#2d1f4f"
  coverage-missing: "#b93c0a"
  coverage-no-gaps: "#15803d"
  gray-alpha-100: "#0000000d"
  gray-alpha-200: "#00000015"
  gray-alpha-300: "#0000001a"
  gray-alpha-400: "#00000014"
  gray-alpha-500: "#00000036"
  gray-alpha-600: "#0000003d"
  gray-alpha-700: "#00000070"
  gray-alpha-800: "#00000082"
  gray-alpha-900: "#000000b3"
  gray-alpha-1000: "#000000e8"
  blue-100: "#f0f7ff"
  blue-200: "#e9f4ff"
  blue-300: "#dfefff"
  blue-400: "#cae7ff"
  blue-500: "#94ccff"
  blue-600: "#48aeff"
  blue-700: "#006bff"
  blue-800: "#0059ec"
  blue-900: "#005ff2"
  blue-1000: "#002359"
  red-100: "#ffeeef"
  red-200: "#ffe8ea"
  red-300: "#ffe3e4"
  red-400: "#ffd7d6"
  red-500: "#ffb1b3"
  red-600: "#ff676d"
  red-700: "#fc0035"
  red-800: "#ea001d"
  red-900: "#d8001b"
  red-1000: "#47000c"
  amber-100: "#fff6de"
  amber-200: "#fff4cf"
  amber-300: "#fff1c1"
  amber-400: "#ffdc73"
  amber-500: "#ffc543"
  amber-600: "#ffa600"
  amber-700: "#ffae00"
  amber-800: "#ff9300"
  amber-900: "#aa4d00"
  amber-1000: "#561900"
  green-100: "#ecfdec"
  green-200: "#e5fce7"
  green-300: "#d3fad1"
  green-400: "#b9f5bc"
  green-500: "#82eb8d"
  green-600: "#4ce15e"
  green-700: "#28a948"
  green-800: "#279141"
  green-900: "#107d32"
  green-1000: "#003a00"
  teal-100: "#defffb"
  teal-200: "#ddfef6"
  teal-300: "#ccf9f1"
  teal-400: "#b1f7ec"
  teal-500: "#52f0db"
  teal-600: "#00e3c4"
  teal-700: "#00ac96"
  teal-800: "#00927f"
  teal-900: "#007f70"
  teal-1000: "#003f34"
  purple-100: "#faf0ff"
  purple-200: "#f9f0ff"
  purple-300: "#f6e8ff"
  purple-400: "#f2d9ff"
  purple-500: "#dfa7ff"
  purple-600: "#c979ff"
  purple-700: "#a000f8"
  purple-800: "#8500d1"
  purple-900: "#7d00cc"
  purple-1000: "#2f004e"
  pink-100: "#ffe8f6"
  pink-200: "#ffe8f3"
  pink-300: "#ffdfeb"
  pink-400: "#ffd3e1"
  pink-500: "#fdb3cc"
  pink-600: "#f97ea7"
  pink-700: "#f22782"
  pink-800: "#e4106e"
  pink-900: "#c41562"
  pink-1000: "#460523"
  # Wide-gamut accent variants in oklch for P3 displays (sRGB hex above is the fallback)
  blue-100-p3: "oklch(97.32% 0.0141 251.56)"
  blue-200-p3: "oklch(96.29% 0.0195 250.59)"
  blue-300-p3: "oklch(94.58% 0.0293 249.84870859673202)"
  blue-400-p3: "oklch(91.58% 0.0473 245.11621922481282)"
  blue-500-p3: "oklch(82.75% 0.0979 248.48)"
  blue-600-p3: "oklch(73.08% 0.1583 248.133320980386)"
  blue-700-p3: "oklch(57.61% 0.2508 258.23)"
  blue-800-p3: "oklch(51.51% 0.2399 257.85)"
  blue-900-p3: "oklch(53.18% 0.2399 256.9900584162342)"
  blue-1000-p3: "oklch(26.67% 0.1099 254.34)"
  red-100-p3: "oklch(96.5% 0.0223 13.09)"
  red-200-p3: "oklch(95.41% 0.0299 14.252646656611997)"
  red-300-p3: "oklch(94.33% 0.0369 15.011509923860523)"
  red-400-p3: "oklch(91.51% 0.0471 19.8)"
  red-500-p3: "oklch(84.47% 0.1018 17.71)"
  red-600-p3: "oklch(71.12% 0.1881 21.22)"
  red-700-p3: "oklch(62.56% 0.2524 23.03)"
  red-800-p3: "oklch(58.19% 0.2482 25.15)"
  red-900-p3: "oklch(54.99% 0.232 25.29)"
  red-1000-p3: "oklch(24.8% 0.1041 18.86)"
  amber-100-p3: "oklch(97.48% 0.0331 85.79)"
  amber-200-p3: "oklch(96.81% 0.0495 90.24227879900472)"
  amber-300-p3: "oklch(95.93% 0.0636 90.52)"
  amber-400-p3: "oklch(91.02% 0.1322 88.25)"
  amber-500-p3: "oklch(86.55% 0.1583 79.63)"
  amber-600-p3: "oklch(80.25% 0.1953 73.59)"
  amber-700-p3: "oklch(81.87% 0.1969 76.46)"
  amber-800-p3: "oklch(77.21% 0.1991 64.28)"
  amber-900-p3: "oklch(52.79% 0.1496 54.65)"
  amber-1000-p3: "oklch(30.83% 0.099 45.48)"
  green-100-p3: "oklch(97.59% 0.0289 145.42)"
  green-200-p3: "oklch(96.92% 0.037 147.15)"
  green-300-p3: "oklch(94.6% 0.0674 144.23)"
  green-400-p3: "oklch(91.49% 0.0976 146.24)"
  green-500-p3: "oklch(85.45% 0.1627 146.3)"
  green-600-p3: "oklch(80.25% 0.214 145.18)"
  green-700-p3: "oklch(64.58% 0.1746 147.27)"
  green-800-p3: "oklch(57.81% 0.1507 147.5)"
  green-900-p3: "oklch(51.75% 0.1453 147.65)"
  green-1000-p3: "oklch(29.15% 0.1197 147.38)"
  teal-100-p3: "oklch(97.72% 0.0359 186.7)"
  teal-200-p3: "oklch(97.06% 0.0347 180.66)"
  teal-300-p3: "oklch(94.92% 0.0478 182.07)"
  teal-400-p3: "oklch(92.76% 0.0718 183.78)"
  teal-500-p3: "oklch(86.88% 0.1344 182.42)"
  teal-600-p3: "oklch(81.5% 0.161 178.96)"
  teal-700-p3: "oklch(64.92% 0.1572 181.95)"
  teal-800-p3: "oklch(57.53% 0.1392 181.66)"
  teal-900-p3: "oklch(52.08% 0.1251 182.93)"
  teal-1000-p3: "oklch(32.11% 0.0788 179.82)"
  purple-100-p3: "oklch(96.65% 0.0244 312.1890119359961)"
  purple-200-p3: "oklch(96.73% 0.0228 309.8)"
  purple-300-p3: "oklch(94.85% 0.0364 310.15)"
  purple-400-p3: "oklch(91.77% 0.0614 312.82)"
  purple-500-p3: "oklch(81.26% 0.1409 310.8)"
  purple-600-p3: "oklch(72.07% 0.2083 308.19)"
  purple-700-p3: "oklch(55.5% 0.3008 306.12)"
  purple-800-p3: "oklch(48.58% 0.2638 305.73)"
  purple-900-p3: "oklch(47.18% 0.2579 304)"
  purple-1000-p3: "oklch(23.96% 0.13 305.66)"
  pink-100-p3: "oklch(95.69% 0.0359 344.6218910697224)"
  pink-200-p3: "oklch(95.71% 0.0321 353.14)"
  pink-300-p3: "oklch(93.83% 0.0451 356.29)"
  pink-400-p3: "oklch(91.12% 0.0573 358.82)"
  pink-500-p3: "oklch(84.28% 0.0915 356.99)"
  pink-600-p3: "oklch(74.33% 0.1547 0.24)"
  pink-700-p3: "oklch(63.52% 0.238 1.01)"
  pink-800-p3: "oklch(59.51% 0.2339 4.21)"
  pink-900-p3: "oklch(53.5% 0.2058 2.84)"
  pink-1000-p3: "oklch(26% 0.0977 359)"
typography:
  heading-72:
    fontFamily: Roboto (system sans-serif)
    fontSize: 72px
    fontWeight: 500
    lineHeight: 80px
    letterSpacing: -0.5px
  heading-64:
    fontFamily: Roboto (system sans-serif)
    fontSize: 64px
    fontWeight: 500
    lineHeight: 72px
    letterSpacing: -0.5px
  heading-56:
    fontFamily: Roboto (system sans-serif)
    fontSize: 56px
    fontWeight: 500
    lineHeight: 64px
    letterSpacing: -0.25px
  heading-48:
    fontFamily: Roboto (system sans-serif)
    fontSize: 48px
    fontWeight: 500
    lineHeight: 56px
    letterSpacing: 0px
  heading-40:
    fontFamily: Roboto (system sans-serif)
    fontSize: 40px
    fontWeight: 500
    lineHeight: 48px
    letterSpacing: 0px
  heading-32:
    fontFamily: Roboto (system sans-serif)
    fontSize: 32px
    fontWeight: 500
    lineHeight: 40px
    letterSpacing: 0px
  heading-24:
    fontFamily: Roboto (system sans-serif)
    fontSize: 24px
    fontWeight: 500
    lineHeight: 32px
    letterSpacing: 0px
  heading-20:
    fontFamily: Roboto (system sans-serif)
    fontSize: 20px
    fontWeight: 500
    lineHeight: 28px
    letterSpacing: 0px
  heading-16:
    fontFamily: Roboto (system sans-serif)
    fontSize: 16px
    fontWeight: 600
    lineHeight: 24px
    letterSpacing: 0.15px
  heading-14:
    fontFamily: Roboto (system sans-serif)
    fontSize: 14px
    fontWeight: 600
    lineHeight: 20px
    letterSpacing: 0.1px
  button-16:
    fontFamily: Roboto (system sans-serif)
    fontSize: 16px
    fontWeight: 600
    lineHeight: 24px
    letterSpacing: 0px
  button-14:
    fontFamily: Roboto (system sans-serif)
    fontSize: 14px
    fontWeight: 600
    lineHeight: 20px
    letterSpacing: 0.1px
  button-12:
    fontFamily: Roboto (system sans-serif)
    fontSize: 12px
    fontWeight: 600
    lineHeight: 16px
    letterSpacing: 0.5px
  label-20:
    fontFamily: Roboto (system sans-serif)
    fontSize: 20px
    fontWeight: 400
    lineHeight: 32px
    letterSpacing: 0px
  label-18:
    fontFamily: Roboto (system sans-serif)
    fontSize: 18px
    fontWeight: 400
    lineHeight: 24px
    letterSpacing: 0px
  label-16:
    fontFamily: Roboto (system sans-serif)
    fontSize: 16px
    fontWeight: 400
    lineHeight: 24px
    letterSpacing: 0.15px
  label-14:
    fontFamily: Roboto (system sans-serif)
    fontSize: 14px
    fontWeight: 400
    lineHeight: 20px
    letterSpacing: 0.25px
  label-13:
    fontFamily: Roboto (system sans-serif)
    fontSize: 13px
    fontWeight: 400
    lineHeight: 18px
    letterSpacing: 0.25px
  label-12:
    fontFamily: Roboto (system sans-serif)
    fontSize: 12px
    fontWeight: 500
    lineHeight: 16px
    letterSpacing: 0.4px
  copy-24:
    fontFamily: Roboto (system sans-serif)
    fontSize: 24px
    fontWeight: 400
    lineHeight: 36px
    letterSpacing: 0px
  copy-20:
    fontFamily: Roboto (system sans-serif)
    fontSize: 20px
    fontWeight: 400
    lineHeight: 32px
    letterSpacing: 0px
  copy-18:
    fontFamily: Roboto (system sans-serif)
    fontSize: 18px
    fontWeight: 400
    lineHeight: 28px
    letterSpacing: 0px
  copy-16:
    fontFamily: Roboto (system sans-serif)
    fontSize: 16px
    fontWeight: 400
    lineHeight: 24px
    letterSpacing: 0.5px
  copy-14:
    fontFamily: Roboto (system sans-serif)
    fontSize: 14px
    fontWeight: 400
    lineHeight: 20px
    letterSpacing: 0.25px
  copy-13:
    fontFamily: Roboto (system sans-serif)
    fontSize: 13px
    fontWeight: 400
    lineHeight: 18px
    letterSpacing: 0.25px
  label-20-mono:
    fontFamily: Geist Mono
    fontSize: 20px
    fontWeight: 400
    lineHeight: 32px
    fontFeature: tnum
  label-14-mono:
    fontFamily: Geist Mono
    fontSize: 14px
    fontWeight: 400
    lineHeight: 20px
    fontFeature: tnum
  label-13-mono:
    fontFamily: Geist Mono
    fontSize: 13px
    fontWeight: 400
    lineHeight: 20px
    fontFeature: tnum
  label-12-mono:
    fontFamily: Geist Mono
    fontSize: 12px
    fontWeight: 400
    lineHeight: 16px
    fontFeature: tnum
  copy-14-mono:
    fontFamily: Geist Mono
    fontSize: 14px
    fontWeight: 400
    lineHeight: 20px
    fontFeature: tnum
  copy-13-mono:
    fontFamily: Geist Mono
    fontSize: 13px
    fontWeight: 400
    lineHeight: 18px
    fontFeature: tnum
spacing:
  1: 4px
  2: 8px
  3: 12px
  4: 16px
  6: 24px
  8: 32px
  10: 40px
  16: 64px
  24: 96px
rounded:
  xs: 4px
  sm: 8px
  md: 16px
  lg: 28px
  full: 9999px
components:
  button-primary:
    backgroundColor: "{colors.brand-primary}"
    textColor: "{colors.brand-on-primary}"
    typography: "{typography.button-14}"
    rounded: "{rounded.full}"
    padding: "0 24px"
    height: 48px
  button-tonal:
    backgroundColor: "{colors.secondary-container}"
    textColor: "{colors.on-secondary-container}"
    typography: "{typography.button-14}"
    rounded: "{rounded.full}"
    padding: "0 16px"
    height: 40px
  button-outlined:
    textColor: "{colors.brand-primary}"
    borderColor: "{colors.gray-500}"
    typography: "{typography.button-14}"
    rounded: "{rounded.full}"
    padding: "0 16px"
    height: 40px
  button-text:
    textColor: "{colors.brand-primary}"
    typography: "{typography.button-14}"
    rounded: "{rounded.full}"
    padding: "0 12px"
    height: 40px
  extended-fab:
    backgroundColor: "{colors.brand-subtle}"
    textColor: "{colors.brand-on-subtle}"
    typography: "{typography.button-14}"
    rounded: "{rounded.md}"
    padding: "0 20px 0 16px"
    height: 56px
  filter-chip:
    selectedBackgroundColor: "{colors.secondary-container}"
    selectedTextColor: "{colors.on-secondary-container}"
    borderColor: "{colors.gray-500}"
    typography: "{typography.button-14}"
    rounded: "{rounded.sm}"
    height: 32px
  card:
    backgroundColor: "{colors.background-200}"
    rounded: "{rounded.lg}"
    padding: 20px
  list-group:
    backgroundColor: "{colors.background-200}"
    outerRadius: 20px
    innerRadius: 4px
    gap: 2px
  navigation-bar:
    backgroundColor: "{colors.gray-100}"
    indicatorColor: "{colors.secondary-container}"
    height: 80px
  input:
    textColor: "{colors.primary}"
    borderColor: "{colors.gray-700}"
    typography: "{typography.label-16}"
    rounded: "{rounded.xs}"
    padding: "0 16px"
    height: 56px
  dialog:
    backgroundColor: "{colors.gray-200}"
    rounded: "{rounded.lg}"
    horizontalInset: "{spacing.10}"
    verticalInset: "{spacing.10}"
---
# Health.md Material 3

## Overview

Health.md on Android follows Material 3 with a fixed, brand-seeded tonal palette. Hierarchy comes from tonal surfaces and shape rather than borders: pages sit on `background-100`, grouped content sits on `background-200` cards with large rounded corners, and the brand purple marks primary actions, selection and focus. The layout mirrors the cross-platform Health.md experience: an **Archive** coverage calendar, **Automations** described as sentences, and **Settings** grouped lists, with **Export now** as a persistent floating action.

This is the Light theme. The Dark theme uses the same token names with different values and lives at `/design.dark.md`. Both themes follow the system appearance. Do not use Material dynamic color or launcher wallpaper colors.

## Signal paywall accessibility

The Signal carousel keeps its footer fixed at standard text sizes in tall windows. At the reading font scale or in a window shorter than the small breakpoint, the carousel and footer share a scrolling column. Each carousel page retains one viewport of reading space and its own scrolling content. Purchase, Restore, and legal links must remain reachable without reducing text size or hiding disclosures.

## Provider connection buttons

Google Drive authorization uses an outlined pill on `background-100`, `gray-1000` text and a `gray-700` outline, with the official full-color Drive product logo preserved without tinting. It retains the 48dp control minimum, existing button typography and spacing, and native pressed/disabled states. Keep the action label explicit (Connect or Reauthorize Google Drive). This neutral provider treatment distinguishes external authorization from Health.md’s purple primary actions in both themes.

## Colors

`background-100` is the page surface and `background-200` the card and list-group surface. The `gray-*` steps are tonal containers and text: `gray-100`–`gray-300` are container fills (navigation bar, chips, inputs), `gray-500` is the outline-variant used for dividers and chip borders, `gray-700` is the outline and the disabled-text token, `gray-900` is secondary text and `gray-1000` primary text. `gray-alpha-*` remain for translucent overlays and scrims. The `brand-*` tonal palette carries primary actions (`brand-primary` on `brand-on-primary`), primary containers such as the Export now button and hero cards (`brand-subtle` on `brand-on-subtle`), and selection. `secondary-container` fills selected chips, segmented buttons, navigation indicators and tonal buttons. `tertiary-container` with `on-tertiary-container` marks offers and cautions that are not errors, such as the paywall's Best value pill and the Export now large-export note. Semantic accents keep their meaning: `green` success, `red` errors, `amber` warnings, plus `blue`, `teal`, `purple` and `pink` for automation identity and charts.

Archive coverage uses dedicated day states: complete days fill with `coverage-complete` and `on-coverage-complete` text; partial days use `gray-300` with a 3px `brand-primary` bottom bar; missing days use a 1.5px dashed `coverage-missing` outline and number; today has a 2px `brand-primary` outline; dates with nothing due render at 38% opacity. The stats card names its gap count in `coverage-missing`, or "No gaps" in `coverage-no-gaps`, on `brand-subtle`. Color never carries meaning alone: every day exposes its status in its accessibility label and the legend names each state.

## Typography

UI copy uses the platform sans-serif (Roboto on Android), which follows the user’s system font and scale. Geist Mono stays bundled for code, paths, identifiers, dates in tables and tabular numbers. Weights are 400 for copy, 500 for headlines and 600 for titles, buttons and emphasized labels. Large numbers in stats use `heading-56` with tabular figures.

## Layout

Spacing follows a 4px scale: 4, 8, 12, 16, 24, 32, 40, 64, 96px. Screens use a 16px side gutter; cards use 20px padding (16px compact). Group settings rows in list groups whose first and last rows take 20px outer corners and inner rows 4px corners with 2px gaps. Breakpoints are `sm` 401px, `md` 601px, `lg` 961px, `xl` 1200px and `2xl` 1400px: below `md` the app uses a bottom navigation bar and an extended Export now button; from `md` up it uses a navigation rail with the Export now button at the top of the rail, the Archive shows the calendar beside the selected day, and single-column screens such as Automations and Settings center at a readable 840px width.

### Android text and display scaling

- Respect the system font and display scale; never shrink text to make controls fit.
- Text-bearing controls use the documented heights as minimums (at least 48 dp touch targets) and grow for wrapped labels.
- Onboarding bodies scroll independently of one persistent primary action. Back and optional Skip live in the header; incomplete permission/folder steps show their actual setup action rather than a disabled Continue button.
- Reading-first onboarding and paywalls apply at font scales of 1.3× or greater, or below the `sm` (401 dp) width/height breakpoint. Use 16 dp page gutters, start-aligned text without forced title line breaks, text-only informational cards with 12 dp padding, and no decorative hero illustrations. Keep all explanatory copy and its scaled type sizes. Normal layouts retain their centered hero presentation.
- Use `gray-900` for readable helper copy and enabled secondary actions; reserve the disabled token for disabled controls.
- Paired actions stack primary-first when available width divided by font scale is below 256 dp (128 dp per action). Compact navigation uses a two-column, text-only tab layout when a row cannot provide 64 dp per tab at the chosen font scale. Labels retain their type tokens and full text in both arrangements.
- Schedule labels sit above their controls. Numeric fields use `label-20-mono`, size for all five supported localized digits, and grow vertically. Value/unit fields stack below the paired-action width threshold; date menus wrap their full labels. Time editors use separated 48 dp minus/plus targets with an 8 dp gap, and a single AM/PM action. Move the period action to its own row when width divided by font scale is below 336 dp; preserve locale ordering and 12/24-hour conventions.
- Settings entry cards use the reading-first presentation when their available width divided by font scale is below 336 dp: omit decorative leading icons and give descriptions the full card width. Configuration-lock rows have one whole-row switch target, with the explanation below rather than squeezed beside the switch. These cards use 16 dp padding.
- Metric selection keeps only compact Back/Search navigation fixed; title, search editor, bulk actions and individually scrollable rows share the list. Separate category expansion from its labeled tri-state checkbox. Each metric has one whole-row checkbox action; crowded names use full width with unit/indicator below.
- Format and frontmatter choices expose one labeled radio/switch action, with non-interactive indicator artwork. Reflow crowded choice groups, put descriptions below controls at full width, and use 16 dp card padding. Input labels wrap outside the editing field; identifiers may scroll horizontally while editing, with a full wrapping reading surface for long values. Separate contextual Add/Delete actions from key/value fields.
- Template editors allocate visible lines from the available height, up to 16 lines and approximately half the viewport; they never require eight visible lines in short or keyboard-open windows. Keep all input, empty-field examples, help and token references; Reset and preview remain scroll-reachable. Back may join an editor's scroll surface rather than consume scarce fixed height.
- Profile rows give names and summaries full width, with distinct Edit Schedule, Delete and labeled enable targets. Profile dialogs use fixed header/footer plus a scrolling body when space permits. Below 401 dp of height divided by font scale, or when the padded title consumes over one third of the available height, scroll the same dialog composition as a whole so title, fields and Save/Cancel remain reachable. Preserve field focus/state, native window density/direction, safe areas and IME clearance; never shrink the title or font scale to preserve fixed chrome.
- Date presets use growing labeled radio targets, stacking below the paired-action threshold; selection artwork must not take width from their labels. Put custom-date labels above full-width 20 sp monospaced values. Schedule history titles and the 48 dp Clear History button reflow at the detailed-control threshold, with readable secondary text and unchanged protection/confirmation behavior.
- Keep app content inside system-bar and display-cutout insets. Measure navigation chrome rather than reserving a fixed bottom inset, so growing tab labels never cover screen content.

## Elevation & Depth

Surfaces are tonal; avoid borders around cards. Only floating actions are elevated. Apply this `box-shadow` for the light theme:

- Floating action (Export now): `0 1px 3px rgba(0, 0, 0, 0.3), 0 4px 8px 3px rgba(0, 0, 0, 0.15)`

Bottom sheets and dialogs use tonal containers (`gray-200`) over the scrim rather than heavy shadows.

## Motion

Use Material standard easing. State changes take 150ms, popovers 200ms and sheets or overlays 300ms. Respect the system animation scale and never animate content the user is reading.

## Shapes

Corners scale with component size: `rounded.xs` (4px) for text fields, `rounded.sm` (8px) for chips and badges, `rounded.md` (16px) for floating actions and calendar days, `rounded.lg` (28px) for cards, sheets and dialogs, and `rounded.full` for buttons, switches and navigation indicators.

## Components

Subscription surfaces use named dimensions in both themes: `GeistSizes.planArtwork` (56dp) keeps the plan identity artwork distinct from a control; `iconSmall` (18dp) fits an inline button glyph; `iconMedium` (20dp) aligns sheet list glyphs with body text; `progressStroke` (2dp) keeps a compact loading indicator legible. The indicator bounds reuse `GeistSpacing.space4` (16dp), and action gaps reuse `space2` (8dp). Grouped settings rows use `GeistSpacing.listGroupGap` (2dp), the existing narrow separation between adjoining row surfaces. Tonal buttons use Material's default flat elevation.

Primary actions are filled pill buttons (48dp tall when they are the screen’s main action). Secondary actions are tonal or outlined pills; low-emphasis actions are text buttons. Switches show a check in the thumb when on. Filter chips select an automation and show a check when selected. Segmented buttons choose one value from two to five options. Top app bars use `heading-24` titles on top-level screens and `heading-20` on sub-screens. Focus shows a two-layer ring (`box-shadow: 0 0 0 2px #fef7ff, 0 0 0 4px #6a3fe0`). All touch targets are at least 48dp.

## Voice & Content

Write in plain sentences. Describe automations as sentences (“Every morning at 7:30, write yesterday’s metrics to Vault/Health”). Name things the way the user sees them: Archive, Automations, Settings, Export now. Never show health values in previews, notifications or widgets that could be seen on a locked screen.

## Do's and Don'ts

- Do use the named Compose tokens in `presentation/theme`; never introduce ad hoc colors, spacing, type sizes or radii.
- Do pair every status color with text or an icon.
- Do keep one filled primary action per screen; the Export now button is the global one.
- Don’t add borders to cards or tonal containers.
- Don’t use dynamic color, gradients or decorative glows.
- Don’t shrink text to make a layout fit; let rows grow and wrap.

## Wear OS surfaces

Wear OS is a scoped platform adaptation that keeps its own Geist-derived watch tokens. The watch app uses Wear Compose components, rotary scrolling, edge-safe round layouts, and a black primary surface to respect OLED and ambient constraints. Named watch tokens are `WearSpacing` (4/8/12/16/24dp), `WearType` (12/14/16/20sp), `WearShape` (6/12/full), and `WearColors` (the Geist dark surface/text plus Health.md purple, green, amber, and red semantics). The watch app keeps bundled Geist Sans; Tiles and complications may use host/platform typography because those remote renderers do not support bundled fonts. Tile and complication content is glanceable, local-cache-only, never described as real-time, and always pairs color with text. Health values are hidden after 24 hours; values 4–24 hours old include a localized age marker.

The dashboard mirrors the watchOS dashboard composition: one row per metric rendered as an icon chip on the dark surface (`gray-100`, `WearShape.md`), with the metric tint applied to the icon only, the localized label in muted text, and the value emphasized in text-color semibold tabular figures. Per-metric tint tokens reference the existing dark accent scales and never introduce new hex values: steps `green-900`, move energy `amber-900`, exercise `amber-700`, sleep `purple-900`, resting heart rate `red-900`, average heart rate `red-700`, HRV `teal-900`, and blood oxygen `teal-700`. Icons come from the Compose Material icon set because bundled Geist has no icon glyphs; icon tint always pairs with the text label so color never carries meaning alone. Stand hours have no Health Connect equivalent and stay absent from Wear surfaces.

## Android App Widgets

Home-screen widgets use Jetpack Glance and remain part of this design system even though they are rendered through Android `RemoteViews` rather than the app’s Compose tree.

- Use the light and dark values from the named widget color tokens through day/night `ColorProvider` values. Do not adopt launcher wallpaper colors or Material dynamic color.
- Use the existing 4px spacing scale, `rounded.md` outer surfaces, and the semantic accent scales for activity, heart, and sleep charts. Bitmap chart artwork must receive token colors rather than define its own palette.
- Glance cannot reliably load bundled app font resources in a remote host. Widget text may therefore use Android’s platform sans-serif and monospace families as a scoped platform exception; keep the documented widget type sizes, weights, hierarchy, and tabular-number intent.
- Treat compact, wide, medium, and tall-large widget layouts as responsive compositions, not fixed phone breakpoints. Content must tolerate launcher padding, OEM cell geometry, and user resizing without clipping.
- Small widget captions use the named `gray-900` token rather than the lower-contrast disabled token, preserving at least 4.5:1 contrast in light and dark themes.
- Picker previews use synthetic data. Health measurements never appear in preview assets.
- The Archive widget uses the coverage day-state tokens and shows coverage only, never health values.
- Health widgets are home-screen-only while Android lacks an equivalent to WidgetKit sensitive-content redaction. Do not expose measurement-bearing providers to keyguard hosts.
