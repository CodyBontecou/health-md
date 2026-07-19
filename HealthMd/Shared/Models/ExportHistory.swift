import Foundation
import Combine

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

    enum CodingKeys: String, CodingKey {
        case id, timestamp, source, success, dateRangeStart, dateRangeEnd
        case successCount, totalCount, failureReason, failedDateDetails
        case targetLabel, exportTarget, fileCount, dailyNoteUpdateCount, dailyNoteSkipCount, partialFailures
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
        partialFailures: [ExportPartialFailure] = []
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
    }

    /// Returns true if all exports succeeded
    var isFullSuccess: Bool {
        success && successCount == totalCount && totalCount > 0 && partialFailures.isEmpty
    }

    /// Returns true if some but not all exports succeeded
    var isPartialSuccess: Bool {
        success && (successCount > 0 || dailyNoteSkipCount > 0)
            && (successCount < totalCount || !partialFailures.isEmpty)
    }

    var partialFailureSummary: String? {
        guard let first = partialFailures.first else { return nil }
        if partialFailures.count == 1 {
            return "Warning: \(first.summary)"
        }
        return "Warning: \(partialFailures.count) metric fetches failed, including \(first.summary)"
    }

    private var isDailyNoteOnlyResult: Bool {
        (dailyNoteUpdateCount > 0 || dailyNoteSkipCount > 0) && fileCount == 0
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
        if isAPIEndpointDelivery {
            return String(localized: "Days Uploaded")
        }
        return String(localized: "Files Exported")
    }

    var resultCountDescription: String {
        if isDailyNoteOnlyResult {
            return "\(dailyNoteUpdateCount) note\(dailyNoteUpdateCount == 1 ? "" : "s") (\(successCount)/\(totalCount) days)"
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
        } else if let reason = failureReason {
            return reason.shortDescription
        } else {
            return String(localized: "Export failed", comment: "Export failure summary")
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

    var detailedDescription: String {
        switch self {
        case .noVaultSelected:
            return String(localized: "No Obsidian vault folder was selected. Please select a vault in the app settings.", comment: "Detailed error: no vault selected")
        case .accessDenied:
            return String(localized: "Could not access the vault folder. If it lives in Files, iCloud Drive, or a network share, reconnect that location and try again. You may need to re-select the folder to refresh permission.", comment: "Detailed error: vault access denied")
        case .noHealthData:
            return String(localized: "No health data was available for the selected date range.", comment: "Detailed error: no health data")
        case .healthKitError:
            return String(localized: "Failed to fetch data from HealthKit. Check that health permissions are granted in the Health app.", comment: "Detailed error: HealthKit error")
        case .deviceLocked:
            return String(localized: "Health data is protected while your device is locked. Unlock your device and try the export again.", comment: "Detailed error: device locked")
        case .fileWriteError:
            return String(localized: "Failed to write the export file to the vault folder.", comment: "Detailed error: file write failed")
        case .backgroundTaskExpired:
            return String(localized: "The background export task was terminated by iOS before completing.", comment: "Detailed error: task expired")
        case .unknown:
            return String(localized: "An unexpected error occurred during export.", comment: "Detailed error: unknown")
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
        partialFailures: [ExportPartialFailure] = []
    ) {
        let entry = ExportHistoryEntry(
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
            partialFailures: partialFailures
        )
        addEntry(entry)
    }

    /// Records a failed export attempt
    func recordFailure(
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
        partialFailures: [ExportPartialFailure] = []
    ) {
        let entry = ExportHistoryEntry(
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
            partialFailures: partialFailures
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
