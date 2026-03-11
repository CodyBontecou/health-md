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
        failedDateDetails: [FailedDateDetail] = []
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
    }

    /// Returns true if all exports succeeded
    var isFullSuccess: Bool {
        success && successCount == totalCount && totalCount > 0
    }

    /// Returns true if some but not all exports succeeded
    var isPartialSuccess: Bool {
        success && successCount > 0 && successCount < totalCount
    }

    /// Summary description for display
    var summaryDescription: String {
        if isFullSuccess {
            return String(localized: "Exported \(successCount) file(s)", comment: "Export success summary")
        } else if isPartialSuccess {
            return String(localized: "Partial: \(successCount)/\(totalCount) files", comment: "Partial export summary")
        } else if let reason = failureReason {
            return reason.shortDescription
        } else {
            return String(localized: "Export failed", comment: "Export failure summary")
        }
    }
}

/// The source of the export (manual or scheduled)
enum ExportSource: String, Codable {
    case manual = "Manual"
    case scheduled = "Scheduled"

    var icon: String {
        switch self {
        case .manual: return "hand.tap.fill"
        case .scheduled: return "clock.fill"
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
            return String(localized: "Unknown error", comment: "Short error: unknown error")
        }
    }

    var detailedDescription: String {
        switch self {
        case .noVaultSelected:
            return String(localized: "No Obsidian vault folder was selected. Please select a vault in the app settings.", comment: "Detailed error: no vault selected")
        case .accessDenied:
            return String(localized: "Could not access the vault folder. You may need to re-select the folder to grant permission.", comment: "Detailed error: vault access denied")
        case .noHealthData:
            return String(localized: "No health data was available for the selected date range.", comment: "Detailed error: no health data")
        case .healthKitError:
            return String(localized: "Failed to fetch data from HealthKit. Check that health permissions are granted in the Health app.", comment: "Detailed error: HealthKit error")
        case .deviceLocked:
            return String(localized: "Health data is protected while your device is locked. The export will retry automatically when your device is unlocked.", comment: "Detailed error: device locked")
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
        failedDateDetails: [FailedDateDetail] = []
    ) {
        let entry = ExportHistoryEntry(
            source: source,
            success: true,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            successCount: successCount,
            totalCount: totalCount,
            failedDateDetails: failedDateDetails
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
        failedDateDetails: [FailedDateDetail] = []
    ) {
        let entry = ExportHistoryEntry(
            source: source,
            success: false,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            successCount: successCount,
            totalCount: totalCount,
            failureReason: reason,
            failedDateDetails: failedDateDetails
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
