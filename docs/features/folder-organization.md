# Folder Organization

## Status

- **Docs status:** draft
- **Video priority:** medium
- **Primary screen:** Export → Folder Structure; selected vault/folder and Health.md subfolder
- **Source files:** `HealthMd/Shared/Models/AdvancedExportSettings.swift`, `HealthMd/Shared/Managers/VaultManager.swift`

## What it does

Folder Organization controls where Health.md writes exported files inside the selected vault or folder. Health.md first uses the selected folder, then the Health.md subfolder, then the optional date-based folder structure.

This keeps large backfills and scheduled exports organized by year, month, week, quarter, or any supported placeholder pattern.

## Who it is for

- Users exporting months or years of health data.
- Obsidian users who want health notes under a dedicated folder.
- Users who want date-based archive folders instead of one flat directory.

## Where to find it

1. Open Health.md.
2. Go to **Export**.
3. Select a vault/folder if needed.
4. Configure the Health.md subfolder and **Folder Structure**.

## Prerequisites

- A selected writable folder or Obsidian vault.
- At least one export format selected.
- Folder names that are valid for iOS Files.

## Setup

1. Select your vault/folder.
2. Set the Health.md subfolder, commonly `Health`.
3. Set **Folder Structure** if you want date-based folders.
4. Use placeholders such as `{year}/{month}`.
5. Export one date and verify the path.
6. Run larger backfills only after the preview/path behavior looks right.

## Supported placeholders

- `{year}` → `2026`
- `{month}` → `05`
- `{day}` → `12`
- `{weekday}` → `Tuesday`
- `{monthName}` → `May`
- `{quarter}` → `Q2`
- `{date}` → `2026-05-12`

## Example paths

Assume:

| Setting | Value |
|---|---|
| Selected vault | `MyVault` |
| Health.md subfolder | `Health` |
| Filename | `{date}` |
| Export date | `2026-05-12` |

| Folder Structure | Output path |
|---|---|
| empty | `MyVault/Health/2026-05-12.md` |
| `{year}` | `MyVault/Health/2026/2026-05-12.md` |
| `{year}/{month}` | `MyVault/Health/2026/05/2026-05-12.md` |
| `{year}/{quarter}` | `MyVault/Health/2026/Q2/2026-05-12.md` |
| `{year}/{monthName}` | `MyVault/Health/2026/May/2026-05-12.md` |

## Tips

- Start flat, then add folders once you know your preferred workflow.
- Use `{year}/{month}` for large archives.
- Use `{year}/{quarter}` for quarterly review workflows.
- Keep Daily Note Injection paths in mind; injection has separate folder settings and resolves from the selected vault/root destination, not from the Health.md subfolder.
- Avoid deeply nested paths if you often browse in the Files app.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Files are under `Health/Health` | Vault folder or subfolder chosen twice | Select the vault root or clear/adjust the Health.md subfolder. |
| Folder placeholder appears literally | Placeholder misspelled or wrong case | Use supported placeholders exactly. |
| Export failed to create folders | Folder access or bookmark issue | Re-select the vault/folder in Health.md. |
| Scheduled exports go to unexpected folders | Scheduled exports reuse current export settings | Check Export tab folder settings before relying on Schedule. |
| Daily notes are in a different place | Daily Note Injection has separate folder/filename settings | Configure Daily Note Injection separately. |

## Video outline

- **Suggested title:** Organize Health.md Exports by Year and Month
- **Hook:** “A year of health exports should not become one messy folder.”
- **Demo flow:**
  1. Show flat export folder.
  2. Set folder structure to `{year}/{month}`.
  3. Export a date range.
  4. Show generated folders in Files or Obsidian.
  5. Explain subfolder vs folder structure vs filename.
- **Key screenshot/recording moments:** folder fields, status path, generated folder tree.
- **CTA / next video:** “Next, we’ll choose how re-exports update existing files.”

## Implementation notes

- `VaultManager` builds paths as `vaultURL / healthSubfolder / formatFolderPath(for:)`.
- `AdvancedExportSettings.defaultFolderStructure` is empty for a flat folder.
- `formatFolderPath(for:)` returns `nil` when the folder structure is empty.
- The same placeholder expansion method powers both filenames and folder paths.
- Directories are created with intermediate directories before files are written.
