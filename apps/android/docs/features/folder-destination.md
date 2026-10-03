# Folder Destination

## Status

- **Docs status:** draft
- **Video priority:** high
- **Primary screen:** Export (and Onboarding → Storage)
- **Source files:** `app/src/main/java/com/healthmd/presentation/export/ExportScreen.kt`, `ExportViewModel.kt`, `data/storage/FileExportManager.kt`

## What it does

Health.md writes exports through Android's system folder picker (Storage Access Framework). You choose one folder — on local storage or behind any document provider such as Google Drive, OneDrive, Syncthing, or Obsidian Sync — and Health.md keeps persistent write access to it across restarts. Under the destination selector, the folder target shows "Choose a local or provider-backed folder" before selection and "Write files to <folder>" after, with a **Select**/**Change** action on the Export Folder card.

## Who it is for

- Obsidian users pointing Health.md at a vault folder.
- Anyone exporting to a synced provider folder so files reach another device.
- Not for the API-endpoint destination: if you send exports over HTTP(S) instead, no folder is involved (see `../api-endpoint-export.md`).

## Where to find it

1. Open Health.md → **Export** tab.
2. Tap the **Export Folder** card (it reads "Select a folder" until one is chosen).
3. Pick a folder in the system picker; Health.md immediately persists access and shows the folder's name.

## Prerequisites

- A folder you can grant write access to.
- For provider-backed folders, the provider's app installed and signed in so its folders appear in the picker.

## Setup

1. Tap **Export Folder → Select**.
2. Navigate to your vault or destination folder in the picker.
3. Confirm — the card switches to the folder name with a **Change** action.

## Example output

```text
My Vault/
├── 2026-05-11.md
├── 2026-05-12.md
└── 2026-05-12.json
```

## Tips

- An Obsidian vault works best when you select the vault root and use the subfolder/filename placeholders under the export configuration (see ./manual-export.md).
- If a provider does not expose writable folders or drops write permission, export to a local folder and let your sync tool move files instead.
- Changing folders later does not move existing files; new exports go to the new destination.
- Export profiles can bind their own folder per profile (see ./export-profiles.md).

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| "Choose a local or provider-backed folder" won't clear | Picker closed without a selection | Reopen the picker and confirm a folder |
| Exports fail with a file-write error | Provider revoked write access or is unreachable | Re-select the folder; check the provider app and connectivity |
| Provider folder missing from picker | Provider not installed or doesn't expose documents | Install/sign in to the provider app, or use a local folder + your own sync |
| Folder card shows a generic label | Provider didn't report a display name | Cosmetic only; exports still write correctly |

## Video outline

- **Suggested title:** Point Health.md at Your Obsidian Vault (or Any Folder)
- **Hook:** "One folder. Every export lands there."
- **Demo flow:**
  1. Export tab → Export Folder → Select.
  2. Pick an Obsidian vault folder in the picker.
  3. Export a day and open the file in Obsidian.
- **Key screenshot/recording moments:** system picker, folder name on the card, file opening in Obsidian.
- **CTA / next video:** ./manual-export.md.

## Implementation notes

Selection uses `ActivityResultContracts.OpenDocumentTree()`; `ExportViewModel.onFolderSelected` takes a persistable read/write URI permission via `FileExportManager.takePersistablePermission` and stores the URI in settings. The display name resolves through `DocumentsContract` (`getFolderDisplayName`), falling back to a generic label. The same SAF flow backs onboarding's Storage page and per-profile destination bindings. Onboarding also persists the URI immediately on selection. Deliberate difference from Apple: Android has no iCloud Drive/Files bookmarker concept; SAF persistable permissions are the storage authority, and a provider that refuses them cannot be written to directly.
