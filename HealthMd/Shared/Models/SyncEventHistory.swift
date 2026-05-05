import Foundation
import Combine

// MARK: - Sync Event

/// Represents a single iPhone→Mac sync event recorded for the Sync history view.
struct SyncEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let peerName: String
    let kind: SyncEventKind
    let recordCount: Int
    let payloadByteEstimate: Int
    let dateRangeStart: Date?
    let dateRangeEnd: Date?
    let failureMessage: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        peerName: String,
        kind: SyncEventKind,
        recordCount: Int = 0,
        payloadByteEstimate: Int = 0,
        dateRangeStart: Date? = nil,
        dateRangeEnd: Date? = nil,
        failureMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.peerName = peerName
        self.kind = kind
        self.recordCount = recordCount
        self.payloadByteEstimate = payloadByteEstimate
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.failureMessage = failureMessage
    }

    var isSuccess: Bool {
        kind != .failed
    }

    /// Short summary suitable for a list row title.
    var summaryDescription: String {
        switch kind {
        case .dataReceived:
            if recordCount == 0 {
                return String(localized: "No new records", comment: "Sync event: empty payload")
            }
            return String(localized: "Received \(recordCount) record(s)", comment: "Sync event: data received")
        case .progressComplete:
            return String(localized: "Sync complete", comment: "Sync event: full sync complete")
        case .failed:
            return failureMessage ?? String(localized: "Sync failed", comment: "Sync event: failed")
        }
    }
}

/// What kind of sync activity the entry represents.
enum SyncEventKind: String, Codable {
    case dataReceived
    case progressComplete
    case failed
}

// MARK: - Sync Event History Manager

/// Persistent storage for iPhone→Mac sync events. Mirrors ExportHistoryManager.
final class SyncEventHistoryManager: ObservableObject {
    static let shared = SyncEventHistoryManager()

    private static let historyKey = "syncEventHistory"
    private static let maxHistoryEntries = 50

    @Published private(set) var history: [SyncEvent] = []

    private init() {
        loadHistory()
    }

    // MARK: - Public Methods

    func record(_ event: SyncEvent) {
        history.insert(event, at: 0)

        if history.count > Self.maxHistoryEntries {
            history = Array(history.prefix(Self.maxHistoryEntries))
        }

        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    // MARK: - Private Methods

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([SyncEvent].self, from: data) else {
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
