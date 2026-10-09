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
    /// an explicitly legacy request for non-attribution settings.
    let settingsSnapshot: ExportSettingsSnapshot?
    /// Capture-only authority also covers Shortcut jobs that intentionally do not
    /// freeze the full export configuration. Missing legacy authority stays missing.
    let sleepCaptureContext: AppleSleepCaptureContext?
    /// Export profile this scheduled request runs (phase 3). Per-profile
    /// in-flight identity: two profiles' pending requests never deduplicate
    /// each other. Nil identifies legacy profile-free requests.
    let profileID: UUID?
    /// Display name captured at queue time for notifications and history
    /// labels. Not used for resolution — `profileID` is authoritative.
    let profileName: String?
    /// Local runtime authority, not part of the exported health-data contract.
    let recoveryGeneration: Int
    let scheduleEnabledAt: Date?
    let apiDestinationIdentity: ScheduledAPIEndpointIdentity?
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
        sleepCaptureContext: AppleSleepCaptureContext? = nil,
        profileID: UUID? = nil,
        profileName: String? = nil,
        recoveryGeneration: Int = 0,
        scheduleEnabledAt: Date? = nil,
        apiDestinationIdentity: ScheduledAPIEndpointIdentity? = nil,
        attemptedAt: Date? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.dates = Self.normalizedDates(dates, calendar: calendar)
        let frozenOriginalTimeZoneIdentifier = originalCalendarTimeZoneIdentifier
            ?? settingsSnapshot?.calendarTimeZoneIdentifier
            ?? calendar.timeZone.identifier
        var originalCalendar = Calendar(identifier: .gregorian)
        originalCalendar.timeZone = TimeZone(identifier: frozenOriginalTimeZoneIdentifier)
            ?? calendar.timeZone
        self.originalRequestedDates = Self.normalizedDates(
            originalRequestedDates ?? dates,
            calendar: originalCalendar
        )
        self.originalCalendarTimeZoneIdentifier = frozenOriginalTimeZoneIdentifier
        self.source = source
        self.scheduledFireDate = scheduledFireDate
        self.scheduledKind = source == .scheduled ? scheduledKind : .completedDay
        self.createdAt = createdAt
        self.notificationMetadata = notificationMetadata
        self.exportTarget = source == .scheduled ? exportTarget : nil
        self.settingsSnapshot = settingsSnapshot
        self.sleepCaptureContext = sleepCaptureContext ?? settingsSnapshot?.sleepCaptureContext
        self.profileID = source == .scheduled ? profileID : nil
        self.profileName = source == .scheduled ? profileName : nil
        self.recoveryGeneration = source == .scheduled ? recoveryGeneration : 0
        self.scheduleEnabledAt = source == .scheduled ? scheduleEnabledAt : nil
        self.apiDestinationIdentity = source == .scheduled ? apiDestinationIdentity : nil
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
        sleepCaptureContext = try container.decodeIfPresent(AppleSleepCaptureContext.self, forKey: .sleepCaptureContext)
        originalCalendarTimeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .originalCalendarTimeZoneIdentifier
        ) ?? settingsSnapshot?.calendarTimeZoneIdentifier
        // Phase-3 identity is additive: legacy persisted requests decode as
        // profile-free and keep their legacy execution path.
        profileID = try container.decodeIfPresent(UUID.self, forKey: .profileID)
        profileName = try container.decodeIfPresent(String.self, forKey: .profileName)
        recoveryGeneration = try container.decodeIfPresent(Int.self, forKey: .recoveryGeneration) ?? 0
        scheduleEnabledAt = try container.decodeIfPresent(Date.self, forKey: .scheduleEnabledAt)
        // Legacy API work lacks proof of its original destination. Do not synthesize it
        // from mutable preferences on resume; execution will fail closed.
        apiDestinationIdentity = try container.decodeIfPresent(
            ScheduledAPIEndpointIdentity.self, forKey: .apiDestinationIdentity
        )
        // Pre-marker persisted requests decode as never-attempted; the
        // fallback-window heuristic covers those during migration.
        attemptedAt = try container.decodeIfPresent(Date.self, forKey: .attemptedAt)
    }


    func recoveredSleepCaptureContext() throws -> AppleSleepCaptureContext {
        if let sleepCaptureContext, let snapshotContext = settingsSnapshot?.sleepCaptureContext,
           sleepCaptureContext != snapshotContext {
            throw AppleSleepCaptureContext.AvailabilityError.missingDurableAttribution
        }
        if let settingsSnapshot {
            return try settingsSnapshot.recoveredSleepCaptureContext(captureContext: sleepCaptureContext)
        }
        return try AppleSleepCaptureContext.recovered(sleepCaptureContext)
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

nonisolated enum PendingExportStoreError: Error, LocalizedError, Equatable {
    case unreadableJournal
    case incompatibleRequestAuthority

    var errorDescription: String? {
        switch self {
        case .unreadableJournal:
            String(localized: "Saved pending exports cannot be read by this app version. They have been preserved.")
        case .incompatibleRequestAuthority:
            String(localized: "This pending export cannot change its saved capture authority. Start a separate export.")
        }
    }
}

struct PendingExportStore: PendingExportStoring {
    static let storageKey = "pendingExportRequests"
    static let successorStorageKey = "pendingExportRequests.sleep-attribution.v1"

    private enum Queue: CaseIterable {
        case historical, successor
        var key: String { self == .historical ? PendingExportStore.storageKey : PendingExportStore.successorStorageKey }
    }

    private struct SuccessorJournal: Codable {
        let schema: String
        let version: Int
        let requests: [PendingExportRequest]
        static let schemaID = "healthmd.pending_exports.sleep_attribution"
    }

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
        self.encoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        self.decoder = decoder
    }

    func loadAll() throws -> [PendingExportRequest] {
        sorted(try loadQueues().values.flatMap { $0 })
    }

    private func loadQueues() throws -> [Queue: [PendingExportRequest]] {
        var queues: [Queue: [PendingExportRequest]] = [:]
        do {
            for queue in Queue.allCases {
                guard let stored = userDefaults.object(forKey: queue.key) else {
                    queues[queue] = []
                    continue
                }
                guard let data = stored as? Data else { throw PendingExportStoreError.unreadableJournal }
                switch queue {
                case .historical:
                    queues[queue] = try decoder.decode([PendingExportRequest].self, from: data)
                case .successor:
                    let journal = try decoder.decode(SuccessorJournal.self, from: data)
                    guard journal.schema == SuccessorJournal.schemaID, journal.version == 1,
                          journal.requests.allSatisfy({ Self.requiresProfileIsolation($0) }) else {
                        throw PendingExportStoreError.unreadableJournal
                    }
                    queues[queue] = journal.requests
                }
            }
            let ids = queues.values.flatMap { $0.map(\.id) }
            guard Set(ids).count == ids.count else { throw PendingExportStoreError.unreadableJournal }
            return queues
        } catch {
            throw PendingExportStoreError.unreadableJournal
        }
    }

    private static func requiresProfileIsolation(_ request: PendingExportRequest) -> Bool {
        request.sleepCaptureContext?.sleepDayAttribution == .morningEnds
            || request.settingsSnapshot?.sleepCaptureContext?.sleepDayAttribution == .morningEnds
            || request.settingsSnapshot?.appleExportEnginePin.map { $0.profile != AppleExportEnginePin.profileID } == true
    }

    private func sameCaptureAuthority(_ lhs: PendingExportRequest, _ rhs: PendingExportRequest) -> Bool {
        lhs.sleepCaptureContext == rhs.sleepCaptureContext
            && lhs.settingsSnapshot?.sleepCaptureContext == rhs.settingsSnapshot?.sleepCaptureContext
            && lhs.settingsSnapshot?.appleExportEnginePin == rhs.settingsSnapshot?.appleExportEnginePin
            && lhs.originalCalendarTimeZoneIdentifier == rhs.originalCalendarTimeZoneIdentifier
    }

    func upsert(_ request: PendingExportRequest) throws {
        let queues = try loadQueues()
        let existingQueue = queues.first { $0.value.contains { $0.id == request.id } }
        if let existing = existingQueue?.value.first(where: { $0.id == request.id }),
           !sameCaptureAuthority(existing, request) {
            throw PendingExportStoreError.incompatibleRequestAuthority
        }
        // Never move a persisted draft job out of its original namespace on upgrade.
        // New successor work goes where historical binaries cannot discover or replace it.
        let queue = existingQueue?.key ?? (Self.requiresProfileIsolation(request) ? .successor : .historical)
        var requests = queues[queue, default: []]
        requests.removeAll { $0.id == request.id || shouldReplace(existing: $0, with: request) }
        requests.append(request)
        try saveChanges([queue: requests])
    }

    func remove(id: PendingExportRequest.ID) throws {
        try clearCompletedRequests(ids: [id])
    }

    func clearCompletedRequests(ids: Set<PendingExportRequest.ID>) throws {
        guard !ids.isEmpty else { return }
        let queues = try loadQueues()
        var changes: [Queue: [PendingExportRequest]] = [:]
        for (queue, requests) in queues where requests.contains(where: { ids.contains($0.id) }) {
            changes[queue] = requests.filter { !ids.contains($0.id) }
        }
        try saveChanges(changes)
    }

    func notificationIdentifier(for request: PendingExportRequest) -> String {
        ExportNotificationIdentifiers.pendingExport(for: request)
    }

    private func shouldReplace(existing: PendingExportRequest, with request: PendingExportRequest) -> Bool {
        guard sameCaptureAuthority(existing, request) else { return false }
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
            && existing.recoveryGeneration == request.recoveryGeneration
            && request.scheduledFireDate != nil
    }

    private func sorted(_ requests: [PendingExportRequest]) -> [PendingExportRequest] {
        requests.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func saveChanges(_ changes: [Queue: [PendingExportRequest]]) throws {
        // Encode every changed queue before modifying either key. An encoding failure
        // must preserve all bytes, and unrelated historical bytes are never re-encoded.
        var encoded: [Queue: Data] = [:]
        for (queue, requests) in changes {
            switch queue {
            case .historical:
                encoded[queue] = try encoder.encode(sorted(requests))
            case .successor:
                encoded[queue] = try encoder.encode(SuccessorJournal(
                    schema: SuccessorJournal.schemaID, version: 1, requests: sorted(requests)))
            }
        }
        for (queue, data) in encoded { userDefaults.set(data, forKey: queue.key) }
    }
}
