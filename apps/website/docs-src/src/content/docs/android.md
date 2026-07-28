---
title: Android App
description: Set up Health.md for Android, export Health Connect data to Markdown, Obsidian Bases, JSON, and CSV, choose Storage Access Framework folders, schedule exports, and automate with Tasker or adb.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Health Connect to private files</p>
  <p>Health.md for Android reads Health Connect on-device and writes Markdown, Obsidian Bases, JSON, or CSV to folders you choose. No Health.md account, no health-data cloud, and no subscription.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Get on Google Play</a>
    <a class="docs-button-secondary" href="/docs/export/">Read Export Docs</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>selectable Health Connect metrics</span></div>
<div><strong>4</strong><span>export formats</span></div>
<div><strong>3</strong><span>free manual export actions</span></div>
<div><strong>0</strong><span>Health.md cloud accounts required</span></div>
</div>

## What the Android app does

Health.md for Android turns Health Connect into a local-first health journal. Choose the metrics you care about, preview the output, then export clean files to a local folder, Obsidian vault, synced provider folder, or any Android document provider that grants write access.

<div class="options">
  <div class="option"><strong>Health Connect source</strong><p>Reads activity, sleep, heart, vitals, body measurements, nutrition, workouts, and other categories through Android's on-device Health Connect APIs.</p></div>
  <div class="option"><strong>Obsidian-native output</strong><p>Writes daily notes, YAML/frontmatter, Obsidian Bases-friendly notes, individual entries, and JSON compatible with the Health.md Obsidian plugin.</p></div>
  <div class="option"><strong>Android-native storage</strong><p>Uses the Storage Access Framework so you can choose folders exposed by local storage, Obsidian, Google Drive, OneDrive, Syncthing, or another provider.</p></div>
</div>

## Requirements

- Android 9 / API 28 or newer.
- A Health Connect-capable device or emulator.
- Health Connect data from Android apps, wearables, or services that write to Health Connect.
- A folder or document provider that allows write access for exports.

## First export

1. Install Health.md from Google Play.
2. Open **Health Connect** setup and grant only the categories you want Health.md to export.
3. Pick the export destination through Android's folder picker.
4. Choose formats: Markdown, Obsidian Bases, JSON, CSV, or any combination.
5. Select metrics and date range.
6. Preview the output.
7. Tap export and verify the generated files in your folder or vault.

The free plan includes 3 manual export actions so you can test permissions, folder access, formats, and your Obsidian workflow before unlocking unlimited exports.

## Destinations on Android

Android does not use the iPhone → Mac local-network destination. Instead, it relies on Android's Storage Access Framework.

| Destination | Android status |
|---|---|
| Local device folder | Supported through the folder picker |
| Obsidian vault | Supported when the vault folder is exposed to Android's picker |
| Google Drive, OneDrive, Syncthing, Obsidian Sync, and similar providers | Supported when the provider exposes writable folders |
| iPhone/Mac local-network destination | Apple-platform-specific; not used by Android |

If a provider does not expose writable folders through Android's picker, Health.md cannot safely write there directly. Choose a provider folder that grants persistent write access or export locally and sync with your preferred tool.

## Formats

The Android app shares the same plain-file goals as the Apple app:

| Format | Use it for |
|---|---|
| Markdown | Readable daily health summaries, templates, and notes |
| Obsidian Bases | Frontmatter-first notes that can be queried in Obsidian database views |
| JSON | Structured daily payloads for scripts, dashboards, notebooks, and the Health.md Obsidian plugin |
| CSV | Spreadsheet and analysis workflows |

Android JSON exports are designed to be compatible with Health.md's Obsidian visualizations. Markdown and Bases exports use the same frontmatter-focused workflow documented in the [format guide](/docs/format/).

## Scheduling and automation

Scheduled exports use Android WorkManager, so the selected time is a target rather than a hard guarantee. Health.md records export history, can recover missed scheduled dates, and lets you retry failed runs.

For Tasker, adb, or other automation tools, Health.md exposes explicit-only broadcast intents. External callers must address the receiver component directly:

```text
com.healthmd.android/com.healthmd.automation.AutomationReceiver
```

Examples:

```bash
adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_YESTERDAY

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_LAST_DAYS \
  --ei com.healthmd.android.extra.DAYS 7

adb shell am broadcast \
  -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
  -a com.healthmd.android.action.EXPORT_RANGE \
  --es com.healthmd.android.extra.START_DATE 2026-03-01 \
  --es com.healthmd.android.extra.END_DATE 2026-03-07
```

Automation uses your current export settings, selected folder, formats, metric selection, free/export accounting, and history.

## Health sources

Health Connect is the default local export path. The Android app also includes a health-source setup area for ecosystems such as Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar, and WHOOP. Where those ecosystems write into Health Connect, Health.md can export the resulting Health Connect records. Direct cloud-provider imports require provider authorization and may have extra setup or availability constraints.

Google Fit is intentionally excluded from the supported-provider surface because Health Connect is Android's preferred health-data layer.

## Pricing and restore

- The Android app includes 3 free manual export actions.
- Unlimited exports and scheduled automation unlock with a one-time lifetime purchase through Google Play Billing.
- There is no subscription and no recurring charge.
- Google Play shows the live local price before purchase.
- Restore Purchase uses the Google account that bought Full Access.

## Privacy model

Health.md for Android is local-first:

- Health Connect records are read on your Android device.
- Exports are written directly to folders you choose.
- Health.md does not run a health-data cloud service.
- Settings and export history stay on-device.
- Billing is handled by Google Play.
- Provider-backed folders sync according to that provider's own terms.

If you want the strictest local setup, run manual exports to a local device folder and leave scheduled exports and provider-backed sync disabled.

## Related docs

<div class="related">
  <a href="/docs/export/"><span>Export</span>Manual export flow, date ranges, previews, history, and file output.</a>
  <a href="/docs/metrics/"><span>Metrics</span>How metric selection and categories work across Health.md.</a>
  <a href="/docs/format/"><span>Formats</span>Markdown, Bases, JSON, CSV, units, filenames, and frontmatter.</a>
  <a href="/docs/visualizations-roadmap/"><span>Obsidian</span>How exported JSON and Markdown power Health.md visualizations.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Last updated 2026-07-08</p>
