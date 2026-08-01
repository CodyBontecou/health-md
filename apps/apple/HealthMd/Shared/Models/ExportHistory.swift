import Foundation
import Combine

/// Privacy-safe request and transfer metadata for an export history entry.
/// Health values and generated file contents are deliberately never persisted here.
struct ExportHistoryOperationDetails: Codable, Equatable {
    enum Kind: String, Codable {
        case generatedFiles = "generated_files"
        case rawExport = "raw_export"
        case canonicalExtraction = "canonical_extraction"
    }

    let kind: Kind
    let requestID: UUID
    let dateSelection: String
    let settingsPolicy: String
    let profile: String?
    let detailLevel: String?
    let metricIDs: [String]
    let categoryIDs: [String]
    let sourceIDs: [String]
    let objectPaths: [String]
    let fieldPointers: [String]
    let partitionCount: Int
    let transferredBytes: Int64
    let sampleCount: Int?
    let recordCount: Int?
    let warningDayCount: Int
    let failedDayCount: Int
    let integrityWarningCount: Int
    let partialFailureCount: Int

    init(
        kind: Kind,
        requestID: UUID,
        dateSelection: String,
        settingsPolicy: String,
        profile: String? = nil,
        detailLevel: String? = nil,
        metricIDs: [String] = [],
        categoryIDs: [String] = [],
        sourceIDs: [String] = [],
        objectPaths: [String] = [],
        fieldPointers: [String] = [],
        partitionCount: Int = 0,
        transferredBytes: Int64 = 0,
        sampleCount: Int? = nil,
        recordCount: Int? = nil,
        warningDayCount: Int = 0,
        failedDayCount: Int = 0,
        integrityWarningCount: Int = 0,
        partialFailureCount: Int = 0
    ) {
        self.kind = kind
        self.requestID = requestID
        self.dateSelection = dateSelection
        self.settingsPolicy = settingsPolicy
        self.profile = profile
        self.detailLevel = detailLevel
        self.metricIDs = Self.boundedValues(metricIDs, maximumCount: 512, maximumUTF8Bytes: 128)
        self.categoryIDs = Self.boundedValues(categoryIDs, maximumCount: 64, maximumUTF8Bytes: 128)
        self.sourceIDs = Self.boundedValues(sourceIDs, maximumCount: 32, maximumUTF8Bytes: 128)
        self.objectPaths = Self.boundedValues(objectPaths, maximumCount: 128, maximumUTF8Bytes: 1_024)
        self.fieldPointers = Self.boundedValues(fieldPointers, maximumCount: 256, maximumUTF8Bytes: 1_024)
        self.partitionCount = max(partitionCount, 0)
        self.transferredBytes = max(transferredBytes, 0)
        self.sampleCount = sampleCount.map { max($0, 0) }
        self.recordCount = recordCount.map { max($0, 0) }
        self.warningDayCount = max(warningDayCount, 0)
        self.failedDayCount = max(failedDayCount, 0)
        self.integrityWarningCount = max(integrityWarningCount, 0)
        self.partialFailureCount = max(partialFailureCount, 0)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try container.decode(Kind.self, forKey: .kind),
            requestID: try container.decode(UUID.self, forKey: .requestID),
            dateSelection: try container.decode(String.self, forKey: .dateSelection),
            settingsPolicy: try container.decode(String.self, forKey: .settingsPolicy),
            profile: try container.decodeIfPresent(String.self, forKey: .profile),
            detailLevel: try container.decodeIfPresent(String.self, forKey: .detailLevel),
            metricIDs: try container.decodeIfPresent([String].self, forKey: .metricIDs) ?? [],
            categoryIDs: try container.decodeIfPresent([String].self, forKey: .categoryIDs) ?? [],
            sourceIDs: try container.decodeIfPresent([String].self, forKey: .sourceIDs) ?? [],
            objectPaths: try container.decodeIfPresent([String].self, forKey: .objectPaths) ?? [],
            fieldPointers: try container.decodeIfPresent([String].self, forKey: .fieldPointers) ?? [],
            partitionCount: try container.decodeIfPresent(Int.self, forKey: .partitionCount) ?? 0,
            transferredBytes: try container.decodeIfPresent(Int64.self, forKey: .transferredBytes) ?? 0,
            sampleCount: try container.decodeIfPresent(Int.self, forKey: .sampleCount),
            recordCount: try container.decodeIfPresent(Int.self, forKey: .recordCount),
            warningDayCount: try container.decodeIfPresent(Int.self, forKey: .warningDayCount) ?? 0,
            failedDayCount: try container.decodeIfPresent(Int.self, forKey: .failedDayCount) ?? 0,
            integrityWarningCount: try container.decodeIfPresent(Int.self, forKey: .integrityWarningCount) ?? 0,
            partialFailureCount: try container.decodeIfPresent(Int.self, forKey: .partialFailureCount) ?? 0
        )
    }

    var hasWarnings: Bool {
        warningDayCount > 0 || failedDayCount > 0 ||
            integrityWarningCount > 0 || partialFailureCount > 0
    }

    private static func boundedValues(
        _ values: [String],
        maximumCount: Int,
        maximumUTF8Bytes: Int
    ) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where !value.isEmpty && value.utf8.count <= maximumUTF8Bytes {
            guard seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count == maximumCount { break }
        }
        return result.sorted()
    }
}

/// Represents a single export attempt (successful or failed)
struct ExportHistoryEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let source: ExportSource
    let success: Bool
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let successCount: Int
    let totalCount: Int
    let failureReason: ExportFailureReason?
    let failedDateDetails: [FailedDateDetail]
    let targetLabel: String?
    let exportTarget: ExportTargetSelection?
    let fileCount: Int?
    let dailyNoteUpdateCount: Int
    let dailyNoteSkipCount: Int
    let partialFailures: [ExportPartialFailure]
    /// Health-free renderer provenance for diagnostics and rollback analysis.
    let appleExportEnginePin: AppleExportEnginePin?
    /// Bounded CLI request/transfer facts. Never contains exported health values.
    let operationDetails: ExportHistoryOperationDetails?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, source, success, dateRangeStart, dateRangeEnd
        case successCount, totalCount, failureReason, failedDateDetails
        case targetLabel, exportTarget, fileCount, dailyNoteUpdateCount, dailyNoteSkipCount, partialFailures
        case appleExportEnginePin, operationDetails
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: ExportSource,
        success: Bool,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        successCount: Int,
        totalCount: Int,
        failureReason: ExportFailureReason? = nil,
        failedDateDetails: [FailedDateDetail] = [],
        targetLabel: String? = nil,
        exportTarget: ExportTargetSelection? = nil,
        fileCount: Int? = nil,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0,
        partialFailures: [ExportPartialFailure] = [],
        appleExportEnginePin: AppleExportEnginePin? = nil,
        operationDetails: ExportHistoryOperationDetails? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.success = success
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.successCount = successCount
        self.totalCount = totalCount
        self.failureReason = failureReason
        self.failedDateDetails = failedDateDetails
        self.targetLabel = targetLabel
        self.exportTarget = exportTarget
        self.fileCount = fileCount
        self.dailyNoteUpdateCount = dailyNoteUpdateCount
        self.dailyNoteSkipCount = dailyNoteSkipCount
        self.partialFailures = partialFailures
        self.appleExportEnginePin = appleExportEnginePin
        self.operationDetails = operationDetails
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decode(ExportSource.self, forKey: .source)
        success = try container.decode(Bool.self, forKey: .success)
        dateRangeStart = try container.decode(Date.self, forKey: .dateRangeStart)
        dateRangeEnd = try container.decode(Date.self, forKey: .dateRangeEnd)
        successCount = try container.decode(Int.self, forKey: .successCount)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        failureReason = try container.decodeIfPresent(ExportFailureReason.self, forKey: .failureReason)
        failedDateDetails = try container.decodeIfPresent([FailedDateDetail].self, forKey: .failedDateDetails) ?? []
        targetLabel = try container.decodeIfPresent(String.self, forKey: .targetLabel)
        exportTarget = try container.decodeIfPresent(ExportTargetSelection.self, forKey: .exportTarget)
        fileCount = try container.decodeIfPresent(Int.self, forKey: .fileCount)
        dailyNoteUpdateCount = try container.decodeIfPresent(Int.self, forKey: .dailyNoteUpdateCount) ?? 0
        dailyNoteSkipCount = try container.decodeIfPresent(Int.self, forKey: .dailyNoteSkipCount) ?? 0
        partialFailures = try container.decodeIfPresent([ExportPartialFailure].self, forKey: .partialFailures) ?? []
        appleExportEnginePin = try container.decodeIfPresent(
            AppleExportEnginePin.self,
            forKey: .appleExportEnginePin
        )
        operationDetails = try container.decodeIfPresent(
            ExportHistoryOperationDetails.self,
            forKey: .operationDetails
        )
    }

    /// Returns true if all exports succeeded
    var isFullSuccess: Bool {
        success && successCount == totalCount && totalCount > 0 &&
            partialFailures.isEmpty && operationDetails?.hasWarnings != true
    }

    /// Returns true if some but not all exports succeeded
    var isPartialSuccess: Bool {
        success && (successCount > 0 || dailyNoteSkipCount > 0)
            && (successCount < totalCount || !partialFailures.isEmpty || operationDetails?.hasWarnings == true)
    }

    var partialFailureSummary: String? {
        guard let first = partialFailures.first else { return nil }
        if partialFailures.count == 1 {
            return "Warning: \(first.summary)"
        }
        return "Warning: \(partialFailures.count) metric fetches failed, including \(first.summary)"
    }

    /// Resolves the most useful reason available, including older history entries
    /// that only persisted a reason on their per-date failure details.
    var failureReasonForDisplay: ExportFailureReason? {
        guard !isFullSuccess else { return nil }
        if let failureReason { return failureReason }
        if let failedDateReason = failedDateDetails.first?.reason { return failedDateReason }
        return success ? nil : .unknown
    }

    var failureRecoverySuggestion: String? {
        failureReasonForDisplay?.recoverySuggestion
    }

    /// Keeps the history list useful at a glance. Generic and write failures use
    /// the captured error when one exists; known failures lead with the fix.
    var failureListMessage: String? {
        guard let reason = failureReasonForDisplay else { return nil }
        if reason == .unknown || reason == .fileWriteError,
           let diagnostic = failureDiagnosticDetails.first {
            return diagnostic
        }
        return reason.recoverySuggestion
    }

    /// Unique underlying messages retained by the export pipeline. These are kept
    /// separate from the plain-language reason so the UI can show them without
    /// making the primary explanation feel like a generic system error.
    var failureDiagnosticDetails: [String] {
        guard !isFullSuccess else { return [] }

        var seen: Set<String> = []
        return failedDateDetails.compactMap { detail in
            guard let rawDetails = detail.errorDetails else { return nil }
            let details = rawDetails.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !details.isEmpty, seen.insert(details).inserted else { return nil }
            return details
        }
    }

    private var isDailyNoteOnlyResult: Bool {
        (dailyNoteUpdateCount > 0 || dailyNoteSkipCount > 0) && fileCount == 0
    }

    /// Raw CLI responses transfer daily data rather than generated files. The
    /// target-label fallback repairs entries written by older app versions.
    var isCLIRawDelivery: Bool {
        if let kind = operationDetails?.kind {
            return kind == .rawExport || kind == .canonicalExtraction
        }
        guard source == .macAgent, fileCount == 0, let targetLabel else { return false }
        return targetLabel == "CLI raw response" || targetLabel == "Direct CLI raw response"
    }

    var sourceLabelForDisplay: String {
        operationDetails != nil || isCLIRawDelivery
            ? String(localized: "Health.md CLI")
            : source.rawValue
    }

    var sourceIconForDisplay: String {
        operationDetails != nil || isCLIRawDelivery ? "terminal.fill" : source.icon
    }

    /// API Endpoint exports POST daily records directly and intentionally do not
    /// create local files. The hostname fallback recognizes entries persisted by
    /// older app versions before `exportTarget` was stored in history.
    var isAPIEndpointDelivery: Bool {
        if exportTarget == .apiEndpoint { return true }
        guard exportTarget == nil,
              successCount > 0,
              fileCount == 0,
              !isDailyNoteOnlyResult,
              let targetLabel else { return false }
        return targetLabel == "localhost" || targetLabel.contains(".")
    }

    var resultCountLabel: String {
        if isDailyNoteOnlyResult {
            return String(localized: "Daily Notes Updated")
        }
        if isCLIRawDelivery {
            return String(localized: "Days Sent")
        }
        if isAPIEndpointDelivery {
            return String(localized: "Days Uploaded")
        }
        return String(localized: "Files Exported")
    }

    var resultCountDescription: String {
        if isDailyNoteOnlyResult {
            return "\(dailyNoteUpdateCount) note\(dailyNoteUpdateCount == 1 ? "" : "s") (\(successCount)/\(totalCount) days)"
        }
        if isCLIRawDelivery {
            return "\(successCount) of \(totalCount)"
        }
        if isAPIEndpointDelivery {
            return "\(successCount) of \(totalCount)"
        }
        if let fileCount {
            return "\(fileCount) file\(fileCount == 1 ? "" : "s") (\(successCount)/\(totalCount) days)"
        }
        return "\(successCount) of \(totalCount)"
    }

    var resultCountAccessibilityDescription: String {
        if isDailyNoteOnlyResult {
            return "\(dailyNoteUpdateCount) daily notes updated across \(successCount) of \(totalCount) days"
        }
        if isCLIRawDelivery {
            return "\(successCount) of \(totalCount) days sent to the CLI"
        }
        if isAPIEndpointDelivery {
            return "\(successCount) of \(totalCount) days uploaded"
        }
        return "\(fileCount ?? successCount) files exported across \(successCount) of \(totalCount) days"
    }

    /// Summary description for display
    var summaryDescription: String {
        let displayedFileCount = fileCount ?? successCount
        if isDailyNoteOnlyResult {
            if dailyNoteSkipCount == 0 {
                return String(localized: "Updated \(dailyNoteUpdateCount) daily note(s)", comment: "Daily note only export success summary")
            }
            if dailyNoteUpdateCount == 0 {
                return String(localized: "Skipped \(dailyNoteSkipCount) missing daily note(s)", comment: "Daily note only terminal skip summary")
            }
            return String(localized: "Updated \(dailyNoteUpdateCount) and skipped \(dailyNoteSkipCount) daily note(s)", comment: "Daily note only mixed outcome summary")
        } else if isCLIRawDelivery && isFullSuccess {
            return String(localized: "Sent \(successCount) day(s) to CLI", comment: "CLI raw export success summary")
        } else if isCLIRawDelivery && isPartialSuccess {
            return String(localized: "Partial: sent \(successCount)/\(totalCount) days to CLI", comment: "Partial CLI raw export summary")
        } else if isAPIEndpointDelivery && isFullSuccess {
            return String(localized: "Uploaded \(successCount) day(s) to API", comment: "API export success summary")
        } else if isAPIEndpointDelivery && isPartialSuccess {
            if !partialFailures.isEmpty {
                return String(localized: "Partial: uploaded \(successCount)/\(totalCount) days with \(partialFailures.count) metric warning(s)", comment: "Partial API export metric warning summary")
            }
            return String(localized: "Partial: uploaded \(successCount)/\(totalCount) days", comment: "Partial API export summary")
        } else if isFullSuccess {
            return String(localized: "Exported \(displayedFileCount) file(s)", comment: "Export success summary")
        } else if isPartialSuccess {
            if !partialFailures.isEmpty {
                return String(localized: "Partial: \(displayedFileCount) file(s), \(partialFailures.count) metric warning(s)", comment: "Partial export metric warning summary")
            }
            return String(localized: "Partial: \(displayedFileCount) file(s), \(successCount)/\(totalCount) days", comment: "Partial export summary")
        } else {
            let reason = failureReasonForDisplay ?? .unknown
            return String(localized: "Export failed: \(reason.shortDescription)", comment: "Export failure summary with explicit reason")
        }
    }
}

/// The source of the export (manual, scheduled, Shortcut, or Mac-agent)
enum ExportSource: String, Codable {
    case manual = "Manual"
    case scheduled = "Scheduled"
    case shortcut = "Shortcut"
    case macAgent = "iPhone → Mac"

    var icon: String {
        switch self {
        case .manual: return "hand.tap.fill"
        case .scheduled: return "clock.fill"
        case .shortcut: return "wand.and.stars"
        case .macAgent: return "iphone"
        }
    }
}

/// Reasons why an export attempt failed
enum ExportFailureReason: String, Codable {
    case noVaultSelected = "no_vault"
    case accessDenied = "access_denied"
    case noHealthData = "no_health_data"
    case healthKitError = "healthkit_error"
    case deviceLocked = "device_locked"
    case fileWriteError = "file_write_error"
    case backgroundTaskExpired = "task_expired"
    case unknown = "unknown"

    var shortDescription: String {
        switch self {
        case .noVaultSelected:
            return String(localized: "No vault selected", comment: "Short error: no vault folder selected")
        case .accessDenied:
            return String(localized: "Vault access denied", comment: "Short error: vault folder access denied")
        case .noHealthData:
            return String(localized: "No health data", comment: "Short error: no health data available")
        case .healthKitError:
            return String(localized: "HealthKit error", comment: "Short error: HealthKit error")
        case .deviceLocked:
            return String(localized: "Device locked", comment: "Short error: device is locked")
        case .fileWriteError:
            return String(localized: "File write failed", comment: "Short error: file write failed")
        case .backgroundTaskExpired:
            return String(localized: "Task timed out", comment: "Short error: background task timed out")
        case .unknown:
            return String(localized: "Unknown error", comment: "Short error: unknown")
        }
    }

    var alertTitle: String {
        switch self {
        case .noHealthData:
            return String(localized: "No Health Data Found", comment: "Alert title for an empty Apple Health export selection")
        default:
            return String(localized: "Export Couldn’t Finish", comment: "Alert title for an export failure")
        }
    }

    var detailedDescription: String {
        switch self {
        case .noVaultSelected:
            return String(localized: "No export folder was selected for this destination, so Health.md had nowhere to save the files.", comment: "Detailed error: no vault selected")
        case .accessDenied:
            return String(localized: "Health.md could not open the selected export folder. The Files, iCloud Drive, or network location may be offline, or the saved folder permission may have expired.", comment: "Detailed error: vault access denied")
        case .noHealthData:
            return String(localized: "Apple Health returned no records for the selected date range and data types. This is expected on a new or empty device, and can also happen when Health.md does not have read access to the selected data.", comment: "Detailed empty state: no health data")
        case .healthKitError:
            return String(localized: "Health.md could not read one or more requested data types from Apple Health.", comment: "Detailed error: HealthKit error")
        case .deviceLocked:
            return String(localized: "iOS protected your health data because the iPhone was locked when Health.md tried to read it.", comment: "Detailed error: device locked")
        case .fileWriteError:
            return String(localized: "Health.md reached the export destination but could not create or update one or more files.", comment: "Detailed error: file write failed")
        case .backgroundTaskExpired:
            return String(localized: "iOS ended the background export before Health.md could finish writing all requested dates.", comment: "Detailed error: task expired")
        case .unknown:
            return String(localized: "Health.md encountered an unexpected error during export. Any system message captured at the time appears in the Technical details section.", comment: "Detailed error: unknown")
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .noVaultSelected:
            return String(localized: "Choose an export folder in Health.md, then retry the export.", comment: "Recovery: no vault selected")
        case .accessDenied:
            return String(localized: "Open the folder in Files to confirm it is available. Then re-select the folder in Health.md and retry.", comment: "Recovery: vault access denied")
        case .noHealthData:
            return String(localized: "Try All Time or another date range. You can also open Apple Health and review Health.md under Profile → Apps and Services. If the device has no matching records, there is nothing to export yet.", comment: "Recovery: no health data")
        case .healthKitError:
            return String(localized: "Open the Health app and review Health.md under Profile → Apps and Services. Allow the needed data types, then retry.", comment: "Recovery: HealthKit error")
        case .deviceLocked:
            return String(localized: "Unlock your iPhone, open Health.md, and retry. Scheduled HealthKit reads cannot finish while the iPhone is locked.", comment: "Recovery: device locked")
        case .fileWriteError:
            return String(localized: "Check that the destination is online and has free space. Re-select the export folder to refresh access, then retry.", comment: "Recovery: file write failed")
        case .backgroundTaskExpired:
            return String(localized: "Open Health.md and retry while the app is visible. If it happens again, export a smaller date range.", comment: "Recovery: task expired")
        case .unknown:
            return String(localized: "Review the Technical details section below, then retry. If it fails again, include that exact message in your bug report.", comment: "Recovery: unknown export error")
        }
    }
}

/// Details about why a specific date failed to export
struct FailedDateDetail: Codable {
    let date: Date
    let reason: ExportFailureReason
    let errorDetails: String?

    init(date: Date, reason: ExportFailureReason, errorDetails: String? = nil) {
        self.date = date
        self.reason = reason
        self.errorDetails = errorDetails
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Returns the detailed error message, including raw error details if available
    var detailedMessage: String {
        if let details = errorDetails, !details.isEmpty {
            return "\(reason.detailedDescription)\n\nDetails: \(details)"
        }
        return reason.detailedDescription
    }
}

// MARK: - Export History Manager

/// Manages persistent storage of export history
class ExportHistoryManager: ObservableObject {
    static let shared = ExportHistoryManager()

    private static let historyKey = "exportHistory"
    private static let maxHistoryEntries = 50

    @Published private(set) var history: [ExportHistoryEntry] = []

    private init() {
        loadHistory()
    }

    // MARK: - Public Methods

    /// Records a successful export attempt
    func recordSuccess(
        id: UUID = UUID(),
        source: ExportSource,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        successCount: Int,
        totalCount: Int,
        failedDateDetails: [FailedDateDetail] = [],
        targetLabel: String? = nil,
        exportTarget: ExportTargetSelection? = nil,
        fileCount: Int? = nil,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0,
        partialFailures: [ExportPartialFailure] = [],
        appleExportEnginePin: AppleExportEnginePin? = nil,
        operationDetails: ExportHistoryOperationDetails? = nil
    ) {
        let entry = ExportHistoryEntry(
            id: id,
            source: source,
            success: true,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            successCount: successCount,
            totalCount: totalCount,
            failedDateDetails: failedDateDetails,
            targetLabel: targetLabel,
            exportTarget: exportTarget,
            fileCount: fileCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            partialFailures: partialFailures,
            appleExportEnginePin: appleExportEnginePin,
            operationDetails: operationDetails
        )
        addEntry(entry)
    }

    /// Records a failed export attempt
    func recordFailure(
        id: UUID = UUID(),
        source: ExportSource,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        reason: ExportFailureReason,
        successCount: Int = 0,
        totalCount: Int = 0,
        failedDateDetails: [FailedDateDetail] = [],
        targetLabel: String? = nil,
        exportTarget: ExportTargetSelection? = nil,
        fileCount: Int? = nil,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0,
        partialFailures: [ExportPartialFailure] = [],
        appleExportEnginePin: AppleExportEnginePin? = nil,
        operationDetails: ExportHistoryOperationDetails? = nil
    ) {
        let entry = ExportHistoryEntry(
            id: id,
            source: source,
            success: false,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            successCount: successCount,
            totalCount: totalCount,
            failureReason: reason,
            failedDateDetails: failedDateDetails,
            targetLabel: targetLabel,
            exportTarget: exportTarget,
            fileCount: fileCount,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            partialFailures: partialFailures,
            appleExportEnginePin: appleExportEnginePin,
            operationDetails: operationDetails
        )
        addEntry(entry)
    }

    /// Clears all history
    func clearHistory() {
        history = []
        saveHistory()
    }

    // MARK: - Private Methods

    private func addEntry(_ entry: ExportHistoryEntry) {
        guard !history.contains(where: { $0.id == entry.id }) else { return }
        history.insert(entry, at: 0)

        // Trim history to max entries
        if history.count > Self.maxHistoryEntries {
            history = Array(history.prefix(Self.maxHistoryEntries))
        }

        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([ExportHistoryEntry].self, from: data) else {
            history = []
            return
        }
        history = decoded
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: Self.historyKey)
        }
    }
}
