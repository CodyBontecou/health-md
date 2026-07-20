import Foundation

enum ExternalProviderAPIError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case requestFailed(statusCode: Int, message: String)
    case invalidURL
    case invalidResponse
    case responseTooLarge(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "WHOOP authorization expired or was revoked. Reconnect WHOOP."
        case .rateLimited(let retryAfterSeconds):
            if let retryAfterSeconds {
                return "WHOOP is rate limiting requests. Try again in about \(retryAfterSeconds) seconds."
            }
            return "WHOOP is rate limiting requests. Try again later."
        case .requestFailed(_, let message):
            return message
        case .invalidURL:
            return "Health.md could not build the provider request URL."
        case .invalidResponse:
            return "The provider returned an invalid response."
        case .responseTooLarge(let maximumBytes):
            return "The provider response exceeded the \(maximumBytes)-byte safety limit."
        }
    }
}

actor WHOOPRateLimitGate {
    private var blockedUntil: Date?

    func remainingSeconds(now: Date = Date()) -> Int? {
        guard let blockedUntil else { return nil }
        let remaining = blockedUntil.timeIntervalSince(now)
        guard remaining > 0 else {
            self.blockedUntil = nil
            return nil
        }
        return max(1, Int(ceil(remaining)))
    }

    func block(for seconds: Int, now: Date = Date()) {
        let candidate = now.addingTimeInterval(TimeInterval(max(seconds, 1)))
        if blockedUntil == nil || candidate > blockedUntil! {
            blockedUntil = candidate
        }
    }
}

struct ExternalProviderAPIClient: Sendable {
    private static let whoopBaseURL = "https://api.prod.whoop.com/developer/v2"
    private static let maximumWHOOPPages = 100

    private let responseLoader: BoundedURLSessionDataLoader
    private let whoopRateLimitGate: WHOOPRateLimitGate
    private let maximumResponseBytes: Int
    private let maximumProviderDayResponseBytes: Int

    init(
        whoopRateLimitGate: WHOOPRateLimitGate = WHOOPRateLimitGate(),
        maximumResponseBytes: Int = 16 * 1_024 * 1_024,
        maximumProviderDayResponseBytes: Int? = nil
    ) {
        let maximumResponseBytes = max(1, maximumResponseBytes)
        self.responseLoader = BoundedURLSessionDataLoader(
            configuration: URLSession.shared.configuration
        )
        self.whoopRateLimitGate = whoopRateLimitGate
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumProviderDayResponseBytes = max(
            1,
            maximumProviderDayResponseBytes ?? maximumResponseBytes
        )
    }

    init(
        session: URLSession,
        whoopRateLimitGate: WHOOPRateLimitGate = WHOOPRateLimitGate(),
        maximumResponseBytes: Int = 16 * 1_024 * 1_024,
        maximumProviderDayResponseBytes: Int? = nil
    ) {
        let maximumResponseBytes = max(1, maximumResponseBytes)
        self.responseLoader = BoundedURLSessionDataLoader(session: session)
        self.whoopRateLimitGate = whoopRateLimitGate
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumProviderDayResponseBytes = max(
            1,
            maximumProviderDayResponseBytes ?? maximumResponseBytes
        )
    }

    func fetchDailyRecord(
        provider: ExternalIntegrationProvider,
        date: Date,
        token: ExternalIntegrationToken,
        calendar: Calendar = .current,
        now: Date = Date()
    ) async throws -> ExternalDailyRecord {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        let requestCounter = ExportPerformanceRequestCounter()
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "external-provider",
                phase: provider.rawValue,
                timer: performanceTimer,
                itemCount: requestCounter.count
            )
        }
        #endif
        let dateString = Self.dayString(date, calendar: calendar)
        let day = DayWindow(date: date, calendar: calendar)
        let responseBudget = ProviderDayResponseBudget(
            maximumBytes: maximumProviderDayResponseBytes
        )

        func loadPayloads() async throws -> [ExternalProviderPayload] {
            try await ProviderDayResponseBudgetContext.$current.withValue(responseBudget) {
                switch provider {
                case .fitbit:
                    return try await fetchFitbit(dateString: dateString, token: token)
                case .oura:
                    return try await fetchOura(dateString: dateString, token: token)
                case .whoop:
                    return try await fetchWHOOP(
                        day: day,
                        requestedDate: date,
                        now: now,
                        calendar: calendar,
                        token: token
                    )
                case .withings:
                    return try await fetchWithings(day: day, dateString: dateString, token: token)
                case .strava:
                    return try await fetchStrava(day: day, token: token)
                }
            }
        }

        let payloads: [ExternalProviderPayload]
        #if DEBUG
        payloads = try await ExportPerformanceInstrumentation.withRequestCounter(
            requestCounter,
            operation: loadPayloads
        )
        #else
        payloads = try await loadPayloads()
        #endif

        return ExternalDailyRecord(
            provider: provider,
            date: dateString,
            payloads: payloads
        )
    }

    func revokeAccess(provider: ExternalIntegrationProvider, token: ExternalIntegrationToken) async throws {
        guard provider == .whoop else { return }
        guard let url = URL(string: "\(Self.whoopBaseURL)/user/access") else {
            throw ExternalProviderAPIError.invalidURL
        }
        var request = authorizedRequest(url: url, method: "DELETE", token: token)
        request.setValue("0", forHTTPHeaderField: "Content-Length")

        let (data, http) = try await response(for: request)
        if http.statusCode == 401 { throw ExternalProviderAPIError.unauthorized }
        if http.statusCode == 429 {
            let reset = Self.rateLimitResetSeconds(from: http)
            await whoopRateLimitGate.block(for: reset ?? 60)
            throw ExternalProviderAPIError.rateLimited(retryAfterSeconds: reset)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.errorText(from: data) ?? "WHOOP could not revoke access (HTTP \(http.statusCode))."
            throw ExternalProviderAPIError.requestFailed(statusCode: http.statusCode, message: message)
        }
    }

    // MARK: - Provider Fetchers

    private func fetchFitbit(dateString: String, token: ExternalIntegrationToken) async throws -> [ExternalProviderPayload] {
        let base = "https://api.fitbit.com"
        let endpoints: [(String, String)] = [
            ("activities", "\(base)/1/user/-/activities/date/\(dateString).json"),
            ("sleep", "\(base)/1.2/user/-/sleep/date/\(dateString).json"),
            ("heart_rate", "\(base)/1/user/-/activities/heart/date/\(dateString)/1d.json"),
            ("hrv", "\(base)/1/user/-/hrv/date/\(dateString).json"),
            ("weight", "\(base)/1/user/-/body/log/weight/date/\(dateString).json")
        ]
        return try await fetchAllGET(endpoints, token: token)
    }

    private func fetchOura(dateString: String, token: ExternalIntegrationToken) async throws -> [ExternalProviderPayload] {
        let base = "https://api.ouraring.com/v2/usercollection"
        let query = "start_date=\(dateString)&end_date=\(dateString)"
        let endpoints: [(String, String)] = [
            ("daily_activity", "\(base)/daily_activity?\(query)"),
            ("daily_readiness", "\(base)/daily_readiness?\(query)"),
            ("daily_sleep", "\(base)/daily_sleep?\(query)"),
            ("daily_spo2", "\(base)/daily_spo2?\(query)"),
            ("sleep", "\(base)/sleep?\(query)"),
            ("workout", "\(base)/workout?\(query)"),
            ("heartrate", "\(base)/heartrate?\(query)")
        ]
        return try await fetchAllGET(endpoints, token: token)
    }

    private struct WHOOPCollection {
        let name: String
        let path: String
        let requiredScope: String
    }

    private func fetchWHOOP(
        day: DayWindow,
        requestedDate: Date,
        now: Date,
        calendar: Calendar,
        token: ExternalIntegrationToken
    ) async throws -> [ExternalProviderPayload] {
        let collections = [
            WHOOPCollection(name: "cycles", path: "/cycle", requiredScope: "read:cycles"),
            WHOOPCollection(name: "recovery", path: "/recovery", requiredScope: "read:recovery"),
            WHOOPCollection(name: "sleep", path: "/activity/sleep", requiredScope: "read:sleep"),
            WHOOPCollection(name: "workouts", path: "/activity/workout", requiredScope: "read:workout")
        ]

        var payloads: [ExternalProviderPayload] = []
        for collection in collections {
            guard token.grants(collection.requiredScope) else {
                payloads.append(Self.missingScopePayload(
                    name: collection.name,
                    endpoint: "\(Self.whoopBaseURL)\(collection.path)",
                    scope: collection.requiredScope
                ))
                continue
            }
            payloads.append(contentsOf: try await fetchWHOOPCollection(collection, day: day, token: token))
        }

        // WHOOP's body measurement endpoint is a current profile singleton and
        // has no measurement timestamp. Export it only with today's sidecar so
        // historical range exports do not repeat today's value for every day.
        if calendar.isDate(requestedDate, inSameDayAs: now) {
            let endpoint = "\(Self.whoopBaseURL)/user/measurement/body"
            if token.grants("read:body_measurement") {
                payloads.append(try await fetchWHOOPSingleton(
                    name: "body_measurements_snapshot",
                    urlString: endpoint,
                    token: token
                ))
            } else {
                payloads.append(Self.missingScopePayload(
                    name: "body_measurements_snapshot",
                    endpoint: endpoint,
                    scope: "read:body_measurement"
                ))
            }
        }

        return payloads
    }

    private func fetchWHOOPCollection(
        _ collection: WHOOPCollection,
        day: DayWindow,
        token: ExternalIntegrationToken
    ) async throws -> [ExternalProviderPayload] {
        var payloads: [ExternalProviderPayload] = []
        var nextToken: String?
        var seenTokens: Set<String> = []

        for page in 1...Self.maximumWHOOPPages {
            guard var components = URLComponents(string: "\(Self.whoopBaseURL)\(collection.path)") else {
                throw ExternalProviderAPIError.invalidURL
            }
            components.queryItems = [
                URLQueryItem(name: "start", value: day.isoStart),
                URLQueryItem(name: "end", value: day.isoEnd),
                URLQueryItem(name: "limit", value: "25")
            ]
            if let nextToken {
                components.queryItems?.append(URLQueryItem(name: "nextToken", value: nextToken))
            }
            guard let url = components.url else { throw ExternalProviderAPIError.invalidURL }
            let pageName = page == 1 ? collection.name : "\(collection.name)_page_\(page)"
            if let remaining = await whoopRateLimitGate.remainingSeconds() {
                payloads.append(Self.rateLimitCooldownPayload(
                    name: pageName,
                    endpoint: Self.redactedEndpoint(url),
                    remainingSeconds: remaining
                ))
                break
            }

            do {
                let (data, http) = try await response(
                    for: authorizedRequest(url: url, token: token)
                )
                if http.statusCode == 401 { throw ExternalProviderAPIError.unauthorized }

                guard (200..<300).contains(http.statusCode) else {
                    if http.statusCode == 429 {
                        await whoopRateLimitGate.block(
                            for: Self.rateLimitResetSeconds(from: http) ?? 60
                        )
                    }
                    payloads.append(Self.errorPayload(
                        name: pageName,
                        url: url,
                        statusCode: http.statusCode,
                        data: data,
                        response: http,
                        providerName: "WHOOP"
                    ))
                    break
                }

                guard let value = Self.strictJSONValue(from: data),
                      case .object(let object) = value,
                      case .array = object["records"] else {
                    payloads.append(ExternalProviderPayload(
                        name: pageName,
                        endpoint: Self.redactedEndpoint(url),
                        statusCode: http.statusCode,
                        error: "WHOOP returned malformed JSON for \(collection.name)."
                    ))
                    break
                }

                payloads.append(ExternalProviderPayload(
                    name: pageName,
                    endpoint: Self.redactedEndpoint(url),
                    statusCode: http.statusCode,
                    data: value
                ))

                guard case .string(let cursor)? = object["next_token"], !cursor.isEmpty else { break }
                guard seenTokens.insert(cursor).inserted else {
                    payloads.append(ExternalProviderPayload(
                        name: "\(collection.name)_pagination",
                        endpoint: Self.redactedEndpoint(url),
                        statusCode: 0,
                        error: "WHOOP returned a repeated pagination cursor."
                    ))
                    break
                }
                nextToken = cursor

                if page == Self.maximumWHOOPPages {
                    payloads.append(ExternalProviderPayload(
                        name: "\(collection.name)_pagination",
                        endpoint: Self.redactedEndpoint(url),
                        statusCode: 0,
                        error: "WHOOP pagination exceeded \(Self.maximumWHOOPPages) pages."
                    ))
                }
            } catch let error as ExternalProviderAPIError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                payloads.append(ExternalProviderPayload(
                    name: pageName,
                    endpoint: Self.redactedEndpoint(url),
                    statusCode: 0,
                    error: "WHOOP could not be reached for \(collection.name). Try again later."
                ))
                break
            }
        }

        return payloads
    }

    private func fetchWHOOPSingleton(
        name: String,
        urlString: String,
        token: ExternalIntegrationToken
    ) async throws -> ExternalProviderPayload {
        guard let url = URL(string: urlString) else { throw ExternalProviderAPIError.invalidURL }
        if let remaining = await whoopRateLimitGate.remainingSeconds() {
            return Self.rateLimitCooldownPayload(
                name: name,
                endpoint: urlString,
                remainingSeconds: remaining
            )
        }
        do {
            let (data, http) = try await response(
                for: authorizedRequest(url: url, token: token)
            )
            if http.statusCode == 401 { throw ExternalProviderAPIError.unauthorized }
            if http.statusCode == 429 {
                await whoopRateLimitGate.block(
                    for: Self.rateLimitResetSeconds(from: http) ?? 60
                )
            }
            if (200..<300).contains(http.statusCode) {
                let value = Self.strictJSONValue(from: data)
                guard data.isEmpty || value != nil else {
                    return ExternalProviderPayload(
                        name: name,
                        endpoint: Self.redactedEndpoint(url),
                        statusCode: http.statusCode,
                        error: "WHOOP returned malformed JSON for body measurements."
                    )
                }
                return ExternalProviderPayload(
                    name: name,
                    endpoint: Self.redactedEndpoint(url),
                    statusCode: http.statusCode,
                    data: value
                )
            }
            return Self.errorPayload(
                name: name,
                url: url,
                statusCode: http.statusCode,
                data: data,
                response: http,
                providerName: "WHOOP"
            )
        } catch ExternalProviderAPIError.unauthorized {
            throw ExternalProviderAPIError.unauthorized
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ExternalProviderPayload(
                name: name,
                endpoint: Self.redactedEndpoint(url),
                statusCode: 0,
                error: "WHOOP could not be reached for body measurements. Try again later."
            )
        }
    }

    private func fetchWithings(day: DayWindow, dateString: String, token: ExternalIntegrationToken) async throws -> [ExternalProviderPayload] {
        let base = "https://wbsapi.withings.net"
        let start = Int(day.start.timeIntervalSince1970)
        let end = Int(day.end.timeIntervalSince1970)
        let ymdQuery = "startdateymd=\(dateString)&enddateymd=\(dateString)"
        let endpoints: [(String, String)] = [
            ("daily_activity", "\(base)/v2/measure?action=getactivity&\(ymdQuery)"),
            ("workouts", "\(base)/v2/measure?action=getworkouts&\(ymdQuery)"),
            ("measures", "\(base)/measure?action=getmeas&startdate=\(start)&enddate=\(end)"),
            ("sleep_summary", "\(base)/v2/sleep?action=getsummary&\(ymdQuery)"),
            ("sleep_events", "\(base)/v2/sleep?action=get&startdate=\(start)&enddate=\(end)")
        ]
        return try await fetchAllGET(endpoints, token: token)
    }

    private func fetchStrava(day: DayWindow, token: ExternalIntegrationToken) async throws -> [ExternalProviderPayload] {
        let base = "https://www.strava.com/api/v3"
        let after = Int(day.start.timeIntervalSince1970)
        let before = Int(day.end.timeIntervalSince1970)
        let endpoints: [(String, String)] = [
            ("activities", "\(base)/athlete/activities?after=\(after)&before=\(before)&per_page=100&page=1")
        ]
        return try await fetchAllGET(endpoints, token: token)
    }

    // MARK: - Requests

    private func fetchAllGET(
        _ endpoints: [(name: String, url: String)],
        token: ExternalIntegrationToken
    ) async throws -> [ExternalProviderPayload] {
        let outcomes = try await Self.boundedConcurrentMap(
            endpoints,
            maximumConcurrency: 4
        ) { endpoint -> EndpointFetchOutcome in
            do {
                return .success(try await fetchGET(
                    name: endpoint.name,
                    urlString: endpoint.url,
                    token: token
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .failure(error)
            }
        }

        // All bounded requests must settle before selecting an error. A faster
        // transport failure must not hide a concurrent 401 and prevent the
        // caller's token-refresh path. Other failures retain endpoint order.
        let failures = outcomes.compactMap(\.failure)
        if failures.contains(where: { error in
            guard let providerError = error as? ExternalProviderAPIError else { return false }
            return providerError == .unauthorized
        }) {
            throw ExternalProviderAPIError.unauthorized
        }
        if let failure = failures.first {
            throw failure
        }
        return outcomes.compactMap(\.success)
    }

    private enum EndpointFetchOutcome: @unchecked Sendable {
        case success(ExternalProviderPayload)
        case failure(any Error)

        var success: ExternalProviderPayload? {
            guard case .success(let payload) = self else { return nil }
            return payload
        }

        var failure: (any Error)? {
            guard case .failure(let error) = self else { return nil }
            return error
        }
    }

    nonisolated static func boundedConcurrentMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maximumConcurrency: Int,
        operation: @escaping @Sendable (Input) async throws -> Output
    ) async throws -> [Output] {
        guard !inputs.isEmpty else { return [] }
        let limit = min(max(1, maximumConcurrency), inputs.count)
        return try await withThrowingTaskGroup(
            of: (Int, Output).self,
            returning: [Output].self
        ) { group in
            var nextInputIndex = 0
            var indexedOutputs: [(index: Int, output: Output)] = []
            indexedOutputs.reserveCapacity(inputs.count)

            func enqueue(_ index: Int) {
                let input = inputs[index]
                group.addTask {
                    (index, try await operation(input))
                }
            }

            while nextInputIndex < limit {
                enqueue(nextInputIndex)
                nextInputIndex += 1
            }
            while let output = try await group.next() {
                indexedOutputs.append(output)
                if nextInputIndex < inputs.count {
                    enqueue(nextInputIndex)
                    nextInputIndex += 1
                }
            }
            return indexedOutputs.sorted { $0.index < $1.index }.map(\.output)
        }
    }

    private func fetchGET(name: String, urlString: String, token: ExternalIntegrationToken) async throws -> ExternalProviderPayload {
        guard let url = URL(string: urlString) else { throw ExternalProviderAPIError.invalidURL }
        let (data, http) = try await response(
            for: authorizedRequest(url: url, token: token)
        )
        if http.statusCode == 401 { throw ExternalProviderAPIError.unauthorized }

        if (200..<300).contains(http.statusCode) {
            let value = Self.strictJSONValue(from: data)
            guard data.isEmpty || value != nil else {
                return ExternalProviderPayload(
                    name: name,
                    endpoint: Self.redactedEndpoint(url),
                    statusCode: http.statusCode,
                    error: "The provider returned malformed JSON."
                )
            }
            return ExternalProviderPayload(
                name: name,
                endpoint: Self.redactedEndpoint(url),
                statusCode: http.statusCode,
                data: value
            )
        }

        return Self.errorPayload(
            name: name,
            url: url,
            statusCode: http.statusCode,
            data: data,
            response: http,
            providerName: "Provider"
        )
    }

    private func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        #if DEBUG
        ExportPerformanceInstrumentation.recordRequest()
        #endif
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await responseLoader.data(
                for: request,
                maximumBytes: maximumResponseBytes
            )
        } catch let error as BoundedURLSessionDataLoaderError {
            switch error {
            case .responseTooLarge(let statusCode, _, let retryAfterSeconds):
                if statusCode == 401 {
                    throw ExternalProviderAPIError.unauthorized
                }
                if statusCode == 429 {
                    await whoopRateLimitGate.block(for: retryAfterSeconds ?? 60)
                    throw ExternalProviderAPIError.rateLimited(
                        retryAfterSeconds: retryAfterSeconds
                    )
                }
                throw ExternalProviderAPIError.responseTooLarge(
                    maximumBytes: maximumResponseBytes
                )
            }
        }
        guard let http = response as? HTTPURLResponse else {
            throw ExternalProviderAPIError.invalidResponse
        }
        if let responseBudget = ProviderDayResponseBudgetContext.current {
            do {
                try await responseBudget.consume(data.count)
            } catch let error as ExternalProviderAPIError {
                if http.statusCode == 401 {
                    throw ExternalProviderAPIError.unauthorized
                }
                if http.statusCode == 429 {
                    let retryAfterSeconds = Self.rateLimitResetSeconds(from: http)
                    await whoopRateLimitGate.block(for: retryAfterSeconds ?? 60)
                    throw ExternalProviderAPIError.rateLimited(
                        retryAfterSeconds: retryAfterSeconds
                    )
                }
                throw error
            }
        }
        return (data, http)
    }

    private func authorizedRequest(
        url: URL,
        method: String = "GET",
        token: ExternalIntegrationToken
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Health.md iOS External Integrations", forHTTPHeaderField: "User-Agent")
        request.setValue(token.authorizationHeaderValue, forHTTPHeaderField: "Authorization")
        return request
    }

    private static func rateLimitCooldownPayload(
        name: String,
        endpoint: String,
        remainingSeconds: Int
    ) -> ExternalProviderPayload {
        ExternalProviderPayload(
            name: name,
            endpoint: endpoint,
            statusCode: 429,
            error: "WHOOP rate limit cooldown is active. Try again in about \(remainingSeconds) seconds."
        )
    }

    private static func missingScopePayload(name: String, endpoint: String, scope: String) -> ExternalProviderPayload {
        ExternalProviderPayload(
            name: name,
            endpoint: endpoint,
            statusCode: 403,
            error: "WHOOP permission \(scope) is missing. Reconnect WHOOP and approve this permission."
        )
    }

    private static func errorPayload(
        name: String,
        url: URL,
        statusCode: Int,
        data: Data,
        response: HTTPURLResponse,
        providerName: String
    ) -> ExternalProviderPayload {
        let parsedValue = strictJSONValue(from: data)
        let error: String
        if statusCode == 429 {
            if let reset = rateLimitResetSeconds(from: response) {
                error = "\(providerName) rate limit reached. Try again in about \(reset) seconds."
            } else {
                error = "\(providerName) rate limit reached. Try again later."
            }
        } else if statusCode == 403 {
            error = "\(providerName) denied this data permission. Reconnect and approve the requested scopes."
        } else {
            error = errorText(from: parsedValue, fallbackData: data) ?? "HTTP \(statusCode)"
        }
        return ExternalProviderPayload(
            name: name,
            endpoint: redactedEndpoint(url),
            statusCode: statusCode,
            data: parsedValue,
            error: error
        )
    }

    private static func redactedEndpoint(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                let normalizedName = item.name.lowercased().filter(\.isLetter)
                let sensitive = ["accesstoken", "clientsecret", "refreshtoken", "code", "nexttoken"]
                    .contains(normalizedName)
                return URLQueryItem(name: item.name, value: sensitive ? "[redacted]" : item.value)
            }
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func strictJSONValue(from data: Data) -> JSONValue? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        return JSONValue(any: object)
    }

    private static func errorText(from data: Data) -> String? {
        errorText(from: strictJSONValue(from: data), fallbackData: data)
    }

    private static func errorText(
        from value: JSONValue?,
        fallbackData: Data
    ) -> String? {
        guard !fallbackData.isEmpty else { return nil }
        let candidate: String?
        if case .object(let object) = value {
            if case .array(let errors)? = object["errors"],
               case .object(let first)? = errors.first {
                if case .string(let message)? = first["message"] {
                    candidate = message
                } else if case .string(let errorType)? = first["errorType"] {
                    candidate = errorType
                } else {
                    candidate = nil
                }
            } else if case .string(let description)? = object["error_description"] {
                candidate = description
            } else if case .string(let error)? = object["error"] {
                candidate = error
            } else if case .string(let message)? = object["message"] {
                candidate = message
            } else {
                candidate = nil
            }
        } else {
            candidate = String(data: fallbackData, encoding: .utf8)
        }
        guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return String(trimmed.prefix(500))
    }

    private static func rateLimitResetSeconds(from response: HTTPURLResponse) -> Int? {
        let value = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
            ?? response.value(forHTTPHeaderField: "Retry-After")
        guard let value, let seconds = Int(value), seconds >= 0 else { return nil }
        return seconds
    }

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let cacheKey = "healthmd.provider-day.\(calendar.identifier).\(calendar.timeZone.identifier)"
        let formatter: DateFormatter
        if let cached = Thread.current.threadDictionary[cacheKey] as? DateFormatter {
            formatter = cached
        } else {
            let created = DateFormatter()
            created.calendar = calendar
            created.locale = Locale(identifier: "en_US_POSIX")
            created.timeZone = calendar.timeZone
            created.dateFormat = "yyyy-MM-dd"
            Thread.current.threadDictionary[cacheKey] = created
            formatter = created
        }
        return formatter.string(from: date)
    }
}

private enum ProviderDayResponseBudgetContext {
    @TaskLocal static var current: ProviderDayResponseBudget?
}

private actor ProviderDayResponseBudget {
    private let maximumBytes: Int
    private var consumedBytes = 0

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func consume(_ byteCount: Int) throws {
        guard byteCount <= maximumBytes - consumedBytes else {
            throw ExternalProviderAPIError.responseTooLarge(
                maximumBytes: maximumBytes
            )
        }
        consumedBytes += byteCount
    }
}

private struct DayWindow {
    let start: Date
    let end: Date

    init(date: Date, calendar: Calendar) {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        start = calendar.startOfDay(for: date)
        end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    var isoStart: String { Self.iso.string(from: start) }
    var isoEnd: String { Self.iso.string(from: end) }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
