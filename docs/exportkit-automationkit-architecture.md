# ExportKit / ExportAutomationKit Architecture

Status: initial architecture for `TODO-3d4a7bd6`
Date: 2026-06-03

This plan defines the package boundaries for extracting Health.md's export engine without changing current product behavior. Later todos should treat this document as the boundary contract and use a strangler strategy: add generic code beside existing Health.md code, prove parity, then route one slice at a time.

For app-facing setup steps and non-Health.md examples, see the [ExportKit / ExportAutomationKit adoption guide](./exportkit-adoption-guide.md).

## Non-negotiable invariants

- Manual Health.md exports stay behavior-compatible.
- Multi-format export keeps current filename ordering and collision behavior, including `Obsidian Bases` receiving `-bases.md` only when Markdown and Obsidian Bases are both selected.
- Folder, subfolder, filename, daily-note, and individual-entry templates keep current placeholder behavior unless a path-safety todo explicitly documents a changed behavior.
- Write modes preserve current semantics:
  - overwrite replaces existing file bytes;
  - append adds `\n\n` plus fresh content;
  - update uses section-aware Markdown merge for Markdown and falls back to overwrite for non-Markdown formats.
- Markdown update mode preserves user sections and frontmatter as `MarkdownMerger` does today.
- Export preview continues to show aggregate files, Daily Note Injection, individual entries, warnings, and truncation.
- Scheduled exports remain behavior-compatible and continue to write to the local iPhone destination, not Connected Mac.
- Server-side APNs registration/schedule sync never sends HealthKit samples, exported file contents, vault paths, or metric values.
- Background failures that represent recoverable work persist pending export requests.
- Tapping fallback notifications retries the exact stored request in the foreground.
- Shortcuts retain local iPhone destination semantics.
- Connected Mac exports keep output parity with local exports.
- `ExportKit` must not depend on HealthKit, Health.md models, `MetricSelectionState`, `HealthMetricsDictionary`, or health metrics.
- `ExportAutomationKit` depends on `ExportKit`, not Health.md.

## 1. Current-state inventory

| Current file / area | Current responsibility | Classification | Target boundary |
|---|---|---|---|
| `HealthMd/Shared/Models/AdvancedExportSettings.swift` | Persisted UI settings for selected formats, metric selection, filename/folder templates, write mode, format customization, individual tracking, Daily Note Injection, granular data. | Mixed; app-specific because it owns `MetricSelectionState`, health categories, UserDefaults, and `ObservableObject`. | Health.md adapter converts this into `ExportKit` value-type settings. Reusable pieces become value types only where health-free. |
| `HealthMd/Shared/Export/ExportPathPlanner.swift` | Computes aggregate folder/file URLs, daily-note paths, relative paths, and daily-note/export collisions. | Mostly reusable, currently coupled to `AdvancedExportSettings` and `DailyNoteInjectionSettings`. | `ExportKit` `ExportPathTemplate`, `ExportPathPlanner`, `PlannedExportFile`. Health adapter supplies template variables and collision roles. |
| `HealthMd/Shared/Managers/VaultManager.swift` | Bookmark persistence, security-scoped destination access, aggregate file writing, write modes, individual entries, daily note injection, status strings. | Mixed. Destination/bookmark/file writer are reusable; HealthData rendering and app status are app-specific. | Split into `ExportDestination`, `DestinationAccess`, `ExportFileWriter` in `ExportKit`; keep `HealthVaultManagerAdapter` in Health.md. |
| `HealthMd/Shared/Managers/ExportOrchestrator.swift` | Date range generation, HealthKit fetch loop, foreground/background export, result classification, history recording. | Mixed. Date loops/results/progress are reusable; HealthKit fetching and Health.md history enums are app-specific. | `ExportKit` orchestrator accepts generic record source/renderers/writer. Health.md adapter maps HealthKit errors and records history. |
| `HealthMd/Shared/Views/ExportPreviewView.swift` | SwiftUI preview UI, preview data fetching, aggregate file previews, Daily Note Injection preview, individual entry preview, warnings, truncation. | Mixed. SwiftUI UI is app-specific; planned-file preview builder/truncation are reusable. | `ExportKit` `ExportPreviewBuilder` + `ExportPreviewDisplayContent`; Health.md keeps SwiftUI view. |
| `HealthMd/Shared/Export/MarkdownMerger.swift` | Section-aware Markdown merge and frontmatter merge. | Reusable with a configurable managed-section strategy. | Move to `ExportKit` as `MarkdownMergeStrategy`; Health.md passes health-managed section names/heading policy. |
| `HealthMd/Shared/Models/ExportHistory.swift` | Export history entries, source enum, failure reasons, manager singleton. | Mixed. Result/failure shape reusable; specific sources and singleton persistence are app-specific. | `ExportKit` result/failure model; `ExportAutomationKit` trigger/source model; Health.md history adapter persists display entries. |
| `HealthMd/Shared/Export/ExportDataSnapshot.swift`, `HealthMetricsDictionary.swift`, `MarkdownExporter.swift`, `JSONExporter.swift`, `CSVExporter.swift`, `ObsidianBasesExporter.swift` | Health-specific snapshot extraction and format rendering. | App-specific renderers. | Stay in Health.md as renderers implementing `ExportKit` protocols. Non-health sample added later proves genericity. |
| `HealthMd/Shared/Export/DailyNoteInjector.swift` | Health metric injection into daily notes; frontmatter merge; optional section merge; preview. | Plugin pattern is reusable; metric extraction is app-specific. | `ExportKit` plugin interface and Markdown merge helper; Health.md `HealthDailyNoteInjectionPlugin`. |
| `HealthMd/Shared/Managers/IndividualEntryExporter.swift` and `IndividualTrackingSettings.swift` | Extract individual Health samples and write timestamped Markdown entry files. | Plugin pattern reusable; sample extraction and metric categories app-specific. | `ExportKit` supplemental file/plugin interface; Health.md individual-entry plugin/adapter. |
| `HealthMd/Shared/Models/ExportSchedule.swift`, `HealthMd/Shared/Utilities/ScheduleDateMath.swift` | Schedule config, lookback, date math, persistence. | Mostly reusable except direct UserDefaults extension and product defaults. | `ExportAutomationKit` value model and schedule calculator; Health.md persistence adapter. |
| `HealthMd/iOS/SchedulingManager.swift` | iOS BGTask/HealthKit background delivery/silent-push handling, pending request drain, notification-tap retry, catch-up, paid-gate and HealthData export runner. | Mixed. Automation flow is reusable; platform APIs, purchase checks, and HealthKit record source are app-specific adapters. | `ExportAutomationKit` runner/coordinator protocols; Health.md iOS adapter wires BGTask, HealthKit, purchase, notifications. |
| `HealthMd/Shared/Managers/ScheduledExportCoordinator.swift` | Creates pending scheduled requests, schedules fallback notifications, completes/clears/preserves requests. | Reusable automation core. | Move to `ExportAutomationKit` using generic pending request/result protocols. |
| `HealthMd/Shared/Models/PendingExportRequest.swift` | Pending request model/store for scheduled and Shortcut exports. | Reusable with generalized trigger source and metadata. | `ExportAutomationKit` `PendingExportRequest`, store protocol, UserDefaults store implementation. |
| `HealthMd/Shared/Notifications/ExportNotificationScheduler.swift` | Pending export notification identifiers, payload parsing, local notification scheduler. | Mostly reusable but `UserNotifications`-specific. | `ExportAutomationKit` notification payload/scheduler behind protocols; keep platform adapter guarded by `#if canImport(UserNotifications)`. |
| `HealthMd/Shared/Managers/PushRegistrationManager.swift` | APNs token capture, user identity, device registration, schedule upsert. | Reusable remote schedule client plus Health.md endpoint/config. | `ExportAutomationKit` `RemoteScheduleClient` protocol and payloads; Health.md config supplies endpoint and auth. |
| `HealthMd/iOS/AppIntents/ExportIntentRunner.swift` | Shortcut export runner, paywall gate, local vault semantics, pending Shortcut request on device lock. | Mixed. Shortcut trigger flow/pending retry is reusable; App Intents and Health.md purchase/history are app-specific. | Health.md shortcut adapter calls `ExportAutomationKit` trigger runner with `.shortcut`. |
| `HealthMd/Shared/Sync/MacExportJobBuilder.swift`, `HealthMd/Shared/Models/ExportSettingsSnapshot.swift`, `HealthMd/macOS/Managers/MacExportJobExecutor.swift` | iOS builds HealthData snapshots plus settings; Mac writes received records with local destination. | Mixed. Snapshot/write parity concept reusable; payload records are Health-specific. | `ExportKit` portable export profile snapshot; Health.md record payload and sync message stay app-specific. |
| `worker/pricing-analytics/*` | Pricing analytics worker. Its `wrangler.toml` explicitly forbids health values, metric names, vault/file paths, or exported content. | Not the scheduled APNs worker implementation in this checkout. | Later server contract todo should document/add scheduled worker contract separately and preserve the no-health-data rule. |
| `HealthMd/Shared/Protocols/RuntimeProtocols.swift`, `ProductionAdapters.swift` | Runtime seams for UserDefaults, bookmarks, filesystem, HTTP. | Reusable pattern. | Equivalent protocols move into packages where they are package-owned; Health.md can keep adapters or wrap them. |

## 2. Proposed modules and dependency direction

### Package layout

Create a Swift package, preferably under `Packages/ExportKits/`, with two public products:

```swift
// Packages/ExportKits/Package.swift
.products: [
  .library(name: "ExportKit", targets: ["ExportKit"]),
  .library(name: "ExportAutomationKit", targets: ["ExportAutomationKit"])
]
.targets: [
  .target(name: "ExportKit"),
  .target(name: "ExportAutomationKit", dependencies: ["ExportKit"]),
  .testTarget(name: "ExportKitTests", dependencies: ["ExportKit"]),
  .testTarget(name: "ExportAutomationKitTests", dependencies: ["ExportAutomationKit"])
]
```

If Xcode project package integration becomes the bottleneck, first add sources in a Health.md-local folder named after these modules with the exact same API names, then move them into the package once the APIs compile. The intended product boundary remains the package above.

### Dependency graph

```text
Health.md iOS/macOS app
  ├─ Health-specific adapters/renderers/plugins
  ├─ App UI, App Intents, HealthKit, purchase/history/analytics, sync
  └─ depends on ExportAutomationKit and ExportKit

ExportAutomationKit
  ├─ trigger sources, schedule math, pending requests, retry coordinator
  ├─ notification and remote-schedule protocols/adapters
  └─ depends on ExportKit only

ExportKit
  ├─ generic export records, formats, renderers, path planning, writer
  ├─ write modes, merge strategies, preview builder, result/progress model
  └─ depends on Foundation only where possible
```

Rules:

- `ExportKit` has no `HealthKit`, `SwiftUI`, `UserNotifications`, `BackgroundTasks`, App Intents, Health.md models, or analytics dependencies.
- `ExportAutomationKit` may expose platform-neutral protocols and optional platform adapters, but no Health.md types.
- Health.md owns conversion from `AdvancedExportSettings`, `HealthData`, `MetricSelectionState`, `HealthKitManager`, and sync payloads.

## 3. Core protocols/types API sketch

The sketches below are boundary contracts, not final implementation code.

### ExportKit values and renderer registry

```swift
public struct ExportFormatDescriptor: Hashable, Codable, Sendable {
    public var id: String              // "markdown", "json", "csv", "obsidianBases"
    public var displayName: String
    public var fileExtension: String
    public var defaultSortKey: String  // preserve current alphabetical-by-rawValue order via adapter
}

public protocol ExportRecord: Sendable {
    var exportRecordID: String { get }
    var exportDate: Date { get }
}

public struct ExportRenderContext: Sendable {
    public var locale: Locale
    public var calendar: Calendar
    public var userInfo: [String: String]
}

public struct RenderedExport: Sendable, Equatable {
    public var content: String
    public var contentType: String     // "text/markdown", "application/json", etc.
}

public protocol ExportRenderer<Record>: Sendable {
    associatedtype Record: ExportRecord
    var descriptor: ExportFormatDescriptor { get }
    func render(record: Record, context: ExportRenderContext) throws -> RenderedExport
}

public struct AnyExportRenderer<Record: ExportRecord>: Sendable {
    public var descriptor: ExportFormatDescriptor
    public var render: @Sendable (Record, ExportRenderContext) throws -> RenderedExport
}

public struct ExportRendererRegistry<Record: ExportRecord>: Sendable {
    public var renderersByFormatID: [String: AnyExportRenderer<Record>]
}
```

Health.md renderers wrap existing `HealthData.export(format:settings:)` initially, then render directly from `ExportDataSnapshot` after parity tests exist.

### Path planning and safety

```swift
public struct ExportPathTemplate: Codable, Sendable, Equatable {
    public var folderTemplate: String
    public var filenameTemplate: String
    public var fileExtension: String
}

public struct ExportPathVariables: Sendable, Equatable {
    public var date: Date
    public var values: [String: String] // date, year, month, day, weekday, monthName, quarter, app-specific extras
}

public enum ExportPathSafetyPolicy: Sendable, Equatable {
    case preserveCurrentBehavior       // trim/split slash, drop empty segments
    case rejectTraversalAndAbsolutePaths
    case sanitizePathComponents
}

public struct PlannedExportFile: Identifiable, Sendable, Equatable {
    public enum Role: Sendable, Equatable {
        case aggregate(formatID: String)
        case supplemental(pluginID: String)
        case mutation(pluginID: String) // e.g. daily note injection into existing file
    }

    public var id: String
    public var role: Role
    public var relativePath: String
    public var destinationURL: URL?
    public var content: String
    public var warnings: [ExportWarning]
}
```

`TODO-add4f202` implementation decision: preserve `ExportPathPlanner.pathSegments` compatibility for safe/display paths (trim the full string, split by `/`, drop empty segments, keep slash-created nested folders), and use `.rejectTraversalAndAbsolutePaths` for write paths. Health.md production writes now reject `..`, absolute paths, and NUL-containing components instead of silently rewriting them; `.sanitizePathComponents` exists for future adopters that explicitly choose rewrite semantics.

### Destination, bookmark access, and writer

```swift
public struct ExportDestination: Sendable, Equatable {
    public var rootURL: URL
    public var displayName: String
    public var baseRelativePath: String // Health.md's `healthSubfolder`, e.g. "Health"
}

public protocol DestinationAccess: Sendable {
    func withAccess<T>(to destination: ExportDestination, _ operation: @Sendable () throws -> T) throws -> T
}

public protocol ExportFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func readString(at url: URL) throws -> String
    func writeString(_ value: String, to url: URL, atomically: Bool) throws
}

public enum ExportWriteMode: String, Codable, Sendable {
    case overwrite
    case append
    case update
}

public protocol ExportMergeStrategy: Sendable {
    func merge(existing: String, new: String, file: PlannedExportFile) throws -> String
}

public struct MarkdownMergeStrategy: ExportMergeStrategy {
    public var managedSectionNames: Set<String>
    public var preservePreamble: Bool
}

public struct ExportFileWriter: Sendable {
    public var fileSystem: ExportFileSystem
    public var mergeStrategies: [String: any ExportMergeStrategy] // keyed by format/content type
}
```

`TODO-b660fec5` implementation decision: stage destination/bookmark/writer APIs locally in `HealthMd/Shared/ExportKit/ExportDestinationWriting.swift`; keep `VaultManager` as the Health.md facade for status strings, side effects, and user settings. Generic writer creates missing parent directories, applies `.rejectTraversalAndAbsolutePaths`, writes atomically by default, and reports per-file results.

`TODO-8671cf6d` implementation decision: add generic `ExportWriteMode`, `ExportMergeStrategy`, `ExportFileWriteAction`, writer overloads for overwrite/append/update, and `MarkdownMergeStrategy` beside the existing writer code. `MarkdownMergeStrategy` ports the previous section/frontmatter algorithm while keeping managed-section names caller-supplied and domain-free. `MarkdownMerger` is a Health.md compatibility facade that supplies the app-owned managed section names for aggregate update mode and Daily Note Injection. `VaultManager` maps the persisted/UI `WriteMode` into `ExportWriteMode` and supplies a Markdown merge strategy only for `.markdown`; update mode for JSON, CSV, and Obsidian Bases intentionally has no strategy and therefore falls back to overwrite, matching prior behavior.

### Orchestrator, progress, and results

```swift
public struct ExportRequest<Record: ExportRecord>: Sendable {
    public var records: [Record]
    public var formatIDs: [String]
    public var destination: ExportDestination
    public var pathVariables: @Sendable (Record, ExportFormatDescriptor) -> ExportPathVariables
    public var writeMode: ExportWriteMode
    public var plugins: [AnyExportPlugin<Record>]
}

public enum ExportProgress<RecordID: Sendable>: Sendable {
    case planning(totalRecords: Int)
    case rendering(recordID: RecordID, formatID: String)
    case writing(relativePath: String)
    case completed(ExportRunResult)
}

public struct ExportRunResult: Sendable, Equatable {
    public var successCount: Int
    public var totalCount: Int
    public var filesWritten: Int
    public var failedRecords: [ExportFailedRecord]
    public var warnings: [ExportWarning]
    public var wasCancelled: Bool
}
```

The Health.md adapter maps `ExportRunResult` to the current `ExportOrchestrator.ExportResult` until the app fully migrates.

`TODO-6763a336` implementation decision: stage generic orchestration APIs locally in `HealthMd/Shared/ExportKit/ExportOrchestration.swift` rather than creating the package target yet. The generic layer owns `ExportDateWindowRequest`, record references, data-source and writer closure adapters, progress events, cancellation handling, structured run failures/results, and a generic `ExportHistoryEvent`. It deliberately has no Health.md, HealthKit, vault, Obsidian, or metric dependencies. Health.md manual foreground exports now call `ExportRunOrchestrator` through thin closures: Health.md still fetches `HealthData`, preserves `ExportPartialFailure` warnings, and delegates writes/status/side effects to `VaultManager`. Background/scheduled, Shortcut, Connected Mac, preview, Daily Note Injection, and individual-entry plugin flows are not rerouted by this slice. Generic no-destination/no-format preflight maps back to the existing Health.md `ExportResult` failure semantics (`noVaultSelected` and `unknown` with the no-format details respectively), and generic no-data/cancellation/partial-failure results map into the existing history UI models.

### Preview builder

```swift
public struct ExportPreview: Sendable, Equatable {
    public var plannedFilesByRecord: [Date: [PlannedExportFile]]
    public var warnings: [ExportWarning]
    public var totalRecordCount: Int
    public var renderedRecordCount: Int
}

public struct ExportPreviewBuilder<Record: ExportRecord>: Sendable {
    public var maxRenderedRecords: Int
    public var maxFetchAttempts: Int
    public func buildPreview(from request: ExportRequest<Record>) async throws -> ExportPreview
}

public struct ExportPreviewDisplayContent: Sendable, Equatable {
    public var text: String
    public var originalByteCount: Int
    public var omittedByteCount: Int
}
```

Keep the current 5 rendered dates / 14 fetch attempts and 64 KB truncation defaults unless explicitly changed by the preview todo.

`TODO-67d6341c` implementation decision: stage generic preview APIs locally in `HealthMd/Shared/ExportKit/ExportPreviewBuilding.swift`. `ExportPreviewBuilder` owns newest-first fetch attempts, max rendered records, selected-format rendering through `ExportRendererRegistry`, planned aggregate file creation, supplemental/mutation preview plans, generic warning aggregation, and no-write preview results. `ExportPreviewDisplayContent` now lives in ExportKit and preserves Health.md's 64 KB head/tail truncation behavior. `PlannedExportFile` carries generic preview metadata (`format`, `contentType`, `displayName`, `estimatedByteCount`) plus computed filename/folder/size/display-content helpers. Health.md keeps `ExportPreviewView` and app-specific preview adapters in `HealthExportPreviewBuilder`, which map HealthData filtering, Daily Note Injection previews, individual entry previews, and Health.md warning copy into generic planned files without adding Health.md concepts to ExportKit. Background/scheduled, plugin routing, and write paths were intentionally not changed by this preview slice.

### Plugins

```swift
public enum ExportPluginOperation {
    case preview
    case validation
    case write
}

public struct ExportPluginContext<Record: ExportRecord> {
    public var record: Record
    public var operation: ExportPluginOperation
    public var destination: ExportDestination?
    public var aggregateFiles: [PlannedExportFile]
    public var writeMode: ExportWriteMode
    public var userInfo: [String: String]
}

public protocol ExportPlugin {
    associatedtype Record: ExportRecord
    var id: String { get }
    func validate(record: Record, context: ExportPluginContext<Record>) throws -> [ExportWarning]
    func planFiles(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginPlan
    func performSideEffects(record: Record, context: ExportPluginContext<Record>) throws -> ExportPluginRunResult
}

public struct AnyExportPlugin<Record: ExportRecord> { /* type erasure */ }
public struct ExportPluginRunner<Record: ExportRecord> { /* validate / plan / perform */ }
```

Health.md Daily Note Injection and individual entry exports become plugins. Aggregate exports stay first-class planned files.

`TODO-0321050f` implementation decision: stage plugin APIs locally in `HealthMd/Shared/ExportKit/ExportPlugins.swift`. The generic layer owns plugin operation/context values, type erasure, plugin plans/results, mutation-vs-aggregate collision detection, and a runner for validation, preview planning, and post-aggregate side effects. It deliberately has no Health.md, HealthKit, vault, Obsidian, or metric dependencies. Health.md implements `HealthDailyNoteInjectionPlugin` as a `.mutation(pluginID:)` plugin and `HealthIndividualEntryExportPlugin` as a `.supplemental(pluginID:)` plugin in `HealthMd/Shared/Export/HealthExportPlugins.swift`. Daily Note Injection validation now rejects aggregate output collisions before aggregate writes and maps back to the existing `ExportError.dailyNotePathConflict`; preview and writes still delegate to `DailyNoteInjector.preview`/`inject` to preserve create-if-missing, frontmatter, and markdown-section merge behavior. Individual entries keep Health-specific sample extraction in Health.md and write plugin-planned Markdown files through the generic `ExportFileWriter` in overwrite mode. `VaultManager` now runs plugin validation and side effects once per exported record/date after all selected aggregate formats are written. `HealthExportPreviewBuilder` uses the same plugins for Daily Note and individual-entry preview rows/warnings. Aggregate export routing, background automation, Shortcut, and Connected Mac behavior were otherwise intentionally left unchanged by this slice.

`TODO-b800e4a5` implementation decision: add a Health.md-owned `HealthAggregateExportAdapter` in `HealthMd/Shared/Export/HealthAggregateExportAdapter.swift` and route `VaultManager` foreground/manual plus caller-managed background aggregate writes through it. The adapter is intentionally app-specific: it bridges `AdvancedExportSettings`, `HealthExportRecord`, and Health.md renderers into generic ExportKit descriptors/renderers, `ExportPathTemplate` planning, `PlannedExportFile`, and `ExportFileWriter`. Production aggregate planned files are vault-root-relative and are written to `ExportDestination(rootURL: vaultURL)` so Daily Note Injection and individual-entry plugin paths remain in the same root-relative coordinate space. Multi-format ordering and collision filenames still come from `ExportRendererRegistry`/Health descriptors; Obsidian Bases receives `-bases` only when Markdown and Bases collide. Markdown update mode supplies a `MarkdownMergeStrategy` configured with Health.md-managed section names only for the Markdown aggregate format, leaving JSON/CSV/Obsidian Bases update mode as overwrite fallback. Preview aggregate rows and plugin aggregate contexts now use the same adapter in preserve-current-behavior mode; production writes use reject-traversal safety. Scheduled automation, Shortcut semantics, server/APNs, and connected-Mac job shape were not otherwise migrated.

`TODO-890757af` implementation decision: stage generic ExportAutomationKit schedule APIs locally in `HealthMd/Shared/ExportAutomationKit/ExportAutomationScheduling.swift`. The generic layer owns `AutomationScheduleFrequency`, `AutomationSchedule`, timezone-aware `AutomationScheduleDateMath`, `AutomationExportDateWindow`, and a `PersistedAutomationConfiguration`/`AutomationExportRequestConfigurationSnapshot` store shape for app-supplied ExportKit request snapshots. It deliberately has no Health.md, HealthKit, health metrics, vault path, APNs, BGTask, notification, or server dependencies. Health.md `ExportSchedule` remains the UserDefaults-compatible persisted/UI model with `Daily`/`Weekly` raw values and bridges into `AutomationSchedule`; `ScheduleDateMath` is now a compatibility facade over the generic date math. Current behavior is preserved: lookback defaults/clamping stay 1/7 and 1–30, scheduled windows end yesterday, latest occurrence keys remain stable, weekly on-device math remains weekday-agnostic, and catch-up treats `lastExportDate` as the run date that exported the previous data day. `ScheduledExportCoordinator` uses the generic pending occurrence window when creating pending scheduled requests, and iOS app-active catch-up now uses the shared date math. Server/APNs sync, silent-push/BGTask execution, pending store/fallback notification internals, notification-tap retry, trigger-source abstraction, and connected-Mac snapshots were not migrated in this slice.

`TODO-2361fb54` implementation decision: extend the local ExportAutomationKit source with routing-only remote schedule contracts: `RemoteScheduleDeviceRegistrationPayload`, `RemoteSchedulePayload`, `RemoteScheduleUpsertPayload`, `RemoteScheduledExportAPNsPayload`, `RemoteScheduleClient`, `RemoteScheduleRetryPolicy`, and `URLSessionRemoteScheduleClient`. These types are generic and must not carry Health.md, HealthKit, health metrics, exported file contents, vault/folder paths, filename templates, selected metric names, or metric values. Health.md `PushRegistrationManager` now bridges APNs token capture and `ExportSchedule` sync into those generic payloads while preserving the deployed endpoint paths and current schedule sync semantics: stable user/install id, platform, bundle id, APNs token registration, timezone, enabled flag, daily/weekly frequency, hour/minute, and weekly weekday; disabling still sends an upsert with `isEnabled: false`. Generic payloads support optional app version/build metadata for worker migration, but Health.md live calls continue omitting those optional fields until the scheduled worker is updated. The checkout only contains `worker/pricing-analytics/`; the scheduled APNs worker implementation is not present, so `worker/scheduled-apns-worker-contract.md` documents the expected server storage fields, silent APNs headers/body, and no-data rules instead of inventing worker code. Silent push/BGTask execution, pending store/fallback notifications, notification tap retry, trigger-source abstraction, and connected-Mac snapshots remain deferred.

`TODO-fc02b9c1` implementation decision: add a local ExportAutomationKit-compatible scheduled background runner to `ExportAutomationScheduling.swift`: `AutomationBackgroundTrigger`, `AutomationBackgroundExportFailureReason`, `AutomationBackgroundExportResult`, `AutomationPreparedScheduledBackgroundWork`, and `AutomationScheduledBackgroundRunner`. The runner is generic over app-owned pending request/result types, resolves the exact scheduled occurrence/fire date, prepares pending work before export, cancels the matching fallback before attempting work, exposes a pre-export hook for BGTask rescheduling/expiration handlers, and returns domain-free success/failure classification. Health.md `SchedulingManager` now routes silent push, BGTask, and data-source background delivery through one `runAutomaticScheduledExport` adapter while preserving the existing local iPhone export pipeline, paid-gate behavior, exact pending-request date windows, completion/failure notification behavior, history recording, and `lastExportDate` updates only after success. A protected-data availability preflight maps locked-device background attempts to the existing device-locked result before data fetch. Pending request storage/notification internals, notification tap retry, trigger-source normalization beyond these generic trigger labels, and connected-Mac snapshots remain deferred.

`TODO-da038d39` implementation decision: add local ExportAutomationKit-compatible pending export primitives in `AutomationPendingExports.swift`: `AutomationPendingExportRequest`, `AutomationPendingExportStore`, `AutomationPendingExportReason`, configurable notification identifier/payload/planner values, `AutomationPendingExportCompletionPolicy`, and `AutomationPendingScheduledExportRequestBuilder`. These types are domain-free and preserve exact stored retry dates on decode/reason updates, scheduled occurrence replacement, Shortcut date deduping, corrupt-data safe loads, deterministic notification identifiers, stable request/source payload metadata, and fallback trigger timing. Health.md keeps a thin compatibility layer in `PendingExportRequest.swift` plus localized `UserNotificationExportScheduler` copy and the existing `healthmd.*` notification identifiers/userInfo keys. `ScheduledExportCoordinator`, silent-push/BGTask paths, app-active drain, and locked Shortcut requests now route persistence/fallback notification decisions through the generic primitives while preserving current behavior: success clears/cancels; protected-data/device-lock failures preserve and send immediate retry notifications; non-lock failures preserve without duplicate immediate fallback; paid-gate/no-attempt totalCount=0 preserves without a new immediate fallback.

`TODO-647b36f0` implementation decision: extend `AutomationPendingExports.swift` with `AutomationPendingExportNotificationTapRouter` and `AutomationPendingExportForegroundRetryCoordinator`. The router parses configured pending-export payloads from identifier/userInfo and supports app-injected legacy reminder matching without carrying product-specific identifiers in the generic type. The foreground coordinator owns reusable retry orchestration: load a stored request, validate the parsed source, preserve created-at/UUID drain ordering, suppress duplicate in-flight request ids, recheck the request is still pending before execution, ask the app adapter for eligibility, and invoke app-supplied execution/skip callbacks. Health.md wires this coordinator into `SchedulingManager` for notification taps and app-active drains while keeping export execution, history recording, localized `notificationExportResult` alerts, schedule-disabled UX, and Shortcut outcome mapping app-specific. Current behavior is preserved: tapped pending notifications retry exact stored dates; scheduled taps fail visibly when scheduling is disabled; Shortcut pending retries ignore schedule-disabled state; success/partial success clear requests and cancel pending/delivered notifications; protected-data failures preserve requests and send immediate retry notifications.

`TODO-1da5c192` implementation decision: add domain-free trigger/source policy APIs in `ExportAutomationTriggers.swift`: `ExportTriggerSource`, `ExportTriggerSourceFamily`, `ExportTriggerSourcePolicy`, quota/destination/execution policies, and schedule-last-export update policy. The generic policy layer maps manual, scheduled, Shortcut, silent push, BGTask, scheduled wake, data-source background delivery, notification-tap retry, app-active drain, and connected-peer triggers to stable source families without Health.md or HealthKit concepts. Pending requests keep their existing persisted raw source values (`scheduled`, `shortcut`) and bridge to trigger families for source validation and retry policies. Health.md maps source families back to existing history labels (`Manual`, `Scheduled`, `Shortcut`, `iPhone → Mac`), and `ExportOrchestrator.recordResult` now has a trigger-source overload that preserves those labels. Manual local, iPad, macOS manual, Shortcut, scheduled background/retry/catch-up, notification tap, app-active drain, and connected-Mac history/quota call sites now route through the policy where practical. Current behavior is preserved: scheduled/background runs retain local iPhone destination semantics and do not burn free quota; Shortcut exports/retries retain local iPhone destination semantics and count quota once after successful deferred retry; manual and connected-peer exports count at most once per successful user action; schedule `lastExportDate` updates after scheduled success and only for Shortcut runs containing yesterday. Connected-Mac payload shape is not migrated; `MacExportJob.exportTriggerSource` is computed metadata only, leaving `TODO-d38b2d4d` to handle portable snapshots.

`TODO-d38b2d4d` implementation decision: stage connected-Mac portable snapshot APIs locally in `HealthMd/Shared/ExportKit/ExportPortableSnapshots.swift`: `PortableExportProfileSnapshot`, `PortableExportTargetSnapshot`, and `PortableRemoteExportJobSnapshot<RecordPayload>`. The generic profile carries format IDs, aggregate folder/filename templates, write mode, enabled plugin IDs, and metadata without app-specific dependencies. Health.md `ExportSettingsSnapshot` now stores that portable profile as the canonical generic export configuration while keeping Health.md renderer/customization/metric/plugin snapshots app-owned; it also encodes legacy `exportFormats`, `filenameFormat`, `folderStructure`, and `writeMode` fields for mixed-version peer compatibility and can decode older payloads into the portable profile. `MacExportJob` exposes a generic portable job envelope while the sync payload and `HealthData` records remain Health.md-owned local-peer data, not cloud/server transfer. The Mac executor reconstructs temporary `AdvancedExportSettings` from the portable profile plus Health.md snapshots and writes through the same `VaultManager`/`HealthAggregateExportAdapter`/ExportKit writer/plugin pipeline as local exports, returning aggregate files-written counts from actual writer results. Current behavior is preserved: source device and requested target metadata, destination display/path, includeGranularData fetch handling, normalized date ranges, cancellation/busy/preflight/write failures, progress messages, history source label via connected-peer trigger policy, and local-vs-Mac aggregate/Daily Note Injection/individual-entry output parity.

`TODO-971c5a71` implementation decision: add a non-health invoice sample regression suite in `HealthMdTests/Export/NonHealthExportKitSampleTests.swift`. The sample adapter uses Markdown/JSON/CSV renderers, `PortableExportProfileSnapshot`, path templates with app-supplied variables, `ExportFileWriter`, overwrite/append/update modes, custom Markdown merge names, `ExportRunOrchestrator` progress/results, `ExportPreviewBuilder`, a supplemental ledger plugin, and pending scheduled retry via `AutomationPendingScheduledExportRequestBuilder` plus `AutomationPendingExportForegroundRetryCoordinator`. A source-scanning test asserts generic ExportKit/ExportAutomationKit files remain free of Health.md, HealthKit, HealthData, metric-selection, Obsidian, and vault concepts. `MarkdownMergeStrategy` was also made domain-free by moving Health.md-managed section names into the app-specific `MarkdownMerger` facade and `HealthAggregateExportAdapter`; focused Health.md parity tests prove aggregate renderer/writer output remains unchanged.

## 4. Health.md-specific adapters

Health.md must keep the following types app-specific:

- `HealthData` and all nested health data structs.
- `HealthKitManager`, HealthKit query/store protocols, and HealthKit errors.
- `HealthMetrics`, `HealthMetricDefinition`, `HealthMetricCategory`, `HealthMetricExportMapping`, `HealthMetricsDictionary`, and `MetricSelectionState`.
- `AdvancedExportSettings` as the persisted/observable UI model. It can expose or be adapted into generic value snapshots, but `ExportKit` must not import it.
- `FormatCustomization`, `FrontmatterConfiguration`, `MarkdownTemplateConfig`, `IndividualTrackingSettings`, and `DailyNoteInjectionSettings` remain Health.md-owned until split into health-free value types. Their health metric key catalog is app-specific.
- `PurchaseManager`, `PricingAnalyticsClient`, `ReviewManager`, and UI status strings.
- App Intents declarations and dialogs.
- iOS/macOS sync message types that transport `HealthData` records.

Proposed Health.md adapter layer:

```swift
struct HealthExportRecord: ExportRecord {
    let healthData: HealthData
    var exportRecordID: String { /* yyyy-MM-dd */ }
    var exportDate: Date { healthData.date }
}

struct HealthExportProfile {
    let formats: [ExportFormatDescriptor]
    let writeMode: ExportWriteMode
    let aggregatePathTemplate: ExportPathTemplate
    let formatCustomization: FormatCustomization
    let metricSelection: MetricSelectionState
    let includeGranularData: Bool
}

enum HealthExportProfileAdapter {
    static func makeProfile(from settings: AdvancedExportSettings, healthSubfolder: String) -> HealthExportProfile
    static func makeRenderers(from settings: AdvancedExportSettings) -> ExportRendererRegistry<HealthExportRecord>
    static func makePlugins(from settings: AdvancedExportSettings, vaultRoot: URL?) -> [AnyExportPlugin<HealthExportRecord>]
}
```

Adapter responsibilities:

- Preserve existing format order: `settings.exportFormats.sorted { $0.rawValue < $1.rawValue }`.
- Preserve filename collision behavior: Obsidian Bases uses `-bases` only if both Markdown and Obsidian Bases are selected.
- Preserve Health.md status strings until UI is migrated.
- Preserve `healthSubfolder` as the aggregate export base path.
- Preserve Daily Note Injection path base as vault root, not `healthSubfolder`.
- Preserve Shortcut exports as local iPhone-folder exports even when the manual target is Connected Mac.

## 5. Automation/background export design

`ExportAutomationKit` owns trigger orchestration but not data fetching/rendering details.

### Automation API sketch

```swift
public enum ExportTriggerSource: String, Codable, Sendable {
    case manual
    case scheduled
    case shortcut
    case silentPush
    case backgroundTask
    case scheduledWake
    case dataSourceBackgroundDelivery
    case appActiveDrain
    case notificationTapRetry
    case connectedPeer
}

public enum ExportTriggerSourceFamily: String, Codable, Sendable {
    case manual
    case scheduled
    case shortcut
    case connectedPeer
}

public struct ExportTriggerSourcePolicy: Codable, Sendable, Equatable {
    public var triggerSource: ExportTriggerSource
    public var sourceFamily: ExportTriggerSourceFamily
    public var quotaPolicy: ExportTriggerQuotaPolicy
    public var destinationPolicy: ExportTriggerDestinationPolicy
    public var executionContext: ExportTriggerExecutionContext
    public var scheduleUpdatePolicy: ExportTriggerScheduleUpdatePolicy
}

public struct AutomationSchedule: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    public var frequency: ScheduleFrequency
    public var preferredHour: Int
    public var preferredMinute: Int
    public var weekday: Int
    public var lookbackDays: Int
    public var lastExportDate: Date?
}

public struct PendingExportRequest: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var recordDates: [Date]
    public var source: ExportTriggerSourceFamily
    public var scheduledFireDate: Date?
    public var createdAt: Date
    public var routingMetadata: [String: String]
}

public protocol PendingExportStore: Sendable {
    func loadAll() throws -> [PendingExportRequest]
    func upsert(_ request: PendingExportRequest) throws
    func remove(id: UUID) throws
    func clearCompleted(ids: Set<UUID>) throws
}

public protocol ExportAutomationRunner: Sendable {
    associatedtype Record: ExportRecord
    func run(request: PendingExportRequest, trigger: ExportTriggerSource) async -> ExportRunResult
}
```

### Manual export

Manual UI stays in Health.md. It constructs a Health.md `ExportRequest` from selected dates/settings/destination, calls `ExportKit`, maps result to current status/history/analytics, and records quota usage only after success. No automation package dependency is required for purely manual local exports, though manual can still use shared trigger/source result types.

### Preview

Preview does not write. Health.md still fetches sample `HealthData`, but planned-file construction moves to `ExportKit`. The SwiftUI view remains Health.md-owned.

### Scheduled background export

Current behavior to preserve:

1. Schedule settings persist locally.
2. Enabling schedule registers BGTask/HealthKit background delivery, registers APNs, and syncs schedule metadata to server.
3. A pending scheduled export request is created/reused for the exact scheduled occurrence before automatic work starts.
4. The export window is complete past days ending yesterday; default daily = 1 day, default weekly = 7 days, clamped 1-30.
5. Success clears the pending request and notification, updates `lastExportDate`, records history, and sends completion notification.
6. Device-locked failure keeps pending request and sends an immediate local retry notification.
7. Non-lock failure preserves pending request but avoids duplicate immediate retry notification unless current behavior says otherwise.
8. App-active drain runs pending scheduled requests while scheduling is still enabled.

ExportAutomationKit should provide `ScheduledExportCoordinator` and pure date math. Health.md keeps the actual BGTask registration and HealthKit background delivery adapter.

### Server/APNs contract

Current app-side schedule sync sends only:

- stable install/user id;
- platform;
- APNs token;
- bundle id;
- timezone;
- schedule enabled/frequency/hour/minute/weekday.

Future server contract should remain routing-only. A silent push payload can include `content-available: 1`, `type: scheduled-export`, and an optional `fireDate`/occurrence key. It must not include HealthData, exported file contents, vault paths, filename templates, selected metric names, or metric values.

### Pending retry and notification taps

`ExportAutomationKit` owns:

- deterministic notification IDs: `healthmd.pending-export.<request-id>` or configurable prefix;
- payload parser for request id + source;
- duplicate suppression/in-flight request IDs;
- drain ordering by `createdAt` then UUID;
- retrying stored dates exactly, never recalculating a different date window on tap.

Health.md owns localized copy and UI alerts.

### Shortcuts

Shortcuts use the same local iPhone export runner as scheduled/background exports. If HealthKit is unavailable because the device is locked, the runner persists a pending `.shortcut` request for exact dates, sends a local retry notification if possible, and returns a pending dialog. It must not consume quota or record failed history for that locked attempt.

### Connected Mac

Connected Mac remains a manual target. iOS fetches HealthData records and sends a portable settings snapshot plus records to macOS. macOS writes using the same renderer/path/writer logic. Future generic shape:

```swift
public struct PortableExportProfileSnapshot: Codable, Sendable { /* format IDs, templates, write mode, plugin snapshots */ }
public struct RemoteExportJob<RecordPayload: Codable & Sendable>: Codable, Sendable { /* dates, records, profile, target */ }
```

Health.md continues to own the `HealthData` payload and peer sync messages.

## 6. Migration phases mapped to todos

| Todo | Boundary from this plan | Expected migration shape |
|---|---|---|
| `TODO-0c2024a0` — format descriptors/renderers | `ExportFormatDescriptor`, `AnyExportRenderer`, `ExportRendererRegistry` | Add generic descriptors and register Health.md wrappers around existing Markdown/JSON/CSV/Obsidian rendering. No behavior changes. |
| `TODO-add4f202` — path templates/path safety | `ExportPathTemplate`, `ExportPathVariables`, `ExportPathSafetyPolicy`, `PlannedExportFile` | Extract current placeholder replacement and relative-path construction. Add tests around existing Health.md paths and document any safety changes. |
| `TODO-b660fec5` — destination/bookmark/writer | `ExportDestination`, `DestinationAccess`, `ExportFileSystem`, `ExportFileWriter` | Move filesystem/bookmark seams out of `VaultManager` while keeping `VaultManager` as Health.md facade. |
| `TODO-8671cf6d` — write modes/merge strategies | `ExportWriteMode`, `ExportMergeStrategy`, `MarkdownMergeStrategy` | Completed locally in `ExportDestinationWriting.swift`; `VaultManager` routes aggregate writes through generic modes while preserving Markdown merge and non-Markdown update fallback. Health.md-managed section names live in the app facade, not ExportKit. |
| `TODO-6763a336` — orchestrator/results/history | `ExportRequest`, `ExportRunResult`, `ExportProgress` | Add generic orchestrator and map to existing `ExportOrchestrator.ExportResult`; then route a focused slice. |
| `TODO-67d6341c` — preview builder | `ExportPreviewBuilder`, `ExportPreview`, `ExportPreviewDisplayContent` | Move planned-file construction/truncation from SwiftUI into reusable builder; Health.md view consumes it. |
| `TODO-0321050f` — plugins | `ExportPlugin` / `AnyExportPlugin` | Implement Daily Note Injection and individual entries as supplemental/mutation plugins. |
| `TODO-b800e4a5` — port aggregate exports | Health.md adapter layer | Route Health.md manual aggregate exports through ExportKit renderers/path/writer; keep side effects/plugins parity. |
| `TODO-890757af` — schedule/date math | `AutomationSchedule`, `ScheduleDateMath` | Move schedule model/date math into ExportAutomationKit; keep Health.md persistence adapter. |
| `TODO-2361fb54` — server/APNs contract | `RemoteScheduleClient` and routing-only payloads | Define worker/client contract and tests that no health/export/vault content is sent. |
| `TODO-fc02b9c1` — silent push/BGTask runner | `AutomationScheduledBackgroundRunner`, background trigger/result taxonomy | Completed locally; Health.md iOS adapter routes BGTask, silent push, and data-source background delivery through the generic runner while keeping app-specific export/pending/notification internals. |
| `TODO-da038d39` — pending store/fallback notifications | `PendingExportRequest`, `PendingExportStore`, notification scheduler | Completed locally; generic pending request/store/reason/payload/planner/completion policy live in `AutomationPendingExports.swift`, with Health.md wrappers preserving existing identifiers, payload keys, localized copy, duplicate replacement, exact dates, and fallback notification behavior. |
| `TODO-647b36f0` — notification tap retry | notification payload parser + retry coordinator | Completed locally; generic tap router and foreground retry coordinator now route pending notification taps/app-active drains to exact stored requests while Health.md owns export/history/UI adapters. |
| `TODO-1da5c192` — trigger-source abstraction | `ExportTriggerSource` | Completed locally; generic trigger/source policy now normalizes manual, scheduled transports, Shortcut, retry/drain, and connected-peer metadata while Health.md bridges to existing history labels/quota/destination semantics. |
| `TODO-d38b2d4d` — connected Mac snapshots | `PortableExportProfileSnapshot`, remote job shape | Completed locally; connected-Mac settings now carry a generic ExportKit profile/job envelope while Health.md keeps local-peer HealthData payloads and app-specific renderer/plugin snapshots. |
| `TODO-971c5a71` — non-health sample/parity tests | Package tests and sample adapter | Completed locally; invoice sample tests exercise ExportKit/ExportAutomationKit APIs and source-scan generic code for domain coupling while Health parity tests guard current output. |
| `TODO-003a9ee3` — adoption docs | Public package APIs | Document how another app adopts ExportKit and ExportAutomationKit. |

## 7. Test/parity strategy

Use tests as the strangler safety net before routing behavior.

### ExportKit parity tests

- Golden output tests for Health.md aggregate Markdown, Obsidian Bases, JSON, and CSV using existing fixtures.
- Descriptor/registry tests proving selected formats sort like `ExportFormat.rawValue` today.
- Filename tests proving `{date}` defaults, folder templates, and Obsidian Bases `-bases` collision handling.
- Path tests around empty folder structure, nested subfolders, whitespace trimming, slash splitting, and daily-note/export collision warnings.
- Writer tests for overwrite/append/update, including non-Markdown update fallback.
- Markdown merge tests for frontmatter merge, user section preservation, managed section replacement, section-level detection, and daily-note preamble preservation.
- Preview builder tests for aggregate rows, Daily Note Injection rows/warnings, individual entry rows, warning aggregation, newest-first selection, max rendered dates/fetch attempts, and truncation.

### ExportAutomationKit parity tests

- Schedule date math tests for daily/weekly/custom lookback and latest occurrence keys.
- Pending request tests for sorted normalized dates, duplicate scheduled occurrence replacement, duplicate Shortcut date replacement, corrupt persisted data, and deterministic notification identifiers.
- Scheduled coordinator tests for success clear/cancel, device-lock preserve/immediate notification, non-lock preserve, and duplicate occurrence reuse.
- Notification payload tests for request id/source only.
- Trigger runner tests for app-active drain ordering, no double-run for in-flight requests, scheduled-disabled skip, Shortcut drain unaffected by schedule disabled, and notification-tap exact-date retry.
- Server contract tests that registration/schedule payloads do not contain health data, metric names, vault paths, filename templates, or exported contents.

### Health.md integration tests

- Keep existing `HealthMdTests/Export/*`, `VaultManagerTests`, `ExportOrchestratorTests`, `ScheduledExportCoordinatorTests`, `SchedulingManagerPendingExportsTests`, `ExportNotificationSchedulerTests`, `MacExportJobBuilderTests`, and `MacExportJobExecutorTests` green during routing.
- Add side-by-side local-vs-ExportKit tests before changing production routing.
- Add connected-Mac parity tests comparing files written by local export and Mac job executor from the same records/settings snapshot.
- Run focused test classes after each slice and broader export/automation suites whenever shared behavior changes.

## 8. Risks and open questions

- Xcode package integration may be more work than local-source extraction. If so, keep API names package-ready and move after first compiling slice.
- `AdvancedExportSettings` and nested `ObservableObject` settings have test lifecycle considerations. Generic package settings should be immutable/value-type snapshots, not observable persisted objects.
- `FormatCustomization` is partly generic formatting and partly Health.md frontmatter field catalog. Split cautiously to avoid leaking health metric keys into `ExportKit`.
- Current CSV rendering is simple string concatenation. Extraction should preserve current bytes before adding any CSV escaping changes.
- Current path behavior is permissive. Path safety changes must be explicit and tested because templates may already rely on nested paths.
- Daily Note Injection mutates files outside the aggregate health subfolder. Plugin planning must model mutation targets and collisions separately from aggregate output files.
- Security-scoped bookmark behavior differs on iOS/macOS. `DestinationAccess` must remain platform-adapted.
- The scheduled APNs worker implementation is not present in this checkout; app-side `PushRegistrationManager` and docs define the observed contract. Server todo should either locate the worker repo or add contract tests/docs here.
- Connected Mac sends `HealthData` records over local peer sync today. ExportKit should not generalize this as server/cloud transfer; it is local peer payload only.
- Individual entry samples use `Any` values today. Package plugin APIs should expose already-rendered supplemental files or type-erased safe value wrappers, not raw `Any`, where possible.

## Decision summary

- Use package-first boundaries: `ExportKit` for generic file planning/render/write/preview, `ExportAutomationKit` for generic trigger/schedule/pending/retry automation.
- Migrate by strangler adapters, not wholesale rewrites.
- Keep Health.md renderers and HealthKit fetching app-owned.
- Preserve current behavior first; cleanup and stricter safety happen only after parity tests establish the baseline.
