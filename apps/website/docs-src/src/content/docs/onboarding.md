---
title: "Onboarding"
description: "A 5-step welcome flow that runs the first time you open the app. Connects HealthKit, picks a vault folder, names the export subfolder, unlocks the app, and confirms you're ready to export."
---

## What it does
<p>Onboarding only appears on first launch. It guides you through everything you need to do <em>once</em> so the rest of the app just works:</p>

<div class="options">
<div class="option"><strong>1. Welcome</strong><p>What the app does, in one screen — Markdown export, scheduled background runs, and local-first destinations you choose.</p></div>
<div class="option"><strong>2. Health Access</strong><p>Triggers iOS's HealthKit permission sheet. Tip: choose <em>Turn On All</em> for the simplest setup. You can adjust later in iOS Settings → Privacy &amp; Security → Health → health.md.</p></div>
<div class="option"><strong>3. Pick Your Vault</strong><p>Opens the iOS document picker. Choose a folder anywhere — iCloud Drive, On My iPhone, an Obsidian vault, or any third-party file provider.</p></div>
<div class="option"><strong>4. Unlock</strong><p>One-time Full Access purchase for unlimited exports. Apple shows the live local price before purchase, and you can come back to this step later from the Paywall.</p></div>
<div class="option"><strong>5. Ready</strong><p>Confirms permissions, vault, and unlock state are all set. <em>Get Started</em> dismisses onboarding for good.</p></div>
</div>

<div class="callout">
<strong>Skip-friendly.</strong>
<p style="margin-top:6px;">The Health Access step is intentionally not gated — denying iOS's permission sheet would otherwise trap you (iOS only shows it once per install). You can grant it later via Settings.</p>
</div>

## Why these steps, in this order
<p>HealthKit access has to be granted before the export engine can read anything. The vault picker is iOS's UIDocumentPickerViewController — it produces a security-scoped bookmark that the app stores and reuses. Picking the vault before the first export means we never have to interrupt an export run with a folder picker.</p>

## Re-running onboarding
<p>There is no in-app reset. To redo the flow, delete and reinstall the app — your purchase will restore via <em>Restore Purchase</em> on the paywall.</p>

## Related

<div class="related">
  <a href="/docs/folder-vault/"><span>Next</span>Folder & Vault — what the picker actually does.</a>
  <a href="/docs/export/"><span>Next</span>Run your first export.</a>
  <a href="/docs/paywall/"><span>Account</span>Unlock & Paywall details.</a>
</div>
