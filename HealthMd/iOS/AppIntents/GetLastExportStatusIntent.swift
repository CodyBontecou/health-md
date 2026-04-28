import AppIntents
import Foundation

/// Snapshot of the most recent export attempt, returned by
/// `GetLastExportStatusIntent`. Designed for dashboards and "alert me if my
/// export fails" automations.
struct LastExportStatus: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Last Export Status")
    }

    static var defaultQuery = LastExportStatusQuery()

    let id: String

    @Property(title: "Timestamp")
    var timestamp: Date

    @Property(title: "Success")
    var success: Bool

    @Property(title: "Days Exported")
    var daysExported: Int

    @Property(title: "Days Attempted")
    var daysAttempted: Int

    @Property(title: "Range Start")
    var rangeStart: Date

    @Property(title: "Range End")
    var rangeEnd: Date

    @Property(title: "Source")
    var source: String

    @Property(title: "Failure Reason")
    var failureReason: String?

    @Property(title: "Summary")
    var summary: String

    var displayRepresentation: DisplayRepresentation {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return DisplayRepresentation(
            title: LocalizedStringResource(stringLiteral: summary),
            subtitle: LocalizedStringResource(stringLiteral: formatter.string(from: timestamp))
        )
    }
}

struct LastExportStatusQuery: EntityQuery {
    func entities(for identifiers: [LastExportStatus.ID]) async throws -> [LastExportStatus] {
        []
    }
}

/// Returns the most recent export entry from history (manual, scheduled, or
/// shortcut). Returns nil if no export has ever run.
struct GetLastExportStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Last Export Status"

    static var description = IntentDescription(
        "Returns details of the most recent Health.md export — timestamp, success, days exported, and any failure reason.",
        categoryName: "Health"
    )

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<LastExportStatus?> & ProvidesDialog {
        guard let entry = ExportHistoryManager.shared.history.first else {
            return .result(
                value: nil,
                dialog: "No exports yet."
            )
        }

        let status = LastExportStatus(
            id: entry.id.uuidString,
            timestamp: entry.timestamp,
            success: entry.success,
            daysExported: entry.successCount,
            daysAttempted: entry.totalCount,
            rangeStart: entry.dateRangeStart,
            rangeEnd: entry.dateRangeEnd,
            source: entry.source.rawValue,
            failureReason: entry.failureReason?.shortDescription,
            summary: entry.summaryDescription
        )

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let dialog = "\(entry.summaryDescription) (\(formatter.string(from: entry.timestamp)))"

        return .result(value: status, dialog: IntentDialog(stringLiteral: dialog))
    }
}

private extension LastExportStatus {
    init(
        id: String,
        timestamp: Date,
        success: Bool,
        daysExported: Int,
        daysAttempted: Int,
        rangeStart: Date,
        rangeEnd: Date,
        source: String,
        failureReason: String?,
        summary: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.success = success
        self.daysExported = daysExported
        self.daysAttempted = daysAttempted
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
        self.source = source
        self.failureReason = failureReason
        self.summary = summary
    }
}
