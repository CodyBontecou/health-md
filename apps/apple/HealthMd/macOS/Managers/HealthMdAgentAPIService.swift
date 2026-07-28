#if os(macOS)
import Foundation

nonisolated enum HealthMdRequestedScopeStatus: String, Codable, Equatable, Sendable {
    case success
    case partialSuccess = "partial_success"
    case failure
    case pending
    case unavailable
}

nonisolated struct HealthMdUnrelatedSkip: Codable, Equatable, Sendable {
    let identifier: String
    let status: HealthMdAvailabilityStatus
    let metricIDs: [String]
    let occurrenceCount: Int
    let firstOwnerDate: String
    let lastOwnerDate: String
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case identifier, status
        case metricIDs = "metric_ids"
        case occurrenceCount = "occurrence_count"
        case firstOwnerDate = "first_owner_date"
        case lastOwnerDate = "last_owner_date"
        case reason
    }
}

nonisolated struct HealthMdRequestedScopeCompletion: Codable, Equatable, Sendable {
    let schema: String
    let schemaVersion: Int
    let status: HealthMdRequestedScopeStatus
    let requestedMetricIDs: [String]
    let daysConsidered: Int
    let metricDaysConsidered: Int
    let completeMetricDays: Int
    let incompleteMetricDays: Int
    let statusCounts: [String: Int]
    let unrelatedSkips: [HealthMdUnrelatedSkip]

    init(
        status: HealthMdRequestedScopeStatus,
        requestedMetricIDs: [String],
        daysConsidered: Int,
        metricDaysConsidered: Int,
        completeMetricDays: Int,
        incompleteMetricDays: Int,
        statusCounts: [String: Int],
        unrelatedSkips: [HealthMdUnrelatedSkip]
    ) {
        schema = "healthmd.requested_scope_completion"
        schemaVersion = 1
        self.status = status
        self.requestedMetricIDs = Array(Set(requestedMetricIDs)).sorted()
        self.daysConsidered = daysConsidered
        self.metricDaysConsidered = metricDaysConsidered
        self.completeMetricDays = completeMetricDays
        self.incompleteMetricDays = incompleteMetricDays
        self.statusCounts = statusCounts
        self.unrelatedSkips = unrelatedSkips
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case status
        case requestedMetricIDs = "requested_metric_ids"
        case daysConsidered = "days_considered"
        case metricDaysConsidered = "metric_days_considered"
        case completeMetricDays = "complete_metric_days"
        case incompleteMetricDays = "incomplete_metric_days"
        case statusCounts = "status_counts"
        case unrelatedSkips = "unrelated_skips"
    }
}

nonisolated struct HealthMdAgentQueryStoreBaseline: Sendable, Equatable {
    let revision: String
    let ownerDateMutationIDs: [String: String]
}

protocol HealthMdAgentQueryExecuting: Sendable {
    func execute(
        _ request: HealthMdQueryRequest,
        detailLevel: HealthMdQueryDetailLevel,
        evidenceScope: HealthMdEvidenceScope
    ) async throws -> HealthMdQueryResponse

    func queryStoreBaseline() async throws -> HealthMdAgentQueryStoreBaseline?

    func requestedScopeCompletion(
        dates: HealthMdDateSelection,
        metricIDs: Set<String>,
        sources: HealthMdSourceSelection,
        changedSince baseline: HealthMdAgentQueryStoreBaseline?
    ) async throws -> HealthMdRequestedScopeCompletion?
}

extension HealthMdAgentQueryExecuting {
    func queryStoreBaseline() async throws -> HealthMdAgentQueryStoreBaseline? { nil }

    func requestedScopeCompletion(
        dates: HealthMdDateSelection,
        metricIDs: Set<String>,
        sources: HealthMdSourceSelection,
        changedSince baseline: HealthMdAgentQueryStoreBaseline?
    ) async throws -> HealthMdRequestedScopeCompletion? { nil }
}

nonisolated struct HealthMdAgentQueryStoreReadiness: Sendable, Equatable {
    let revision: String
    let ownerDateCount: Int
    let firstOwnerDate: String?
    let lastOwnerDate: String?
}

protocol HealthMdAgentQueryReadinessProviding: Sendable {
    func queryStoreReadiness() async throws -> HealthMdAgentQueryStoreReadiness
}

/// Serves the local query API. The loopback listener is the complete access
/// boundary: every request carries its own metric, source, date, and detail scope.
@MainActor
final class HealthMdAgentAPIService {
    private struct QueryBody: Decodable {
        let request: HealthMdQueryRequest
        let detailLevel: HealthMdQueryDetailLevel?

        enum CodingKeys: String, CodingKey {
            case request
            case detailLevel = "detail_level"
        }
    }

    private struct RefreshBody: Decodable {
        let dates: HealthMdDateSelection
        let metrics: HealthMdMetricSelection
        let sources: HealthMdSourceSelection
        let detailLevel: HealthMdQueryDetailLevel?
        let waitTimeoutSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case dates, metrics, sources
            case detailLevel = "detail_level"
            case waitTimeoutSeconds = "wait_timeout_seconds"
        }
    }

    typealias RefreshExecutor = @MainActor (
        _ dates: HealthMdDateSelection,
        _ selection: CanonicalHealthDataSelection,
        _ requestedDateIdentifiers: [String]?,
        _ waitTimeoutSeconds: Double
    ) async -> MacIPhoneExportRequestCoordinator.ExportResponse

    private let exportCoordinator: MacIPhoneExportRequestCoordinator
    private let syncService: SyncService
    private let destinationStatus: () -> MacDestinationStatus
    private let queryExecutor: (any HealthMdAgentQueryExecuting)?
    private let availableProviderIDs: [String]
    private let refreshExecutor: RefreshExecutor?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        exportCoordinator: MacIPhoneExportRequestCoordinator,
        syncService: SyncService,
        destinationStatus: @escaping () -> MacDestinationStatus,
        queryExecutor: (any HealthMdAgentQueryExecuting)? = nil,
        availableProviderIDs: [String]? = nil,
        refreshExecutor: RefreshExecutor? = nil
    ) {
        self.exportCoordinator = exportCoordinator
        self.syncService = syncService
        self.destinationStatus = destinationStatus
        self.queryExecutor = queryExecutor
        self.availableProviderIDs = availableProviderIDs
            ?? ConnectedAppsFeature.enabledProviders.map(\.id)
        self.refreshExecutor = refreshExecutor

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func respond(
        request: HealthMdControlServer.ParsedHTTPRequest
    ) async -> HealthMdControlServer.AgentAPIResponse {
        switch (request.method, request.path) {
        case ("GET", "/v1/agent/capabilities"):
            return jsonObject(status: 200, object: capabilities())
        case ("GET", "/v1/agent/metrics"):
            return metricCatalogResponse()
        case ("GET", "/v1/agent/readiness"):
            return await readinessResponse()
        case ("POST", "/v1/agent/query"):
            return await queryResponse(body: request.body, requiresPacket: false)
        case ("POST", "/v1/agent/evidence"):
            return await queryResponse(body: request.body, requiresPacket: true)
        case ("POST", "/v1/agent/refresh"):
            return await refreshResponse(body: request.body)
        case ("GET", "/v1/agent/profiles"),
             ("POST", "/v1/agent/activity/query"):
            return queryError(
                status: 410,
                code: "removed_endpoint",
                message: "Profiles, credentials, grants, and access activity are no longer part of the local API. Scope each request directly."
            )
        default:
            if let route = Self.jobRoute(request.path) {
                return await jobResponse(
                    method: request.method,
                    route: route,
                    body: request.body
                )
            }
            return jsonObject(status: 404, object: ["error": "not_found"])
        }
    }

    private func queryResponse(
        body data: Data,
        requiresPacket: Bool
    ) async -> HealthMdControlServer.AgentAPIResponse {
        guard Self.hasOnlyTopLevelKeys(data, allowed: ["request", "detail_level"]) else {
            return queryError(
                status: 400,
                code: "invalid_query_request",
                message: "The query body contains unsupported fields. Supply request and optional detail_level directly."
            )
        }
        let body: QueryBody
        do {
            body = try decoder.decode(QueryBody.self, from: data)
        } catch {
            return queryError(
                status: 400,
                code: "invalid_query_request",
                message: "The query body is invalid."
            )
        }

        if requiresPacket {
            guard case .derivePacket = body.request.operation else {
                return queryError(
                    status: 400,
                    code: "evidence_operation_required",
                    message: "Evidence endpoint requires derive_packet."
                )
            }
        }

        guard let queryExecutor else {
            return queryError(
                status: 503,
                code: "query_store_unavailable",
                message: "The encrypted query store is not ready."
            )
        }

        let detailLevel = body.detailLevel ?? .summary
        let evidenceScope: HealthMdEvidenceScope
        do {
            evidenceScope = try makeEvidenceScope(
                request: body.request,
                detailLevel: detailLevel
            )
        } catch let error as DirectScopeError {
            return queryError(status: 400, code: error.rawValue, message: error.message)
        } catch {
            return queryError(
                status: 400,
                code: "invalid_query_scope",
                message: "The query scope is invalid."
            )
        }

        do {
            let response = try await queryExecutor.execute(
                body.request,
                detailLevel: detailLevel,
                evidenceScope: evidenceScope
            )
            return HealthMdControlServer.AgentAPIResponse(
                statusCode: 200,
                body: try HealthMdQueryCanonicalSerializer.data(for: response)
            )
        } catch let error as HealthMdQueryContractError {
            return queryError(
                status: 400,
                code: String(describing: error),
                message: "The query could not be evaluated."
            )
        } catch {
            return queryError(
                status: 503,
                code: "query_execution_failed",
                message: "The encrypted query could not be completed."
            )
        }
    }

    private func refreshResponse(
        body data: Data
    ) async -> HealthMdControlServer.AgentAPIResponse {
        guard let refreshExecutor else {
            return queryError(
                status: 503,
                code: "fresh_acquisition_unavailable",
                message: "Request-scoped iPhone acquisition is unavailable."
            )
        }

        guard Self.hasOnlyTopLevelKeys(
            data,
            allowed: ["dates", "metrics", "sources", "detail_level", "wait_timeout_seconds"]
        ) else {
            return queryError(
                status: 400,
                code: "invalid_refresh_request",
                message: "The refresh body contains unsupported fields. Supply dates, metrics, sources, detail_level, and wait_timeout_seconds directly."
            )
        }

        let body: RefreshBody
        do {
            body = try decoder.decode(RefreshBody.self, from: data)
        } catch {
            return queryError(
                status: 400,
                code: "invalid_refresh_request",
                message: "Refresh requires explicit dates, metrics, and sources."
            )
        }

        let timeout = body.waitTimeoutSeconds ?? 300
        guard HealthMdControlServer.isValidWaitTimeout(timeout) else {
            return queryError(
                status: 400,
                code: "invalid_timeout",
                message: "wait_timeout_seconds must be finite and between 5 and 900 seconds."
            )
        }

        let metricIDs: [String]
        let sourceIDs: [String]
        let requestedDateIdentifiers: [String]?
        do {
            metricIDs = try resolvedMetricIDs(body.metrics)
            sourceIDs = try resolvedAcquisitionSourceIDs(body.sources)
            requestedDateIdentifiers = try Self.requestedDateIdentifiers(body.dates)
        } catch let error as DirectScopeError {
            return queryError(status: 400, code: error.rawValue, message: error.message)
        } catch {
            return queryError(
                status: 400,
                code: "invalid_date_range",
                message: "The requested acquisition dates are invalid."
            )
        }

        let selection = CanonicalHealthDataSelection(
            metricIDs: metricIDs,
            sourceIDs: sourceIDs,
            detailLevel: body.detailLevel == .lossless ? .lossless : .summary
        )
        let acquisitionProviderIDs = Set(availableProviderIDs)
        let completionSources = HealthMdSourceSelection.explicit(
            sourceIDs: sourceIDs.filter { !acquisitionProviderIDs.contains($0) },
            providerIDs: sourceIDs.filter(acquisitionProviderIDs.contains)
        )
        let completionBaseline = try? await queryExecutor?.queryStoreBaseline()
        let response = await refreshExecutor(
            body.dates,
            selection,
            requestedDateIdentifiers,
            timeout
        )

        var completionDates = body.dates
        if case .allAvailable = completionDates,
           let jobID = response.jobID,
           let identifiers = exportCoordinator.resolvedDateIdentifiers(jobID: jobID),
           let first = identifiers.first,
           let last = identifiers.last {
            completionDates = .exact(.init(startDate: first, endDate: last))
        }

        let completion: HealthMdRequestedScopeCompletion?
        if response.status == .success || response.status == .partialSuccess,
           let queryExecutor,
           let completionBaseline {
            completion = try? await queryExecutor.requestedScopeCompletion(
                dates: completionDates,
                metricIDs: Set(metricIDs),
                sources: completionSources,
                changedSince: completionBaseline
            )
        } else {
            completion = nil
        }

        let responseData = (try? enrichedRefreshData(
            response,
            completion: completion
        )) ?? Data()
        return HealthMdControlServer.AgentAPIResponse(
            statusCode: Self.httpStatus(for: response),
            body: responseData
        )
    }

    private func enrichedRefreshData(
        _ response: MacIPhoneExportRequestCoordinator.ExportResponse,
        completion: HealthMdRequestedScopeCompletion?
    ) throws -> Data {
        let encoded = try response.controlAPIData(using: encoder)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            return encoded
        }

        let fallback: HealthMdRequestedScopeStatus
        switch response.status {
        case .success, .partialSuccess: fallback = .unavailable
        case .accepted, .preparing, .timedOut: fallback = .pending
        case .failure, .cancelled: fallback = .failure
        case .unavailable: fallback = .unavailable
        }
        object["corpus_status"] = response.status.rawValue
        object["requested_scope_status"] = (completion?.status ?? fallback).rawValue
        object["requested_scope_verification"] = completion == nil
            ? "unavailable" : "verified_current_refresh"
        if let completion {
            let data = try encoder.encode(completion)
            let scopeObject = try JSONSerialization.jsonObject(with: data)
            object["requested_scope"] = scopeObject
            object["unrelated_skips"] = (scopeObject as? [String: Any])?["unrelated_skips"] ?? []
        } else {
            object["requested_scope"] = NSNull()
            object["unrelated_skips"] = []
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func makeEvidenceScope(
        request: HealthMdQueryRequest,
        detailLevel: HealthMdQueryDetailLevel
    ) throws -> HealthMdEvidenceScope {
        let metricIDs = Set(try resolvedMetricIDs(request.metrics))
        let selectedSources = try resolvedQuerySources(request.sources)
        let allowsAppleHealth = selectedSources.sourceIDs.contains("apple_health")
        let allowedDetails: Set<String>
        if detailLevel == .lossless,
           case .derivePacket(_, let detailIDs) = request.operation {
            allowedDetails = Set(detailIDs)
        } else {
            allowedDetails = []
        }

        return HealthMdEvidenceScope(
            allowedMetricIDs: metricIDs,
            allowedDetailIDs: allowedDetails,
            allowsWorkouts: metricIDs.contains("workouts"),
            allowedSourceIDs: allowsAppleHealth ? nil : selectedSources.sourceIDs,
            allowedProviderIDs: selectedSources.providerIDs,
            allowsEvidenceValues: detailLevel == .lossless
        )
    }

    private func resolvedMetricIDs(
        _ selection: HealthMdMetricSelection
    ) throws -> [String] {
        let available = Set(HealthMetrics.all.map(\.id))
        switch selection {
        case .allAvailable:
            return available.sorted()
        case .explicit(let metricIDs):
            let requested = Set(metricIDs)
            guard !requested.isEmpty else { throw DirectScopeError.emptyMetrics }
            guard requested.isSubset(of: available) else { throw DirectScopeError.unknownMetric }
            return requested.sorted()
        }
    }

    private func resolvedAcquisitionSourceIDs(
        _ selection: HealthMdSourceSelection
    ) throws -> [String] {
        let available = Set(["apple_health"] + availableProviderIDs)
        let requested: Set<String>
        switch selection {
        case .allAvailable:
            requested = available
        case .explicit(let sourceIDs, let providerIDs):
            requested = Set(sourceIDs + providerIDs)
        }
        guard !requested.isEmpty else { throw DirectScopeError.emptySources }
        guard requested.isSubset(of: available) else { throw DirectScopeError.unknownSource }
        return requested.sorted()
    }

    private func resolvedQuerySources(
        _ selection: HealthMdSourceSelection
    ) throws -> (sourceIDs: Set<String>, providerIDs: Set<String>) {
        let availableProviders = Set(availableProviderIDs)
        switch selection {
        case .allAvailable:
            return (["apple_health"], availableProviders)
        case .explicit(let sourceIDs, let providerIDs):
            let sources = Set(sourceIDs)
            let providers = Set(providerIDs)
            let knownSources = Set([
                "apple_health",
                HealthMdEvidenceSourceIDs.healthMdSummary,
                HealthMdEvidenceSourceIDs.providerNative,
                HealthMdEvidenceSourceIDs.diagnostics
            ])
            guard !sources.isEmpty || !providers.isEmpty else {
                throw DirectScopeError.emptySources
            }
            guard sources.isSubset(of: knownSources),
                  providers.isSubset(of: availableProviders) else {
                throw DirectScopeError.unknownSource
            }
            return (sources, providers)
        }
    }

    private func readinessResponse() async -> HealthMdControlServer.AgentAPIResponse {
        var checks: [[String: Any]] = []
        var nextActions: [[String: Any]] = []
        var cachedOwnerDateCount: Int?
        var queryStore: [String: Any] = ["available": false]

        if let readinessProvider = queryExecutor as? any HealthMdAgentQueryReadinessProviding {
            do {
                let readiness = try await readinessProvider.queryStoreReadiness()
                cachedOwnerDateCount = readiness.ownerDateCount
                queryStore = [
                    "available": true,
                    "revision": readiness.revision,
                    "owner_date_count": readiness.ownerDateCount,
                    "first_owner_date": readiness.firstOwnerDate ?? NSNull(),
                    "last_owner_date": readiness.lastOwnerDate ?? NSNull()
                ]
                checks.append([
                    "code": "encrypted_query_store",
                    "status": readiness.ownerDateCount == 0 ? "warning" : "ready",
                    "blocking": false,
                    "message": readiness.ownerDateCount == 0
                        ? "The encrypted query store is ready but empty."
                        : "Cached query data is available."
                ])
            } catch {
                queryStore = ["available": false, "error": error.localizedDescription]
                checks.append([
                    "code": "encrypted_query_store",
                    "status": "unavailable",
                    "blocking": true,
                    "message": error.localizedDescription
                ])
            }
        } else {
            checks.append([
                "code": "encrypted_query_store",
                "status": "unavailable",
                "blocking": true,
                "message": "The encrypted query executor is not configured."
            ])
        }

        let connected = syncService.connectionState == .connected
        let compatiblePeer = syncService.remoteCapabilities?
            .supportsRequestScopedContextAcquisition == true
            && syncService.localCapabilities.supportsRequestScopedContextAcquisition
        let canRefresh = refreshExecutor != nil && connected && compatiblePeer
        checks.append([
            "code": "fresh_iphone_acquisition",
            "status": canRefresh ? "ready" : "warning",
            "blocking": false,
            "message": canRefresh
                ? "The connected iPhone can acquire the requested scope."
                : "Cached queries may work, but fresh acquisition needs a connected, compatible iPhone."
        ])
        if !canRefresh {
            nextActions.append([
                "code": "connect_iphone_for_fresh_data",
                "message": "Unlock the iPhone, open Health.md, and wait for it to connect."
            ])
        }

        if cachedOwnerDateCount == 0 && !canRefresh {
            checks.append([
                "code": "usable_query_data_path",
                "status": "action_required",
                "blocking": true,
                "message": "No cached owner days are available and fresh acquisition is unavailable."
            ])
        } else if cachedOwnerDateCount != nil {
            checks.append([
                "code": "usable_query_data_path",
                "status": "ready",
                "blocking": false,
                "message": "A local query data path is available."
            ])
        }

        let hasBlockingFailure = checks.contains {
            ($0["blocking"] as? Bool) == true
                && ["action_required", "unavailable"].contains($0["status"] as? String ?? "")
        }
        return jsonObject(status: 200, object: [
            "schema": "healthmd.local_readiness",
            "schema_version": 1,
            "status": hasBlockingFailure ? "action_required" : "ready",
            "query_store": queryStore,
            "iphone": [
                "connected": connected,
                "name": (syncService.connectedPeerName as Any?) ?? NSNull(),
                "supports_request_scoped_context_acquisition": compatiblePeer,
                "can_trigger_fresh_acquisition": canRefresh
            ],
            "checks": checks,
            "next_actions": nextActions
        ])
    }

    private func metricCatalogResponse() -> HealthMdControlServer.AgentAPIResponse {
        let metrics: [[String: Any]] = HealthMetrics.all
            .sorted { $0.id < $1.id }
            .map { metric in
                [
                    "id": metric.id,
                    "name": metric.name,
                    "category": metric.category.rawValue,
                    "unit": metric.unit,
                    "archive_only": metric.isArchiveOnly,
                    "availability": metric.availability.rawValue,
                    "requires_separate_authorization": metric.category.requiresSeparateAuthorization
                ]
            }
        return jsonObject(status: 200, object: [
            "schema": "healthmd.metric_catalog",
            "schema_version": 1,
            "metrics": metrics
        ])
    }

    private func jobResponse(
        method: String,
        route: (jobID: UUID, action: String?),
        body: Data
    ) async -> HealthMdControlServer.AgentAPIResponse {
        let response: MacIPhoneExportRequestCoordinator.ExportResponse
        switch (method, route.action) {
        case ("GET", nil):
            response = exportCoordinator.jobResponse(jobID: route.jobID)
        case ("POST", .some("resume")):
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let timeout = object?["wait_timeout_seconds"] as? Double ?? 300
            guard HealthMdControlServer.isValidWaitTimeout(timeout) else {
                return queryError(
                    status: 400,
                    code: "invalid_timeout",
                    message: "Invalid inactivity timeout."
                )
            }
            response = await exportCoordinator.resumeExport(
                jobID: route.jobID,
                waitTimeoutSeconds: timeout,
                syncService: syncService,
                destinationStatus: destinationStatus()
            )
        case ("POST", .some("cancel")):
            response = exportCoordinator.cancelExport(
                jobID: route.jobID,
                syncService: syncService
            )
        default:
            return jsonObject(status: 405, object: ["error": "method_not_allowed"])
        }

        do {
            return HealthMdControlServer.AgentAPIResponse(
                statusCode: Self.httpStatus(for: response),
                body: try response.controlAPIData(using: encoder)
            )
        } catch {
            return jsonObject(status: 500, object: ["error": "encode_failed"])
        }
    }

    private func capabilities() -> [String: Any] {
        [
            "schema": "healthmd.local_capabilities",
            "schema_version": 1,
            "query_request": "healthmd.query_request/1",
            "query_response": "healthmd.query_response/1",
            "context_day": "healthmd.query_context_day/1",
            "evidence_packet": "healthmd.evidence_packet/1",
            "request_scoped": true,
            "all_available_metrics": true,
            "all_available_history": true,
            "lossless_detail": true,
            "complete_cursor_traversal": true,
            "metric_catalog": "healthmd.metric_catalog/1",
            "readiness": "healthmd.local_readiness/1",
            "query_operations": [
                "metric_series", "source_record_listing", "workout_listing",
                "sleep_session_listing", "workout_sleep_alignment", "coverage",
                "period_comparison", "derive_packet"
            ],
            "sleep_session_windows": true,
            "workout_sleep_alignment": true,
            "requested_scope_completion": "healthmd.requested_scope_completion/1",
            "unrelated_skip_diagnostics": true,
            "request_scoped_context_acquisition": true,
            "maximum_page_items": HealthMdPageControls.maximumItems,
            "maximum_page_bytes": HealthMdPageControls.maximumBytes,
            "fresh_acquisition": refreshExecutor != nil
        ]
    }

    private func queryError(
        status: Int,
        code: String,
        message: String
    ) -> HealthMdControlServer.AgentAPIResponse {
        do {
            return HealthMdControlServer.AgentAPIResponse(
                statusCode: status,
                body: try HealthMdQueryCanonicalSerializer.data(
                    for: HealthMdQueryError(code: code, message: message)
                )
            )
        } catch {
            return HealthMdControlServer.AgentAPIResponse(
                statusCode: 500,
                body: Data("{\"error\":\"encode_failed\"}".utf8)
            )
        }
    }

    private func jsonObject(
        status: Int,
        object: [String: Any]
    ) -> HealthMdControlServer.AgentAPIResponse {
        do {
            return HealthMdControlServer.AgentAPIResponse(
                statusCode: status,
                body: try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys, .withoutEscapingSlashes]
                )
            )
        } catch {
            return HealthMdControlServer.AgentAPIResponse(
                statusCode: 500,
                body: Data("{\"error\":\"encode_failed\"}".utf8)
            )
        }
    }

    private static func hasOnlyTopLevelKeys(
        _ data: Data,
        allowed: Set<String>
    ) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return false }
        return Set(dictionary.keys).isSubset(of: allowed)
    }

    private static func jobRoute(_ path: String) -> (jobID: UUID, action: String?)? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 4 || components.count == 5,
              components[0] == "v1", components[1] == "agent", components[2] == "jobs",
              let jobID = UUID(uuidString: String(components[3])) else { return nil }
        let action = components.count == 5 ? String(components[4]) : nil
        guard action == nil || action == "resume" || action == "cancel" else { return nil }
        return (jobID, action)
    }

    private static func requestedDateIdentifiers(
        _ selection: HealthMdDateSelection
    ) throws -> [String]? {
        switch selection {
        case .allAvailable:
            return nil
        case .exact(let range):
            guard let start = ownerDate(range.startDate),
                  let end = ownerDate(range.endDate),
                  start <= end else {
                throw DirectScopeError.invalidDates
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            var identifiers: [String] = []
            var current = start
            while current <= end {
                identifiers.append(formatter.string(from: current))
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                    throw DirectScopeError.invalidDates
                }
                current = next
            }
            return identifiers
        }
    }

    private static func ownerDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value),
              formatter.string(from: date) == value else { return nil }
        return date
    }

    private static func httpStatus(
        for response: MacIPhoneExportRequestCoordinator.ExportResponse
    ) -> Int {
        if response.failureReason == "job_not_found" { return 404 }
        switch response.status {
        case .success, .partialSuccess: return 200
        case .accepted, .preparing: return 202
        case .timedOut: return 408
        case .cancelled: return 409
        case .failure: return 422
        case .unavailable: return 503
        }
    }

    private enum DirectScopeError: String, Error {
        case emptyMetrics = "empty_metric_selection"
        case unknownMetric = "unknown_metric"
        case emptySources = "empty_source_selection"
        case unknownSource = "unknown_source"
        case invalidDates = "invalid_date_range"

        var message: String {
            switch self {
            case .emptyMetrics: return "Select at least one metric."
            case .unknownMetric: return "The request contains an unsupported metric."
            case .emptySources: return "Select at least one source."
            case .unknownSource: return "The request contains an unsupported source or provider."
            case .invalidDates: return "The request contains an invalid date range."
            }
        }
    }
}
#endif
