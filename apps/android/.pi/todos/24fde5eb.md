{
  "id": "24fde5eb",
  "title": "P0: Build Android Export Preview",
  "tags": [
    "android",
    "parity",
    "p0",
    "preview",
    "exports"
  ],
  "status": "closed",
  "created_at": "2026-06-05T14:38:20.431Z"
}

Implemented.

## What changed
- Added `ExportPreview` domain models and `ExportRepository.previewHealthData`.
- Added `ExportOrchestrator.previewDates` dry-run path bounded to 14 preview days.
- Export screen now has a Preview action when permissions, folder, and formats are valid.
- Preview dialog shows date coverage, total files/bytes, file paths, format, sizes, content snippets, no-data/warning states, and Daily Note/Individual Entry side effects.
- Preview performs no writes, records no history, and does not consume quota.

## Validation
- `./gradlew testDebugUnitTest` passes.
