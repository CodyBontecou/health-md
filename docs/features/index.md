# Health.md iOS Feature Documentation Index

This directory is the canonical inventory for documenting Health.md end-to-end. Each feature should eventually have:

1. a user-facing docs page for the docs site, and
2. a video outline that can become one episode in the Health.md feature series.

Use [`_template.md`](./_template.md) for new feature pages. Use [`video-series.md`](./video-series.md) as the running episode roadmap.

## Draft status

All feature pages in the inventory below now have first-pass drafts. The next editorial pass should add screenshots, verify each workflow on device, and decide which pages are ready for the public docs site.

## Feature inventory

| Area | Feature | User promise | Docs status | Video priority | Primary source |
|---|---|---|---|---|---|
| Setup | [Onboarding](./onboarding.md) | First-run path for permissions, sample export preview, Obsidian plugin visualization, optional folder setup, unlock/free exports, and readiness. | Drafted | High | `HealthMd/iOS/Views/OnboardingView.swift` |
| Setup | [HealthKit permissions](./healthkit-permissions.md) | Connect Health.md to Apple Health and choose readable data types. | Drafted | High | `HealthKitManager`, `OnboardingView` |
| Setup | [Vault/folder selection](./vault-folder-selection.md) | Pick an Obsidian vault, iCloud Drive folder, or Files location for exports. | Drafted | High | `VaultManager`, `FolderPicker` |
| Export | [Manual date-range export](./manual-export.md) | Export one day or a range of days on demand. | Drafted | High | `ExportTabView`, `ExportOrchestrator` |
| Export | [Export preview](./export-preview.md) | Inspect generated files before writing them to disk. | Drafted | Medium | `Shared/Views/ExportPreviewView.swift` |
| Export | [Metric selection](./metric-selection.md) | Select from 171 metrics across 18 HealthKit categories. | Drafted | High | `MetricSelectionView`, `HealthMetrics.swift` |
| Export | [Multi-format export](./multi-format-export.md) | Write Markdown, Obsidian Bases, JSON, and CSV in one export run. | Drafted | High | `AdvancedExportSettings`, `VaultManager` |
| Export | [Roll-up summaries](./rollup-summaries.md) | Generate weekly, monthly, and yearly summaries in every selected export format. | Drafted | Medium | `HealthRollupGenerator`, `Rollup*Exporter`, `ExportOrchestrator` |
| Export formats | [Markdown export](./markdown-export.md) | Human-readable daily health notes with optional frontmatter and grouped sections. | Drafted | High | `MarkdownExporter.swift` |
| Export formats | [Obsidian Bases export](./obsidian-bases.md) | Database-friendly frontmatter-only `.md` files. | Drafted | High | `ObsidianBasesExporter.swift` |
| Export formats | [JSON export](./json-export.md) | Structured export for scripts, analysis, and external tools. | Drafted | Medium | `JSONExporter.swift` |
| Export formats | [CSV export](./csv-export.md) | Spreadsheet-friendly export with one row per metric. | Drafted | Medium | `CSVExporter.swift` |
| Export formats | [Export schema contract](./export-schema.md) | Keep Markdown, Bases, JSON, CSV, and the data dictionary versioned and machine-readable. | Drafted | Low | `HealthMdExportSchema`, `ExportSchemaSignatureTests` |
| Export formats | [Data dictionary and roll-up rules](./data-dictionary.md) | Explain every exported key, unit, HealthKit identifier, and weekly/monthly/yearly aggregation rule. | Drafted | Low | `HealthMetricDataDictionary`, `HealthMetricRollupRule` |
| Formatting | [Date/time/unit preferences](./date-time-units.md) | Choose date style, time style, and metric/imperial units. | Drafted | Medium | `FormatCustomizationView.swift`, `FormatPreferences.swift` |
| Formatting | [Frontmatter customization](./frontmatter-customization.md) | Rename metric fields, choose snake_case/camelCase, add static and placeholder fields. | Drafted | High | `FrontmatterCustomizationView` |
| Formatting | [Markdown template customization](./markdown-template-customization.md) | Pick compact/standard/detailed/custom Markdown output. | Drafted | Medium | `MarkdownTemplateView`, `MarkdownExporter.swift` |
| Organization | [Filename templates](./filename-templates.md) | Use placeholders like `{date}`, `{year}`, `{month}`, `{weekday}`, `{monthName}`, `{quarter}`. | Drafted | High | `AdvancedExportSettings.swift` |
| Organization | [Folder organization](./folder-organization.md) | Use date-based subfolders like `{year}/{quarter}` or `{year}/{month}`. | Drafted | High | `AdvancedExportSettings.swift`, `VaultManager` |
| Organization | [Write modes](./write-modes.md) | Choose overwrite, append, or update/merge behavior when a file already exists. | Drafted | Medium | `WriteMode`, `MarkdownMerger.swift` |
| Obsidian | [Daily note injection](./daily-note-injection.md) | Merge health metrics into existing Obsidian daily notes. | Drafted | High | `DailyNoteInjectionView.swift`, `DailyNoteInjector.swift` |
| Advanced data | [Time-series data](./time-series-data.md) | Include timestamped samples so intraday charts can be rebuilt later. | Drafted | Medium | `includeGranularData`, `HealthKitManager` |
| Advanced data | [Individual entry tracking](./individual-entry-tracking.md) | Create separate timestamped files for mood, symptoms, workouts, vitals, etc. | Drafted | High | `IndividualTrackingView.swift`, `IndividualEntryExporter.swift` |
| Advanced data | [Mood / State of Mind](./mood-state-of-mind.md) | Export iOS State of Mind daily averages plus individual mood entries. | Drafted | High | `HealthData`, `SystemHealthStoreAdapter`, `IndividualEntryExporter` |
| Advanced data | [Workout details](./workout-details.md) | Export workout-level HR, pace/speed, cadence, power, laps, splits, and time series. | Drafted | Medium | `HealthStoreProtocol.swift`, `SystemHealthStoreAdapter.swift` |
| Advanced data | [Third-party integrations](./third-party-integrations.md) | Deferred Connected Apps/provider sidecar implementation kept behind `ConnectedAppsFeature.isEnabled == false`. | Deferred | Medium | `Shared/Integrations`, `ExternalIntegrationManager`, `worker/oauth-broker` |
| Automation | [Scheduled exports](./scheduled-exports.md) | Run recurring exports at a selected time with notifications and retry handling. | Drafted | High | `ScheduleSettingsView.swift`, `SchedulingManager.swift`, `PushRegistrationManager.swift` |
| Automation | [Apple Shortcuts](./apple-shortcuts.md) | Trigger exports and retrieve health summaries from Shortcuts/Siri. | Drafted | High | `HealthMd/iOS/AppIntents` |
| Automation | [Mac CLI iPhone export trigger](./cli-mac-iphone-export.md) | Trigger an export from a connected, open iPhone using the Mac app or CLI. | Drafted | Medium | `SyncPayload.swift`, `HealthMdControlServer.swift`, `scripts/healthmd` |
| Automation | [API Endpoint export](./api-endpoint-export.md) | Send selected Apple Health JSON directly from iPhone to a user-configured HTTP(S) endpoint. | Drafted | Medium | `APIExportSettings`, `APIExportClient`, `ExportTabView` |
| Automation | [CLI distribution](./cli-distribution.md) | Bundle the CLI in the Mac app while also supporting standalone terminal installs. | Drafted | Medium | `HealthMdCLI`, `HealthMd-macOS`, `scripts/healthmd` |
| Reliability | [Export history and retry](./export-history-retry.md) | Review recent export results and retry failed dates. | Drafted | Medium | `ExportHistory.swift`, `ScheduleSettingsView.swift` |
| Mac destination | [iPhone → Mac destination](./mac-sync.md) | Start exports on iPhone and write Health.md files to a selected Mac folder over the local network. | Drafted | High | `SyncSettingsView.swift`, `ExportTabView.swift`, `SyncService.swift` |
| Community | [Discord and feedback](./community-feedback.md) | Join the app community, send feedback, or open GitHub issues. | Drafted | Low | `SettingsTabView`, `FeedbackHelper.swift` |
| Purchase | [Full Access unlock](./full-access-unlock.md) | Explain the free export quota, subscriptions, lifetime plans, and restore behavior. | Drafted | Medium | `PurchaseManager.swift`, `PaywallView.swift` |
| Privacy | [Local-first privacy model](./privacy-local-first.md) | Explain exactly what stays local and what the scheduling worker stores. | Drafted | High | `README.md`, `PushRegistrationManager.swift` |

## Suggested video series order

1. **Health.md Beginner Walkthrough: Apple Health → Obsidian** — [Onboarding](./onboarding.md) + [Manual Export](./manual-export.md)
2. **How to Export Apple Health Data to Markdown** — [Markdown Export](./markdown-export.md)
3. **Append Apple Health Data to Your Obsidian Daily Note** — [Daily Note Injection](./daily-note-injection.md)
4. **Use Apple Health Data in Obsidian Bases** — [Obsidian Bases Export](./obsidian-bases.md)
5. **Customize Health.md File Names, Folders, and Templates** — [Filename Templates](./filename-templates.md) + [Folder Organization](./folder-organization.md)
6. **Automate Health.md with Scheduled Exports** — [Scheduled Exports](./scheduled-exports.md)
7. **Run Health.md from Apple Shortcuts** — [Apple Shortcuts](./apple-shortcuts.md)
8. **Track Mood / State of Mind in Obsidian** — [Mood / State of Mind](./mood-state-of-mind.md)
9. **Export Individual Health Entries, Not Just Daily Summaries** — [Individual Entry Tracking](./individual-entry-tracking.md)
10. **Workout Deep Dive: Pace, HR, Power, Cadence, Splits** — [Workout Details](./workout-details.md)
11. **Use Your Mac as a Local Destination for iPhone Health.md Exports** — [Mac Destination](./mac-sync.md)
12. **Send Apple Health Data to Your Own API** — [API Endpoint Export](./api-endpoint-export.md)
13. **Health.md Privacy Architecture: Where Your Data Goes** — [Privacy and Local-First Design](./privacy-local-first.md)

## Documentation rules

- Prefer user-facing language first; put implementation details at the bottom.
- Every feature page should include at least one concrete path/example output.
- Every feature page should include a video outline, even if the video is low priority.
- Call out limitations honestly, especially iOS locked-device behavior and HealthKit permission constraints.
- When screenshots are captured later, add a `Screenshots needed` checklist to each page.
