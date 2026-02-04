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
            return "Exported \(successCount) file\(successCount == 1 ? "" : "s")"
        } else if isPartialSuccess {
            return "Partial: \(successCount)/\(totalCount) files"
        } else if let reason = failureReason {
            return reason.shortDescription
        } else {
            return "Export failed"
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
            return "No vault selected"
        case .accessDenied:
            return "Vault access denied"
        case .noHealthData:
            return "No health data"
        case .healthKitError:
            return "HealthKit error"
        case .deviceLocked:
            return "Device locked"
        case .fileWriteError:
            return "File write failed"
        case .backgroundTaskExpired:
            return "Task timed out"
        case .unknown:
            return "Unknown error"
        }
    }

    var detailedDescription: String {
        switch self {
        case .noVaultSelected:
            return "No Obsidian vault folder was selected. Please select a vault in the app settings."
        case .accessDenied:
            return "Could not access the vault folder. You may need to re-select the folder to grant permission."
        case .noHealthData:
            return "No health data was available for the selected date range."
        case .healthKitError:
            return "Failed to fetch data from HealthKit. Check that health permissions are granted in the Health app."
        case .deviceLocked:
            return "Health data is protected while your device is locked. The export will retry automatically when your device is unlocked."
        case .fileWriteError:
            return "Failed to write the export file to the vault folder."
        case .backgroundTaskExpired:
            return "The background export task was terminated by iOS before completing."
        case .unknown:
            return "An unexpected error occurred during export."
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
