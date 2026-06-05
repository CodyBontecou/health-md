{
  "id": "a227eaef",
  "title": "P1: Complete frontmatter customization UI parity",
  "tags": [
    "android",
    "parity",
    "p1",
    "settings",
    "frontmatter"
  ],
  "status": "closed",
  "created_at": "2026-06-05T14:39:14.469Z"
}

## Goal
Expose Android frontmatter customization options that already exist in the model and match iOS UI.

## Current gap
`FrontmatterConfiguration` supports custom fields, placeholder fields, include date/type, custom keys/values, per-field enable/rename, and key style, but Android UI mainly exposes date/time/unit and markdown template settings.

## Key files
- `app/src/main/java/com/healthmd/domain/model/FrontmatterConfig.kt`
- `app/src/main/java/com/healthmd/presentation/settings/FormatCustomizationScreen.kt`
- `app/src/main/java/com/healthmd/presentation/settings/SettingsViewModel.kt`
- iOS reference: `FormatCustomizationView.swift` / `FrontmatterCustomizationView`

## Acceptance criteria
- Add Frontmatter Fields screen reachable from Format Customization.
- Users can choose snake_case/camelCase, include/exclude date/type, edit date/type keys/values.
- Users can enable/disable and rename metric fields.
- Users can add/delete static custom fields and placeholder fields.
- Search/filter fields by key or metric name.
- Changes persist and affect Markdown frontmatter, Obsidian Bases, and Daily Note Injection.

Implemented frontmatter customization UI parity:
- Added `FrontmatterCustomizationScreen` reachable from Format Customization.
- Supports snake/camel key style, date/type toggles and keys/values, metric field enable/rename with search, static custom fields, and placeholder fields.
- Updates persist through `FormatCustomization.frontmatterConfig`, affecting Markdown frontmatter, Obsidian Bases, and Daily Note Injection.

Validation: `./gradlew testDebugUnitTest` passes.
