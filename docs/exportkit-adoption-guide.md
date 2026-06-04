# ExportKit / ExportAutomationKit Adoption Guide

This guide is for an app that wants Health.md's export engine patterns without adopting Health.md's domain model. The reusable API surface now lives in the standalone Swift package repo at `../../ExportKit`:

- `ExportKit` from `Sources/ExportKit/`
- `ExportAutomationKit` from `Sources/ExportAutomationKit/`

`ExportKit` owns rendering, path planning, file writing, previews, plugins, results, and portable job snapshots. `ExportAutomationKit` owns schedules, trigger policies, pending retry, background-run coordination, notification routing/UserNotifications fallback alerts, and remote APNs schedule contracts. Add the package to another app and keep app-specific records, renderers, UI copy, settings, quota, and analytics in that app's adapter layer.

The invoice examples below come from `HealthMdTests/Export/NonHealthExportKitSampleTests.swift`. They intentionally use invoices, not HealthKit, so they are safe templates for other apps.

## New app checklist

1. Define an app record that conforms to `ExportRecord` and contains only your app's export payload.
2. Define one `ExportFormatDescriptor` per output format.
3. Implement `ExportRenderer` types and register them with `ExportRendererRegistry`.
4. Persist a domain-free `PortableExportProfileSnapshot` for selected format IDs, folder/filename templates, write mode, plugin IDs, and generic metadata.
5. Build `ExportPathVariables` with date placeholders plus app-specific variables such as `recordID`, `customerSlug`, `project`, or `format`.
6. Plan `PlannedExportFile` values with `ExportPathTemplate` and `.rejectTraversalAndAbsolutePaths` for real writes.
7. Resolve an `ExportDestination` and optional `DestinationAccess` / bookmark adapter.
8. Write files with `ExportFileWriter` using `.overwrite`, `.append`, or `.update` plus an app-owned `ExportMergeStrategy` such as `MarkdownMergeStrategy(managedSectionNames:)`.
9. Wrap fetching and writing in `ExportRunOrchestrator` so progress, cancellation, failures, warnings, and history mapping are generic.
10. Add `ExportPreviewBuilder` for no-write previews and `ExportPluginRunner` for supplemental files or mutation targets.
11. If you need cross-device/local-peer jobs, encode `PortableRemoteExportJobSnapshot<RecordPayload>` with an app-owned record payload.
12. If you need scheduled exports, bridge your UI settings into `AutomationSchedule`, use `AutomationScheduleDateMath`, register APNs routing-only metadata, persist `AutomationPendingExportRequest` before background work, and route notification taps through `AutomationPendingExportForegroundRetryCoordinator`.
13. Keep all domain-specific types in your app adapter layer. Do not add your models, server payload data, or platform UI types to `ExportKit` or `ExportAutomationKit`.

## Module boundaries

| Layer | Owns | Must not know about |
|---|---|---|
| `ExportKit` | `ExportRecord`, format descriptors, renderers, path templates, path safety, destinations, bookmark/file-system seams, writer, write modes, merge strategies, orchestrator, progress/results/history value shapes, previews, plugins, portable snapshots | HealthKit, Health.md models, app UI, server workers, purchase/quota systems, UserNotifications/BGTask/App Intents, domain enums |
| `ExportAutomationKit` | Schedule value model/date math, persisted automation config shape, remote schedule client payloads, background runner, pending requests, fallback notification payload planning, tap router, foreground retry coordinator, trigger-source policies | Exported records, rendered file contents, app-specific data categories, destination file paths/templates, Health.md settings, UI copy |
| Your app adapter | Domain records, data fetching, renderer implementations, settings UI/persistence, bookmarks, local notifications, BGTask/APNs plumbing, quota/purchase/history/analytics, migration from old settings | Reusable policy decisions that belong in ExportKit/ExportAutomationKit |

A good rule: if code mentions your app's record fields, user-facing copy, settings model, or platform services, keep it outside the generic modules and pass only value snapshots or closures into the generic APIs.

## 1. Define a domain record

`ExportKit` only requires identity and date. Your record can be `Codable` if you plan to use portable snapshots or local-peer jobs.

```swift
struct InvoiceRecord: ExportRecord, Codable, Equatable {
    var id: String
    var issuedDate: Date
    var customer: String
    var status: InvoiceStatus
    var lines: [InvoiceLine]

    var exportRecordID: String { id }
    var exportDate: Date { issuedDate }
}
```

Do not put Health.md types such as `HealthData`, `MetricSelectionState`, or `HealthMetricsDictionary` in a reusable record. If your app has a large domain object, wrap it in an adapter record owned by your app target.

## 2. Register formats and renderers

Use `ExportFormatDescriptor` instead of a shared enum. IDs are stable API/persistence keys; display names are UI labels; `defaultSortKey` controls deterministic output order.

```swift
let markdownDescriptor = ExportFormatDescriptor(
    id: "invoice-markdown",
    displayName: "Invoice Markdown",
    fileExtension: "md",
    contentType: "text/markdown",
    defaultSortKey: "20-Markdown"
)

struct InvoiceMarkdownRenderer: ExportRenderer {
    var descriptor: ExportFormatDescriptor { markdownDescriptor }

    func render(record: InvoiceRecord, context: ExportRenderContext) throws -> RenderedExport {
        RenderedExport(
            content: """
            # Invoice \(record.id)

            ## Invoice
            - Customer: \(record.customer)
            """,
            contentType: descriptor.contentType
        )
    }
}

let registry = try ExportRendererRegistry(renderers: [
    AnyExportRenderer(InvoiceMarkdownRenderer()),
    AnyExportRenderer(InvoiceJSONRenderer()),
    AnyExportRenderer(InvoiceCSVRenderer())
])
```

Useful registry calls:

- `descriptors(for:)` validates selected format IDs and returns sorted descriptors.
- `render(record:formatID:context:)` renders through the registered formatter.
- `resolvedFilenames(baseName:selectedFormatIDs:)` applies extension collision suffixes. Health.md uses this to keep Markdown and Obsidian Bases filename behavior compatible; another app can use it for any colliding extension pair.

## 3. Store a portable export profile

`PortableExportProfileSnapshot` is a reusable, domain-free configuration envelope. It does not contain selected records, rendered content, server secrets, destination file paths, or app-specific filter settings.

```swift
let profile = PortableExportProfileSnapshot(
    formatIDs: ["invoice-markdown", "invoice-json"],
    aggregateFolderTemplate: "Invoices/{customerSlug}/{year}/{month}/{format}",
    aggregateFilenameTemplate: "{recordID}",
    writeMode: .overwrite,
    enabledPluginIDs: ["invoice-ledger"],
    metadata: ["sampleDomain": "invoice"]
)
```

If your app needs extra settings, wrap this profile in an app-owned snapshot:

```swift
struct InvoiceExportSettingsSnapshot: Codable {
    var exportProfile: PortableExportProfileSnapshot
    var includeDrafts: Bool
    var currencyCode: String
}
```

Keep app-owned filtering/rendering options in the wrapper, not in `ExportKit`.

## 4. Plan paths with templates and safety policies

`ExportPathVariables` provides built-in date placeholders:

- `{date}` = `yyyy-MM-dd`
- `{year}`
- `{month}`
- `{day}`
- `{weekday}`
- `{monthName}`
- `{quarter}`

Add your own placeholders through `values`.

```swift
let template = profile.aggregatePathTemplate(fileExtension: markdownDescriptor.fileExtension)
let variables = ExportPathVariables(date: record.exportDate, values: [
    "customerSlug": record.customerSlug,
    "recordID": record.exportRecordID,
    "format": "markdown"
])

let relativePath = try template.plannedRelativePath(
    variables: variables,
    safetyPolicy: .rejectTraversalAndAbsolutePaths
)
```

Safety policies:

| Policy | Use for | Behavior |
|---|---|---|
| `.preserveCurrentBehavior` | Legacy previews/display compatibility | Trim, split on `/`, drop empty components. Does not reject traversal. |
| `.rejectTraversalAndAbsolutePaths` | Production writes | Reject absolute paths, `..`, and NUL-containing components so exports cannot escape the selected destination. |
| `.sanitizePathComponents` | Apps that prefer rewrite over rejection | Drop traversal and rewrite invalid filename characters. Document this choice for users. |

For real writes, prefer `.rejectTraversalAndAbsolutePaths`. Use `.preserveCurrentBehavior` only when preserving legacy preview strings or existing UI display behavior is required.

## 5. Build planned files

`PlannedExportFile` is the common unit used by writers, previews, plugins, and collision checks.

```swift
func planAggregateFile(
    record: InvoiceRecord,
    descriptor: ExportFormatDescriptor,
    rendered: RenderedExport
) throws -> PlannedExportFile {
    let relativePath = try profile
        .aggregatePathTemplate(fileExtension: descriptor.fileExtension)
        .plannedRelativePath(
            variables: pathVariables(record: record, descriptor: descriptor),
            safetyPolicy: .rejectTraversalAndAbsolutePaths
        )

    return PlannedExportFile(
        id: "\(record.exportRecordID)-\(descriptor.id)",
        role: .aggregate(formatID: descriptor.id),
        relativePath: relativePath,
        content: rendered.content,
        format: descriptor,
        contentType: rendered.contentType,
        displayName: descriptor.displayName,
        estimatedByteCount: rendered.content.utf8.count
    )
}
```

Use roles consistently:

- `.aggregate(formatID:)` for primary selected-format exports.
- `.supplemental(pluginID:)` for extra files such as invoice ledger entries.
- `.mutation(pluginID:)` for plugins that update an existing file such as a daily note or project log.

## 6. Resolve destinations and write files

`ExportDestination` represents a user-selected root plus an optional app-owned base subfolder.

```swift
let destination = ExportDestination(
    rootURL: selectedFolderURL,
    displayName: "Client Exports",
    baseRelativePath: "Exports"
)
```

Use `ExportDestinationBookmarkStore`, `ExportBookmarkAccessing`, and `SecurityScopedDestinationAccess` when your platform requires security-scoped bookmarks. Use `PassthroughDestinationAccess` or no access wrapper for sandbox-free tests and in-memory file systems.

```swift
let writer = ExportFileWriter(
    fileSystem: FileManagerExportFileSystem(),
    destinationAccess: SecurityScopedDestinationAccess(bookmarkAccess: bookmarkAdapter),
    safetyPolicy: .rejectTraversalAndAbsolutePaths
)

let results = try writer.write(
    plannedFiles,
    to: destination,
    mode: profile.writeMode,
    mergeStrategies: [
        markdownDescriptor.id: MarkdownMergeStrategy(managedSectionNames: ["invoice"])
    ]
)
```

Write modes:

| Mode | Behavior |
|---|---|
| `.overwrite` | Replace existing file bytes. |
| `.append` | Read existing file and append `\n\n` plus new content. |
| `.update` | If a merge strategy is supplied for the file ID, format ID, or plugin ID, merge existing and new content. Without a strategy, fall back to overwrite. |

`MarkdownMergeStrategy` is domain-free. Its default managed section set is empty. Each app must provide the section headings it owns, such as `managedSectionNames: ["invoice"]`. This preserves user-authored sections while replacing app-managed sections and merging frontmatter.

## 7. Orchestrate exports with progress and results

`ExportRunOrchestrator` separates fetching from writing and returns a reusable result model.

```swift
let orchestrator = ExportRunOrchestrator<Date, InvoiceRecord>(
    dataSource: AnyExportRecordDataSource { date in
        ExportFetchedRecord(record: recordsByDate[calendar.startOfDay(for: date)])
    },
    writer: AnyExportRecordWriter { record, context in
        guard let destination = context.destination else { throw InvoiceExportError.noDestination }

        let descriptors = try registry.descriptors(for: context.formatIDs)
        let files = try descriptors.map { descriptor in
            try planAggregateFile(
                record: record,
                descriptor: descriptor,
                rendered: registry.render(record: record, formatID: descriptor.id)
            )
        }

        let writeResults = try writer.write(files, to: destination, mode: context.writeMode)
        return ExportRecordWriteSummary(filesWritten: writeResults.count)
    },
    failureMapper: { error in
        ExportRunFailure(reason: .writeError, errorDescription: error.localizedDescription)
    }
)

let request = ExportRunRequest(
    recordInputs: requestedDates,
    formatIDs: profile.formatIDs,
    destination: destination,
    writeMode: profile.writeMode,
    recordReference: { ExportRecordReference(id: dayString($0), date: $0) }
)

let result = await orchestrator.run(request) { progress in
    switch progress.phase {
    case .planning, .fetching, .rendering, .writing, .completed:
        updateProgressUI(progress)
    }
}
```

Map `ExportRunResult` to your app's history or UI:

- `status` is `.fullSuccess`, `.partialSuccess`, `.failure`, or `.empty`.
- `successCount`, `totalCount`, and `filesWritten` are suitable for summaries.
- `failedRecords` carries record references plus `ExportRunFailure`.
- `warnings` should be displayed or logged without treating the run as failed.
- `wasCancelled` lets your app distinguish user cancellation from runtime failure.

## 8. Build previews without writing

`ExportPreviewBuilder` fetches the newest available records first, renders selected aggregate formats, adds supplemental/mutation plans, and truncates large preview content through `ExportPreviewDisplayContent`.

```swift
let pluginRunner = ExportPluginRunner(plugins: [AnyExportPlugin(InvoiceLedgerPlugin(fileWriter: writer))])

let previewRequest = ExportPreviewRequest(
    recordInputs: requestedDates,
    selectedFormatIDs: profile.formatIDs,
    dataSource: dataSource,
    rendererRegistry: registry,
    recordReference: { ExportRecordReference(id: dayString($0), date: $0) },
    planAggregateFile: { record, descriptor, rendered in
        try planAggregateFile(record: record, descriptor: descriptor, rendered: rendered)
    },
    supplementalFilePlanner: { record, aggregateFiles in
        let context = ExportPluginContext(
            record: record,
            operation: .preview,
            aggregateFiles: aggregateFiles,
            writeMode: profile.writeMode
        )
        return try pluginRunner.previewSupplementalPlan(record: record, context: context)
    }
)

let preview = try await ExportPreviewBuilder<Date, InvoiceRecord>().buildPreview(previewRequest)
```

Default preview limits are 5 rendered records, 14 fetch attempts, and 64 KB rendered content per file with a head/tail truncation marker. Your UI remains app-owned; it should render `ExportPreview.records`, `PlannedExportFile.displayName`, `relativePath`, `sizeLabel`, warnings, and `displayContent()`.

## 9. Add plugins for supplemental files and mutations

Plugins run per record, not per selected aggregate format. The invoice sample writes one ledger file per invoice even when Markdown and JSON are both selected.

```swift
struct InvoiceLedgerPlugin: ExportPlugin {
    let fileWriter: ExportFileWriter
    let id = "invoice-ledger"

    func validate(record: InvoiceRecord, context: ExportPluginContext<InvoiceRecord>) throws -> [ExportWarning] {
        record.status == .draft
            ? [ExportWarning(id: "\(record.id)-draft", message: "Invoice \(record.id) is still draft")]
            : []
    }

    func planFiles(record: InvoiceRecord, context: ExportPluginContext<InvoiceRecord>) throws -> ExportPluginPlan {
        ExportPluginPlan(files: [try ledgerFile(for: record)], warnings: try validate(record: record, context: context))
    }

    func performSideEffects(record: InvoiceRecord, context: ExportPluginContext<InvoiceRecord>) throws -> ExportPluginRunResult {
        guard let destination = context.destination else { throw InvoiceExportError.noDestination }
        _ = try fileWriter.write(try ledgerFile(for: record), to: destination, mode: .overwrite)
        return ExportPluginRunResult(pluginID: id, filesWritten: 1)
    }
}
```

For mutation plugins, create `PlannedExportFile(role: .mutation(pluginID:))` and run `ExportPluginCollisionDetector.mutationCollisions(pluginFiles:aggregateFiles:)` during validation so a mutation target cannot overwrite an aggregate export file.

## 10. Portable snapshots and local-peer export jobs

Use `PortableRemoteExportJobSnapshot<RecordPayload>` when one device prepares records and another local peer writes them. The generic envelope carries dates, source device metadata, target metadata, and `PortableExportProfileSnapshot`; the record payload remains app-owned.

```swift
let job = PortableRemoteExportJobSnapshot(
    jobID: UUID(),
    createdAt: Date(),
    sourceDeviceName: "Sample iPhone",
    dateRangeStart: firstDate,
    dateRangeEnd: lastDate,
    records: invoiceRecords,
    exportProfile: profile,
    requestedTarget: PortableExportTargetSnapshot(
        kindID: "local-folder",
        displayName: "Shared Samples",
        destinationDisplayName: "Invoices"
    )
)
```

Do not treat this as a cloud transfer abstraction. If your app sends record payloads across devices, keep it local-peer or otherwise apply your own privacy model outside ExportKit. The generic profile must not contain rendered file contents or destination path secrets.

## 11. Automate schedules and date math

Bridge your app's schedule UI/persistence into `AutomationSchedule`.

```swift
let schedule = AutomationSchedule(
    isEnabled: true,
    frequency: .daily,
    preferredHour: 8,
    preferredMinute: 0,
    lookbackDays: 2,
    timeZoneIdentifier: "UTC"
)

let fireDate = AutomationScheduleDateMath.latestScheduledOccurrenceDate(
    schedule: schedule,
    now: Date(),
    calendar: calendar
)

let dates = AutomationScheduleDateMath.scheduledExportDates(
    schedule: schedule,
    fireDate: fireDate ?? Date(),
    calendar: calendar
)
```

Current behavior preserved by the generic math:

- daily default lookback = 1 complete past day;
- weekly default lookback = 7 complete past days;
- lookback is clamped to 1...30 days;
- scheduled windows end yesterday relative to the fire day;
- catch-up treats `lastExportDate` as the run date that exported the previous data day.

`PersistedAutomationConfiguration` can store an `AutomationSchedule` plus an `AutomationExportRequestConfigurationSnapshot`. Keep app-specific export filters in `encodedConfiguration` or in your own wrapper; do not add record contents to the automation configuration.

## 12. Keep server/APNs scheduled exports routing-only

The remote worker contract is documented in [Scheduled APNs Worker Contract](../worker/scheduled-apns-worker-contract.md). A reusable app should follow the same privacy boundary.

Device registration may send only routing metadata:

```swift
let registration = RemoteScheduleDeviceRegistrationPayload(
    userId: stableInstallID,
    platform: "ios",
    apnsToken: tokenHex,
    bundleId: Bundle.main.bundleIdentifier ?? "com.example.app"
)
try await remoteScheduleClient.registerDevice(registration)
```

Schedule upsert may send only timing metadata:

```swift
let upsert = RemoteScheduleUpsertPayload(
    userId: stableInstallID,
    timezone: schedule.timeZoneIdentifier,
    schedule: RemoteSchedulePayload(schedule: schedule),
    platform: "ios",
    bundleId: Bundle.main.bundleIdentifier
)
try await remoteScheduleClient.upsertSchedule(upsert)
```

The worker's silent APNs payload should be background-only:

```json
{
  "aps": { "content-available": 1 },
  "type": "scheduled-export",
  "scheduledFireDate": "2026-06-04T08:00:00Z"
}
```

The server must never receive or store exported records, rendered files, destination paths, folder/filename templates, selected data categories, category names, metric names, values, vault contents, or pending retry date windows.

## 13. Background runner, pending store, and fallback notifications

Before background work starts, create or reuse a pending request for the exact scheduled occurrence. This is what makes foreground tap-to-retry reliable when the device is locked, the background task times out, or protected data is unavailable.

```swift
let requestBuilder = AutomationPendingScheduledExportRequestBuilder(
    calendar: calendar,
    metadata: ["domain": "invoice"]
)

let pending = requestBuilder.makeRequest(
    schedule: schedule,
    fireDate: resolvedFireDate,
    existingRequests: try pendingStore.loadAll()
)
try pendingStore.upsert(pending)
```

Use `AutomationPendingExportFallbackNotificationPlanner` to build deterministic fallback notification identifiers and userInfo. Your app owns the actual `UserNotifications` scheduling and localized copy through an `AutomationPendingExportNotificationScheduling` adapter.

Use `AutomationScheduledBackgroundRunner` to preserve the order of operations:

```swift
let outcome = await AutomationScheduledBackgroundRunner(calendar: calendar).runScheduledExport(
    trigger: .silentPush,
    schedule: schedule,
    requestedFireDate: payloadFireDate,
    preparePendingWork: { context in
        let request = requestBuilder.makeRequest(
            schedule: context.schedule,
            fireDate: context.resolvedFireDate,
            existingRequests: (try? pendingStore.loadAll()) ?? []
        )
        try? pendingStore.upsert(request)
        return AutomationPreparedScheduledBackgroundWork(
            request: request,
            dates: request.dates,
            scheduledFireDate: request.scheduledFireDate
        )
    },
    cancelPendingFallback: { work in
        if let work { notificationScheduler.cancelPendingExportNotification(id: work.request.id) }
    },
    beforeExport: { prepared in
        scheduleNextBGTaskAndInstallExpirationHandler(prepared)
    },
    export: { dates, context in
        let runResult = await runInvoiceExport(dates: dates)
        return (runResult, AutomationBackgroundExportResult(
            successCount: runResult.successCount,
            totalCount: runResult.totalCount,
            primaryFailureReason: mapFailure(runResult),
            wasCancelled: runResult.wasCancelled
        ))
    }
)
```

Then apply `AutomationPendingExportCompletionPolicy`:

| Background result | Pending request | Notification behavior | Schedule/history side effects |
|---|---|---|---|
| `successCount > 0` | Clear completed request | Cancel pending/delivered fallback | Record success and update `lastExportDate` if trigger policy allows. |
| `.protectedDataUnavailable` | Preserve with protected-data reason | Send immediate retry notification | Do not mark schedule complete. |
| Attempted failure, timeout, or cancellation | Preserve with failure reason | Do not send duplicate immediate fallback; optionally schedule a delayed fallback through your planner | Do not mark schedule complete. |
| No attempted work / quota blocked / schedule disabled | Preserve or skip according to app policy | Usually no immediate fallback | Record a skip if your app UI needs it. |

## 14. Notification tap retry lifecycle

A tap must retry the exact stored request dates. Do not recalculate the export window from "now" during tap handling.

```swift
let configuration = AutomationPendingExportNotificationConfiguration(
    identifierPrefix: "invoice.pending-export."
)
let router = AutomationPendingExportNotificationTapRouter(configuration: configuration)
let retryCoordinator = AutomationPendingExportForegroundRetryCoordinator(pendingExportStore: pendingStore)

if case .pendingExport(let payload) = router.route(identifier: identifier, userInfo: userInfo) {
    await retryCoordinator.retryPendingExport(
        requestID: payload.requestID,
        source: payload.source,
        trigger: .notificationTap,
        shouldAttempt: { request, trigger in
            let policy = trigger.exportTriggerSource.policy(
                resolvedSourceFamily: request.source.exportTriggerSourceFamily
            )
            return policy.destinationPolicy == .localDevice ? .eligible : .skipped(.scheduleDisabled)
        },
        execute: { request, trigger in
            await runInvoiceExport(dates: request.dates)
        }
    )
}
```

Lifecycle diagram:

```text
Remote schedule due
  -> worker sends routing-only silent APNs
  -> app receives silent push / BGTask / data-source wake
  -> resolve scheduled fire date
  -> create or reuse pending request with exact export dates
  -> schedule delayed fallback notification
  -> start background export and cancel stale fallback for this attempt
      -> success or partial success
           -> clear pending request
           -> cancel pending/delivered fallback notifications
           -> record history, update lastExportDate when policy allows
      -> protected data unavailable / device locked
           -> preserve pending request with protected-data reason
           -> send immediate fallback notification
      -> timeout, cancellation, write/fetch failure, no data
           -> preserve pending request with failure reason
           -> avoid duplicate immediate fallback unless app policy explicitly reschedules
  -> user taps fallback notification or app becomes active
  -> tap router parses request id + source only
  -> foreground retry coordinator loads stored request
  -> validate source, eligibility, and in-flight status
  -> run export for request.dates exactly as stored
      -> success clears request; retryable failure preserves it
```

## 15. Trigger-source policies

`ExportTriggerSourcePolicy` normalizes how different triggers affect quota, destination, execution context, and schedule completion.

```swift
let policy = ExportTriggerSource.silentPush.policy()
// sourceFamily == .scheduled
// destinationPolicy == .localDevice
// quotaPolicy == .never
// scheduleUpdatePolicy == .afterSuccessfulRun

let retryPolicy = ExportTriggerSource.notificationTapRetry.policy(
    resolvedSourceFamily: pendingRequest.source.exportTriggerSourceFamily
)
```

Policy summary:

| Trigger | Source family | Destination | Quota | Schedule update |
|---|---|---|---|---|
| `.manual` | `.manual` | app-selected | once after successful run | never |
| `.scheduled`, `.silentPush`, `.backgroundTask`, `.scheduledWake`, `.dataSourceBackgroundDelivery` | `.scheduled` | local device | never | after successful scheduled run |
| `.shortcut` | `.shortcut` | local device | once after successful run | when previous complete day was included |
| `.notificationTapRetry`, `.appActiveDrain` | resolved from pending request | family-specific | family-specific | family-specific |
| `.connectedPeer` | `.connectedPeer` | connected peer | once after successful run | never |

Use the policy in your app adapter to decide whether to record quota usage, update schedule state, choose a local destination, or label history. Keep user-facing strings outside the generic policy type.

## 16. Health.md-specific adapter examples, separated

The following files are examples of how Health.md uses the generic APIs while keeping Health.md concepts out of the reusable modules:

- `HealthMd/Shared/Export/HealthExportRenderers.swift` wraps `HealthData` in `HealthExportRecord` and implements Health.md Markdown, JSON, CSV, and Obsidian Bases renderers.
- `HealthMd/Shared/Export/HealthAggregateExportAdapter.swift` bridges `AdvancedExportSettings` to `ExportRendererRegistry`, `ExportPathTemplate`, `PlannedExportFile`, and `ExportFileWriter` while preserving Health.md filename collision behavior and write modes.
- `HealthMd/Shared/Export/MarkdownMerger.swift` is a Health.md facade that supplies Health.md-owned managed Markdown section names to the domain-free `MarkdownMergeStrategy`.
- `HealthMd/Shared/Export/HealthExportPlugins.swift` adapts Daily Note Injection and individual entry tracking into generic plugin roles.
- `HealthMd/Shared/Managers/PushRegistrationManager.swift` bridges APNs token capture and Health.md schedule settings into the generic remote schedule payloads.
- `HealthMd/iOS/SchedulingManager.swift` wires BGTask, silent push, protected-data checks, pending retry, local notifications, purchase/history side effects, and Health.md export execution around the generic automation runner.
- `HealthMd/Shared/Models/ExportSettingsSnapshot.swift`, `HealthMd/Shared/Sync/MacExportJobBuilder.swift`, and `HealthMd/macOS/Managers/MacExportJobExecutor.swift` keep Health.md record payloads app-owned while sharing `PortableExportProfileSnapshot` for connected-Mac parity.

Do not copy Health.md adapter types into a different app unless you are also copying Health.md's domain. Copy the generic patterns: wrap your record, implement renderers, map settings into `PortableExportProfileSnapshot`, provide plugins for your supplemental work, and keep your app-specific settings/history/notifications in your app target.

## Security and privacy rules

- Server registration is routing-only. Never upload exported data, rendered files, template strings, destination paths, selected categories, names, values, or pending retry date windows.
- Real write paths should use `.rejectTraversalAndAbsolutePaths` so templates cannot escape the selected destination.
- Security-scoped bookmark access belongs in an app/platform adapter, not in renderers.
- Persist pending requests before background export starts so protected-data failures can be retried in the foreground.
- Notification payloads should include only request ID, source, reason, and generic type keys.
- Tap-to-retry must use stored dates exactly.
- Connected-peer jobs may carry app-owned record payloads only through your local-peer privacy model; do not generalize them as server/cloud exports.
- Keep reusable source scans or tests that reject app/domain terms from `ExportKit` and `ExportAutomationKit`.

## Related docs and tests

- [ExportKit / ExportAutomationKit Architecture](./exportkit-automationkit-architecture.md)
- [Scheduled APNs Worker Contract](../worker/scheduled-apns-worker-contract.md)
- `HealthMdTests/Export/NonHealthExportKitSampleTests.swift`
- `../../ExportKit/Sources/ExportKit/*`
- `../../ExportKit/Sources/ExportAutomationKit/*`
