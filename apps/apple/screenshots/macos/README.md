# macOS App Store screenshots

This directory contains the reproducible source for the light-mode Mac App Store screenshot set. The current macOS app is a destination/agent: iPhone owns export formats, metrics, date ranges, filenames, and schedules; Mac receives those jobs, validates the destination, writes files, and reports recent activity. The screenshots intentionally use that shipped behavior instead of the obsolete, unreachable Mac Export, Schedule, Preview, and History views that remain in source.

## One-command locale generation

From `apps/apple`:

```bash
./scripts/generate-macos-app-store-screenshots.sh en-US
```

Replace `en-US` with any supported locale identifier: `de-DE`, `es-ES`, `fr-FR`, `it`, `ja`, `ko`, `nl-NL`, `pt-BR`, or `zh-Hans`.

The command builds an isolated DEBUG app, captures five real light-mode windows, composes the 2880 × 1800 sRGB marketing images, writes the HTML review page, and runs `asc screenshots validate`. It never uploads screenshots.

Observed working toolchain:

- macOS with a Retina display
- Xcode 26.6 (build 17F113)
- Apple Swift 6.3.3
- `asc` 3.7.0

The source uses only Xcode/macOS frameworks and shell tools already shipped with macOS. No third-party image package is required.

## Source layout

```text
screenshots/macos/
  README.md
  copy.json                 locale-keyed marketing copy and explicit order
  captures/<locale>/        native 2200 × 1464 localized app-window captures
  review/index.html         combined deterministic/ImageGen comparison
  review/en-US/index.html   full-size and ~20% visual review
  review/en-US/asc-validation.json
  review/<locale>/index.html
  review/es-ES/comparison.html
  review/<locale>/imagegen/ raw and normalized ImageGen review candidates
scripts/
  capture-macos-app-store-screenshots.sh
  compose-macos-app-store-screenshots.swift
  generate-macos-app-store-screenshots.sh
fastlane/screenshots-macos/en-US/
  01_sync_with_iphone.png
  02_export_health_data.png
  03_automate_every_export.png
  04_preview_before_export.png
  05_configure_your_app.png
fastlane/screenshots-macos/<locale>/
  01_sync_with_iphone.png
  ...
  05_configure_your_app.png
```

## Capture

`capture-macos-app-store-screenshots.sh` builds the `HealthMd-macOS` Debug configuration under the dedicated bundle identifier `com.codybontecou.obsidianhealth.screenshot`. This prevents capture from closing, reading preferences from, or changing an already-running development or production copy of Health.md.

`MacMarketingCapture` and its fixture hooks compile only under `DEBUG && os(macOS)`. They:

- force Aqua/light appearance;
- use the neutral peer name `Demo iPhone`;
- display `~/Health.md Demo/Exports` while writing only to an isolated temporary folder;
- use fixed export-event IDs, dates, counts, and byte estimates;
- use fixed storage capacity rather than the developer Mac's live free-space value;
- disable real browsing and persisted activity-history writes;
- select and scroll the current Home or Settings surface for each story;
- capture the real app window at Retina scale.

No debug fixture path is compiled into Release builds. Raw captures stay unscaled under `captures/<locale>/`.

Capture without composition:

```bash
./scripts/capture-macos-app-store-screenshots.sh en-US
```

## Composition

`copy.json` keeps locale copy separate from raw captures and fixes upload order explicitly. The Swift compositor uses SF system typography, a warm-white/lavender canvas, a single safe-area grid, one chip style, and one window treatment. It writes directly into an sRGB Core Graphics context.

The compositor rejects unsupported locales, missing locale copy, missing captures, captures with the wrong native dimensions, missing or duplicated screen order, more than three chips, text that cannot fit within two lines at the minimum type size, and outputs that are not 2880 × 1800. Headline and supporting-copy containers wrap without depending on Latin word boundaries and reserve a two-line layout for longer future translations.

Recompose from existing captures:

```bash
MAC_SCREENSHOT_SKIP_CAPTURE=1 \
  ./scripts/generate-macos-app-store-screenshots.sh en-US
```

The supported locale identifiers are `en-US`, `de-DE`, `es-ES`, `fr-FR`, `it`, `ja`, `ko`, `nl-NL`, `pt-BR`, and `zh-Hans`. Copy, native captures, deterministic compositions, and validation records exist for all ten locales.

## Review and validation

Open `review/index.html` to switch among all localized sets and compare the English reference, deterministic localized composition, and ImageGen candidate side by side. Each locale also has `review/<locale>/index.html`, where every deterministic screen appears as a scrollable 2880-pixel source and at approximately 20% App Store thumbnail size. Review at 100%, 50%, and thumbnail scale for clipping, contrast, stale claims, personal data, and app/copy agreement.

For every non-English locale, ImageGen receives the English final as its layout reference, the real localized app capture as the UI input, and verbatim localized copy from `copy.json`. Raw outputs, normalized 2880 × 1800 candidates, prompt notes, and validation are under `review/<locale>/imagegen/`. The deterministic compositor output remains the pixel-faithful alternative and is never overwritten by ImageGen.

The generation command records local App Store validation in `review/en-US/asc-validation.json`. The equivalent manual commands are:

```bash
asc screenshots validate \
  --path fastlane/screenshots-macos/en-US \
  --device-type DESKTOP \
  --output json

git diff --check
```

## English narrative changes

The exact rationale is stored with each screen in `copy.json` and shown in the review page.

- Sync keeps the approved privacy-specific copy and shows a connected, ready Mac destination.
- Export is reframed as saving iPhone-created exports to the chosen Mac folder; Mac no longer owns format or date-range configuration.
- Schedule is reframed as receiver readiness; schedules are configured and run on iPhone.
- Preview uses the requested fallback, `Track Every Export`, and shows the current Activity Feed. The filename stays `04_preview_before_export.png` to satisfy the requested ordered deliverable.
- Configure shows current General settings and accurately identifies iPhone-controlled export shape.

Compared with the old dark set, the new system improves thumbnail hierarchy, contrast, whitespace, UI scale, privacy wording, path anonymization, and future localization capacity. It also removes stale metric counts and unsupported Mac-side configuration claims.
