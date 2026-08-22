# Health.md for Android Feature Documentation Index

This directory is the canonical inventory for documenting Health.md for Android end-to-end, mirroring the Apple feature index at `apps/apple/docs/features/index.md`. Each feature should eventually have:

1. a user-facing docs page here (use [`_template.md`](./_template.md)), and
2. a video outline that can become one episode in the feature series.

Deep machine contracts live in [`docs/export-contract/`](../export-contract/) and are linked from each page rather than duplicated. Product-wide cross-platform status lives in the repository-root [`docs/features/feature-inventory.md`](../../../../docs/features/feature-inventory.md).

## Draft status

All new pages below are first-pass drafts written from source. The next editorial pass should add screenshots, verify each workflow on a physical device (Pixel 7 per `AGENTS.md`), and decide which pages are ready for the public docs site.

## Feature inventory

| Area | Feature | User promise | Docs status | Video priority | Primary source |
|---|---|---|---|---|---|
| Setup | [Onboarding](./onboarding.md) | First-run path: Health Connect setup, permissions, destination, formats, and first export. | Draft | High | `presentation/onboarding/OnboardingScreen.kt` |
| Setup | [Health Connect permissions](./health-connect-permissions.md) | Grant only the categories you want exported, with a rationale screen for review. | Draft | High | `presentation/HealthPermissionsRationaleActivity.kt`, `data/health/` |
| Setup | [Folder destination](./folder-destination.md) | Pick any SAF folder: local, Obsidian vault, Drive, OneDrive, Syncthing, or another provider. | Draft | High | `data/storage/`, Export screen folder UI |
| Export | [Manual export](./manual-export.md) | Export one day or a range on demand; 10 free actions before unlock. | Draft | High | `presentation/export/ExportScreen.kt` |
| Export | [Metric selection](./metric-selection.md) | Choose from 106 Health Connect metrics with search and category toggles. | Draft | High | `presentation/metrics/MetricSelectionScreen.kt` |
| Export | [Export preview](./export-preview.md) | Inspect generated output before writing to your folder. | Draft | Medium | `presentation/export/` preview components |
| Export | [Export profiles](./export-profiles.md) | Save named configurations with independent settings, destinations, and schedules. | Draft | Medium | `presentation/export/ExportProfilesScreen.kt` |
| Export | [Multi-format export](./multi-format-export.md) | Write Markdown, Bases, JSON, and CSV in one export action. | Draft | High | `domain/model/` export settings, `ExportScreen.kt` |
| Export formats | [Markdown export](./markdown-export.md) | Readable daily summaries with template choices. | Draft | High | `data/export/MarkdownExporter.kt` |
| Export formats | [JSON export](./json-export.md) | `healthmd.health_data` daily payloads compatible with the Obsidian plugin. | Draft | High | `data/export/JsonExporter.kt`, `HealthMdExportSchema.kt` |
| Export formats | [CSV export](./csv-export.md) | One row per metric or timestamped sample for spreadsheets. | Draft | Medium | `data/export/CsvExporter.kt` |
| Export formats | [Obsidian Bases export](./obsidian-bases.md) | Frontmatter-first notes queryable in Obsidian database views. | Draft | High | `data/export/ObsidianBasesExporter.kt` |
| Formatting | [Filename templates](./filename-templates.md) | `{date}`, `{year}`, `{month}`, `{weekday}` placeholders in filenames. | Draft | Medium | `domain/model/` path templates, `data/storage/` |
| Formatting | [Folder organization](./folder-organization.md) | Date-based subfolders like `{year}/{month}` under your destination. | Draft | Medium | same |
| Formatting | [Frontmatter customization](./frontmatter-customization.md) | Rename metric fields, choose casing, add static and placeholder fields. | Draft | Medium | `presentation/settings/FrontmatterCustomizationScreen.kt` |
| Formatting | [Write modes](./write-modes.md) | Overwrite, append, or merge when a file already exists. | Draft | Medium | `data/export/MarkdownMerger.kt` |
| Obsidian | [Daily note injection](./daily-note-injection.md) | Merge health sections into existing Obsidian daily notes. | Draft | High | `data/export/DailyNoteInjector.kt`, `DailyNoteInjectionScreen.kt` |
| Advanced data | [Individual entry tracking](./individual-entry-tracking.md) | Timestamped per-record files: workouts, sleep stages, vitals. | Draft | High | `data/export/IndividualEntryExporter.kt` |
| Advanced data | [Workout details](./workout-details.md) | Complete workout sessions with route status, splits, and samples where Health Connect provides them. | Existing | Medium | `domain/model/` workouts, `data/health/` |
| Advanced data | [Raw API snapshots](./raw-snapshots.md) | Immutable, versioned JSON/NDJSON provider-native archive with manifests and checksums. | Draft | Medium | `rawexport/`, [`raw-snapshot-v1`](../export-contract/raw-snapshot-v1.md) |
| Advanced data | [Cloud providers](./cloud-providers.md) | Connect Fitbit, Oura, WHOOP, and Withings for raw provider snapshots. | Draft | Medium | `presentation/oauth/`, [`health-provider-support`](../health-provider-support.md) |
| Automation | [Scheduled exports](./scheduled-exports.md) | WorkManager scheduling with exact-alarm option, boot recovery, and missed-date retry. | Draft | High | `data/scheduler/`, `presentation/schedule/ScheduleScreen.kt` |
| Automation | [Automation intents](./automation-intents.md) | Trigger exports from Tasker or adb; launcher shortcuts. | Draft | Medium | `automation/AutomationReceiver.kt`, [`android-automation-intents`](../android-automation-intents.md) |
| Automation | [Export history and retry](./export-history-retry.md) | Review recent runs and retry failed dates from Room-backed history. | Draft | Medium | `data/history/`, `presentation/history/HistoryScreen.kt` |
| Automation | [API endpoint export](./api-endpoint-export.md) | Send the `healthmd.api_export` envelope to your HTTP(S) endpoint with encrypted auth. | Draft | Medium | `data/export/API*`, [`api-endpoint-export`](../api-endpoint-export.md) |
| Devices | [Direct CLI](./direct-cli.md) | Pair with the standalone `healthmd` CLI over LAN or Tailscale for computer-side exports. | Draft | Medium | `presentation/directcli/`, [`android-desktop-destination`](../android-desktop-destination.md) |
| Devices | [Home-screen widgets](./widgets.md) | Glance widgets: Health Summary, Activity, Heart Range, Sleep. | Existing | Medium | `widget/` |
| Devices | Wear OS companion | Tiles and complications; phone stays authoritative. | Runbook only | Low | [`wear-os-implementation.md`](./wear-os-implementation.md) |
| Reports | [Clinician report](./clinician-report.md) | Turn a date range into one accessible PDF to share with a clinician. | Draft | Medium | `presentation/clinicianreport/` |
| Purchase | [Lifetime unlock](./lifetime-unlock.md) | 10 free manual export actions; one-time lifetime unlock, no subscription. | Draft | Medium | `presentation/paywall/`, `data/billing/` |
| Privacy | [Local-first privacy](./privacy-local-first.md) | No Health.md health-data cloud; every destination is user-directed. | Draft | High | README privacy sections, private spools |

## Suggested video series order

1. **Health Connect → Obsidian in Five Minutes:** [Onboarding](./onboarding.md) + [Manual export](./manual-export.md)
2. **Choose Exactly the Metrics You Want:** [Metric selection](./metric-selection.md)
3. **Every Format at Once:** [Multi-format export](./multi-format-export.md)
4. **Append Health Data to Your Daily Note:** [Daily note injection](./daily-note-injection.md)
5. **Automate with Scheduled Exports:** [Scheduled exports](./scheduled-exports.md)
6. **Trigger Exports from Tasker:** [Automation intents](./automation-intents.md)
7. **Send Health Data to Your Own API:** [API endpoint export](./api-endpoint-export.md)
8. **Pair Your Phone with Your Computer's CLI:** [Direct CLI](./direct-cli.md)
9. **Archive Everything, Losslessly:** [Raw API snapshots](./raw-snapshots.md)
10. **One PDF for Your Next Appointment:** [Clinician report](./clinician-report.md)

## Documentation rules

- Prefer user-facing language first; put implementation details at the bottom.
- Never fabricate parity with Apple: if Health Connect cannot express something HealthKit can (or vice versa), say so explicitly and keep identities distinct (for example, HRV RMSSD here is not HealthKit SDNN).
- Link machine contracts under `docs/export-contract/` instead of restating field lists.
- Call out Android realities honestly: exact-alarm permission trade-offs, SAF provider quirks, lock-screen widget redaction limits.
- Every feature page should include a video outline, even if the video is low priority.
- Update this index and the root [`feature-inventory.md`](../../../../docs/features/feature-inventory.md) when a feature is added.
