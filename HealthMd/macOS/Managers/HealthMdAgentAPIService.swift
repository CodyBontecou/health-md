#if os(macOS)
import Foundation

protocol HealthMdAgentQueryExecuting: Sendable {
    func execute(
        _ request: HealthMdQueryRequest,
        detailLevel: AgentDetailLevel,
        evidenceScope: HealthMdEvidenceScope
    ) async throws -> HealthMdQueryResponse
}

@MainActor
final class HealthMdAgentAPIService {
    private struct QueryBody: Decodable {
        let grantID: UUID
        let profile: HealthContextProfileReference
        let request: HealthMdQueryRequest
        let detailLevel: AgentDetailLevel?
        let correlationID: UUID?

        enum CodingKeys: String, CodingKey {
            case grantID = "grant_id"
            case profile, request
            case detailLevel = "detail_level"
            case correlationID = "correlation_id"
        }
    }

    private struct ActivityBody: Decodable {
        let cursor: String?
        let maxItems: Int?
        enum CodingKeys: String, CodingKey { case cursor, maxItems = "max_items" }
    }

    private struct RefreshBody: Decodable {
        let grantID: UUID
        let profile: HealthContextProfileReference
        let dates: HealthMdDateSelection?
        let waitTimeoutSeconds: Double?
        let correlationID: UUID?

        enum CodingKeys: String, CodingKey {
            case grantID = "grant_id"
            case profile, dates
            case waitTimeoutSeconds = "wait_timeout_seconds"
            case correlationID = "correlation_id"
        }
    }

    typealias RefreshExecutor = @MainActor (
        _ registration: AgentClientRegistration,
        _ grantID: UUID,
        _ policy: HealthContextExecutionPolicy,
        _ waitTimeoutSeconds: Double
    ) async -> MacIPhoneExportRequestCoordinator.ExportResponse

    private let agentAccessManager: MacAgentAccessManager
    private let profileManager: HealthContextProfileManager
    private let exportCoordinator: MacIPhoneExportRequestCoordinator
    private let syncService: SyncService
    private let destinationStatus: () -> MacDestinationStatus
    private let queryExecutor: (any HealthMdAgentQueryExecuting)?
    private let refreshExecutor: RefreshExecutor?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        agentAccessManager: MacAgentAccessManager,
        profileManager: HealthContextProfileManager,
        exportCoordinator: MacIPhoneExportRequestCoordinator,
        syncService: SyncService,
        destinationStatus: @escaping () -> MacDestinationStatus,
        queryExecutor: (any HealthMdAgentQueryExecuting)? = nil,
        refreshExecutor: RefreshExecutor? = nil
    ) {
        self.agentAccessManager = agentAccessManager
        self.profileManager = profileManager
        self.exportCoordinator = exportCoordinator
        self.syncService = syncService
        self.destinationStatus = destinationStatus
        self.queryExecutor = queryExecutor
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
        registration: AgentClientRegistration,
        request: HealthMdControlServer.ParsedHTTPRequest
    ) async -> HealthMdControlServer.AgentAPIResponse {
        switch (request.method, request.path) {
        case ("GET", "/v1/agent/capabilities"):
            return jsonObject(status: 200, object: capabilities())
        case ("GET", "/v1/agent/profiles"):
            return profilesResponse(registration: registration)
        case ("POST", "/v1/agent/query"):
            return await queryResponse(
                registration: registration,
                request: request,
                requiresPacket: false,
                surface: Self.requestedSurface(request.headers)
            )
        case ("POST", "/v1/agent/evidence"):
            return await queryResponse(
                registration: registration,
                request: request,
                requiresPacket: true,
                surface: Self.requestedSurface(request.headers)
            )
        case ("POST", "/v1/agent/activity/query"):
            return activityResponse(registration: registration, body: request.body)
        case ("POST", "/v1/agent/refresh"):
            return await refreshResponse(
                registration: registration,
                body: request.body,
                surface: Self.requestedSurface(request.headers)
            )
        default:
            if let route = Self.jobRoute(request.path) {
                return await jobResponse(
                    registration: registration,
                    method: request.method,
                    route: route,
                    body: request.body
                )
            }
            return json(status: 404, value: ["error": "not_found"])
        }
    }

    private func queryResponse(
        registration: AgentClientRegistration,
        request: HealthMdControlServer.ParsedHTTPRequest,
        requiresPacket: Bool,
        surface: HealthContextSurface?
    ) async -> HealthMdControlServer.AgentAPIResponse {
        guard let surface else {
            return queryError(status: 400, code: "invalid_agent_surface", message: "The requested agent surface is unknown.")
        }
        let body: QueryBody
        do {
            body = try decoder.decode(QueryBody.self, from: request.body)
        } catch {
            return queryError(status: 400, code: "invalid_query_request", message: "The query body is invalid.")
        }
        if requiresPacket {
            guard case .derivePacket = body.request.operation else {
                return queryError(status: 400, code: "evidence_operation_required", message: "Evidence endpoint requires derive_packet.")
            }
        }
        guard let profile = profileManager.profile(id: body.profile.profileID),
              (try? profile.reference()) == body.profile else {
            return queryError(status: 403, code: "profile_reference_mismatch", message: "The pinned profile is unavailable.")
        }
        let effectivePolicy: HealthContextProfileEffectivePolicy
        let resolvedProfilePolicy: HealthContextExecutionPolicy
        do {
            let dateRequest: HealthContextDateRequest?
            if case .relative = profile.datePolicy {
                dateRequest = nil
            } else {
                dateRequest = try Self.profileDateRequest(body.request.dates)
            }
            resolvedProfilePolicy = try HealthContextProfileResolver.resolve(
                profile: profile,
                reference: body.profile,
                request: HealthContextProfileResolutionRequest(
                    caller: surface == .commandLine ? .commandLine : .registeredAgent,
                    surface: surface,
                    destinationID: "agent_api",
                    dateRequest: dateRequest,
                    confirmationProvided: false
                ),
                availableMetricIDs: HealthMetrics.all.map(\.id),
                availableSourceIDs: ["apple_health"] + ExternalIntegrationProvider.allCases.map(\.id),
                now: Date()
            )
            effectivePolicy = try HealthContextProfileAgentPolicyMapper.effectivePolicy(
                profile: profile,
                reference: body.profile
            )
        } catch {
            return queryError(status: 403, code: "profile_policy_unavailable", message: "The profile cannot authorize this agent surface.")
        }
        let accessRequest: AgentAccessRequest
        do {
            accessRequest = try makeAccessRequest(
                registration: registration,
                body: body
            )
        } catch {
            return queryError(status: 400, code: "invalid_query_scope", message: "The requested query scope is invalid.")
        }
        guard Self.agentDateScope(resolvedProfilePolicy.request.dates).contains(accessRequest.dateScope) else {
            return queryError(status: 403, code: "profile_date_scope_denied", message: "The requested dates exceed the resolved profile policy.")
        }
        let context = AgentAuthorizationContext(
            request: accessRequest,
            grantID: body.grantID,
            profilePolicy: effectivePolicy,
            healthKitAuthorization: AgentHealthKitAuthorizationSnapshot(
                state: .notRequiredForCachedData,
                readableMetrics: .allAvailable
            )
        )
        let decision: AgentAuthorizationDecision
        do {
            decision = try await agentAccessManager.authorizationDecision(context)
        } catch {
            return queryError(status: 503, code: "activity_history_unavailable", message: "Health.md could not record authorization activity.")
        }
        guard decision.isAuthorized else {
            return queryError(
                status: 403,
                code: decision.reasonCode.rawValue,
                message: "The exact query scope is not authorized."
            )
        }
        guard let queryExecutor else {
            return queryError(status: 503, code: "query_store_unavailable", message: "The encrypted query store is not ready.")
        }

        do {
            let response = try await queryExecutor.execute(
                body.request,
                detailLevel: body.detailLevel ?? .summary,
                evidenceScope: Self.evidenceScope(
                    for: resolvedProfilePolicy,
                    request: body.request
                )
            )
            let data = try HealthMdQueryCanonicalSerializer.data(for: response)
            _ = try? await agentAccessManager.recordActivity(
                for: accessRequest,
                grantID: body.grantID,
                resultRecordCount: response.items.count + (response.packet?.facts.count ?? 0),
                resultByteCount: data.count,
                outcome: .succeeded
            )
            return HealthMdControlServer.AgentAPIResponse(statusCode: 200, body: data)
        } catch let error as HealthMdQueryContractError {
            _ = try? await agentAccessManager.recordActivity(
                for: accessRequest,
                grantID: body.grantID,
                resultRecordCount: 0,
                resultByteCount: 0,
                outcome: .failed,
                reasonCode: .invalidRequest
            )
            return queryError(status: 400, code: String(describing: error), message: "The query could not be evaluated.")
        } catch {
            return queryError(status: 503, code: "query_execution_failed", message: "The encrypted query could not be completed.")
        }
    }

    private func refreshResponse(
        registration: AgentClientRegistration,
        body data: Data,
        surface: HealthContextSurface?
    ) async -> HealthMdControlServer.AgentAPIResponse {
        guard let surface else {
            return queryError(status: 400, code: "invalid_agent_surface", message: "The requested agent surface is unknown.")
        }
        guard let refreshExecutor else {
            return queryError(status: 503, code: "fresh_acquisition_unavailable", message: "Profile-scoped iPhone acquisition is unavailable.")
        }
        let body: RefreshBody
        do {
            body = try decoder.decode(RefreshBody.self, from: data)
        } catch {
            return queryError(status: 400, code: "invalid_refresh_request", message: "The refresh body is invalid.")
        }
        let timeout = body.waitTimeoutSeconds ?? 300
        guard HealthMdControlServer.isValidWaitTimeout(timeout),
              let profile = profileManager.profile(id: body.profile.profileID),
              (try? profile.reference()) == body.profile else {
            return queryError(status: 403, code: "profile_reference_mismatch", message: "The pinned profile or timeout is invalid.")
        }

        let dateRequest: HealthContextDateRequest?
        do {
            dateRequest = try Self.profileDateRequest(body.dates)
        } catch {
            return queryError(status: 400, code: "invalid_date_range", message: "The requested acquisition dates are invalid.")
        }
        let executionPolicy: HealthContextExecutionPolicy
        let effectivePolicy: HealthContextProfileEffectivePolicy
        do {
            executionPolicy = try HealthContextProfileResolver.resolve(
                profile: profile,
                reference: body.profile,
                request: HealthContextProfileResolutionRequest(
                    caller: surface == .commandLine ? .commandLine : .registeredAgent,
                    surface: surface,
                    destinationID: "agent_api",
                    dateRequest: dateRequest,
                    confirmationProvided: false
                ),
                availableMetricIDs: HealthMetrics.all.map(\.id),
                availableSourceIDs: ["apple_health"] + ExternalIntegrationProvider.allCases.map(\.id),
                now: Date()
            )
            effectivePolicy = try HealthContextProfileAgentPolicyMapper.effectivePolicy(
                profile: profile,
                reference: body.profile
            )
        } catch {
            return queryError(status: 403, code: "profile_execution_denied", message: error.localizedDescription)
        }

        guard executionPolicy.request.sourceIDs.contains("apple_health") else {
            return queryError(
                status: 422,
                code: "provider_only_acquisition_unsupported",
                message: "Fresh acquisition currently requires Apple Health in the resolved source scope; cached provider evidence remains queryable independently."
            )
        }

        let accessRequest = AgentAccessRequest(
            clientIdentity: .registered(registration.id),
            profileReference: body.profile,
            operation: .exportHealthData,
            dateScope: Self.agentDateScope(executionPolicy.request.dates),
            metricScope: .metricIDs(Set(executionPolicy.request.metricIDs)),
            detailLevel: executionPolicy.request.detailLevel == .lossless ? .losslessRecords : .summary,
            destinationClass: .connectedDevice,
            correlationID: body.correlationID ?? UUID()
        )
        let decision: AgentAuthorizationDecision
        do {
            decision = try await agentAccessManager.authorizationDecision(AgentAuthorizationContext(
                request: accessRequest,
                grantID: body.grantID,
                profilePolicy: effectivePolicy,
                healthKitAuthorization: AgentHealthKitAuthorizationSnapshot(
                    state: .verificationRequiredOnIPhone,
                    readableMetrics: .allAvailable
                )
            ))
        } catch {
            return queryError(status: 503, code: "activity_history_unavailable", message: "Health.md could not record acquisition authorization.")
        }
        guard decision.isAuthorized else {
            return queryError(status: 403, code: decision.reasonCode.rawValue, message: "The exact acquisition scope is not authorized.")
        }

        let response = await refreshExecutor(
            registration,
            body.grantID,
            executionPolicy,
            timeout
        )
        let responseData = (try? response.controlAPIData(using: encoder)) ?? Data()
        _ = try? await agentAccessManager.recordActivity(
            for: accessRequest,
            grantID: body.grantID,
            resultRecordCount: response.successCount ?? 0,
            resultByteCount: responseData.count,
            outcome: response.status == .failure || response.status == .unavailable ? .failed : .succeeded
        )
        let status = response.status == .unavailable ? 503
            : (response.status == .failure ? 422 : (response.status == .success || response.status == .partialSuccess ? 200 : 202))
        return HealthMdControlServer.AgentAPIResponse(statusCode: status, body: responseData)
    }

    private static func evidenceScope(
        for policy: HealthContextExecutionPolicy,
        request: HealthMdQueryRequest
    ) -> HealthMdEvidenceScope {
        let sourceIDs = Set(policy.request.sourceIDs)
        let allowsAppleHealth = sourceIDs.contains("apple_health")
        let providerIDs = Set(ExternalIntegrationProvider.allCases.map(\.id))
        let allowedProviders = sourceIDs.intersection(providerIDs)
        let allowedDetails: Set<String>
        if policy.request.detailLevel == .lossless,
           case .derivePacket(_, let detailIDs) = request.operation {
            allowedDetails = Set(detailIDs)
        } else {
            allowedDetails = []
        }
        return HealthMdEvidenceScope(
            allowedMetricIDs: Set(policy.request.metricIDs),
            allowedDetailIDs: allowedDetails,
            allowsWorkouts: policy.request.metricIDs.contains("workouts"),
            // Apple Health product selection authorizes every provenance source
            // represented inside its canonical records. Provider-native evidence
            // is authorized independently by stable provider ID.
            allowedSourceIDs: allowsAppleHealth ? nil : [],
            allowedProviderIDs: allowedProviders,
            allowsEvidenceValues: policy.request.detailLevel == .lossless
        )
    }

    private func makeAccessRequest(
        registration: AgentClientRegistration,
        body: QueryBody
    ) throws -> AgentAccessRequest {
        let dateScope: AgentDateScope
        switch body.request.dates {
        case .allAvailable:
            dateScope = .allHistory
        case .exact(let range):
            guard let start = Self.ownerDate(range.startDate, endOfDay: false),
                  let end = Self.ownerDate(range.endDate, endOfDay: true),
                  start <= end else { throw HealthMdQueryContractError.invalidDateRange }
            dateScope = .exact(start: start, end: end)
        }
        let metricScope: AgentMetricScope
        switch body.request.metrics {
        case .allAvailable: metricScope = .allAvailable
        case .explicit(let metricIDs): metricScope = .metricIDs(Set(metricIDs))
        }
        return AgentAccessRequest(
            clientIdentity: .registered(registration.id),
            profileReference: body.profile,
            operation: .readHealthData,
            dateScope: dateScope,
            metricScope: metricScope,
            detailLevel: body.detailLevel ?? .summary,
            destinationClass: .loopbackResponse,
            correlationID: body.correlationID ?? UUID()
        )
    }

    private func profilesResponse(
        registration: AgentClientRegistration
    ) -> HealthMdControlServer.AgentAPIResponse {
        let clientGrants = agentAccessManager.grants(for: registration.id)
        let profilesByID = Dictionary(uniqueKeysWithValues: profileManager.profiles.map { ($0.id, $0) })
        let entries: [[String: Any]] = clientGrants.compactMap { grant -> [String: Any]? in
            guard let profile = profilesByID[grant.profileReference.profileID],
                  (try? profile.reference()) == grant.profileReference,
                  let data = try? encoder.encode(profile),
                  let profileJSON = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return [
                "grant_id": grant.id.uuidString.lowercased(),
                "grant_status": grant.status(at: Date()).rawValue,
                "profile": profileJSON
            ]
        }
        return jsonObject(status: 200, object: [
            "schema": "healthmd.agent_profiles",
            "schema_version": 1,
            "profiles": entries
        ])
    }

    private func activityResponse(
        registration: AgentClientRegistration,
        body: Data
    ) -> HealthMdControlServer.AgentAPIResponse {
        let controls = (try? decoder.decode(ActivityBody.self, from: body))
            ?? ActivityBody(cursor: nil, maxItems: nil)
        let maxItems = controls.maxItems ?? 100
        guard maxItems > 0, maxItems <= HealthMdPageControls.maximumItems else {
            return queryError(status: 400, code: "invalid_page_controls", message: "Invalid activity page size.")
        }
        let records = agentAccessManager.activity.filter {
            $0.clientIdentity.registrationID == registration.id
        }
        let offset: Int
        if let cursor = controls.cursor {
            guard let priorID = Self.activityCursorID(cursor),
                  let priorIndex = records.firstIndex(where: { $0.id == priorID }) else {
                return queryError(status: 400, code: "invalid_cursor", message: "Invalid or stale activity cursor.")
            }
            offset = priorIndex + 1
        } else {
            offset = 0
        }
        let end = min(offset + maxItems, records.count)
        let page = Array(records[offset..<end])
        let next = end < records.count ? page.last.map { Self.activityCursor(for: $0.id) } : nil
        do {
            let recordsData = try encoder.encode(page)
            let recordsJSON = try JSONSerialization.jsonObject(with: recordsData)
            return jsonObject(status: 200, object: [
                "schema": "healthmd.agent_activity_page",
                "schema_version": 1,
                "records": recordsJSON,
                "next_cursor": next ?? NSNull()
            ])
        } catch {
            return queryError(status: 500, code: "activity_encode_failed", message: "Activity could not be encoded.")
        }
    }

    private func jobResponse(
        registration: AgentClientRegistration,
        method: String,
        route: (jobID: UUID, action: String?),
        body: Data
    ) async -> HealthMdControlServer.AgentAPIResponse {
        let response: MacIPhoneExportRequestCoordinator.ExportResponse
        switch (method, route.action) {
        case ("GET", nil):
            response = exportCoordinator.jobResponse(
                jobID: route.jobID,
                ownerRegistrationID: registration.id
            )
        case ("POST", .some("resume")):
            let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let timeout = object?["wait_timeout_seconds"] as? Double ?? 300
            guard HealthMdControlServer.isValidWaitTimeout(timeout) else {
                return queryError(status: 400, code: "invalid_timeout", message: "Invalid inactivity timeout.")
            }
            guard let ownerGrantID = exportCoordinator.jobOwnerGrantID(
                jobID: route.jobID,
                ownerRegistrationID: registration.id
            ), let ownerGrant = agentAccessManager.grants.first(where: { $0.id == ownerGrantID }),
               ownerGrant.status(at: Date()) == .active else {
                return queryError(status: 403, code: "grant_inactive", message: "The job's owning grant is not active.")
            }
            response = await exportCoordinator.resumeExport(
                jobID: route.jobID,
                waitTimeoutSeconds: timeout,
                ownerRegistrationID: registration.id,
                syncService: syncService,
                destinationStatus: destinationStatus()
            )
        case ("POST", .some("cancel")):
            response = exportCoordinator.cancelExport(
                jobID: route.jobID,
                ownerRegistrationID: registration.id,
                syncService: syncService
            )
        default:
            return json(status: 405, value: ["error": "method_not_allowed"])
        }
        let status: Int = response.failureReason == "job_not_found" ? 404
            : (response.status == .success || response.status == .partialSuccess ? 200 : 202)
        do {
            return HealthMdControlServer.AgentAPIResponse(
                statusCode: status,
                body: try response.controlAPIData(using: encoder)
            )
        } catch {
            return json(status: 500, value: ["error": "encode_failed"])
        }
    }

    private func capabilities() -> [String: Any] {
        [
            "schema": "healthmd.agent_capabilities",
            "schema_version": 1,
            "query_request": "healthmd.query_request/1",
            "query_response": "healthmd.query_response/1",
            "context_day": "healthmd.query_context_day/1",
            "evidence_packet": "healthmd.evidence_packet/1",
            "all_available_metrics": true,
            "all_available_history": true,
            "lossless_detail": true,
            "complete_cursor_traversal": true,
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

    private func json<T: Encodable>(
        status: Int,
        value: T
    ) -> HealthMdControlServer.AgentAPIResponse {
        do {
            return HealthMdControlServer.AgentAPIResponse(
                statusCode: status,
                body: try encoder.encode(value)
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

    private static func activityCursor(for id: UUID) -> String {
        Data("healthmd.activity.v1:\(id.uuidString.lowercased())".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func activityCursorID(_ cursor: String) -> UUID? {
        var base64 = cursor.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let value = String(data: data, encoding: .utf8),
              value.hasPrefix("healthmd.activity.v1:") else { return nil }
        return UUID(uuidString: String(value.dropFirst("healthmd.activity.v1:".count)))
    }

    private static func requestedSurface(_ headers: [String: String]) -> HealthContextSurface? {
        guard let raw = headers["x-healthmd-surface"] else { return .localControlAPI }
        let surface = HealthContextSurface(rawValue: raw)
        guard surface == .localControlAPI || surface == .commandLine || surface == .mcpStdio else {
            return nil
        }
        return surface
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

    private static func profileDateRequest(_ selection: HealthMdDateSelection?) throws -> HealthContextDateRequest? {
        guard let selection else { return nil }
        switch selection {
        case .allAvailable:
            return .allHistory
        case .exact(let range):
            guard let start = ownerDate(range.startDate, endOfDay: false),
                  let end = ownerDate(range.endDate, endOfDay: false),
                  start <= end else { throw HealthMdQueryContractError.invalidDateRange }
            return .bounded(HealthContextBoundedDateRange(start: start, end: end))
        }
    }

    private static func agentDateScope(_ request: HealthContextDateRequest) -> AgentDateScope {
        switch request {
        case .allHistory: return .allHistory
        case .bounded(let range): return .exact(start: range.start, end: range.end)
        }
    }

    private static func ownerDate(_ value: String, endOfDay: Bool) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let start = formatter.date(from: value), formatter.string(from: start) == value else { return nil }
        return endOfDay ? start.addingTimeInterval(86_400 - 0.001) : start
    }
}
#endif
