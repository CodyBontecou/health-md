# ExportKit package

The reusable export foundation has been extracted into the standalone Swift Package repo at `../../ExportKit`. Health.md consumes that local package via SwiftPM so it can share export orchestration, path planning, preview, scheduling, pending retry, and notification plumbing with other iOS/macOS apps without sharing app-specific data models.

## Products

- `ExportKit`
  - Generic record/renderer contracts
  - Path templates and safe destination-relative file planning
  - Destination/bookmark abstractions and file writing
  - Export run orchestration, progress, history, previews, plugins, portable snapshots
- `ExportAutomationKit`
  - Schedule date math and trigger policies
  - Pending export request persistence/retry coordination
  - Remote schedule/APNs payload contracts
  - UserNotifications-backed pending export notification scheduling

## Integration shape

Each app supplies the domain-specific pieces:

1. A record type conforming to `ExportRecord`.
2. One or more `AnyExportRenderer<Record>` or concrete `ExportRenderer` implementations for that app's formats.
3. Path templates / `PlannedExportFile` mapping for that app's folder and filename conventions.
4. Optional `ExportPlugin`s for supplemental files or side effects.
5. App-specific pending-export notification copy and userInfo keys.

The package owns the reusable mechanics, not the exported domain.

```swift
import ExportKit
import ExportAutomationKit

struct InvoiceRecord: ExportRecord {
    var id: String
    var exportDate: Date
    var total: Decimal
    var exportRecordID: String { id }
}

let markdown = ExportFormatDescriptor(
    id: "invoice-markdown",
    displayName: "Invoice Markdown",
    fileExtension: "md",
    contentType: "text/markdown"
)

let renderer = AnyExportRenderer<InvoiceRecord>(descriptor: markdown) { invoice, _ in
    RenderedExport(
        content: "# Invoice \(invoice.id)\nTotal: \(invoice.total)",
        contentType: markdown.contentType
    )
}
```

Pending export notifications stay configurable per app:

```swift
let notificationConfig = AutomationPendingExportNotificationConfiguration(
    identifierPrefix: "myapp.pending-export.",
    typeValue: "pending-export",
    typeUserInfoKey: "myapp.notification.type",
    requestIDUserInfoKey: "myapp.pendingExport.requestID",
    sourceUserInfoKey: "myapp.pendingExport.source",
    reasonUserInfoKey: "myapp.pendingExport.reason",
    categoryIdentifier: "myapp.pending-export.retry"
)

let scheduler = AutomationUserNotificationPendingExportScheduler(
    configuration: notificationConfig,
    contentConfiguration: AutomationPendingExportNotificationContentConfiguration(
        title: "Export Needs Attention",
        body: "Open the app to retry your export."
    )
)
```

Health.md keeps its HealthKit/export formatting adapters in the app target, while the reusable notification scheduler now delegates to `AutomationUserNotificationPendingExportScheduler` with Health.md-specific copy and payload keys.
