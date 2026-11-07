import Foundation

/// Health-free facts the destination screens derive from existing local state:
/// export history, profiles and the HTTP status of a connection test.
enum SettingsDestinationActivity {
    /// The most recent successful run that wrote to `target`. History entries recorded
    /// before targets existed carry no target; those were always iPhone-folder runs
    /// unless they came from the Mac agent.
    static func lastSuccess(
        to target: ExportTargetSelection,
        in history: [ExportHistoryEntry]
    ) -> Date? {
        history
            .filter { entry in
                guard entry.success else { return false }
                if let recorded = entry.exportTarget { return recorded == target }
                return target == .localIPhoneFolder && entry.source != .macAgent
            }
            .map(\.timestamp)
            .max()
    }

    /// The most recent request a paired CLI made, from the history the direct export
    /// paths record. Status-only commands are not recorded, so this is a lower bound.
    static func lastDirectCLIRequest(in history: [ExportHistoryEntry]) -> Date? {
        let directKinds: Set<ExportHistoryOperationDetails.Kind> = [
            .generatedFiles, .rawExport, .canonicalExtraction,
        ]
        return history
            .filter { entry in entry.operationDetails.map { directKinds.contains($0.kind) } ?? false }
            .map(\.timestamp)
            .max()
    }

    /// "today", "yesterday", "3 days ago".
    static func relativeDayText(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        return formatter.localizedString(from: DateComponents(day: days))
    }

    /// Names of the folder automations that write to the default folder: either no folder
    /// of their own, or a saved folder at the same path as the default one.
    static func profilesUsingDefaultFolder(
        profiles: [ExportProfile],
        savedFolders: [SavedVaultDestination],
        defaultFolderPath: String?
    ) -> [String] {
        profiles
            .filter { $0.target == .localIPhoneFolder }
            .filter { profile in
                guard let id = profile.folderVaultID else { return true }
                guard let defaultFolderPath,
                      let saved = savedFolders.first(where: { $0.id == id }) else { return false }
                return saved.standardizedPath == defaultFolderPath
            }
            .map(\.name)
    }

    /// "Today at 2:00 PM", "Yesterday at 9:12 AM", "Oct 24, 2026 at 6:00 AM".
    static func timestampText(
        _ date: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: date)
    }

    /// "200 OK", "401 Unauthorized". Reason phrases are HTTP protocol tokens (RFC 9110),
    /// so they are shown untranslated, the same way the status code is.
    static func httpStatusText(_ code: Int) -> String {
        guard let reason = reasonPhrases[code] else { return "HTTP \(code)" }
        return "\(code) \(reason)"
    }

    private static let reasonPhrases: [Int: String] = [
        200: "OK", 201: "Created", 202: "Accepted", 204: "No Content",
        301: "Moved Permanently", 302: "Found", 304: "Not Modified",
        307: "Temporary Redirect", 308: "Permanent Redirect",
        400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 408: "Request Timeout", 409: "Conflict",
        413: "Content Too Large", 415: "Unsupported Media Type", 429: "Too Many Requests",
        500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway",
        503: "Service Unavailable", 504: "Gateway Timeout",
    ]
}

/// Checks that a configured API endpoint answers, without sending health data.
///
/// The endpoint contract treats every POST as a snapshot the server may replace or
/// upsert, so a test must not POST. A HEAD request with the configured Authorization
/// reaches the same URL and reports its HTTP status; a POST-only route answering
/// "405 Method Not Allowed" still proves the host, TLS and path are reachable.
struct APIEndpointConnectionTester {
    var session: URLSession = .shared
    var timeout: TimeInterval = 15

    func statusCode(for destination: APIExportDestinationSnapshot) async throws -> Int {
        var request = URLRequest(url: destination.endpointURL, timeoutInterval: timeout)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Health.md iOS API Export", forHTTPHeaderField: "User-Agent")
        if let authorization = destination.authorizationHeaderValue {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIExportClientError.invalidResponse
        }
        return http.statusCode
    }

    /// The Authorization value `APIExportSettings` would send for `token`.
    static func authorizationHeaderValue(for token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.localizedCaseInsensitiveContains("Bearer ") || trimmed.localizedCaseInsensitiveContains("Basic ") {
            return trimmed
        }
        return "Bearer \(trimmed)"
    }
}

/// Local display names for the single API endpoint and Agent Data gateway. Names are
/// labels on this device only: they are never sent, exported or included in shared setups.
struct DestinationNameStore {
    static let apiEndpointKey = "apiExport.displayName"
    static let agentDataGatewayKey = "agentDataGateway.displayName"

    var defaults: UserDefaults = .standard

    var apiEndpointName: String {
        get { defaults.string(forKey: Self.apiEndpointKey) ?? "" }
        nonmutating set { store(newValue, key: Self.apiEndpointKey) }
    }

    var agentDataGatewayName: String {
        get { defaults.string(forKey: Self.agentDataGatewayKey) ?? "" }
        nonmutating set { store(newValue, key: Self.agentDataGatewayKey) }
    }

    private func store(_ value: String, key: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
    }
}
