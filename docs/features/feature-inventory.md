# Health.md Feature Inventory — Baseline

- **Status:** Living baseline. First compiled 2026-08-22 from full-source recon of every component (Apple iOS/iPadOS/macOS/watchOS/widgets, Android phone/Wear/widgets, CLI+MCP, shared Rust core, contracts, practice portal, website).
- **Purpose:** One structured inventory of every product feature, used as the baseline to manage documentation: every row says what exists, where the evidence lives, and whether a docs page exists.
- **Method:** Source-first (screens, navigations, exporters, intents, CLI clap tree, MCP tool catalog, protocol specs), cross-checked against each component's docs tree. Docs status: ✅ dedicated page · 🟡 covered inside another page · ❌ no docs · 🔧 internal/no user docs needed.
- **Related inventories:** `packages/contracts/product-capabilities.json` (machine-readable export-contract capabilities), `apps/apple/docs/features/index.md` (Apple feature-doc index), `packages/contracts/manifest.json` (public contract registry). This page is the product-wide superset.

## Product surfaces

| Surface | Location | Notes |
|---|---|---|
| iOS + iPadOS app | `apps/apple/HealthMd/iOS` | 4 tabs: Export, Schedule, Sync, Settings |
| macOS app | `apps/apple/HealthMd/macOS` | Sidebar: Home, CLI, Settings; menu-bar popup |
| watchOS app + watch widgets | `apps/apple/HealthMdWatch`, `HealthMdWatchWidgets` | Dashboard app + 10 widget metrics |
| iOS widgets + Live Activity | `apps/apple/HealthMdWidgets` | 4 widget families + CLI export Live Activity |
| Android phone app | `apps/android/app` | Tabs: Export, Schedule, History, Settings; feature docs tree at `apps/android/docs/features/` mirroring Apple's |
| Wear OS companion | `apps/android/wear` | Tiles + complications; phone stays authoritative |
| Android widgets | `apps/android/app/.../widget` | Glance: Health Summary, Activity, Heart Range, Sleep |
| Standalone CLI + MCP | `apps/cli/crates/*` | `healthmd` CLI, `healthmd-mcp`, portable macOS/Linux/Windows |
| Shared Rust core | `packages/healthmd-core-rust` | Metric registry, semantic/render engine, protocol, UniFFI |
| Contracts | `packages/contracts` | Language-neutral public + internal contracts |
| Practice portal (synthetic) | `apps/practice` | Production-disabled clinician-portal foundation |
| Website + public docs | `apps/website` | Astro docs site, 10 locales, blog, visualizations |
| Cloudflare workers | `apps/apple/worker/{oauth-broker,pricing-analytics}` | OAuth broker + coarse pricing analytics |

---

## 1. Onboarding & permissions

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| First-run onboarding flow | iOS, Android | 7-step path: welcome → health access → sample export → Obsidian plugin demo → folder → unlock → ready | `iOS/Views/OnboardingView.swift`; `android presentation/onboarding/OnboardingScreen.kt` | ✅ `apple docs/features/onboarding.md`; 🟡 website `onboarding.md` |
| Health data permission request | iOS, Android | Request read access to HealthKit types / Health Connect permission flow | `Shared/Managers/HealthKitManager.swift`; android `data/health/` | ✅ `healthkit-permissions.md`; 🟡 website |
| Permission rationale & usage disclosure | Android | Exported Health Connect rationale screen (`ACTION_SHOW_PERMISSIONS_RATIONALE`) + platform `ViewPermissionUsageActivity` activity-alias onto the same screen (`VIEW_PERMISSION_USAGE`); enforced by manifest contract test | `presentation/HealthPermissionsRationaleActivity.kt`, `AndroidManifest.xml` (activity + alias), `HealthConnectManifestContractTest.kt` | 🔧 |
| Sample export preview (onboarding) | iOS, Android | Preview a sample export before choosing destination | `OnboardingView.swift` (`sampleExportStepIndex`); android onboarding | 🟡 inside onboarding pages |
| Obsidian plugin visualization demo | iOS | Embedded HTML/JS demo of the external Obsidian plugin | `iOS/Resources/PluginVisualization/*` | 🟡 inside onboarding |
| Folder/vault selection | iOS, macOS, Android | Pick Obsidian vault, iCloud Drive/Files, or SAF document-provider folder | `iOS/Views/FolderPicker.swift`, `VaultManager`; android SAF storage | ✅ `vault-folder-selection.md`, `folder-organization.md` |
| Mac onboarding | macOS | First-run Mac setup | `macOS/Views/MacOnboardingView.swift` | 🟡 iOS-oriented onboarding page |
| Onboarding analytics | Android | First-party onboarding event funnel | `android docs/onboarding-analytics.md`, `data/attribution/` | 🔧 internal doc only |

## 2. Metric selection & data scope

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Metric selection UI | iOS, macOS, Android | Apple: 225+ definitions, 21 categories, special-access flows. Android: 106 Health Connect metrics, search + category toggles | `iOS/Views/MetricSelectionView.swift`, `HealthKitRecordCatalog`; android `presentation/metrics/MetricSelectionScreen.kt` | ✅ `metric-selection.md`; website `metrics.md` |
| Shared metric registry | core (all) | Deterministic Rust-owned metric identities, units, aliases, profile order | `healthmd-core/registry/metric-registry-v1.json`, adapters in Apple/Android | ✅ website `shared-metric-registry.md`; 🟡 |
| HealthKit special-access metrics | iOS | Special permission flows for restricted metric classes | `HealthKitRecordCatalog`, metric-selection doc | ✅ |
| Android compatibility keys | Android | Legacy compatibility keys for existing scripts | android export settings | 🟡 android README |
| Data dictionary | iOS, core | Every exported key, unit, HK identifier, aggregation rule (generated) | `HealthMetricDataDictionary`, `docs/reference/generated/core/` | ✅ `data-dictionary.md` + reference |

## 3. Export formats & content

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Markdown daily export | iOS, macOS, Android | Readable daily health notes, grouped sections | `Shared/Export/MarkdownExporter.swift`; android `data/export/MarkdownExporter.kt` | ✅ `markdown-export.md` |
| Obsidian Bases export | iOS, macOS, Android | Frontmatter-only `.md` database notes | `ObsidianBasesExporter` | ✅ `obsidian-bases.md` |
| JSON daily export | iOS, macOS, Android | `healthmd.health_data` v8 (Apple) / v4+v5 (Android) + typed provider sections | `JSONExporter`, `HealthMetricsDictionary.swift`; android `JsonExporter.kt` | ✅ `json-export.md`, `export-schema.md` |
| CSV export | iOS, macOS, Android | Summary rows + canonical source objects as RFC 4180-safe JSON rows | `CSVExporter` | ✅ `csv-export.md` |
| NDJSON raw output | Android, CLI | Raw snapshot artifacts in JSON or NDJSON | android `rawexport/`; CLI `--raw-format ndjson` | ✅ `raw-snapshot-v1.md` |
| Multi-format single run | iOS, macOS, Android | MD+Bases+JSON+CSV in one export action (counts as one action) | `AdvancedExportSettings` | ✅ `multi-format-export.md` |
| Roll-up summaries | iOS, macOS (Android planned) | Weekly/monthly/yearly + requested-range rollups in every selected format | `HealthRollupGenerator`, `Rollup*Exporter`; contract `rollup-summary/v9` | ✅ `rollup-summaries.md` |
| Lossless HealthKit archive | iOS | Every selected public source record retained (`healthmd.healthkit_records` v1), UUIDs/provenance/relationships | `HealthKitRecordArchiveSerializer` | ✅ `time-series-data.md` |
| Individual entry tracking | iOS, macOS, Android | Timestamped per-record notes: workouts, sleep stages, vitals (BP/glucose/temp/weight) | `IndividualEntryExporter` | ✅ `individual-entry-tracking.md` |
| Mood / State of Mind export | iOS | Daily State of Mind averages + individual mood entries | `SystemHealthStoreAdapter+SpecializedRecords.swift` | ✅ `mood-state-of-mind.md` |
| Workout details | iOS, macOS, Android | Complete public workout graphs + route/splits/metadata while keeping MD/Bases readable | `SystemHealthStoreAdapter+CanonicalWorkouts.swift` | ✅ `workout-details.md` (apple + android) |
| Medication dose events | iOS | HealthKit medication catalog + taken/skipped dose events in export | export schema; parity ledger | ✅ via export-schema/parity docs |
| Zip archive export toggle | iOS | Bundle export files into a zip (DEFLATE) | `ExportTabView.swift:673`, `ZipArchiveWriter.swift` | 🟡 within `multi-format-export.md` |
| Export schema contract | iOS, Android, CLI, core | Versioned public schema (Apple v8; Android frozen v4 + analytical v5; v9 proposed) | `packages/contracts/`, `HealthMdExportSchema` | ✅ `export-schema.md` + contracts |
| Raw API Snapshot product | Android (+CLI delivery) | Immutable versioned JSON/NDJSON provider-native snapshot: Health Connect + Fitbit/Oura/WHOOP/Withings cloud; manifests, checksums, `.sha256` sidecars, preview-without-destination, HTTPS-only streaming upload | android `rawexport/`, `rawchanges/`; docs `raw-snapshot-v1.md`, `raw-record-v1.md`, `raw-changes-v1.md` | ✅ android export-contract docs + website `guides/raw-snapshots` (canonical EN, translations pending) |
| Raw changes backend | Android | `healthmd.raw-changes` change tokens + deletion tombstones for incremental archives | android `rawchanges/` | ✅ `raw-changes-v1.md` |
| Exercise route consent | Android | Explicit consent coordination before exporting exercise routes | `rawexport/ExerciseRouteConsent*.kt` | 🟡 raw docs |
| Daily note injection | iOS, macOS, Android | Merge health sections into existing Obsidian daily notes | `DailyNoteInjector` (+`MarkdownMerger`) | ✅ `daily-note-injection.md`; website `daily-notes.md` |
| Clinician report (PDF) | iOS, Android | Clinician-facing configured report (presets, metric selection) rendered to PDF with share sheet; localized copy | `iOS/ClinicianReport/*`, `Shared/ClinicianReport/`; android `presentation/clinicianreport/` | ✅ `apps/apple/docs/features/clinician-report.md` (spec: root `docs/features/clinician-report-v1.md`) |

## 4. Export configuration & customization

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Filename templates | iOS, macOS, Android | `{date}`, `{year}`, `{YR}`, `{month}`, `{weekday}`, `{monthName}`, `{quarter}` placeholders | `AdvancedExportSettings`, `ExportPathPlanner` | ✅ `filename-templates.md` |
| Folder organization | iOS, macOS, Android | Date-based subfolders `{year}/{month}`, `{year}/{quarter}`; Android folder-by-type | `AdvancedExportSettings`, `VaultManager` | ✅ `folder-organization.md` |
| Frontmatter customization | iOS, macOS, Android | Rename metric fields, snake/camelCase, static + placeholder fields | `FrontmatterCustomizationView` | ✅ `frontmatter-customization.md` |
| Markdown template choice | iOS, macOS, Android | Compact/standard/detailed/custom templates | `MarkdownTemplateView`, `MarkdownExporter` | ✅ `markdown-template-customization.md` |
| Date/time/unit preferences | iOS, macOS, Android | Date style, time style, metric/imperial | `FormatPreferences`, `FormatCustomizationView` | ✅ `date-time-units.md` |
| Write modes | iOS, macOS, Android | Overwrite / append / update-merge | `WriteMode`, `MarkdownMerger` | ✅ `write-modes.md` |
| Emoji headers / grouping options | macOS (+iOS) | Section grouping, emoji headers, folder-by-type | `MacSettingsView` Format tab | 🟡 mac settings coverage |
| Configuration protection | iOS | "Prevent Accidental Changes" lock for config edits | `SettingsTabView.configurationProtectionSection` | 🟡 within `manual-export.md` |

## 5. Export execution & reliability

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Manual date-range export | iOS, macOS, Android | One day or range on demand | `ExportTabView`, `ExportOrchestrator` | ✅ `manual-export.md` |
| Export preview | iOS, macOS, Android | Inspect generated files + size estimate before writing | `ExportPreviewView`, `ExportPreviewSizeEstimator` | ✅ `export-preview.md` |
| Export profiles | iOS, macOS, Android | Named configs: independent metrics, formats, destinations, schedules; overlap detection | `ExportProfilesView`, `Shared/Models/ExportProfileOverlapDetector.swift`, `Shared/Managers/ExportProfileCoordinator.swift` | ✅ `export-profiles.md` |
| Export history & retry | iOS, macOS, Android | Review results, retry failed dates (Room DB on Android) | `ExportHistory`, `ScheduleSettingsView`; android `data/history/` | ✅ `export-history-retry.md` |
| Export issue guidance | iOS, macOS | In-app guidance/help sheets for export problems | `ExportIssueGuidance.swift`, `ExportFormatHelpSheet.swift` | 🟡 permission guidance in `healthkit-permissions.md` |
| Exported Markdown viewer | iOS | In-app viewer for generated markdown | `ExportedMarkdownViewer.swift` | 🟡 within `export-preview.md` |
| Export progress banners / Live Activity | iOS | Export activity banners + CLI export Live Activity | `iOS/Components/*Banner*.swift`, `CLIExportLiveActivity*` | 🟡 within `scheduled-exports.md` + `widgets.md` |
| Awake/foreground coordination | Android | Keep-export-awake coordination for foreground execution | `data/export/ExportAwakeCoordinator.kt` | 🔧 |
| Export performance lab | iOS, macOS (debug) | Instrumentation, lab telemetry, API sink; release-absence checked | `iOS/Debug/IPhoneExportPerformanceLabCoordinator.swift`, `scripts/export-performance-lab.py` | 🔧 internal testing docs |
| Export engine parity machinery | iOS (internal) | Legacy/shadow/Rust planner comparator, pins, rollout copy, evidence recorder | `Shared/ExportEngine/*` | 🔧 internal (ADR-0001, rollout runbooks) |

## 6. Export destinations

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Vault / files folder destination | iOS, macOS, Android | Obsidian vault, iCloud Drive, Files, or any SAF provider (Drive/OneDrive/Syncthing/Obsidian Sync) | `VaultManager`, SAF storage | ✅ `vault-folder-selection.md`, android README |
| Mac destination (iPhone → Mac) | iOS, macOS | Encrypted, bounded, checksum-validated transfer over Multipeer Connectivity; partitioned connected transfer; sync event history | `SyncService.swift`, `ConnectedTransfer`, `SyncStateMachine` | ✅ `mac-sync.md`; ref `connected-mac-iphone-protocol.md` |
| API endpoint export | iOS, Android | POST Apple v8 JSON / `healthmd.api_export` envelope to user HTTP(S) endpoint; Android: encrypted Bearer/Basic + custom headers, EncryptedSharedPreferences, scheduled uploads, target-aware retries | `APIExportClient`, `APIEndpointExportRunner`; android `data/export/API*` | ✅ `api-endpoint-export.md` (both) |
| Raw snapshot streaming upload | Android | Separate HTTPS-only, no-redirect, header-validated streaming contract; temp artifact deleted after attempt | `RawSnapshotApiClient.kt`, `RawSnapshotExportRunner.kt` | ✅ raw docs |
| CLI destination | iOS, Android | Production-generated files streamed to computer filesystem via direct protocol | CLI `export --destination` | ✅ CLI README + skill |
| Connected corpus transfer | iOS, macOS | iPhone → Mac canonical raw corpus spool/transfer, recovery | `IPhoneConnectedCorpusProducer`, `ConnectedCorpus*` | 🟡 cli-mac-iphone-export.md |

## 7. Automation

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Scheduled exports | iOS, macOS, Android | Recurring exports at chosen time; APNs push registration (Apple), notifications, missed-date recovery, boot rescheduling (Android WorkManager) | `SchedulingManager`, `ExportNotificationScheduler`, `PushRegistrationManager`; android `data/scheduler/*Worker.kt` | ✅ `scheduled-exports.md`; website `scheduling.md` |
| Per-profile schedules | iOS, macOS, Android | Independent schedules per export profile | `ProfileScheduleSection`; android `ScheduledProfileExportWorker` | 🟡 export-profiles/scheduled docs |
| Apple Shortcuts / App Intents | iOS | 9 intents: export range/date/last-N/yesterday, get summary, get export status, toggle schedule, App Shortcuts provider | `iOS/AppIntents/*` | ✅ `apple-shortcuts.md`; website `shortcuts.md` |
| Explicit broadcast automation intents | Android | Tasker/adb explicit broadcast receiver triggers exports | `automation/AutomationReceiver.kt`, `docs/android-automation-intents.md` | ✅ android doc |
| Launcher shortcuts | Android | Export / Schedule / History shortcuts | res shortcuts | 🟡 android README |
| Deep links / exported routes | Android | Handled initial routes incl. shared-setup import | `HealthMdNavigation.kt` | 🟡 |
| `healthmd://` URL scheme | iOS | Custom URL scheme registered for external deep links | `HealthMd/Info.plist` (`CFBundleURLSchemes`) | 🔧 |
| Agent-local API (loopback) | macOS | `/v1/agent/*` on port 17645: capabilities, metrics, readiness, query, evidence, refresh, durable jobs | `HealthMdAgentAPIService.swift`, `HealthMdControlServer.swift` | ✅ `agent-local-api.md`; website `agent-api.md` |

## 8. Developer & agent surfaces (CLI / MCP / queries)

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| `healthmd status` / `direct devices` / `unpair` / `reset-trust` | CLI | Readiness, device inventory, trust management | `healthmd-cli/src/main.rs` | ✅ README + skill |
| `healthmd export` (raw / files / Android) | CLI | Raw JSON/NDJSON, production-generated files (iOS v1 / Android v2), provider + format flags, `--allow-partial` | main.rs, `healthmd-client` | ✅ |
| `healthmd extract` | CLI | Scoped canonical extraction projection (iOS v1) incl. JSONL | main.rs | ✅ website `cli-extract.md` |
| `healthmd query <op>` | CLI | Typed operations through the same registry/evaluator as MCP (iOS query v3) | main.rs, `healthmd-operations` | ✅ |
| `healthmd resume` / `cancel` | CLI | Durable job resume/cancel (7-day jobs) | main.rs, `job.rs`/`v2_job.rs` | ✅ website `cli-jobs.md` |
| `healthmd direct pair` | CLI | iOS 6-digit / Android 20-digit pairing; QR code; LAN + Tailscale addresses | `pairing.rs` | ✅ |
| `healthmd setup codex` | CLI | Guided Codex MCP host config + pairing | `onboarding.rs` | ✅ skill |
| `healthmd mcp serve` / `serve-read-only` | CLI, macOS | Full 19-tool local MCP; 13-tool read-only profile, stdio | `healthmd-mcp`, `mcp-tools-v1.json` | ✅ `local-mcp.md`, `remote-mcp.md`; website `mcp.md` |
| `healthmd mcp serve-http` | CLI | Loopback Streamable HTTP with Host/Origin allowlists + optional OAuth resource server (JWT/JWKS) | `transport/streamable_http.rs`, `auth/jwt.rs` | ✅ `remote-mcp.md` |
| `healthmd mcp schema` | CLI | Offline fixed tool JSON-Schema catalog | main.rs | ✅ |
| MCP tool catalog (19 tools) | CLI, macOS | status/doctor/capabilities/metrics; metric_chart (PNG/HTML), sleep_sessions, training_alignment, workouts, coverage, compare_periods, training_evidence; query, evidence_packet; pairing_start/status; export_files + job status/resume/cancel | `healthmd-operations/src/registry.rs`, assets | ✅ reference/generated/automation |
| Evidence packets / query manifests | macOS, CLI, iOS | `healthmd.evidence_packet` v1, `healthmd.query_request/response/error` v1 paged typed queries | `Shared/Query/*`, `docs/reference/evidence-packets.md` | 🟡 reference docs only (not in features index) |
| Encrypted query-context store | macOS | AES-256-GCM per-day encrypted local context, Keychain device key | `EncryptedHealthContextStore.swift` | ✅ page exists but missing from features index |
| Bounded encrypted query executor | macOS | Bounded-memory paged execution over encrypted context | `EncryptedHealthContextQueryExecutor.swift` | ✅ page exists but missing from features index |
| Bundled CLI distribution | macOS | `healthmd` + `healthmd-mcp` bundled in Mac app; Install for Terminal; Codex/Claude connect; agent skill install | `HealthMdCLI/`, `MacCLIView.swift`, `scripts/healthmd` | ✅ `cli-distribution.md` |
| Credential helper + OS keychain | CLI | OS credential store integration, credential-helper protocol, supervision probe | `credentials.rs` | 🔧 internal |
| Remote MCP relay profile | CLI | `RemoteReadOnly` surface profile for remote relay identity | `healthmd-operations/src/model.rs` | 🟡 remote-mcp.md |

## 9. Device sync & direct protocol

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Direct iPhone service | iOS | Foreground iPhone serves export protocol v1 / query protocol v3 to CLI/MCP; QR pairing scanner | `IPhoneDirectCLIService.swift`, `DirectCLIPairingScannerView.swift` | ✅ `cli-direct-iphone.md`; website `cli-direct.md` |
| Manual IP / Tailscale sync | iOS, macOS, CLI | Direct TCP connect-by-address fallback (ports 17646/17647) | `MacIPhoneExportRequestCoordinator.swift` | ✅ `manual-ip-sync.md` |
| Direct protocol v1 (iOS) | contract | TCP listener, 6-digit code, 2 MiB packets, 512 KiB chunks, 7-day jobs, immutable fingerprints | `packages/contracts/direct-protocol/v1/` | ✅ protocol docs |
| Direct protocol v2 (Android) | contract | 20-digit pairing, provider-native raw + generated files, fail-closed | `direct-protocol/v2/` | ✅ |
| Query protocol v3 (iPhone) | contract | Typed query capability: coverage, series, sleep sessions, workouts, alignment, packets; cursors; page caps | `direct-protocol/v3/` | ✅ |
| Direct CLI pairing UI | Android | Settings → Direct CLI; 20-digit code; visible data-sync foreground service; Keystore trust; resumable 7-day transfers; private spools | `presentation/directcli/DirectCliScreen.kt`, `direct-protocol/` Kotlin | ✅ android README + desktop-destination doc |
| CLI-triggered Mac↔iPhone export | iOS, macOS | Trigger export on connected open iPhone from Mac/CLI, file mode, strict raw profile | `MacExportJobBuilder`, `SyncPayload.swift` | ✅ `cli-mac-iphone-export.md` |
| Corpus export session & recovery | iOS, macOS | Corpus producer, progress journal, recovery manager | `IPhoneCorpusExportRecoveryManager.swift` | 🟡 |

## 10. Widgets & wearables

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| iOS home-screen widgets | iOS | HealthSummary, ActivityRings, HeartRange, SleepSummary; small/medium/large + accessories | `HealthMdWidgets/HealthWidgets.swift` | ✅ `apps/apple/docs/features/widgets.md` |
| CLI Export Live Activity | iOS | Live Activity showing CLI export progress | `HealthMdWidgets/CLIExportLiveActivityWidget.swift` | ✅ within `widgets.md` |
| Watch app | watchOS | Watch dashboard from health snapshot | `HealthMdWatch/WatchDashboardView.swift` | ✅ `apps/apple/docs/features/watch-app.md` |
| Watch widgets | watchOS | DailyActivity, Recovery, Steps, MoveEnergy, ExerciseMinutes, StandHours, Sleep, RestingHeartRate, HRV, BloodOxygen | `HealthMdWatchWidgets/WatchHealthWidgets.swift` | ✅ within `watch-app.md` |
| Android home-screen widgets | Android | Glance: Health Summary, Activity, Heart Range, Sleep; 14-day no-backup snapshot; 7-day charts; permission-revocation pulse; no lock-screen measurement widgets | `widget/` package | ✅ `docs/features/widgets.md` |
| Wear OS tiles | Wear | DailyActivity + Recovery tiles | `wear/.../surface/HealthTiles.kt` | ✅ `wear-os-implementation.md` + website `guides/wear-os` (canonical EN, translations pending) |
| Wear OS complications | Wear | 10 metric complications (activity, recovery, steps, move, exercise, sleep, RHR, avg HR, HRV, SpO2) | `wear/.../surface/HealthComplications.kt` | ✅ wear docs |
| Wear data layer sync | Wear, Android | Phone-authoritative aggregate transport, diagnostics provider, invalidation | `wear/.../sync/`, `wearable-contract/` | ✅ |

## 11. Third-party integrations & providers

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| WHOOP integration (beta) | iOS | OAuth via broker worker; typed `providers.whoop` v1 section (cycle/recovery/sleep/workout/snapshot) + native sidecars; gated `CONNECTED_APPS_WHOOP_ENABLED` | `Shared/Integrations/WHOOPProviderSections.swift`, `worker/oauth-broker/` | ✅ `third-party-integrations.md` (Beta) |
| Dormant provider prototypes | iOS | Fitbit, Oura, Withings, Strava implemented but deferred | `ExternalProviderAPIClient.swift` | 🟡 third-party doc |
| Cloud raw providers | Android | Fitbit/Oura/WHOOP/Withings raw snapshots: exact provider response bytes, pagination disclosure; unsupported providers reported | `rawexport/CloudRawHealthDataProvider.kt`, `RawHealthRepositoryRegistry.kt`, OAuth callback `presentation/oauth/` | ✅ `health-provider-support.md`, cloud-raw-provider-ledger |
| OAuth broker worker | cloud | Token-free OAuth code exchange/refresh relay | `worker/oauth-broker/src/index.ts` | 🟡 third-party doc |
| Obsidian plugin (external) | external | Community visualizations plugin; separate repo; onboarding demo + JSON consumers | external repo `health-md-visualizations` | ✅ website visualizations docs |

## 12. Clinician & practice surfaces

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Clinician report (in-app) | iOS, Android | Configurable clinician report → PDF → share; date presets; freeze-while-busy | `iOS/ClinicianReport/*`; android `presentation/clinicianreport/` | ❌ feature page (spec: root `docs/features/clinician-report-v1.md`) |
| Practice portal (synthetic) | Practice | Production-disabled clinician portal foundation: 26 fixed routes, one `POST /api/v1/operation` synthetic simulator, tenant/MFA/CSRF/audit models as test doubles, pilot protocol + EHR discovery docs | `apps/practice/src/*`, `docs/product/practice/` | ✅ practice docs (component-scoped) |
| Practice feature policy gate | iOS | In-app policy gating clinician-portal features | `Shared/Practice/PracticeFeaturePolicy.swift` | 🔧 |

## 13. Purchases, paywall & monetization

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Full Access unlock | iOS, macOS | StoreKit 2; 10 free exports; subscription + Individual/Family Lifetime; Family Sharing; restore | `PurchaseManager.swift`, `PaywallView.swift`, `HealthMd.storekit` (at `apps/apple/HealthMd.storekit`) | ✅ `full-access-unlock.md`; website `paywall.md` |
| Lifetime unlock (Play Billing) | Android | One-time lifetime purchase; 10 free manual export actions; action-based (not file-based) accounting | `data/billing/`, `domain/billing/` | ✅ android README Pricing |
| Paywall screen | iOS, Android | Contextual paywall (onboarding, export limit, schedule limit, settings upgrade) | `PaywallView.swift`; android `presentation/paywall/` | ✅ |
| Pricing experiments | iOS | A/B pricing funnel (lifetime price experiment) with analytics worker | `docs/experiments/*`, `Shared/Analytics/PricingExperiment*` | 🔧 internal experiments docs |
| Pricing analytics worker | cloud | Cloudflare Worker + D1; coarse pseudonymous pricing/onboarding events; no health values | `worker/pricing-analytics/` | 🔧 worker README |
| Install attribution | Android | Play Install Referrer first-party campaign attribution, no general analytics SDK | `data/attribution/`, `docs/campaign-attribution.md` | 🔧 |
| In-app review prompt | Android | User-initiated Play review after successful exports | Play In-App Review | 🔧 |
| Release notes (in-app) | Android | In-app release notes screen | `presentation/release/ReleaseNotes.kt` | 🔧 |
| Marketing/demo sheets | iOS | Demo sheets for metrics/format/tracking/paywall/onboarding (marketing contexts) | `ContentView.swift:346-387` | 🔧 |

## 14. Privacy & security model

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Local-first privacy model | all | No Health.md health-data cloud; every destination user-directed | `privacy-local-first.md`, READMEs | ✅ |
| Encrypted direct transport | iOS, Android, CLI | ChaCha20-Poly1305 `HMDSC001` channels; X25519/HMAC transcript proofs; digest-chained partitions | `healthmd-protocol/src/crypto.rs`, `DirectCrypto.kt` | ✅ protocol docs |
| Private spooling | CLI, Android | Health payloads assembled on private disk spools, never logged | client storage; android no-backup spools | ✅ durability docs |
| Destination binding / path hardening | CLI | Immutable destinations, traversal/symlink rejection, Windows path hardening | `generated_path.rs` | ✅ |
| Credential storage | Android, CLI | Android Keystore + EncryptedSharedPreferences (excluded from backup); CLI OS keychain | `APIExportCredentialStore.kt`, `credentials.rs` | ✅ api-endpoint docs |
| Encrypted Mac context store | macOS | See §8 | | ✅ |

## 15. Community, support & content

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Discord / email feedback / GitHub issues | iOS, macOS | Support section + FeedbackHelper | `SettingsTabView.supportSection` | ✅ `community-feedback.md` |
| Feature video series roadmap | iOS docs | 14-episode roadmap tied to feature pages | `docs/features/video-series.md` | ✅ |
| Website public docs | website | 28 doc pages incl. 10 locales (de, es, fr, it, ja, ko, nl, pt-br, zh-hans + en), guides, reference, blog, visualizations, llms.txt | `apps/website/docs-src/src/content/docs/` | ✅ |
| Release-notes notelet media | iOS | Short in-app release videos/images | `iOS/Resources/ReleaseNotes/` | 🔧 |

## 16. Shared foundations

| Feature | Products | Description | Evidence | Docs |
|---|---|---|---|---|
| Shared Rust core (semantic/render) | core | Deterministic post-capture semantic ingestion + frozen render formats (apple_v8, rollups, android v4/v5) | `healthmd-core/src/{semantic,render}` | ✅ ADR-0001, milestone baselines |
| Rust output profile engine (planned) | core | Native-authoritative → Rust serialization migration, shadow gates | `product-capabilities.json` (planned) | ✅ rollout runbooks |
| UniFFI bindings | core | Swift + Kotlin bindings, xcframework, registry adapters | `healthmd-core-uniffi`, `scripts/generate-*-bindings.sh` | ✅ |
| Share My Setup (portable configuration) | iOS, macOS, Android | Export/review/transactionally import bounded setup profile (no health data/credentials); apply/undo/share; registry entry `planned` pending device QA (contract pre-canonical) | `Shared/SharedSetup/`, `iOS/SharedSetup/SharedSetupCoordinator.swift`; android `sharedsetup/`; contract `shared-setup/v1` | 🟡 `apps/apple/docs/features/share-my-setup.md` (status: needs QA) |
| Semantic-input / render-input contracts | core | Internal post-capture envelope + rendering/artifact-plan contracts | `packages/contracts/{semantic-input,render-input}` | ✅ contract docs |
| Unified v9 proposal | contract | Proposed unified Apple/Android daily contract with platform sections | `proposals/unified-health-data-v9` | ✅ RFC-0004 |

## 17. Release & CI surfaces (meta)

Apple (`apple-ci`, `apple-nightly`, `release-ios`, `release-macos`, `apple-submit-version`, `apple-review-status`, `apple-review-state`, `apple-cancel-review-submission`, `apple-announce`), Android (`android-ci`, `android-release`, promote-production ±recover, announce, wear evidence/screenshots), CLI (`cli-ci`, `cli-release`, `cli-publish-crates`, `cli-sbom`), core (`core-rust-ci`), practice (`practice-ci`), website (`website-ci`). Distribution: App Store, Google Play (incl. Wear same listing), cargo-dist + crates.io + homebrew tap, commit-based website deploys. See root `AGENTS.md` release contract.

---

## Documentation gap analysis

### A. Features with no dedicated docs page (candidates for new pages)
- None remaining. (Website follow-up: translate `guides/raw-snapshots` and `guides/wear-os` into the 9 non-English locales and promote them from canonical-English fallback to authored guides. Android follow-up: editorial pass — screenshots, on-device verification, and public-site selection for the 26 new `apps/android/docs/features/` pages drafted 2026-08-22.)

(Closed 2026-08-22: Clinician Report page drafted and indexed; the four Apple index omissions were added to the table; iOS widgets + Live Activity page drafted and indexed; Watch app + watch widgets page drafted and indexed; Share My Setup page drafted as `needs QA` per its pre-canonical contract and indexed; six minor Apple surfaces folded into existing pages — configuration protection → `manual-export.md`, zip export → `multi-format-export.md`, exported Markdown viewer → `export-preview.md`, permission guidance → `healthkit-permissions.md`, progress banners → `scheduled-exports.md`, Mac menu-bar popup → `mac-sync.md`; Wear OS and Raw API Snapshot public website guides published as canonical-English fallback pages under `guides/` with sidebar entries in all 10 locale labels, verified by i18n:check, website tests, and a full site build.)

### C. Docs-only / weakly-mapped surfaces
- None fully orphaned. `bounded-encrypted-query-executor.md` and `encrypted-query-context-store.md` have thin user-facing UI (Mac settings maintenance buttons) and read as contract docs — consider moving to `docs/reference/` or reframing.
- Query manifests / evidence packets have reference docs but no feature-page framing.

### D. Cross-platform parity flags (from `product-capabilities.json` + ledgers)
- Range/rollup summaries: Apple available, Android planned (v9).
- Share My Setup: planned on both (contract + code staged).
- Apple-only: lossless HealthKit archive, medication dose events, State of Mind, wrist temperature, hearing/symptoms, typed WHOOP section.
- Android-only: activity intensity, planned workouts, menstruation periods, PHR/FHIR, nutrition meals, contextual source fields, skin temperature, cloud raw snapshots (Fitbit/Oura/WHOOP/Withings), raw changes backend.
- Never equivalent (explicitly distinct): HRV SDNN vs RMSSD; wrist vs skin temperature; Apple menstrual flow vs HC period intervals.

## Using this baseline

1. **New feature → add a row** in the matching domain before shipping; docs status starts ❌.
2. **Docs work → flip status** only when a page exists and is linked from the component index (Apple `features/index.md`; website docs nav).
3. **Quarterly audit:** re-run source recon per component; diff against this page; reconcile `product-capabilities.json` for export-contract rows.
4. **Ownership rule:** Apple rows evidence under `apps/apple`, Android under `apps/android`, CLI/MCP under `apps/cli`, contracts under `packages/contracts`, practice under `apps/practice` (synthetic — do not publish as product features).
