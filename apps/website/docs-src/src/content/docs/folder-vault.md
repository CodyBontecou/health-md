---
title: "Folder & Vault"
description: "Pick where your Markdown files live and name the subfolder where exports get written. The vault is just any iOS folder — Obsidian, Files, iCloud Drive, or third-party file providers all work."
---

## What "vault" means here
<p>The app uses <em>vault</em> as a generic name for the folder you've picked, regardless of whether you actually use Obsidian. If you do use Obsidian, point it at your Obsidian vault root. Otherwise, pick any folder — iCloud Drive's <code>Documents/Health</code>, an On My iPhone folder, etc.</p>

## How the picker works
<p>Tapping the vault row opens iOS's standard document picker (<code>UIDocumentPickerViewController</code>). When you pick a folder, iOS returns a <em>security-scoped URL</em> — a long-lived handle that lets the app keep accessing the folder across launches without re-prompting. The app stores this as a bookmark in <code>UserDefaults</code>.</p>

## Subfolder name
<p>After picking the vault, you're prompted to name the subfolder where exports go. The default is <code>Health</code>. Whatever you choose becomes the prefix for every exported file's path:</p>

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
<div class="option"><strong>On My iPhone</strong><p>Pick a folder you've created in Files → On My iPhone. Local-only, no sync.</p></div>
<div class="option"><strong>Third-party providers</strong><p>Dropbox, Google Drive, Working Copy, etc. — anything that exposes a Files-app provider works the same way.</p></div>
</div>

<div class="callout">
<strong>iOS quirk.</strong>
<p style="margin-top:6px;">If iOS revokes the security-scoped bookmark (rare — usually only if the underlying folder is deleted or moved), exports will start to fail. The fix is to re-pick the vault from <em>Settings</em>.</p>
</div>

## Related

<div class="related">
  <a href="/docs/onboarding/"><span>Previous</span>Onboarding — where you first pick the vault.</a>
  <a href="/docs/export/"><span>Next</span>Run an export into your new vault.</a>
  <a href="/docs/format/"><span>Customize</span>Format Customization — how the files inside the subfolder are written.</a>
</div>
