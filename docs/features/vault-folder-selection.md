# Vault Folder Selection

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Onboarding → Choose Export Folder; Export → Vault badge; Export → Output
- **Source files:** `HealthMd/iOS/Views/OnboardingView.swift`, `HealthMd/iOS/Views/ExportTabView.swift`, `HealthMd/Shared/Managers/VaultManager.swift`, `HealthMd/Shared/Models/AdvancedExportSettings.swift`

## What it does

Vault Folder Selection tells Health.md where to write exported health files. The folder can be an Obsidian vault, an iCloud Drive folder, or a local folder in Files. Health.md stores secure folder access so future manual, scheduled, and Shortcut exports can write to the same location.

By default, exports go inside a `Health` subfolder within the selected folder.

## Who it is for

- Obsidian users who want health files in a vault.
- Users who want local or iCloud Drive exports they can inspect in Files.
- Users organizing exports with custom subfolders, folder templates, or filename templates.

## Where to find it

During first launch:

1. Open Health.md.
2. Continue to **Choose Export Folder**.
3. Tap **Select Folder**.

After setup:

1. Open Health.md.
2. Go to **Export**.
3. Tap the **Vault** status badge to choose a folder.
4. Use **Output** settings to edit the subfolder, folder organization, and filename format.

## Prerequisites

- A destination folder available in the iOS Files picker.
- For Obsidian workflows, an Obsidian vault stored somewhere Files can access.
- HealthKit permission and export formats configured before you expect useful files.

## Setup

1. Tap **Select Folder** or the **Vault** badge.
2. Choose your Obsidian vault or another folder.
3. Confirm the Vault badge shows the folder name.
4. In **Export → Output**, edit **Subfolder** if you do not want the default `Health` folder.
5. Optionally set **Folder Organization** with placeholders like `{year}` or `{month}`.
6. Optionally set **Filename Format**, such as `{date}` or `{year}-{month}-{day}-{weekday}`.
7. Check **Export Path Preview** before exporting.

## Path behavior

Health.md builds export paths as:

```text
<selected folder>/<Health.md subfolder>/<folder organization>/<filename>.<extension>
```

Example settings:

| Setting | Value |
|---|---|
| Selected folder | `MyVault` |
| Subfolder | `Health` |
| Folder Organization | `{year}/{month}` |
| Filename Format | `{date}` |
| Date | `2026-05-12` |
| Format | Markdown |

Result:

```text
MyVault/Health/2026/05/2026-05-12.md
```

If the subfolder is empty and folder organization is empty:

```text
MyVault/2026-05-12.md
```

## Supported placeholders

Filename supports:

- `{date}` → `2026-05-12`
- `{year}` → `2026`
- `{month}` → `05`
- `{day}` → `12`
- `{weekday}` → `Tuesday`
- `{monthName}` → `May`
- `{quarter}` → `Q2`

Folder organization supports the same date placeholders except it is used as a path.

## Tips

- Select the vault root if you want Health.md files to appear in Obsidian.
- Keep the default `Health` subfolder for a clean vault.
- Use `{year}/{month}` for long-running exports so daily files do not all live in one folder.
- Use the path preview before exporting a large date range.
- If Files access breaks, re-select the folder to refresh the secure bookmark.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Export says no vault selected | No folder bookmark is saved | Tap the Vault badge and choose a folder. |
| Cannot access folder | iOS security-scoped access failed or bookmark is stale | Re-select the folder from the Files picker. |
| Files are in the wrong folder | Subfolder or folder organization setting is unexpected | Check **Export → Output** and the path preview. |
| Obsidian does not show files | You selected a folder outside the vault | Select the vault root or move the export folder into the vault. |
| Daily note injection writes somewhere unexpected | Daily Note Injection has its own vault/root-relative folder and filename settings | Check **Export → Daily Note Injection**. `Daily` resolves to `<vault>/Daily/...`, not `<vault>/Health/Daily/...`. |

## Video outline

- **Suggested title:** Choose the Right Obsidian Folder for Health.md
- **Hook:** “The folder you choose controls every manual, scheduled, and Shortcut export.”
- **Demo flow:**
  1. Show folder selection during onboarding.
  2. Pick an Obsidian vault.
  3. Open Export → Output.
  4. Change subfolder and folder organization.
  5. Show the path preview updating.
  6. Export one day and open the file in Obsidian or Files.
- **Key screenshot/recording moments:** Files picker, Vault badge, Output rows, path preview, generated file.
- **CTA / next video:** “Next, we’ll run a manual export.”

## Implementation notes

- `VaultManager.setVaultFolder(_:)` starts security-scoped access, saves bookmark data, and stores `vaultURL`/`vaultName`.
- The selected folder bookmark key is `obsidianVaultBookmark`.
- `healthSubfolder` defaults to `Health` and is persisted separately.
- `VaultManager.exportHealthData(...)` creates directories as needed before writing files.
- `AdvancedExportSettings.formatFolderPath(for:)` and `filename(for:format:)` apply the date placeholders used in path previews and exports.
