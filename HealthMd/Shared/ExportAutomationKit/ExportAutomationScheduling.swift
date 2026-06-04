import Foundation

/// Domain-free frequency model for automated exports.
///
/// Raw values intentionally use the lowercase package/server spelling. Apps with
/// existing persisted frequency enums can bridge into this type for reusable date math.
enum AutomationScheduleFrequency: String, Codable, CaseIterable, Sendable {
    case daily = "daily"
    case weekly = "weekly"

    var interval: TimeInterval {
        switch self {
        case .daily:
            return 24 * 60 * 60
        case .weekly:
            return 7 * 24 * 60 * 60
        }
    }
}

/// Generic schedule configuration for automated export runners.
///
/// This value is deliberately free of app-specific data, platform runner, and UI
/// concepts. App-specific code can bridge its persisted schedule into this model
/// before calling `AutomationScheduleDateMath`.
struct AutomationSchedule: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var frequency: AutomationScheduleFrequency
    var preferredHour: Int
    var preferredMinute: Int

    /// ISO weekday for weekly schedules (1 = Monday … 7 = Sunday).
    ///
    /// Some adopters store this value for remote schedule sync compatibility.
    /// Current generic date math does not use it when advancing weekly occurrences;
    /// weekly schedules still advance by seven days from the trigger day.
    var weekday: Int

    /// Number of complete past days to include in each scheduled export.
    var lookbackDays: Int {
        didSet {
            lookbackDays = Self.clampedLookbackDays(lookbackDays)
        }
    }

    /// IANA timezone identifier used by generic date math when no explicit
    /// calendar is supplied.
    var timeZoneIdentifier: String

    /// Timestamp of the last successful scheduled export run.
    var lastExportDate: Date?

    static let minimumLookbackDays = 1
    static let maximumLookbackDays = 30

    static func defaultLookbackDays(for frequency: AutomationScheduleFrequency) -> Int {
        frequency == .weekly ? 7 : 1
    }

    static func clampedLookbackDays(_ days: Int) -> Int {
        min(max(Self.minimumLookbackDays, days), Self.maximumLookbackDays)
    }

    init(
        isEnabled: Bool = false,
        frequency: AutomationScheduleFrequency = .daily,
        preferredHour: Int = 8,
        preferredMinute: Int = 0,
        weekday: Int = 1,
        lookbackDays: Int? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        lastExportDate: Date? = nil
    ) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.preferredHour = preferredHour
        self.preferredMinute = preferredMinute
        self.weekday = weekday
        self.lookbackDays = Self.clampedLookbackDays(lookbackDays ?? Self.defaultLookbackDays(for: frequency))
        self.timeZoneIdentifier = timeZoneIdentifier
        self.lastExportDate = lastExportDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        self.frequency = try c.decode(AutomationScheduleFrequency.self, forKey: .frequency)
        self.preferredHour = try c.decode(Int.self, forKey: .preferredHour)
        self.preferredMinute = try c.decode(Int.self, forKey: .preferredMinute)
        self.weekday = try c.decodeIfPresent(Int.self, forKey: .weekday) ?? 1
        let decodedLookbackDays = try c.decodeIfPresent(Int.self, forKey: .lookbackDays)
        self.lookbackDays = Self.clampedLookbackDays(decodedLookbackDays ?? Self.defaultLookbackDays(for: frequency))
        self.timeZoneIdentifier = try c.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? TimeZone.current.identifier
        self.lastExportDate = try c.decodeIfPresent(Date.self, forKey: .lastExportDate)
    }

    var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    func defaultCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

/// Complete-day export window for a scheduled occurrence.
struct AutomationExportDateWindow: Codable, Equatable, Sendable {
    var fireDate: Date
    var dates: [Date]

    var startDate: Date? { dates.first }
    var endDate: Date? { dates.last }
    var totalCount: Int { dates.count }
}

/// Pure reusable schedule date math for ExportAutomationKit.
///
/// All methods are deterministic. Callers can pass a calendar to preserve an
/// existing app's behavior exactly; otherwise the schedule's timezone is used.
enum AutomationScheduleDateMath {
    static func calculateNextRunDate(
        schedule: AutomationSchedule,
        now: Date,
        calendar: Calendar? = nil
    ) -> Date? {
        let calendar = resolvedCalendar(schedule: schedule, calendar: calendar)
        var todayAtPreferred = calendar.dateComponents([.year, .month, .day], from: now)
        todayAtPreferred.hour = schedule.preferredHour
        todayAtPreferred.minute = schedule.preferredMinute
        todayAtPreferred.second = 0

        guard let scheduled = calendar.date(from: todayAtPreferred) else { return nil }

        if scheduled > now {
            return scheduled
        }

        switch schedule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: scheduled)
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: scheduled)
        }
    }

    /// Determine catch-up data days, bounded by the configured lookback and
    /// ending with yesterday. `lastExportDate` is the day an export ran, so that
    /// run covered the previous data day; the next data day is the run day.
    static func catchUpDatesNeeded(
        schedule: AutomationSchedule,
        now: Date,
        calendar: Calendar? = nil
    ) -> [Date] {
        let calendar = resolvedCalendar(schedule: schedule, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return [] }

        let lookbackDays = AutomationSchedule.clampedLookbackDays(schedule.lookbackDays)
        guard let oldestDate = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else { return [] }

        let lastExportedDataDay: Date
        if let lastExport = schedule.lastExportDate {
            let exportRunDay = calendar.startOfDay(for: lastExport)
            lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: exportRunDay) ?? exportRunDay
        } else {
            lastExportedDataDay = calendar.date(byAdding: .day, value: -1, to: oldestDate) ?? oldestDate
        }

        guard lastExportedDataDay < yesterday else { return [] }
        guard let dayAfterLastExport = calendar.date(byAdding: .day, value: 1, to: lastExportedDataDay) else {
            return []
        }

        return dateRange(from: max(dayAfterLastExport, oldestDate), through: yesterday, calendar: calendar)
    }

    /// Returns the complete data days covered by one scheduled occurrence. The
    /// scheduled fire date is the run day, so the export window ends with the
    /// prior calendar day and includes the configured clamped lookback count.
    static func scheduledExportDates(
        schedule: AutomationSchedule,
        fireDate: Date,
        calendar: Calendar? = nil
    ) -> [Date] {
        let calendar = resolvedCalendar(schedule: schedule, calendar: calendar)
        let fireDay = calendar.startOfDay(for: fireDate)
        let lookbackDays = AutomationSchedule.clampedLookbackDays(schedule.lookbackDays)

        guard let startDate = calendar.date(byAdding: .day, value: -lookbackDays, to: fireDay),
              let endDate = calendar.date(byAdding: .day, value: -1, to: fireDay)
        else {
            return []
        }

        return dateRange(from: startDate, through: endDate, calendar: calendar)
    }

    static func scheduledExportDateWindow(
        schedule: AutomationSchedule,
        fireDate: Date,
        calendar: Calendar? = nil
    ) -> AutomationExportDateWindow {
        AutomationExportDateWindow(
            fireDate: fireDate,
            dates: scheduledExportDates(schedule: schedule, fireDate: fireDate, calendar: calendar)
        )
    }

    /// Alias used by pending/fallback scheduling code to make the invariant
    /// explicit: pending requests store the exact scheduled occurrence window.
    static func pendingExportDateWindow(
        schedule: AutomationSchedule,
        fireDate: Date,
        calendar: Calendar? = nil
    ) -> AutomationExportDateWindow {
        scheduledExportDateWindow(schedule: schedule, fireDate: fireDate, calendar: calendar)
    }

    /// Returns the scheduled occurrence that should be considered due at `now`.
    /// If today's preferred time has not arrived, this returns the previous
    /// frequency interval, matching the stable pending occurrence key used by scheduled triggers.
    static func latestScheduledOccurrenceDate(
        schedule: AutomationSchedule,
        now: Date,
        calendar: Calendar? = nil
    ) -> Date? {
        let calendar = resolvedCalendar(schedule: schedule, calendar: calendar)
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = schedule.preferredHour
        components.minute = schedule.preferredMinute
        components.second = 0

        guard let todayAtPreferredTime = calendar.date(from: components) else { return nil }

        if todayAtPreferredTime <= now {
            return todayAtPreferredTime
        }

        switch schedule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: -1, to: todayAtPreferredTime)
        case .weekly:
            return calendar.date(byAdding: .day, value: -7, to: todayAtPreferredTime)
        }
    }

    private static func resolvedCalendar(schedule: AutomationSchedule, calendar: Calendar?) -> Calendar {
        calendar ?? schedule.defaultCalendar()
    }

    private static func dateRange(from startDate: Date, through endDate: Date, calendar: Calendar) -> [Date] {
        guard startDate <= endDate else { return [] }

        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
}

/// Type-erased app-supplied export configuration snapshot for automation.
///
/// ExportAutomationKit can persist and pass this snapshot through scheduling
/// flows without knowing which concrete app or ExportKit adopter created it.
struct AutomationExportRequestConfigurationSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var requestKind: String
    var formatIDs: [String]
    var destinationID: String?
    var encodedConfiguration: Data?
    var metadata: [String: String]

    init(
        schemaVersion: Int = 1,
        requestKind: String,
        formatIDs: [String] = [],
        destinationID: String? = nil,
        encodedConfiguration: Data? = nil,
        metadata: [String: String] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.requestKind = requestKind
        self.formatIDs = formatIDs
        self.destinationID = destinationID
        self.encodedConfiguration = encodedConfiguration
        self.metadata = metadata
    }
}

struct PersistedAutomationConfiguration: Codable, Equatable, Sendable {
    var schedule: AutomationSchedule
    var exportRequestConfiguration: AutomationExportRequestConfigurationSnapshot?

    init(
        schedule: AutomationSchedule = AutomationSchedule(),
        exportRequestConfiguration: AutomationExportRequestConfigurationSnapshot? = nil
    ) {
        self.schedule = schedule
        self.exportRequestConfiguration = exportRequestConfiguration
    }
}

protocol AutomationConfigurationStoring {
    func load() throws -> PersistedAutomationConfiguration?
    func save(_ configuration: PersistedAutomationConfiguration) throws
    func clear()
}

struct UserDefaultsAutomationConfigurationStore: AutomationConfigurationStoring {
    let storageKey: String
    let userDefaults: UserDefaults
    let encoder: JSONEncoder
    let decoder: JSONDecoder

    init(
        storageKey: String = "exportAutomationConfiguration",
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.storageKey = storageKey
        self.userDefaults = userDefaults
        self.encoder = encoder
        self.decoder = decoder
    }

    func load() throws -> PersistedAutomationConfiguration? {
        guard let data = userDefaults.data(forKey: storageKey) else { return nil }
        return try decoder.decode(PersistedAutomationConfiguration.self, from: data)
    }

    func save(_ configuration: PersistedAutomationConfiguration) throws {
        let data = try encoder.encode(configuration)
        userDefaults.set(data, forKey: storageKey)
    }

    func clear() {
        userDefaults.removeObject(forKey: storageKey)
    }
}

// MARK: - Remote schedule registration contract

/// Stable app/device routing metadata used by a remote schedule worker.
struct RemoteScheduleDeviceRegistrationPayload: Codable, Equatable, Sendable {
    var userId: String
    var platform: String
    var apnsToken: String
    var bundleId: String
    var appVersion: String?
    var appBuild: String?

    init(
        userId: String,
        platform: String,
        apnsToken: String,
        bundleId: String,
        appVersion: String? = nil,
        appBuild: String? = nil
    ) {
        self.userId = userId
        self.platform = platform
        self.apnsToken = apnsToken
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.appBuild = appBuild
    }
}

/// Schedule fields mirrored to the remote worker.
struct RemoteSchedulePayload: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var frequency: AutomationScheduleFrequency
    var hour: Int
    var minute: Int
    var weekday: Int?

    init(
        isEnabled: Bool,
        frequency: AutomationScheduleFrequency,
        hour: Int,
        minute: Int,
        weekday: Int? = nil
    ) {
        self.isEnabled = isEnabled
        self.frequency = frequency
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
    }

    init(schedule: AutomationSchedule) {
        self.init(
            isEnabled: schedule.isEnabled,
            frequency: schedule.frequency,
            hour: schedule.preferredHour,
            minute: schedule.preferredMinute,
            weekday: schedule.frequency == .weekly ? schedule.weekday : nil
        )
    }
}

/// Upsert body for remote schedule state. Sending `schedule.isEnabled == false`
/// is the generic unregister/update operation; the worker can remove or disable
/// the stored schedule for this installation without any export payload data.
struct RemoteScheduleUpsertPayload: Codable, Equatable, Sendable {
    var userId: String
    var timezone: String
    var schedule: RemoteSchedulePayload
    var platform: String?
    var bundleId: String?
    var appVersion: String?
    var appBuild: String?

    init(
        userId: String,
        timezone: String,
        schedule: RemoteSchedulePayload,
        platform: String? = nil,
        bundleId: String? = nil,
        appVersion: String? = nil,
        appBuild: String? = nil
    ) {
        self.userId = userId
        self.timezone = timezone
        self.schedule = schedule
        self.platform = platform
        self.bundleId = bundleId
        self.appVersion = appVersion
        self.appBuild = appBuild
    }
}

/// Routing-only APNs body emitted by the remote schedule worker for due runs.
struct RemoteScheduledExportAPNsPayload: Codable, Equatable, Sendable {
    struct APS: Codable, Equatable, Sendable {
        var contentAvailable: Int

        init(contentAvailable: Int = 1) {
            self.contentAvailable = contentAvailable
        }

        enum CodingKeys: String, CodingKey {
            case contentAvailable = "content-available"
        }
    }

    var aps: APS
    var type: String
    var scheduledFireDate: String?

    init(
        aps: APS = APS(),
        type: String = RemoteScheduleWorkerContract.scheduledExportPushType,
        scheduledFireDate: String? = nil
    ) {
        self.aps = aps
        self.type = type
        self.scheduledFireDate = scheduledFireDate
    }
}

enum RemoteScheduleWorkerContract {
    static let deviceRegistrationPath = "/devices/register"
    static let scheduleUpsertPath = "/schedules/upsert"
    static let scheduledExportPushType = "scheduled-export"
    static let apnsPushType = "background"
    static let apnsPriority = "5"
}

protocol RemoteScheduleClient {
    func registerDevice(_ payload: RemoteScheduleDeviceRegistrationPayload) async throws
    func upsertSchedule(_ payload: RemoteScheduleUpsertPayload) async throws
}

struct RemoteScheduleRetryPolicy: Equatable, Sendable {
    var maxAttempts: Int
    var retryDelayNanoseconds: UInt64

    init(maxAttempts: Int = 3, retryDelayNanoseconds: UInt64 = 500_000_000) {
        self.maxAttempts = max(1, maxAttempts)
        self.retryDelayNanoseconds = retryDelayNanoseconds
    }

    func shouldRetry(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard case RemoteScheduleClientError.unsuccessfulStatusCode(let statusCode) = error else {
            return false
        }
        return statusCode == 429 || (500..<600).contains(statusCode)
    }
}

enum RemoteScheduleClientError: Error, Equatable {
    case invalidHTTPResponse
    case unsuccessfulStatusCode(Int)
}

struct URLSessionRemoteScheduleClient: RemoteScheduleClient {
    var baseURL: URL
    var session: URLSession
    var encoder: JSONEncoder
    var retryPolicy: RemoteScheduleRetryPolicy

    init(
        baseURL: URL,
        session: URLSession = .shared,
        encoder: JSONEncoder = JSONEncoder(),
        retryPolicy: RemoteScheduleRetryPolicy = RemoteScheduleRetryPolicy()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.encoder = encoder
        self.retryPolicy = retryPolicy
    }

    func registerDevice(_ payload: RemoteScheduleDeviceRegistrationPayload) async throws {
        try await post(path: RemoteScheduleWorkerContract.deviceRegistrationPath, body: payload)
    }

    func upsertSchedule(_ payload: RemoteScheduleUpsertPayload) async throws {
        try await post(path: RemoteScheduleWorkerContract.scheduleUpsertPath, body: payload)
    }

    private func post<T: Encodable>(path: String, body: T) async throws {
        var lastError: Error?

        for attempt in 1...retryPolicy.maxAttempts {
            do {
                var request = URLRequest(url: baseURL.appendingPathComponent(path))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try encoder.encode(body)

                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw RemoteScheduleClientError.invalidHTTPResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw RemoteScheduleClientError.unsuccessfulStatusCode(http.statusCode)
                }
                return
            } catch {
                lastError = error
                guard attempt < retryPolicy.maxAttempts, retryPolicy.shouldRetry(error) else {
                    throw error
                }
                try await Task.sleep(nanoseconds: retryPolicy.retryDelayNanoseconds)
            }
        }

        if let lastError { throw lastError }
    }
}

// MARK: - Scheduled background runner

/// Platform-neutral trigger labels for automatic scheduled wake attempts.
enum AutomationBackgroundTrigger: String, Codable, Equatable, Sendable {
    case silentPush = "silent_push"
    case backgroundTask = "background_task"
    case scheduledWake = "scheduled_wake"
    case dataSourceBackgroundDelivery = "data_source_background_delivery"
}

enum AutomationBackgroundSkipReason: String, Codable, Equatable, Sendable {
    case scheduleDisabled = "schedule_disabled"
}

enum AutomationBackgroundExportFailureReason: String, Codable, Equatable, Sendable {
    case noDestination = "no_destination"
    case quotaBlocked = "quota_blocked"
    case protectedDataUnavailable = "protected_data_unavailable"
    case noData = "no_data"
    case cancelled = "cancelled"
    case timeLimitExceeded = "time_limit_exceeded"
    case exportFailed = "export_failed"
    case unknown = "unknown"
}

/// Domain-free summary of a background export attempt.
struct AutomationBackgroundExportResult: Equatable, Sendable {
    var successCount: Int
    var totalCount: Int
    var primaryFailureReason: AutomationBackgroundExportFailureReason?
    var wasCancelled: Bool

    init(
        successCount: Int,
        totalCount: Int,
        primaryFailureReason: AutomationBackgroundExportFailureReason? = nil,
        wasCancelled: Bool = false
    ) {
        self.successCount = successCount
        self.totalCount = totalCount
        self.primaryFailureReason = primaryFailureReason
        self.wasCancelled = wasCancelled
    }

    static func success(count: Int, total: Int? = nil) -> Self {
        Self(successCount: count, totalCount: total ?? count)
    }

    static func failure(
        totalCount: Int,
        reason: AutomationBackgroundExportFailureReason,
        wasCancelled: Bool = false
    ) -> Self {
        Self(
            successCount: 0,
            totalCount: totalCount,
            primaryFailureReason: reason,
            wasCancelled: wasCancelled
        )
    }

    static func timedOut(totalCount: Int) -> Self {
        failure(totalCount: totalCount, reason: .timeLimitExceeded)
    }

    var shouldUpdateLastExport: Bool {
        successCount > 0
    }
}

struct AutomationBackgroundDateRange: Codable, Equatable, Sendable {
    var start: Date
    var end: Date
    var totalCount: Int
}

struct AutomationScheduledBackgroundRunContext: Equatable, Sendable {
    var trigger: AutomationBackgroundTrigger
    var schedule: AutomationSchedule
    var requestedFireDate: Date?
    var resolvedFireDate: Date
}

/// Wraps an app-owned pending request with the generic dates needed by the runner.
struct AutomationPreparedScheduledBackgroundWork<Request> {
    var request: Request
    var dates: [Date]
    var scheduledFireDate: Date?

    init(request: Request, dates: [Date], scheduledFireDate: Date?) {
        self.request = request
        self.dates = dates
        self.scheduledFireDate = scheduledFireDate
    }
}

struct AutomationScheduledBackgroundPreparedRun<Request> {
    var context: AutomationScheduledBackgroundRunContext
    var pendingWork: AutomationPreparedScheduledBackgroundWork<Request>?
    var dates: [Date]
    var dateRange: AutomationBackgroundDateRange
}

struct AutomationScheduledBackgroundRunOutcome<Request, ExportResult> {
    var context: AutomationScheduledBackgroundRunContext?
    var pendingWork: AutomationPreparedScheduledBackgroundWork<Request>?
    var dates: [Date]
    var dateRange: AutomationBackgroundDateRange?
    var exportResult: ExportResult?
    var backgroundResult: AutomationBackgroundExportResult?
    var skipReason: AutomationBackgroundSkipReason?

    var shouldUpdateLastExport: Bool {
        backgroundResult?.shouldUpdateLastExport == true
    }
}

struct AutomationScheduledBackgroundRunner {
    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    @MainActor
    func runScheduledExport<Request, ExportResult>(
        trigger: AutomationBackgroundTrigger,
        schedule: AutomationSchedule,
        requestedFireDate: Date? = nil,
        now: Date = Date(),
        preparePendingWork: @MainActor (AutomationScheduledBackgroundRunContext) async -> AutomationPreparedScheduledBackgroundWork<Request>?,
        cancelPendingFallback: @MainActor (AutomationPreparedScheduledBackgroundWork<Request>?) async -> Void,
        beforeExport: @MainActor (AutomationScheduledBackgroundPreparedRun<Request>) async -> Void = { _ in },
        export: @MainActor ([Date], AutomationScheduledBackgroundRunContext) async -> (ExportResult, AutomationBackgroundExportResult)
    ) async -> AutomationScheduledBackgroundRunOutcome<Request, ExportResult> {
        guard schedule.isEnabled else {
            return AutomationScheduledBackgroundRunOutcome(
                context: nil,
                pendingWork: nil,
                dates: [],
                dateRange: nil,
                exportResult: nil,
                backgroundResult: nil,
                skipReason: .scheduleDisabled
            )
        }

        let resolvedFireDate = requestedFireDate
            ?? AutomationScheduleDateMath.latestScheduledOccurrenceDate(
                schedule: schedule,
                now: now,
                calendar: calendar
            )
            ?? now
        let context = AutomationScheduledBackgroundRunContext(
            trigger: trigger,
            schedule: schedule,
            requestedFireDate: requestedFireDate,
            resolvedFireDate: resolvedFireDate
        )
        let pendingWork = await preparePendingWork(context)
        let dates = pendingWork?.dates ?? AutomationScheduleDateMath.scheduledExportDates(
            schedule: schedule,
            fireDate: resolvedFireDate,
            calendar: calendar
        )
        let dateRange = backgroundDateRange(
            dates: dates,
            fireDate: pendingWork?.scheduledFireDate ?? resolvedFireDate,
            usedPendingWork: pendingWork != nil
        )
        let prepared = AutomationScheduledBackgroundPreparedRun(
            context: context,
            pendingWork: pendingWork,
            dates: dates,
            dateRange: dateRange
        )

        await cancelPendingFallback(pendingWork)
        await beforeExport(prepared)

        let (exportResult, backgroundResult) = await export(dates, context)

        return AutomationScheduledBackgroundRunOutcome(
            context: context,
            pendingWork: pendingWork,
            dates: dates,
            dateRange: dateRange,
            exportResult: exportResult,
            backgroundResult: backgroundResult,
            skipReason: nil
        )
    }

    private func backgroundDateRange(
        dates: [Date],
        fireDate: Date,
        usedPendingWork: Bool
    ) -> AutomationBackgroundDateRange {
        if let first = dates.first, let last = dates.last {
            return AutomationBackgroundDateRange(start: first, end: last, totalCount: dates.count)
        }

        let fallbackDate: Date
        if usedPendingWork {
            fallbackDate = calendar.date(byAdding: .day, value: -1, to: fireDate) ?? fireDate
        } else {
            fallbackDate = fireDate
        }
        let fallback = calendar.startOfDay(for: fallbackDate)
        return AutomationBackgroundDateRange(start: fallback, end: fallback, totalCount: 0)
    }
}
