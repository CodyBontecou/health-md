# Android store screenshot plan

The current audit and copy template replace the old `200027.png`–`200059.png` pairing notes:

- Audit: [`aso-audit-2026-08-04.md`](aso-audit-2026-08-04.md)
- Localized campaign copy: [`../play-store-screenshots/locales/`](../play-store-screenshots/locales/)
- Store assets: [`../play-console/screenshots/`](../play-console/screenshots/)

## Canonical sequence

| Order | Theme | Interface evidence |
| ---: | --- | --- |
| 1 | Export Health Connect data | Export screen with formats, date range and destination |
| 2 | Export in the format you need | Markdown, CSV, JSON, NDJSON, Obsidian Bases and FHIR options |
| 3 | Choose from 100+ metrics | Metric categories and selection controls |
| 4 | Private by design | User-selected destination and preview flow |
| 5 | Automate your health archive | Schedule and export-history screens |
| 6 | Preview every file first | File preview, path and structure |
| 7 | Health widgets at a glance | Activity, sleep, heart and combined widgets |
| 8 | Connect your own tools | Configured endpoint or paired desktop CLI |

Use `100+`, not an exact metric total. Keep one headline and one supporting line per image. Give the app interface most of each frame and avoid repeated logo blocks.

## Current assets

### Phone

`play-console/screenshots/en-US/phone/` contains the reviewed eight-image English campaign at 1080×1920. It follows the canonical sequence above and replaces the older five-image, 941×1672 set. Store graphics remain user-owned work.

Draft locale phone campaigns are generated through the repository's `appstore-ai-images` reference-swap workflow. Each edit supplies `gpt-image-2` with the English master, the matching genuine localized API 35 app capture and the exact localized marketing copy. Completed paid outputs are imported only after manifest and dimension validation by `scripts/finalize-ai-localized-play-screenshots.py`. This workflow does not upload or publish Play assets.

### Seven-inch tablet

`play-console/screenshots/en-US/sevenInch/` contains four genuine 1200×1920 captures from an API 35 Nexus 7 profile:

1. Welcome
2. Export
3. Schedule
4. Settings

### Ten-inch tablet

`play-console/screenshots/en-US/tenInch/` contains four genuine 2560×1600 captures from an API 35 Pixel Tablet profile:

1. Welcome
2. Export
3. Schedule
4. Settings

These are direct large-screen renders of the current app, not resized phone images. They intentionally contain no marketing overlay that could be cropped on tablet placements.

## Validation

Run:

```bash
cd apps/android
./scripts/validate-play-listing.sh
```

The command prepares canonical Fastlane metadata, checks listing limits and screenshot dimensions, and runs `gplay validate` for both reviewed and draft locales. It does not upload anything.
