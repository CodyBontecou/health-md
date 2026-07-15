import Foundation

enum ExternalProviderAPIError: LocalizedError, Equatable {
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case requestFailed(statusCode: Int, message: String)
    case invalidURL
    case invalidResponse

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

    private let session: URLSession
    private let whoopRateLimitGate: WHOOPRateLimitGate

    init(
        session: URLSession = .shared,
        whoopRateLimitGate: WHOOPRateLimitGate = WHOOPRateLimitGate()
    ) {
        self.session = session
        self.whoopRateLimitGate = whoopRateLimitGate
    }

    func fetchDailyRecord(
        provider: ExternalIntegrationProvider,
        date: Date,
        token: ExternalIntegrationToken,
        calendar: Calendar = .current,
        now: Date = Date()
    ) async throws -> ExternalDailyRecord {
        let dateString = Self.dayString(date, calendar: calendar)
        let day = DayWindow(date: date, calendar: calendar)
        let payloads: [ExternalProviderPayload]

        switch provider {
        case .fitbit:
            payloads = try await fetchFitbit(dateString: dateString, token: token)
        case .oura:
            payloads = try await fetchOura(dateString: dateString, token: token)
        case .whoop:
            payloads = try await fetchWHOOP(
                day: day,
                requestedDate: date,
                now: now,
                calendar: calendar,
                token: token
            )
        case .withings:
            payloads = try await fetchWithings(day: day, dateString: dateString, token: token)
        case .strava:
            payloads = try await fetchStrava(day: day, token: token)
        }

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

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ExternalProviderAPIError.invalidResponse
        }
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
                let (data, response) = try await session.data(for: authorizedRequest(url: url, token: token))
                guard let http = response as? HTTPURLResponse else {
                    throw ExternalProviderAPIError.invalidResponse
                }
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
            let (data, response) = try await session.data(for: authorizedRequest(url: url, token: token))
            guard let http = response as? HTTPURLResponse else {
                throw ExternalProviderAPIError.invalidResponse
            }
            if http.statusCode == 401 { throw ExternalProviderAPIError.unauthorized }
            if http.statusCode == 429 {
                await whoopRateLimitGate.block(
                    for: Self.rateLimitResetSeconds(from: http) ?? 60
                )
            }
            if (200..<300).contains(http.statusCode) {
                guard data.isEmpty || Self.strictJSONValue(from: data) != nil else {
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
                    data: Self.strictJSONValue(from: data)
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

    private func fetchAllGET(_ endpoints: [(name: String, url: String)], token: ExternalIntegrationToken) async throws -> [ExternalProviderPayload] {
        var payloads: [ExternalProviderPayload] = []
        payloads.reserveCapacity(endpoints.count)
        for endpoint in endpoints {
            payloads.append(try await fetchGET(name: endpoint.name, urlString: endpoint.url, token: token))
        }
        return payloads
    }

    private func fetchGET(name: String, urlString: String, token: ExternalIntegrationToken) async throws -> ExternalProviderPayload {
        guard let url = URL(string: urlString) else { throw ExternalProviderAPIError.invalidURL }
        let (data, response) = try await session.data(for: authorizedRequest(url: url, token: token))
        guard let http = response as? HTTPURLResponse else { throw ExternalProviderAPIError.invalidResponse }
        if http.statusCode == 401 { throw ExternalProviderAPIError.unauthorized }

        if (200..<300).contains(http.statusCode) {
            guard data.isEmpty || Self.strictJSONValue(from: data) != nil else {
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
                data: Self.strictJSONValue(from: data)
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
            error = errorText(from: data) ?? "HTTP \(statusCode)"
        }
        return ExternalProviderPayload(
            name: name,
            endpoint: redactedEndpoint(url),
            statusCode: statusCode,
            data: strictJSONValue(from: data),
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
        guard !data.isEmpty else { return nil }
        let candidate: String?
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errors = object["errors"] as? [[String: Any]], let first = errors.first {
                candidate = first["message"] as? String ?? first["errorType"] as? String
            } else if let description = object["error_description"] as? String {
                candidate = description
            } else if let error = object["error"] as? String {
                candidate = error
            } else {
                candidate = object["message"] as? String
            }
        } else {
            candidate = String(data: data, encoding: .utf8)
        }
        guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
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
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
