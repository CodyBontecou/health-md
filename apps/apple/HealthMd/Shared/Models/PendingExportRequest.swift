import Foundation

enum PendingExportSource: String, Codable, Equatable {
    case scheduled
    case shortcut
}

struct PendingExportRequest: Codable, Equatable, Identifiable {
    let id: UUID
    /// Residual dates still requiring daily work.
    private(set) var dates: [Date]
    /// Immutable original owner-date request used to overwrite/regenerate the same range summary.
    let originalRequestedDates: [Date]
    /// Frozen calendar authority for the original request. Nil identifies a legacy request.
    let originalCalendarTimeZoneIdentifier: String?
    let source: PendingExportSource
    let scheduledFireDate: Date?
    let scheduledKind: ScheduledExportKind
    let createdAt: Date
    let notificationMetadata: [String: String]
    /// Scheduled export destination captured at the time work is queued. Nil
    /// means legacy local-folder behavior for previously persisted requests or
    /// Shortcut requests, which intentionally keep their iPhone-folder pipeline.
    let exportTarget: ExportTargetSelection?
    /// Frozen output-affecting settings for durable scheduled work. A missing snapshot identifies
    /// an explicitly legacy request that continues to read mutable settings at execution time.
    let settingsSnapshot: ExportSettingsSnapshot?
    /// Export profile this scheduled request runs (phase 3). Per-profile
    /// in-flight identity: two profiles' pending requests never deduplicate
    /// each other. Nil identifies legacy profile-free requests.
    let profileID: UUID?
    /// Display name captured at queue time for notifications and history
    /// labels. Not used for resolution — `profileID` is authoritative.
    let profileName: String?
    /// When a scheduled run attempted this request and preserved unresolved
    /// dates for retry. An attempted request is a preserved retry: bulk
    /// fallback re-arm cancellation must never delete it (only its exact-ID
    /// completion/discard paths may). Nil means the request was armed as a
    /// not-yet-fired fallback and never ran.
    private(set) var attemptedAt: Date?

    /// Copy with `attemptedAt` set, preserving the already-normalized dates
    /// exactly. The designated initializer re-normalizes through its calendar
    /// and would shift dates captured under a different timezone.
    func markingAttempted(at timestamp: Date) -> PendingExportRequest {
        replacingResidualDates(dates, attemptedAt: timestamp)
    }

    /// Copy with reduced residual work while preserving the immutable original
    /// owner-date instants byte-for-byte. Callers must compute `dates` with the
    /// request's frozen timezone authority before using this method.
    func replacingResidualDates(
        _ dates: [Date],
        attemptedAt timestamp: Date
    ) -> PendingExportRequest {
        var copy = self
        copy.dates = dates
        copy.attemptedAt = timestamp
        return copy
    }

    var usesLegacyMutableSettings: Bool { settingsSnapshot == nil }

    init(
        id: UUID = UUID(),
        dates: [Date],
        originalRequestedDates: [Date]? = nil,
        originalCalendarTimeZoneIdentifier: String? = nil,
        source: PendingExportSource,
        scheduledFireDate: Date? = nil,
        scheduledKind: ScheduledExportKind = .completedDay,
        createdAt: Date = Date(),
        notificationMetadata: [String: String] = [:],
        exportTarget: ExportTargetSelection? = nil,
        settingsSnapshot: ExportSettingsSnapshot? = nil,
        profileID: UUID? = nil,
        profileName: String? = nil,
        attemptedAt: Date? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.dates = Self.normalizedDates(dates, calendar: calendar)
        self.originalRequestedDates = Self.normalizedDates(
            originalRequestedDates ?? dates,
            calendar: calendar
        )
        self.originalCalendarTimeZoneIdentifier = originalCalendarTimeZoneIdentifier
            ?? settingsSnapshot?.calendarTimeZoneIdentifier
            ?? calendar.timeZone.identifier
        self.source = source
        self.scheduledFireDate = scheduledFireDate
        self.scheduledKind = source == .scheduled ? scheduledKind : .completedDay
        self.createdAt = createdAt
        self.notificationMetadata = notificationMetadata
        self.exportTarget = source == .scheduled ? exportTarget : nil
        self.settingsSnapshot = settingsSnapshot
        self.profileID = source == .scheduled ? profileID : nil
        self.profileName = source == .scheduled ? profileName : nil
        self.attemptedAt = source == .scheduled ? attemptedAt : nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        dates = try container.decode([Date].self, forKey: .dates)
        originalRequestedDates = try container.decodeIfPresent(
            [Date].self,
            forKey: .originalRequestedDates
        ) ?? dates
        source = try container.decode(PendingExportSource.self, forKey: .source)
        scheduledFireDate = try container.decodeIfPresent(Date.self, forKey: .scheduledFireDate)
        scheduledKind = source == .scheduled
            ? (try container.decodeIfPresent(ScheduledExportKind.self, forKey: .scheduledKind) ?? .completedDay)
            : .completedDay
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        notificationMetadata = try container.decodeIfPresent([String: String].self, forKey: .notificationMetadata) ?? [:]
        exportTarget = source == .scheduled
            ? try container.decodeIfPresent(ExportTargetSelection.self, forKey: .exportTarget)
            : nil
        // Missing snapshots are intentionally legacy. Decoding never freezes current preferences.
        settingsSnapshot = try container.decodeIfPresent(
            ExportSettingsSnapshot.self,
            forKey: .settingsSnapshot
        )
        originalCalendarTimeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .originalCalendarTimeZoneIdentifier
        ) ?? settingsSnapshot?.calendarTimeZoneIdentifier
        // Phase-3 identity is additive: legacy persisted requests decode as
        // profile-free and keep their legacy execution path.
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName)
        // Pre-marker persisted requests decode as never-attempted; the
        // fallback-window heuristic covers those during migration.
        attemptedAt = try container.decodeIfPresent(Date.self, forKey: .attemptedAt)
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

        // Per-profile replacement identity: two profiles (or a profile and
        // the legacy schedule) firing at the same minute must never clobber
        // each other's stored request or preserved retry — the stable-ID
        // notification of a clobbered request would become a dead tap.
        return existing.source == .scheduled
            && request.source == .scheduled
            && existing.scheduledFireDate == request.scheduledFireDate
            && existing.scheduledKind == request.scheduledKind
            && existing.profileID == request.profileID
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
