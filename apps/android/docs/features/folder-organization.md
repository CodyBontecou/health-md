# Folder organization

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export
- **Source files:** `domain/model/ExportSettings.kt`, `presentation/export/ExportConfigurationSection.kt`

## What it does

Sorts exports into date-based subfolders under your destination — pick a preset (flat, by year, by month, by year/month) or write a custom folder template with the same placeholders as [filename templates](./filename-templates.md), like `{year}/{quarter}`.

## Who it is for

- Long-term exporters who don't want hundreds of files in one folder.
- Obsidian users mirroring an existing vault structure.

## Where to find it

1. Open the **Export** tab.
2. In the **Folder Organization** section, choose a preset or enter a **Custom folder template**.

## Prerequisites

- A folder selected through the Android folder picker (your destination).
- Nothing else — subfolders are created automatically.

## Setup

1. Choose a preset:
   - **Flat** — everything directly in the destination folder
   - **By Year** — `2026/`
   - **By Month** — `05/`
   - **By Year/Month** — `2026/05/`
2. Or type a custom template using placeholders like `{year}/{quarter}`.
3. Preview an export to see the resolved path before writing.

## Example output

Custom template `{year}/{quarter}` with the default `health` subfolder, exporting May 12, 2026:

```text
MyVault/
└── health/
    └── 2026/
        └── Q2/
            ├── 2026-05-12.md
            └── 2026-05-12.json
```

## Tips

- A custom template overrides the preset — clearing the template field returns you to the selected preset.
- Your destination subfolder (default `health`) always comes first; the date structure nests inside it.
- All placeholder rules from [filename templates](./filename-templates.md) apply, including locale-aware `{weekday}` and `{monthName}`.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Everything lands flat | Organization set to **Flat**, or custom template is blank | Pick a preset or fill the custom template |
| Subfolders not created | Document provider doesn't support nested folder creation | Use a local folder or a provider that supports subfolders |
| Custom template ignored | A preset is also selected and the template field is blank | The custom template must be non-empty to take effect |

## Video outline

- **Suggested title:** Keep Years of Health Exports Tidy
- **Hook:** "Three hundred days of exports. One clean folder tree."
- **Demo flow:**
  1. Show a flat export folder getting crowded.
  2. Switch to **By Year/Month** and re-export.
  3. Show `{year}/{quarter}` custom nesting in a file manager.
- **Key screenshot/recording moments:** folder tree before/after, custom template field.
- **CTA / next video:** [Write modes](./write-modes.md).

## Implementation notes

`ExportSettings.formatFolderPath` resolves `folderStructure` when non-empty, else the `FolderOrganization` preset mapping (`FLAT` → none, `BY_YEAR` → `{year}`, `BY_MONTH` → `{month}`, `BY_YEAR_MONTH` → `{year}/{month}`); an empty resolution exports flat. `aggregateSubfolderPath` joins the user subfolder (default `health`) with the resolved date path. Folder creation happens through the Storage Access Framework — provider support for nested document creation determines what works on Drive/OneDrive-style providers.
