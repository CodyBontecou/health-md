---
title: "Folder & Vault"
description: "Select an iOS folder for your Markdown files. Use Obsidian, Files, iCloud Drive, or another file provider."
---

## What "vault" means here
<p>The app uses <em>vault</em> as a generic name for your selected folder, even if you do not use Obsidian. If you use Obsidian, select your Obsidian vault root. Otherwise, select any folder, such as iCloud Drive's <code>Documents/Health</code> or an On My iPhone folder.</p>

## How the picker works
<p>Tapping the vault row opens iOS's standard document picker (<code>UIDocumentPickerViewController</code>). When you pick a folder, iOS returns a <em>security-scoped URL</em>, a long-lived handle that lets the app keep accessing the folder across launches without re-prompting. The app stores this as a bookmark in <code>UserDefaults</code>.</p>

## Subfolder name
<p>After picking the vault, you are prompted to name the subfolder where exports go. The default is <code>Health</code>. Whatever you choose becomes the prefix for every exported file's path:</p>

<div class="doc-diagram folder-tree" aria-label="Example Health.md export folder tree">
<span>{vault}/</span>
<span>└─ <span class="accent">{subfolder}/</span> <span class="dim">← what you name in Health.md</span></span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-28-tuesday.md</span>
<span>&nbsp;&nbsp;&nbsp;├─ 2026-04-27-monday.json</span>
<span>&nbsp;&nbsp;&nbsp;└─ _healthmd_data_dictionary.json</span>
</div>

<p>You can change the subfolder later from <em>Settings → Obsidian Vault</em>. Existing files are not moved.</p>

## Cross-app behavior
<div class="options">
<div class="option"><strong>Obsidian</strong><p>Pick the Obsidian vault root. Set the subfolder to e.g. <code>Health</code> so exports show up as a folder in your vault tree.</p></div>
<div class="option"><strong>iCloud Drive</strong><p>Pick a folder under iCloud Drive. Files sync to all your Apple devices automatically.</p></div>
<div class="option"><strong>On My iPhone</strong><p>Select a folder that you created in Files → On My iPhone. This folder is local and does not sync.</p></div>
<div class="option"><strong>Third-party providers</strong><p>Dropbox, Google Drive, Working Copy, etc., anything that exposes a Files-app provider works the same way.</p></div>
</div>

<div class="callout">
<strong>iOS quirk.</strong>
<p style="margin-top:6px;">If iOS revokes the security-scoped bookmark (rare, usually only if the underlying folder is deleted or moved), exports will start to fail. The fix is to re-pick the vault from <em>Settings</em>.</p>
</div>

## Replacing or moving a selected folder safely

When a saved bookmark resolves at a changed path, Health.md rebinds automatically if persistent identity proves it is the same folder. It can also accept a successfully resolved security-scoped bookmark when neither the saved nor resolved folder exposes persistent identity, which is common for cloud providers. It never treats a nearby path alone as proof. Export history still shows the privacy-safe destination label used by each run.

Select the folder again if it was deleted or access was revoked. Also select it again if persistent identities conflict or Health.md cannot verify a move. Health.md fails closed instead of writing to an ambiguous destination. Each [export profile](/docs/export-profiles/) owns its destination. Verify or select the affected folder again for each profile.

## Related

<div class="related">
  <a href="/docs/export-profiles/"><span>Multiple destinations</span>Export Profiles, bind and verify a separate folder for each saved setup.</a>
  <a href="/docs/onboarding/"><span>Previous</span>Onboarding, where you first pick the vault.</a>
  <a href="/docs/export/"><span>Next</span>Run an export into your new vault.</a>
  <a href="/docs/format/"><span>Customize</span>Format Customization, how the files inside the subfolder are written.</a>
</div>
