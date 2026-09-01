---
title: Android App
description: Set up Health.md for Android, export Health Connect data to Markdown, Obsidian Bases, JSON, and CSV, choose Storage Access Framework folders, schedule exports, and automate with Tasker or adb.
---

<div class="docs-hero">
  <p class="docs-eyebrow">Health Connect to private files</p>
  <p>Health.md for Android reads Health Connect on-device and writes Markdown, Obsidian Bases, JSON, or CSV to folders you choose. No Health.md account, no health-data cloud, and no subscription.</p>
  <div class="docs-actions">
    <a class="docs-button" href="https://play.google.com/store/apps/details?id=com.healthmd.android" target="_blank" rel="noopener">Get on Google Play</a>
    <a class="docs-button-secondary" href="https://f-droid.org/packages/com.healthmd.android/" target="_blank" rel="noopener">Get on F-Droid</a>
    <a class="docs-button-secondary" href="/docs/export/">Read Export Docs</a>
  </div>
</div>

<div class="reference-stats">
<div><strong>106</strong><span>selectable Health Connect metrics</span></div>
<div><strong>4</strong><span>export formats</span></div>
<div><strong>2</strong><span>Android distribution channels</span></div>
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

1. Install Health.md from Google Play or F-Droid.
2. Open **Health Connect** setup and grant only the categories you want Health.md to export.
3. Pick the export destination through Android's folder picker.
4. Choose formats: Markdown, Obsidian Bases, JSON, CSV, or any combination.
5. Select metrics and date range.
6. Preview the output.
7. Tap export and verify the generated files in your folder or vault.

The Google Play build includes 10 manual export actions before its one-time unlock. The F-Droid build includes unlimited access with no purchase or restore flow.

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

Scheduled exports require the one-time lifetime entitlement in the Google Play build and are included in the F-Droid build. They use a one-shot exact alarm when you grant Android's Alarms & reminders access, with durable WorkManager work as a backup. Without exact-alarm access, WorkManager becomes the primary scheduler, so the selected time is a target rather than a hard guarantee. Health.md records export history, can recover missed scheduled dates, and lets you retry failed runs.

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

Automation uses the active profile by default, including its frozen destination, formats, metrics, accounting, and history. A supplied `PROFILE` extra can select a stable profile ID or name; an unknown reference fails closed instead of using current settings. Scheduled runs also stay bound to their profile. See [Export profiles](/docs/export-profiles/).

### Background readiness and scheduled cancellation

- Allow background Health Connect reads for unattended exports; otherwise open Health.md to complete the health-data read.
- Keep notifications enabled so Android can show active work, foreground-service state, results, and recovery actions.
- Grant Alarms & reminders only when you want exact-alarm scheduling. Without it, durable WorkManager work remains available but the chosen time is approximate.
- Cancelling a scheduled run stops only that attempt. Completed dates remain complete, unresolved dates can be retried, and the recurring schedule remains enabled.

## Health sources

Health Connect is the local export path in both channels. The Google Play build also includes a health-source setup area for ecosystems such as Samsung Health, Huawei Health, Fitbit, Garmin, Withings, Oura, Polar, and WHOOP. Where those ecosystems write into Health Connect, either build can export the resulting Health Connect records. Direct cloud-provider imports and OAuth callbacks are Play-only. The F-Droid provider catalog contains Health Connect only.

Google Fit is intentionally excluded from the supported-provider surface because Health Connect is Android's preferred health-data layer.

### Exact local-day steps

Daily step totals use exact zoned-local-day boundaries. Health.md clips and splits overlapping Health Connect intervals at local midnight before aggregating, so travel and daylight-saving changes do not shift steps into the wrong day.

## Distribution, pricing, and switching

- **Google Play:** 10 free manual export actions, followed by one lifetime purchase through Google Play Billing. There is no subscription. Restore Purchase uses the purchasing Google account.
- **F-Droid:** unlimited access is included. There is no free counter, Billing dependency, paywall, purchase, or restore action.
- **F-Droid scope:** Health Connect only, with no Wear OS integration, direct cloud-provider OAuth, Play review, attribution, or Health.md onboarding telemetry.
- **Shared outcome:** both channels use the same Health Connect capture, exporters, schemas, automation actions, and direct-device protocol.
- **Switching:** Google Play and F-Droid use different signing keys, so changing channels requires uninstalling the app first.

A channel switch does not migrate purchases, settings, history, credentials, or private transfer state. Exported files remain in the destination you chose.

If Google Play Billing disconnects transiently, the Play build reconnects and refreshes entitlement state automatically. A temporary service loss does not permanently remove Premium; use Restore Purchase only if the account remains unresolved after connectivity returns.

## Privacy model

Health.md for Android is local-first:

- Health Connect records are read on your Android device.
- Exports are written directly to folders you choose.
- Health.md does not run a health-data cloud service.
- Settings and export history stay on-device.
- Billing is handled by Google Play in the Play build; F-Droid includes unlimited access without Billing and contains no Health.md telemetry code or telemetry identity/state.
- Provider-backed folders sync according to that provider's own terms.

If you want the strictest local setup, run manual exports to a local device folder and leave scheduled exports and provider-backed sync disabled.

## Related docs

<div class="related">
  <a href="/docs/export-profiles/"><span>Profiles</span>Save independent destinations, output settings, schedules, and stable automation IDs.</a>
  <a href="/docs/export/"><span>Export</span>Manual export flow, date ranges, previews, history, and file output.</a>
  <a href="/docs/metrics/"><span>Metrics</span>How metric selection and categories work across Health.md.</a>
  <a href="/docs/format/"><span>Formats</span>Markdown, Bases, JSON, CSV, units, filenames, and frontmatter.</a>
  <a href="/docs/visualizations-roadmap/"><span>Obsidian</span>How exported JSON and Markdown power Health.md visualizations.</a>
</div>

<p style="margin-top:48px; color:var(--sl-color-gray-3); font-size:14px;">Last updated 2026-09-01</p>
