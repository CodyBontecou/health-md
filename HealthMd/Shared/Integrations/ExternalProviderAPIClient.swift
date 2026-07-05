import Foundation

enum ExternalProviderAPIError: LocalizedError, Equatable {
    case unauthorized
    case invalidURL
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "The provider token has expired or was revoked."
        case .invalidURL:
            return "Health.md could not build the provider request URL."
        case .invalidResponse:
            return "The provider returned an invalid response."
        }
    }
}

struct ExternalProviderAPIClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDailyRecord(
        provider: ExternalIntegrationProvider,
        date: Date,
        token: ExternalIntegrationToken,
        calendar: Calendar = .current
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
            payloads = try await fetchWHOOP(day: day, token: token)
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

    private func fetchWHOOP(day: DayWindow, token: ExternalIntegrationToken) async throws -> [ExternalProviderPayload] {
        let base = "https://api.prod.whoop.com/developer/v2"
        let start = day.isoStart.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? day.isoStart
        let end = day.isoEnd.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? day.isoEnd
        let query = "start=\(start)&end=\(end)&limit=25"
        let endpoints: [(String, String)] = [
            ("cycles", "\(base)/cycle?\(query)"),
            ("recovery", "\(base)/recovery?\(query)"),
            ("sleep", "\(base)/activity/sleep?\(query)"),
            ("workouts", "\(base)/activity/workout?\(query)"),
            ("body_measurements", "\(base)/user/measurement/body")
        ]
        return try await fetchAllGET(endpoints, token: token)
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
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Health.md iOS External Integrations", forHTTPHeaderField: "User-Agent")
        request.setValue(token.authorizationHeaderValue, forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExternalProviderAPIError.invalidResponse }
        if http.statusCode == 401 { throw ExternalProviderAPIError.unauthorized }

        if (200..<300).contains(http.statusCode) {
            return ExternalProviderPayload(
                name: name,
                endpoint: redactedEndpoint(url),
                statusCode: http.statusCode,
                data: Self.jsonValue(from: data)
            )
        }

        return ExternalProviderPayload(
            name: name,
            endpoint: redactedEndpoint(url),
            statusCode: http.statusCode,
            data: Self.jsonValue(from: data),
            error: Self.errorText(from: data) ?? "HTTP \(http.statusCode)"
        )
    }

    private func redactedEndpoint(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        if let queryItems = components.queryItems {
            components.queryItems = queryItems.map { item in
                let sensitive = ["access_token", "client_secret", "refresh_token", "code"].contains(item.name.lowercased())
                return URLQueryItem(name: item.name, value: sensitive ? "[redacted]" : item.value)
            }
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

    private static func jsonValue(from data: Data) -> JSONValue? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data, options: []) {
            return JSONValue(any: object)
        }
        guard let string = String(data: data, encoding: .utf8), !string.isEmpty else { return nil }
        return .string(string)
    }

    private static func errorText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)
        }
        if let errors = object["errors"] as? [[String: Any]], let first = errors.first {
            return first["message"] as? String ?? first["errorType"] as? String
        }
        if let error = object["error"] as? String { return error }
        if let message = object["message"] as? String { return message }
        return nil
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
