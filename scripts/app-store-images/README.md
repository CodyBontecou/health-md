# App Store image draft generator

This is a small, repo-aware first draft for generating App Store marketing images for the app in the current repository.

It inspects the repo for an app name, product copy, brand colors, typography hints, feature names and existing screenshots. The generic draft campaign sends only abstract-background prompts to OpenAI and composites app UI locally. The explicit Health.md localized reference-swap workflows described below instead send the English master, localized app capture and copy reference to `gpt-image-2` for masked image editing. If no screenshots are found, generic outputs are marked draft-only with placeholders.

## Setup

Install the tool dependencies from the repo root:

```bash
npm --prefix scripts/app-store-images install
```

Store your OpenAI API key in macOS Keychain once:

```bash
npm --prefix scripts/app-store-images run store-key
```

You can also export it in your shell instead:

```bash
OPENAI_API_KEY=your_key_here
```

The key is required only when `--generate` is passed. Dry runs never call the AI API. Do not commit real keys to `.env`, `.env.example`, or source files.

## Dry run

Dry-run is the default and writes only a plan/manifest:

```bash
npm --prefix scripts/app-store-images run plan
# or
npm --prefix scripts/app-store-images exec -- tsx scripts/app-store-images/generate.ts --dry-run
```

This prints the planned image count, model, quality, target size, screenshot sources, and prompts, then writes:

```text
app-store-output/manifest.json
```

## Generate images

Generation requires either a stored Keychain key or `OPENAI_API_KEY`, plus an explicit `--generate` flag:

```bash
npm --prefix scripts/app-store-images run generate
# equivalent:
npm --prefix scripts/app-store-images exec -- tsx scripts/app-store-images/generate.ts --generate --max-images 3
```

Outputs are written to:

```text
app-store-output/backgrounds/
app-store-output/final/
app-store-output/manifest.json
```

`app-store-output/` is ignored by git and should be reviewed manually before any App Store submission.

## Localized reference-swap workflow

The preferred Health.md localization workflow uses an OpenAI masked image edit. It sends the English App Store master, the corresponding localized simulator capture, and a rendered localized-copy reference to OpenAI. Local post-processing restores every unmasked English-master pixel and places the real localized simulator UI into the existing device frame.

Each locale needs nine 1320×2868 simulator captures under `app-store-output/simulator-captures/<locale>/`, named `01-export-top.png` through `09-mac-destination.png`. Marketing copy lives in `app-store-input/localizations/marketing-<locale>.json`; locale-to-capture mappings live in `app-store-input/localizations/marketing-locales.json`.

Capture one or more app-language folders, then map them into canonical App Store locale folders:

```bash
cd apps/apple
./scripts/capture-marketing.sh de fr it ja ko nl pt-BR zh-Hans
cd ../..
npm --prefix scripts/app-store-images run prepare:localized-captures -- --locale de-DE --capture-locale de
```

Dry-run one slide or a complete locale before making paid calls:

```bash
npm --prefix scripts/app-store-images run edit:localized-slide -- --locale de-DE --slide 2
npm --prefix scripts/app-store-images run plan:localized-set -- --locale de-DE
```

Generate one slide or a complete nine-slide locale explicitly:

```bash
npm --prefix scripts/app-store-images run edit:localized-slide -- --locale de-DE --slide 2 --generate
npm --prefix scripts/app-store-images run generate:localized-set -- --locale de-DE
```

`--slide` accepts `1` through `9`. Outputs are written under `app-store-output/ai-edits/<locale>-slide-<n>-reference-swap/`; accepted review copies belong under `app-store-output/localized-tests/<locale>/`. The `edit:es-slide` alias remains available for Spanish.

This workflow makes one paid image-edit request per generated slide and never uploads assets to App Store Connect.

### Android Google Play localized reference swaps

The Android campaign uses the same OpenAI reference-swap approach with eight 1080×1920 English masters and genuine 1080×2340 localized API 35 captures. Each paid edit sends the English master, localized Android capture and rendered localized-copy reference to `gpt-image-2`. The resulting image is kept as a seamless AI-regenerated image; no screenshot or typography layer is pasted over it afterwards.

Dry-run or generate a locale:

```bash
npm --prefix scripts/app-store-images run plan:android-localized-set -- --locale de-DE
npm --prefix scripts/app-store-images run generate:android-localized-set -- --locale de-DE
```

The eight-edit locale set costs approximately $0.32 at medium quality before manual retries. Outputs and per-slide manifests are written beneath `app-store-output/android-ai-edits/<locale>/`. Validate and import completed paid sets into the authored Play tree with:

```bash
cd apps/android
./scripts/finalize-ai-localized-play-screenshots.py --locales de-DE
```

The capture, generation and finalization commands do not upload or publish anything to Google Play.

If the image API is unavailable or reaches its billing limit, a reviewed paid locale can be reused as the masked artwork donor. The fallback removes only the donor copy, draws exact localized typography, and still composites the target locale’s real simulator UI locally:

```bash
npm --prefix scripts/app-store-images run build:localized-slide:local -- --locale ja --slide 4 --donor-locale de-DE
```

The fallback refuses to overwrite an existing final image unless `--force` is passed and records `local-deterministic-billing-limit-fallback` in the slide manifest.

## Spanish simulator AI background experiments

The alternative Health.md campaign generates three entirely new OpenAI backgrounds, then composites fresh Spanish iPhone Simulator captures locally. In this mode, simulator screenshots are never sent to OpenAI.

Expected 1320×2868 simulator captures:

```text
app-store-output/simulator-captures/es-ES/01-export-top.png
app-store-output/simulator-captures/es-ES/02-export-formats.png
app-store-output/simulator-captures/es-ES/03-daily-note-injection.png
```

Inspect the plan without making paid calls, then generate:

```bash
npm --prefix scripts/app-store-images run generate:es-simulator:plan
npm --prefix scripts/app-store-images run generate:es-simulator
```

Campaign copy, visual prompts, screenshot order, and brand settings live in:

```text
app-store-input/campaigns/es-ES-simulator-ai.json
app-store-input/brand.es-ES-ai.json
```

AI backgrounds and experimental composites are written under `app-store-output/ai-regenerated/es-ES/`. This campaign uses `gpt-image-2`, medium quality, one background per screen, and a hard three-image cap. It never uploads assets to App Store Connect.

The older `localize:es-test` command remains available only as a no-cost local overlay experiment; it is not the canonical review set.

## Screenshots

Put real app screenshots here:

```text
app-store-input/screenshots/
```

PNG, JPG, JPEG, and WEBP files are supported. The tool also looks in common repo folders such as `screenshots/`, `Screenshots/`, `fastlane/screenshots/`, `metadata/`, `docs/`, `app-store/`, and `marketing/`.

If no screenshots exist, the generated final images use a neutral frame that says “Add app screenshot here” and the manifest sets `draftOnly: true`.

## Brand overrides

Copy the example file and adjust it if detection is not good enough:

```bash
cp app-store-input/brand.example.json app-store-input/brand.json
```

Shape:

```json
{
  "appName": "App Name",
  "primaryColor": "#000000",
  "secondaryColor": "#ffffff",
  "accentColor": "#4F46E5",
  "fontFamily": "system",
  "category": "productivity",
  "tone": "premium, calm, modern"
}
```

## Cost controls

The tool is conservative by default:

- dry-run mode is default
- no AI call happens unless `--generate` is passed
- `--max-images` defaults to `3`
- an absolute first-draft cap rejects more than `6` images
- `--max-variants-per-screen` defaults to `1`
- an absolute first-draft cap rejects more than `2` variants per screen
- `--quality` defaults to `medium`
- `--model` defaults to `gpt-image-2`
- generic background generation retries each image at most once
- reference-swap retries are manual and require `--force`
- existing output PNGs are not overwritten unless `--force` is passed

Useful flags:

```bash
--target-size 1320x2868   # default; also supports 1290x2796 and 1260x2736
--input-screenshots app-store-input/screenshots
--output-dir app-store-output
--brand-file app-store-input/brand.json
--seed 123                # passed through if the model supports it
--force                   # overwrite previous PNG outputs
```

## What repo inspection looks for

The detector is intentionally generic and conservative. It checks common sources such as:

- iOS `Info.plist`, XcodeGen `project.yml`, Xcode project files, `package.json`, and README titles for the app name
- CSS/theme/token files, Swift design files, Tailwind config, and marketing HTML for colors and typography hints
- README/docs/website copy, HTML article cards, headings, and localization-like strings for feature ideas
- common screenshot/marketing folders for real UI screenshots

## Notes

This is a practical draft pipeline, not a production App Store submission system. Review copy, screenshots, generated backgrounds, and device framing before submitting anything to App Store Connect.
