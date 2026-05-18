import Foundation

enum PendingExportSource: String, Codable, Equatable {
    case scheduled
    case shortcut
}

struct PendingExportRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let dates: [Date]
    let source: PendingExportSource
    let scheduledFireDate: Date?
    let createdAt: Date
    let notificationMetadata: [String: String]

    init(
        id: UUID = UUID(),
        dates: [Date],
        source: PendingExportSource,
        scheduledFireDate: Date? = nil,
        createdAt: Date = Date(),
        notificationMetadata: [String: String] = [:],
        calendar: Calendar = .current
    ) {
        self.id = id
        self.dates = Self.normalizedDates(dates, calendar: calendar)
        self.source = source
        self.scheduledFireDate = scheduledFireDate
        self.createdAt = createdAt
        self.notificationMetadata = notificationMetadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        dates = try container.decode([Date].self, forKey: .dates)
        source = try container.decode(PendingExportSource.self, forKey: .source)
        scheduledFireDate = try container.decodeIfPresent(Date.self, forKey: .scheduledFireDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        notificationMetadata = try container.decodeIfPresent([String: String].self, forKey: .notificationMetadata) ?? [:]
    }

    private static func normalizedDates(_ dates: [Date], calendar: Calendar = .current) -> [Date] {
        let startOfDays = dates.map { calendar.startOfDay(for: $0) }
        return Array(Set(startOfDays)).sorted()
    }
}

protocol PendingExportStoring {
    func loadAll() throws -> [PendingExportRequest]
    func upsert(_ request: PendingExportRequest) throws
    func remove(id: PendingExportRequest.ID) throws
    func clearCompletedRequests(ids: Set<PendingExportRequest.ID>) throws
    func notificationIdentifier(for request: PendingExportRequest) -> String
}

struct PendingExportStore: PendingExportStoring {
    static let storageKey = "pendingExportRequests"

    private let userDefaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func loadAll() throws -> [PendingExportRequest] {
        guard let data = userDefaults.data(forKey: Self.storageKey) else {
            return []
        }
        return (try? decoder.decode([PendingExportRequest].self, from: data)) ?? []
    }

    func upsert(_ request: PendingExportRequest) throws {
        var requests = try loadAll()
        requests.removeAll { existing in
            existing.id == request.id || shouldReplace(existing: existing, with: request)
        }
        requests.append(request)
        try save(requests)
    }

    func remove(id: PendingExportRequest.ID) throws {
        let remaining = try loadAll().filter { $0.id != id }
        try save(remaining)
    }

    func clearCompletedRequests(ids: Set<PendingExportRequest.ID>) throws {
        guard !ids.isEmpty else { return }
        let remaining = try loadAll().filter { !ids.contains($0.id) }
        try save(remaining)
    }

    func notificationIdentifier(for request: PendingExportRequest) -> String {
        ExportNotificationIdentifiers.pendingExport(for: request)
    }

    private func shouldReplace(existing: PendingExportRequest, with request: PendingExportRequest) -> Bool {
        if existing.source == .shortcut && request.source == .shortcut {
            return existing.dates == request.dates
        }

        return existing.source == .scheduled
            && request.source == .scheduled
            && existing.scheduledFireDate == request.scheduledFireDate
            && request.scheduledFireDate != nil
    }

    private func save(_ requests: [PendingExportRequest]) throws {
        let sorted = requests.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
        let data = try encoder.encode(sorted)
        userDefaults.set(data, forKey: Self.storageKey)
    }
}
