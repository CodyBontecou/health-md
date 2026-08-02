#if os(iOS)
import CryptoKit
import Foundation
import HealthMdConnectionCore
import Security
import UIKit

private enum IPhoneDirectQueryError: Error {
    case invalidRequest
    case queryUnavailable
    case requestInProgress
    case protectedDataUnavailable
    case healthKitNotAuthorized
    case accessUnavailable
    case responseTooLarge
    case queryScopeTooLarge
    case cancelled

    var code: String {
        switch self {
        case .invalidRequest: "invalid_query_request"
        case .queryUnavailable: "query_unavailable"
        case .requestInProgress: "request_in_progress"
        case .protectedDataUnavailable: "protected_data_unavailable"
        case .healthKitNotAuthorized: "healthkit_authorization_required"
        case .accessUnavailable: "access_unavailable"
        case .responseTooLarge: "query_response_too_large"
        case .queryScopeTooLarge: "query_scope_too_large"
        case .cancelled: "query_cancelled"
        }
    }

    var publicMessage: String {
        switch self {
        case .invalidRequest: "The direct query request is invalid or unsupported."
        case .queryUnavailable: "The iPhone could not complete the direct query."
        case .requestInProgress: "Another direct iPhone operation is already active."
        case .protectedDataUnavailable: "Unlock iPhone before starting a direct query."
        case .healthKitNotAuthorized: "Authorize the selected Health access before starting a direct query."
        case .accessUnavailable: "Direct query access is not currently available."
        case .responseTooLarge: "The query response exceeded the negotiated page bound."
        case .queryScopeTooLarge: "The requested query scope exceeds the foreground iPhone resource budget. Narrow dates or metrics and page through the complete logical corpus."
        case .cancelled: "The direct query was cancelled."
        }
    }

    var retryable: Bool {
        switch self {
        case .requestInProgress, .protectedDataUnavailable, .queryUnavailable: true
        default: false
        }
    }
}

private enum IPhoneDirectQueryCursorKeyProvider {
    private static let service = "com.codybontecou.obsidianhealth.direct-query"
    private static let account = "cursor-key-v1"

    static func loadOrCreate() throws -> Data {
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           data.count == 32 {
            return data
        }
        guard status == errSecItemNotFound else { throw IPhoneDirectQueryError.queryUnavailable }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw IPhoneDirectQueryError.queryUnavailable
        }
        let key = Data(bytes)
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            return try loadOrCreate()
        }
        guard addStatus == errSecSuccess else { throw IPhoneDirectQueryError.queryUnavailable }
        return key
    }
}

@MainActor
final class IPhoneDirectQueryCaptureCache {
    private struct Entry {
        let generation: UUID
        let key: Data
        let days: [HealthMdCompactContextDay]
        let expiresAt: Date
    }

    private let lifetime: TimeInterval
    private var entry: Entry?
    private var evictionTask: Task<Void, Never>?

    init(lifetime: TimeInterval = 10 * 60) {
        precondition(
            lifetime.isFinite && lifetime >= 0 &&
                lifetime <= Double(UInt64.max) / 1_000_000_000
        )
        self.lifetime = lifetime
    }

    var isEmpty: Bool { entry == nil }

    func continuation(for key: Data, now: Date = Date()) -> [HealthMdCompactContextDay]? {
        guard let entry else { return nil }
        guard entry.expiresAt > now else {
            clear()
            return nil
        }
        guard entry.key == key else { return nil }
        return entry.days
    }

    func store(key: Data, days: [HealthMdCompactContextDay], now: Date = Date()) {
        clear()
        let generation = UUID()
        entry = Entry(
            generation: generation,
            key: key,
            days: days,
            expiresAt: now.addingTimeInterval(lifetime)
        )
        let delayNanoseconds = UInt64(lifetime * 1_000_000_000)
        evictionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            } catch {
                return
            }
            guard self?.entry?.generation == generation else { return }
            self?.clear()
        }
    }

    func clear() {
        evictionTask?.cancel()
        evictionTask = nil
        entry = nil
    }
}

/// Executes bounded query-contract operations directly against a foreground iPhone.
/// It never exposes HealthKit source bodies or writes a desktop destination.
@MainActor
final class IPhoneDirectQueryCoordinator {
    static let shared = IPhoneDirectQueryCoordinator()
    private static let maximumCompactContextBytes = 64 * 1_024 * 1_024

    private struct CaptureKey: Encodable {
        let metrics: HealthMdMetricSelection
        let sources: HealthMdSourceSelection
        let dates: HealthMdDateSelection
        let detailLevel: DirectQueryDetailLevel
        let peerInstallationID: UUID
        enum CodingKeys: String, CodingKey {
            case metrics, sources, dates
            case detailLevel = "detail_level"
            case peerInstallationID = "peer_installation_id"
        }
    }

    private(set) var activeRequestID: UUID?
    private let captureCache = IPhoneDirectQueryCaptureCache()
    var isQuerying: Bool { activeRequestID != nil }

    private init() {}

    func clearCachedContext() {
        captureCache.clear()
    }

    func handle(
        _ request: DirectQueryRequest,
        channel: DirectSecureChannel,
        healthKitManager: HealthKitManager
    ) async {
        guard activeRequestID == nil else {
            try? await reject(request, error: .requestInProgress, channel: channel)
            return
        }
        activeRequestID = request.requestID
        defer {
            if activeRequestID == request.requestID { activeRequestID = nil }
        }
        do {
            let response = try await HealthKitQueryExecutionController.withController {
                try await execute(
                    request,
                    peerInstallationID: channel.peerInstallationID,
                    healthKitManager: healthKitManager
                )
            }
            guard !Task.isCancelled else { throw IPhoneDirectQueryError.cancelled }
            try await channel.send(.queryResponse(response))
        } catch {
            let safeError: IPhoneDirectQueryError
            if Task.isCancelled {
                safeError = .cancelled
            } else if let contractError = error as? HealthMdQueryContractError {
                safeError = contractError == .singleItemExceedsPageBytes
                    ? .responseTooLarge
                    : .invalidRequest
            } else {
                safeError = error as? IPhoneDirectQueryError ?? .queryUnavailable
            }
            try? await reject(request, error: safeError, channel: channel)
        }
    }

    private func execute(
        _ directRequest: DirectQueryRequest,
        peerInstallationID: UUID,
        healthKitManager: HealthKitManager
    ) async throws -> DirectQueryResponse {
        guard directRequest.protocolVersion == HealthMdDirectProtocol.queryVersion,
              directRequest.createdAt <= Date().addingTimeInterval(5 * 60),
              directRequest.createdAt.addingTimeInterval(HealthMdDirectProtocol.jobLifetime) > Date(),
              UIApplication.shared.applicationState == .active else {
            throw IPhoneDirectQueryError.invalidRequest
        }
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw IPhoneDirectQueryError.protectedDataUnavailable
        }
        guard healthKitManager.isAuthorized else {
            throw IPhoneDirectQueryError.healthKitNotAuthorized
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let queryData = try JSONEncoder.healthMdDirectQuery.encode(directRequest.query)
        guard queryData.count <= HealthMdDirectProtocol.maximumPacketBytes,
              let query = try? decoder.decode(HealthMdQueryRequest.self, from: queryData),
              query.schema == HealthMdQuerySchemas.queryRequest,
              query.schemaVersion == HealthMdQuerySchemas.version,
              query.page.maxItems > 0,
              query.page.maxItems <= DirectQueryCapabilities.current.maximumPageItems,
              query.page.maxBytes > 0,
              query.page.maxBytes <= DirectQueryCapabilities.current.maximumPageBytes,
              operationID(query.operation).map(DirectQueryCapabilities.current.operations.contains) == true else {
            throw IPhoneDirectQueryError.invalidRequest
        }
        if case .sourceRecordListing = query.operation,
           directRequest.detailLevel != .lossless {
            throw IPhoneDirectQueryError.invalidRequest
        }

        let metricIDs = try resolveMetricIDs(query.metrics)
        try validateSources(query.sources)
        let captureKey = try JSONEncoder.healthMdDirectQuery.encode(CaptureKey(
            metrics: query.metrics,
            sources: query.sources,
            dates: query.dates,
            detailLevel: directRequest.detailLevel,
            peerInstallationID: peerInstallationID
        ))
        let continuationDays: [HealthMdCompactContextDay]?
        if query.page.cursor != nil {
            guard let cachedDays = captureCache.continuation(for: captureKey) else {
                throw IPhoneDirectQueryError.invalidRequest
            }
            continuationDays = cachedDays
        } else {
            continuationDays = nil
        }
        let authorized = try await healthKitManager.hasRecordedAuthorizationDecision(
            forMetricIDs: metricIDs
        )
        guard authorized else { throw IPhoneDirectQueryError.healthKitNotAuthorized }

        if continuationDays == nil {
            await PurchaseManager.shared.refreshStatus()
            guard PurchaseManager.shared.canExport else { throw IPhoneDirectQueryError.accessUnavailable }
        }

        let timeZone = TimeZone.current
        let settings = AdvancedExportSettings()
        settings.exportTimeZoneOverride = timeZone
        settings.includeGranularData = directRequest.detailLevel == .lossless
        settings.metricSelection.enabledMetrics = metricIDs
        let days: [HealthMdCompactContextDay]
        if let continuationDays {
            days = continuationDays
        } else {
            let dates = try await resolveDates(
                query.dates,
                metricIDs: metricIDs,
                healthKitManager: healthKitManager,
                timeZone: timeZone
            )
            guard !dates.isEmpty else { throw IPhoneDirectQueryError.invalidRequest }
            var capturedDays: [HealthMdCompactContextDay] = []
            capturedDays.reserveCapacity(min(dates.count, 366))
            var compactContextBytes = 0
            let formatter = Self.sourceDateFormatter(timeZone: timeZone)
            for date in dates {
                try Task.checkCancellation()
                let outcome = try await HealthKitDailyCapture.capture(
                    date: date,
                    includeGranularData: settings.includeGranularData,
                    metricSelection: settings.metricSelection,
                    transform: .sanitizeGranularAndFilter,
                    emptyRecordPolicy: .retain,
                    fetchExternalRecords: false,
                    failurePolicy: .connectedMac,
                    fetchHealthData: { date, includeGranularData, metricSelection in
                        try await healthKitManager.fetchHealthData(
                            for: date,
                            includeGranularData: includeGranularData,
                            metricSelection: metricSelection,
                            timeZone: timeZone
                        )
                    },
                    fetchExternalDailyRecords: nil
                )
                try Task.checkCancellation()
                let day: HealthMdCompactContextDay
                if let record = outcome.record {
                    day = try HealthMdQueryContextProjector.project(
                        record,
                        options: HealthMdContextProjectionOptions(
                            enabledMetricIDs: metricIDs,
                            includesAppleHealth: true
                        )
                    )
                } else {
                    day = try unavailableDay(
                        ownerDate: formatter.string(from: date),
                        date: date,
                        timeZone: timeZone,
                        metricIDs: metricIDs
                    )
                }
                let dayBytes = try JSONEncoder.healthMdDirectQuery.encode(day).count
                guard dayBytes <= Self.maximumCompactContextBytes - compactContextBytes else {
                    throw IPhoneDirectQueryError.queryScopeTooLarge
                }
                compactContextBytes += dayBytes
                capturedDays.append(day)
            }
            days = capturedDays
        }

        let scope = try evidenceScope(
            query: query,
            metricIDs: metricIDs,
            detailLevel: directRequest.detailLevel
        )
        let evaluator = try HealthMdQueryEvaluator(
            days: days,
            cursorKey: try IPhoneDirectQueryCursorKeyProvider.loadOrCreate(),
            cursorBinding: peerInstallationID.uuidString.lowercased()
        )
        let response = try evaluator.evaluateBounded(query, evidenceScope: scope)
        let responseData = try JSONEncoder.healthMdDirectQuery.encode(response)
        guard responseData.count <= query.page.maxBytes,
              responseData.count <= DirectQueryCapabilities.current.maximumPageBytes,
              responseData.count <= HealthMdDirectProtocol.maximumPacketBytes else {
            throw IPhoneDirectQueryError.responseTooLarge
        }
        let directResponse = try decoder.decode(DirectJSONValue.self, from: responseData)
        if response.nextCursor != nil {
            captureCache.store(key: captureKey, days: days)
        } else {
            captureCache.clear()
        }
        if query.page.cursor == nil {
            try PurchaseManager.shared.recordExportUse(jobID: directRequest.requestID)
        }
        return DirectQueryResponse(requestID: directRequest.requestID, response: directResponse)
    }

    private func reject(
        _ request: DirectQueryRequest,
        error: IPhoneDirectQueryError,
        channel: DirectSecureChannel
    ) async throws {
        try await channel.send(.queryRejected(DirectQueryFailure(
            requestID: request.requestID,
            code: error.code,
            message: error.publicMessage,
            retryable: error.retryable
        )))
    }

    private func resolveMetricIDs(_ selection: HealthMdMetricSelection) throws -> Set<String> {
        let available = HealthMetrics.availableMetricIDsInCurrentBuild
        switch selection {
        case .allAvailable:
            return available
        case .explicit(let identifiers):
            let requested = Set(identifiers)
            guard !requested.isEmpty, requested.isSubset(of: available) else {
                throw IPhoneDirectQueryError.invalidRequest
            }
            return requested
        }
    }

    private func validateSources(_ selection: HealthMdSourceSelection) throws {
        switch selection {
        case .allAvailable:
            return
        case .explicit(let sourceIDs, let providerIDs):
            guard providerIDs.isEmpty,
                  !sourceIDs.isEmpty,
                  Set(sourceIDs).isSubset(of: ["apple_health", "healthmd_summary"]) else {
                throw IPhoneDirectQueryError.invalidRequest
            }
        }
    }

    private func evidenceScope(
        query: HealthMdQueryRequest,
        metricIDs: Set<String>,
        detailLevel: DirectQueryDetailLevel
    ) throws -> HealthMdEvidenceScope {
        let allowedDetails: Set<String>
        if detailLevel == .lossless,
           case .derivePacket(_, let detailIDs) = query.operation {
            allowedDetails = Set(detailIDs)
        } else {
            allowedDetails = []
        }
        let allowedSources: Set<String>?
        let allowedProviders: Set<String>?
        switch query.sources {
        case .allAvailable:
            allowedSources = nil
            allowedProviders = nil
        case .explicit(let sourceIDs, let providerIDs):
            allowedSources = Set(sourceIDs)
            allowedProviders = Set(providerIDs)
        }
        return HealthMdEvidenceScope(
            allowedMetricIDs: metricIDs,
            allowedDetailIDs: allowedDetails,
            allowsWorkouts: metricIDs.contains("workouts"),
            allowedSourceIDs: allowedSources,
            allowedProviderIDs: allowedProviders,
            allowsEvidenceValues: detailLevel == .lossless
        )
    }

    private func operationID(_ operation: HealthMdQueryOperation) -> String? {
        switch operation {
        case .metricSeries: "metric_series"
        case .periodComparison: "period_comparison"
        case .workoutListing: "workout_listing"
        case .sleepSessionListing: "sleep_session_listing"
        case .workoutSleepAlignment: "workout_sleep_alignment"
        case .sourceRecordListing: "source_record_listing"
        case .coverage: "coverage"
        case .derivePacket: "derive_packet"
        }
    }

    private func resolveDates(
        _ selection: HealthMdDateSelection,
        metricIDs: Set<String>,
        healthKitManager: HealthKitManager,
        timeZone: TimeZone
    ) async throws -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        switch selection {
        case .exact(let range):
            let formatter = Self.sourceDateFormatter(timeZone: timeZone)
            guard let start = formatter.date(from: range.startDate),
                  let end = formatter.date(from: range.endDate),
                  start <= end else {
                throw IPhoneDirectQueryError.invalidRequest
            }
            return try sourceDateRange(from: start, to: end, calendar: calendar)
        case .allAvailable:
            let discovery = await healthKitManager.discoverEarliestHealthDataDate(
                enabledMetricIDs: metricIDs,
                timeZone: timeZone
            )
            guard discovery.isComplete else { throw IPhoneDirectQueryError.queryUnavailable }
            let end = calendar.startOfDay(for: Date())
            let start = discovery.earliestDate.map(calendar.startOfDay(for:)) ?? end
            return try sourceDateRange(from: start, to: end, calendar: calendar)
        }
    }

    private func sourceDateRange(from start: Date, to end: Date, calendar: Calendar) throws -> [Date] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard let distance = calendar.dateComponents([.day], from: startDay, to: endDay).day,
              distance >= 0,
              distance < 366_000 else {
            throw IPhoneDirectQueryError.queryScopeTooLarge
        }
        var values: [Date] = []
        values.reserveCapacity(distance + 1)
        var current = calendar.startOfDay(for: start)
        let terminal = calendar.startOfDay(for: end)
        while current <= terminal {
            values.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return values
    }

    private func unavailableDay(
        ownerDate: String,
        date: Date,
        timeZone: TimeZone,
        metricIDs: Set<String>
    ) throws -> HealthMdCompactContextDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw IPhoneDirectQueryError.queryUnavailable
        }
        let limitation = HealthMdLimitation(
            code: "capture_unavailable",
            message: "The iPhone did not provide a captured value for this owner day."
        )
        let definitions = Dictionary(uniqueKeysWithValues: HealthMetrics.all.map { ($0.id, $0) })
        let metrics = metricIDs.sorted().map { metricID in
            HealthMdContextMetric(
                observationID: "\(ownerDate):\(metricID)",
                metricID: metricID,
                displayName: definitions[metricID]?.name ?? metricID,
                value: nil,
                status: .failed,
                limitations: [limitation]
            )
        }
        let digest = SHA256.hash(data: Data("direct-query-missing:\(ownerDate)".utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return HealthMdCompactContextDay(
            ownerDate: ownerDate,
            intervalStart: start,
            intervalEnd: end,
            calendarTimeZone: timeZone.identifier,
            source: HealthMdSourceDescriptor(
                schema: "healthmd.direct_query_capture",
                schemaVersion: 1,
                digest: digest
            ),
            status: .failed,
            metrics: metrics,
            limitations: [limitation]
        )
    }

    private static func sourceDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private extension JSONEncoder {
    static var healthMdDirectQuery: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
#endif
