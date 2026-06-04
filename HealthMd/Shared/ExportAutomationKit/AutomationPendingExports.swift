import Foundation

/// Domain-free source family for pending automation work that needs a foreground retry.
///
/// Pending requests store only the original export family so notification taps
/// and app-active drains can retry the exact request through the generic
/// `ExportTriggerSource` policy without changing persisted raw values.
enum AutomationPendingExportSource: String, Codable, Equatable, Sendable {
    case scheduled
    case shortcut
}

/// Domain-free reason taxonomy for preserving retryable pending export work.
enum AutomationPendingExportReason: String, Codable, Equatable, Sendable {
    case protectedDataUnavailable = "protected_data_unavailable"
    case destinationAccessDenied = "destination_access_denied"
    case quotaBlocked = "quota_blocked"
    case noData = "no_data"
    case unknown = "unknown"

    init(backgroundFailureReason: AutomationBackgroundExportFailureReason) {
        switch backgroundFailureReason {
        case .protectedDataUnavailable:
            self = .protectedDataUnavailable
        case .noDestination:
            self = .destinationAccessDenied
        case .quotaBlocked:
            self = .quotaBlocked
        case .noData:
            self = .noData
        case .cancelled, .timeLimitExceeded, .exportFailed, .unknown:
            self = .unknown
        }
    }
}

/// Persisted retry request for an export attempt that could not finish.
///
/// The stored dates are the exact record dates to retry. Construction normalizes
/// newly-created requests to start-of-day, sorted order for duplicate detection;
/// decoding preserves already-persisted dates exactly for compatibility.
struct AutomationPendingExportRequest: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let dates: [Date]
    let source: AutomationPendingExportSource
    let reason: AutomationPendingExportReason?
    let scheduledFireDate: Date?
    let createdAt: Date
    let metadata: [String: String]

    /// Compatibility alias for existing app call sites while the generic shape
    /// uses neutral metadata naming.
    var notificationMetadata: [String: String] { metadata }

    var requestedDates: [Date] { dates }

    init(
        id: UUID = UUID(),
        dates: [Date],
        source: AutomationPendingExportSource,
        reason: AutomationPendingExportReason? = nil,
        scheduledFireDate: Date? = nil,
        createdAt: Date = Date(),
        metadata: [String: String] = [:],
        notificationMetadata: [String: String]? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.dates = Self.normalizedDates(dates, calendar: calendar)
        self.source = source
        self.reason = reason
        self.scheduledFireDate = scheduledFireDate
        self.createdAt = createdAt
        self.metadata = notificationMetadata ?? metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        dates = try container.decode([Date].self, forKey: .dates)
        source = try container.decode(AutomationPendingExportSource.self, forKey: .source)
        reason = try container.decodeIfPresent(AutomationPendingExportReason.self, forKey: .reason)
        scheduledFireDate = try container.decodeIfPresent(Date.self, forKey: .scheduledFireDate)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
            ?? container.decodeIfPresent([String: String].self, forKey: .notificationMetadata)
            ?? [:]
    }

    private init(
        id: UUID,
        preservingDates dates: [Date],
        source: AutomationPendingExportSource,
        reason: AutomationPendingExportReason?,
        scheduledFireDate: Date?,
        createdAt: Date,
        metadata: [String: String]
    ) {
        self.id = id
        self.dates = dates
        self.source = source
        self.reason = reason
        self.scheduledFireDate = scheduledFireDate
        self.createdAt = createdAt
        self.metadata = metadata
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(dates, forKey: .dates)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(scheduledFireDate, forKey: .scheduledFireDate)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(metadata, forKey: .notificationMetadata)
    }

    func with(reason newReason: AutomationPendingExportReason?) -> AutomationPendingExportRequest {
        AutomationPendingExportRequest(
            id: id,
            preservingDates: dates,
            source: source,
            reason: newReason,
            scheduledFireDate: scheduledFireDate,
            createdAt: createdAt,
            metadata: metadata
        )
    }

    private static func normalizedDates(_ dates: [Date], calendar: Calendar = .current) -> [Date] {
        let startOfDays = dates.map { calendar.startOfDay(for: $0) }
        return Array(Set(startOfDays)).sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case dates
        case source
        case reason
        case scheduledFireDate
        case createdAt
        case metadata
        case notificationMetadata
    }
}

protocol AutomationPendingExportStoring {
    func loadAll() throws -> [AutomationPendingExportRequest]
    func upsert(_ request: AutomationPendingExportRequest) throws
    func remove(id: AutomationPendingExportRequest.ID) throws
    func clearCompletedRequests(ids: Set<AutomationPendingExportRequest.ID>) throws
    func notificationIdentifier(for request: AutomationPendingExportRequest) -> String
}

struct AutomationPendingExportNotificationIdentifierFactory: Equatable, Sendable {
    var prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func pendingExport(id: AutomationPendingExportRequest.ID) -> String {
        prefix + id.uuidString.lowercased()
    }

    func pendingExport(for request: AutomationPendingExportRequest) -> String {
        pendingExport(id: request.id)
    }
}

struct AutomationPendingExportStore: AutomationPendingExportStoring {
    static let storageKey = "pendingExportRequests"

    let storageKey: String
    let userDefaults: UserDefaults
    let encoder: JSONEncoder
    let decoder: JSONDecoder
    let notificationIdentifierFactory: AutomationPendingExportNotificationIdentifierFactory

    init(
        storageKey: String = Self.storageKey,
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder(),
        notificationIdentifierFactory: AutomationPendingExportNotificationIdentifierFactory = AutomationPendingExportNotificationIdentifierFactory(prefix: "exportAutomation.pending-export.")
    ) {
        self.storageKey = storageKey
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
        self.notificationIdentifierFactory = notificationIdentifierFactory
    }

    func loadAll() throws -> [AutomationPendingExportRequest] {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return []
        }
        return (try? decoder.decode([AutomationPendingExportRequest].self, from: data)) ?? []
    }

    func upsert(_ request: AutomationPendingExportRequest) throws {
        var requests = try loadAll()
        requests.removeAll { existing in
            existing.id == request.id || shouldReplace(existing: existing, with: request)
        }
        requests.append(request)
        try save(requests)
    }

    func remove(id: AutomationPendingExportRequest.ID) throws {
        let remaining = try loadAll().filter { $0.id != id }
        try save(remaining)
    }

    func clearCompletedRequests(ids: Set<AutomationPendingExportRequest.ID>) throws {
        guard !ids.isEmpty else { return }
        let remaining = try loadAll().filter { !ids.contains($0.id) }
        try save(remaining)
    }

    func notificationIdentifier(for request: AutomationPendingExportRequest) -> String {
        notificationIdentifierFactory.pendingExport(for: request)
    }

    private func shouldReplace(existing: AutomationPendingExportRequest, with request: AutomationPendingExportRequest) -> Bool {
        if existing.source == .shortcut && request.source == .shortcut {
            return existing.dates == request.dates
        }

        return existing.source == .scheduled
            && request.source == .scheduled
            && existing.scheduledFireDate == request.scheduledFireDate
            && request.scheduledFireDate != nil
    }

    private func save(_ requests: [AutomationPendingExportRequest]) throws {
        let sorted = requests.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
        let data = try encoder.encode(sorted)
        userDefaults.set(data, forKey: storageKey)
    }
}

struct AutomationPendingExportNotificationConfiguration: Equatable, Sendable {
    var identifierFactory: AutomationPendingExportNotificationIdentifierFactory
    var typeValue: String
    var typeUserInfoKey: String
    var requestIDUserInfoKey: String
    var sourceUserInfoKey: String
    var reasonUserInfoKey: String
    var categoryIdentifier: String
    var threadIdentifier: String

    init(
        identifierPrefix: String,
        typeValue: String = "pending-export",
        typeUserInfoKey: String = "exportAutomation.notification.type",
        requestIDUserInfoKey: String = "exportAutomation.pendingExport.requestID",
        sourceUserInfoKey: String = "exportAutomation.pendingExport.source",
        reasonUserInfoKey: String = "exportAutomation.pendingExport.reason",
        categoryIdentifier: String = "exportAutomation.pending-export.retry",
        threadIdentifier: String? = nil
    ) {
        self.identifierFactory = AutomationPendingExportNotificationIdentifierFactory(prefix: identifierPrefix)
        self.typeValue = typeValue
        self.typeUserInfoKey = typeUserInfoKey
        self.requestIDUserInfoKey = requestIDUserInfoKey
        self.sourceUserInfoKey = sourceUserInfoKey
        self.reasonUserInfoKey = reasonUserInfoKey
        self.categoryIdentifier = categoryIdentifier
        self.threadIdentifier = threadIdentifier ?? categoryIdentifier
    }
}

struct AutomationPendingExportNotificationPayload: Equatable, Sendable {
    let requestID: AutomationPendingExportRequest.ID
    let source: AutomationPendingExportSource
    let reason: AutomationPendingExportReason?

    init(
        requestID: AutomationPendingExportRequest.ID,
        source: AutomationPendingExportSource,
        reason: AutomationPendingExportReason? = nil
    ) {
        self.requestID = requestID
        self.source = source
        self.reason = reason
    }

    init(request: AutomationPendingExportRequest) {
        self.init(requestID: request.id, source: request.source, reason: request.reason)
    }

    init?(userInfo: [AnyHashable: Any], configuration: AutomationPendingExportNotificationConfiguration) {
        guard userInfo[configuration.typeUserInfoKey] as? String == configuration.typeValue,
              let requestIDString = userInfo[configuration.requestIDUserInfoKey] as? String,
              let requestID = UUID(uuidString: requestIDString),
              let sourceString = userInfo[configuration.sourceUserInfoKey] as? String,
              let source = AutomationPendingExportSource(rawValue: sourceString)
        else {
            return nil
        }

        self.requestID = requestID
        self.source = source

        if let reasonString = userInfo[configuration.reasonUserInfoKey] as? String {
            self.reason = AutomationPendingExportReason(rawValue: reasonString)
        } else {
            self.reason = nil
        }
    }

    func userInfo(configuration: AutomationPendingExportNotificationConfiguration) -> [String: String] {
        var userInfo = [
            configuration.typeUserInfoKey: configuration.typeValue,
            configuration.requestIDUserInfoKey: requestID.uuidString.lowercased(),
            configuration.sourceUserInfoKey: source.rawValue
        ]
        if let reason {
            userInfo[configuration.reasonUserInfoKey] = reason.rawValue
        }
        return userInfo
    }
}

enum AutomationPendingExportNotificationTapRoute: Equatable, Sendable {
    case pendingExport(AutomationPendingExportNotificationPayload)
    case legacyScheduledExportReminder
}

struct AutomationPendingExportNotificationTapRouter {
    var configuration: AutomationPendingExportNotificationConfiguration
    var isLegacyScheduledExportReminderIdentifier: (String) -> Bool

    init(
        configuration: AutomationPendingExportNotificationConfiguration,
        isLegacyScheduledExportReminderIdentifier: @escaping (String) -> Bool = { _ in false }
    ) {
        self.configuration = configuration
        self.isLegacyScheduledExportReminderIdentifier = isLegacyScheduledExportReminderIdentifier
    }

    func route(
        identifier: String,
        userInfo: [AnyHashable: Any]
    ) -> AutomationPendingExportNotificationTapRoute? {
        if let payload = AutomationPendingExportNotificationPayload(
            userInfo: userInfo,
            configuration: configuration
        ) {
            return .pendingExport(payload)
        }

        if isLegacyScheduledExportReminderIdentifier(identifier) {
            return .legacyScheduledExportReminder
        }

        return nil
    }
}

struct AutomationPendingExportNotificationPlan: Equatable, Sendable {
    let identifier: String
    let userInfo: [String: String]
    let triggerInterval: TimeInterval?
    let categoryIdentifier: String
    let threadIdentifier: String
}

protocol AutomationPendingExportNotificationScheduling {
    func schedulePendingExportNotification(for request: AutomationPendingExportRequest) async throws
    func sendImmediatePendingExportNotification(for request: AutomationPendingExportRequest) async throws
    func cancelPendingExportNotification(id: AutomationPendingExportRequest.ID)
}

enum AutomationPendingExportRetryTrigger: String, Codable, Equatable, Sendable {
    case notificationTap = "notification_tap"
    case appActiveDrain = "app_active_drain"
}

enum AutomationPendingExportRetrySkipReason: Equatable, Sendable {
    case loadFailed(String)
    case requestNotFound(AutomationPendingExportRequest.ID)
    case sourceMismatch(expected: AutomationPendingExportSource, actual: AutomationPendingExportSource)
    case scheduleDisabled
    case alreadyInFlight(AutomationPendingExportRequest.ID)
    case requestNoLongerPending(AutomationPendingExportRequest.ID)
}

struct AutomationPendingExportRetryEligibility: Equatable, Sendable {
    let shouldAttempt: Bool
    let skipReason: AutomationPendingExportRetrySkipReason?

    static let eligible = AutomationPendingExportRetryEligibility(shouldAttempt: true, skipReason: nil)

    static func skipped(_ reason: AutomationPendingExportRetrySkipReason) -> AutomationPendingExportRetryEligibility {
        AutomationPendingExportRetryEligibility(shouldAttempt: false, skipReason: reason)
    }
}

struct AutomationPendingExportRetryOutcome: Equatable, Sendable {
    let requestID: AutomationPendingExportRequest.ID?
    let request: AutomationPendingExportRequest?
    let trigger: AutomationPendingExportRetryTrigger
    let didExecute: Bool
    let skipReason: AutomationPendingExportRetrySkipReason?

    static func executed(
        request: AutomationPendingExportRequest,
        trigger: AutomationPendingExportRetryTrigger
    ) -> AutomationPendingExportRetryOutcome {
        AutomationPendingExportRetryOutcome(
            requestID: request.id,
            request: request,
            trigger: trigger,
            didExecute: true,
            skipReason: nil
        )
    }

    static func skipped(
        request: AutomationPendingExportRequest?,
        requestID: AutomationPendingExportRequest.ID?,
        trigger: AutomationPendingExportRetryTrigger,
        reason: AutomationPendingExportRetrySkipReason
    ) -> AutomationPendingExportRetryOutcome {
        AutomationPendingExportRetryOutcome(
            requestID: request?.id ?? requestID,
            request: request,
            trigger: trigger,
            didExecute: false,
            skipReason: reason
        )
    }
}

@MainActor
final class AutomationPendingExportForegroundRetryCoordinator {
    typealias EligibilityHandler = @MainActor (
        AutomationPendingExportRequest,
        AutomationPendingExportRetryTrigger
    ) -> AutomationPendingExportRetryEligibility
    typealias ExecuteHandler = @MainActor (
        AutomationPendingExportRequest,
        AutomationPendingExportRetryTrigger
    ) async -> Void
    typealias SkipHandler = @MainActor (
        AutomationPendingExportRequest?,
        AutomationPendingExportRetryTrigger,
        AutomationPendingExportRetrySkipReason
    ) async -> Void

    private let pendingExportStore: AutomationPendingExportStoring
    private var inFlightRequestIDs: Set<AutomationPendingExportRequest.ID> = []

    init(pendingExportStore: AutomationPendingExportStoring) {
        self.pendingExportStore = pendingExportStore
    }

    @discardableResult
    func retryPendingExport(
        requestID: AutomationPendingExportRequest.ID,
        source expectedSource: AutomationPendingExportSource?,
        trigger: AutomationPendingExportRetryTrigger,
        shouldAttempt: EligibilityHandler,
        execute: ExecuteHandler,
        onSkip: SkipHandler? = nil
    ) async -> AutomationPendingExportRetryOutcome {
        let request: AutomationPendingExportRequest
        do {
            guard let loadedRequest = try pendingExportStore.loadAll().first(where: { $0.id == requestID }) else {
                let reason = AutomationPendingExportRetrySkipReason.requestNotFound(requestID)
                if let onSkip {
                    await onSkip(nil, trigger, reason)
                }
                return .skipped(request: nil, requestID: requestID, trigger: trigger, reason: reason)
            }
            request = loadedRequest
        } catch {
            let reason = AutomationPendingExportRetrySkipReason.loadFailed(error.localizedDescription)
            if let onSkip {
                await onSkip(nil, trigger, reason)
            }
            return .skipped(request: nil, requestID: requestID, trigger: trigger, reason: reason)
        }

        if let expectedSource, request.source != expectedSource {
            let reason = AutomationPendingExportRetrySkipReason.sourceMismatch(
                expected: expectedSource,
                actual: request.source
            )
            if let onSkip {
                await onSkip(request, trigger, reason)
            }
            return .skipped(request: request, requestID: requestID, trigger: trigger, reason: reason)
        }

        return await retry(
            request,
            trigger: trigger,
            shouldAttempt: shouldAttempt,
            execute: execute,
            onSkip: onSkip
        )
    }

    @discardableResult
    func drainPendingExports(
        trigger: AutomationPendingExportRetryTrigger,
        shouldAttempt: EligibilityHandler,
        execute: ExecuteHandler,
        onSkip: SkipHandler? = nil
    ) async -> [AutomationPendingExportRetryOutcome] {
        let requests: [AutomationPendingExportRequest]
        do {
            requests = try pendingExportStore.loadAll().sorted(by: pendingExportSort)
        } catch {
            let reason = AutomationPendingExportRetrySkipReason.loadFailed(error.localizedDescription)
            if let onSkip {
                await onSkip(nil, trigger, reason)
            }
            return [.skipped(request: nil, requestID: nil, trigger: trigger, reason: reason)]
        }

        guard !requests.isEmpty else { return [] }

        var outcomes: [AutomationPendingExportRetryOutcome] = []
        for request in requests {
            let outcome = await retry(
                request,
                trigger: trigger,
                shouldAttempt: shouldAttempt,
                execute: execute,
                onSkip: onSkip
            )
            outcomes.append(outcome)
        }
        return outcomes
    }

    private func retry(
        _ request: AutomationPendingExportRequest,
        trigger: AutomationPendingExportRetryTrigger,
        shouldAttempt: EligibilityHandler,
        execute: ExecuteHandler,
        onSkip: SkipHandler?
    ) async -> AutomationPendingExportRetryOutcome {
        let eligibility = shouldAttempt(request, trigger)
        guard eligibility.shouldAttempt else {
            let reason = eligibility.skipReason ?? .requestNoLongerPending(request.id)
            if let onSkip {
                await onSkip(request, trigger, reason)
            }
            return .skipped(request: request, requestID: request.id, trigger: trigger, reason: reason)
        }

        guard !inFlightRequestIDs.contains(request.id) else {
            let reason = AutomationPendingExportRetrySkipReason.alreadyInFlight(request.id)
            if let onSkip {
                await onSkip(request, trigger, reason)
            }
            return .skipped(request: request, requestID: request.id, trigger: trigger, reason: reason)
        }

        inFlightRequestIDs.insert(request.id)
        defer { inFlightRequestIDs.remove(request.id) }

        do {
            let isStillPending = try pendingExportStore.loadAll().contains { storedRequest in
                storedRequest.id == request.id && storedRequest.source == request.source
            }
            guard isStillPending else {
                let reason = AutomationPendingExportRetrySkipReason.requestNoLongerPending(request.id)
                if let onSkip {
                    await onSkip(request, trigger, reason)
                }
                return .skipped(request: request, requestID: request.id, trigger: trigger, reason: reason)
            }
        } catch {
            let reason = AutomationPendingExportRetrySkipReason.loadFailed(error.localizedDescription)
            if let onSkip {
                await onSkip(request, trigger, reason)
            }
            return .skipped(request: request, requestID: request.id, trigger: trigger, reason: reason)
        }

        await execute(request, trigger)
        return .executed(request: request, trigger: trigger)
    }

    private func pendingExportSort(
        _ lhs: AutomationPendingExportRequest,
        _ rhs: AutomationPendingExportRequest
    ) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }
}

struct AutomationPendingExportFallbackNotificationPlanner {
    var configuration: AutomationPendingExportNotificationConfiguration
    var fallbackDelay: TimeInterval
    var now: () -> Date

    init(
        configuration: AutomationPendingExportNotificationConfiguration,
        fallbackDelay: TimeInterval = 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.configuration = configuration
        self.fallbackDelay = fallbackDelay
        self.now = now
    }

    func scheduledNotificationPlan(for request: AutomationPendingExportRequest) -> AutomationPendingExportNotificationPlan {
        makePlan(for: request, immediate: false)
    }

    func immediateNotificationPlan(for request: AutomationPendingExportRequest) -> AutomationPendingExportNotificationPlan {
        makePlan(for: request, immediate: true)
    }

    func identifier(for id: AutomationPendingExportRequest.ID) -> String {
        configuration.identifierFactory.pendingExport(id: id)
    }

    private func makePlan(
        for request: AutomationPendingExportRequest,
        immediate: Bool
    ) -> AutomationPendingExportNotificationPlan {
        let payload = AutomationPendingExportNotificationPayload(request: request)
        return AutomationPendingExportNotificationPlan(
            identifier: configuration.identifierFactory.pendingExport(for: request),
            userInfo: payload.userInfo(configuration: configuration),
            triggerInterval: immediate ? nil : scheduledTriggerInterval(for: request),
            categoryIdentifier: configuration.categoryIdentifier,
            threadIdentifier: configuration.threadIdentifier
        )
    }

    private func scheduledTriggerInterval(for request: AutomationPendingExportRequest) -> TimeInterval? {
        guard let scheduledFireDate = request.scheduledFireDate else {
            return nil
        }

        let fallbackDate = scheduledFireDate.addingTimeInterval(fallbackDelay)
        return max(1, fallbackDate.timeIntervalSince(now()))
    }
}

enum AutomationPendingExportCompletion: Equatable, Sendable {
    case clearedAfterSuccess
    case preservedProtectedDataUnavailable
    case preservedFailure
    case preservedWithoutAttempt

    var shouldClearRequest: Bool {
        self == .clearedAfterSuccess
    }

    var shouldSendImmediateFallbackNotification: Bool {
        self == .preservedProtectedDataUnavailable
    }
}

struct AutomationPendingExportCompletionPolicy: Sendable {
    func completion(for result: AutomationBackgroundExportResult) -> AutomationPendingExportCompletion {
        if result.successCount > 0 {
            return .clearedAfterSuccess
        }

        if result.primaryFailureReason == .protectedDataUnavailable {
            return .preservedProtectedDataUnavailable
        }

        return result.totalCount > 0 ? .preservedFailure : .preservedWithoutAttempt
    }

    func pendingReason(for result: AutomationBackgroundExportResult) -> AutomationPendingExportReason? {
        guard result.successCount == 0 else { return nil }

        if let backgroundReason = result.primaryFailureReason {
            return AutomationPendingExportReason(backgroundFailureReason: backgroundReason)
        }

        return result.totalCount > 0 ? .unknown : nil
    }
}

struct AutomationPendingScheduledExportRequestBuilder {
    var calendar: Calendar
    var now: () -> Date
    var makeID: () -> UUID
    var metadata: [String: String]

    init(
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        makeID: @escaping () -> UUID = UUID.init,
        metadata: [String: String] = [:]
    ) {
        self.calendar = calendar
        self.now = now
        self.makeID = makeID
        self.metadata = metadata
    }

    func makeRequest(
        schedule: AutomationSchedule,
        fireDate: Date,
        existingRequests: [AutomationPendingExportRequest]
    ) -> AutomationPendingExportRequest {
        let existingRequest = existingRequests.first { request in
            request.source == .scheduled
                && request.scheduledFireDate == fireDate
        }

        return AutomationPendingExportRequest(
            id: existingRequest?.id ?? makeID(),
            dates: AutomationScheduleDateMath.pendingExportDateWindow(
                schedule: schedule,
                fireDate: fireDate,
                calendar: calendar
            ).dates,
            source: .scheduled,
            scheduledFireDate: fireDate,
            createdAt: existingRequest?.createdAt ?? now(),
            metadata: metadata,
            calendar: calendar
        )
    }
}
