import CryptoKit
import Foundation

/// Adoption boundary for receiver-coverage v1. Not wired into schedules: a caller must durably
/// admit the frozen occurrence and selection evidence before it can capture or upload anything.
/// Instances contain private routing metadata; never encode, describe, or log them.
struct ReceiverCoveragePreflight {
    enum Policy: String { case fullLookback = "full_lookback", missingDays = "missing_days" }
    enum BoundaryError: Error { case invalidConfiguration, invalidOccurrence, invalidResponse, destinationChanged }

    static let deadlineSeconds = 10
    static let maximumResponseBytes = 64 * 1024
    let uploadURL: URL
    let preflightURL: URL
    let headers: [String: String]
    let destinationBinding: String
    let scopeID: String
    let calendarTimeZone: TimeZone
    let calendarTimeZoneIdentifier: String
    let refreshRecentDays: Int

    private init(uploadURL: URL, preflightURL: URL, headers: [String: String], destinationBinding: String,
                 scopeID: String, calendarTimeZone: TimeZone, calendarTimeZoneIdentifier: String, refreshRecentDays: Int) {
        self.uploadURL = uploadURL
        self.preflightURL = preflightURL
        self.headers = headers
        self.destinationBinding = destinationBinding
        self.scopeID = scopeID
        self.calendarTimeZone = calendarTimeZone
        self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier
        self.refreshRecentDays = refreshRecentDays
    }

    /// A missing setting is full lookback, including for existing HTTP endpoints. In this case
    /// do not consult credentials, generate a binding, validate preflight settings, or send traffic.
    static func prepare(
        policy: Policy = .fullLookback,
        uploadURL: String,
        preflightURL: String,
        uploadHeaders: [String: String],
        scopeID: String,
        calendarTimeZone: String,
        frozenOutputSettings: Data,
        refreshRecentDays: Int,
        installationKey: Data
    ) throws -> Self? {
        guard policy == .missingDays else { return nil }
        guard let upload = endpoint(uploadURL), let preflight = endpoint(preflightURL),
              upload.host == preflight.host, upload.port == preflight.port,
              identifier(scopeID), let zone = TimeZone(identifier: calendarTimeZone),
              TimeZone.knownTimeZoneIdentifiers.contains(calendarTimeZone) || calendarTimeZone == "UTC",
              (0...30).contains(refreshRecentDays), installationKey.count == 32,
              !frozenOutputSettings.isEmpty else { throw BoundaryError.invalidConfiguration }
        var credentials: [String: String] = [:]
        for (name, value) in uploadHeaders {
            let lower = name.lowercased()
            guard !name.isEmpty, name.utf8.allSatisfy({ headerToken.contains($0) }),
                  !reservedHeaders.contains(lower), credentials[lower] == nil,
                  value.utf8.allSatisfy({ $0 >= 32 && $0 <= 126 }) else {
                throw BoundaryError.invalidConfiguration
            }
            credentials[lower] = value
        }
        guard credentials.count <= 64,
              credentials.reduce(0, { $0 + $1.key.utf8.count + $1.value.utf8.count }) <= 16_384 else {
            throw BoundaryError.invalidConfiguration
        }
        // Length-prefixed UTF-8/binary fields are identical on Apple and Android. Bind the full
        // frozen settings bytes; do not substitute mutable settings or an unkeyed credential hash.
        var fields = [Data("receiver-coverage-destination-v1".utf8), Data("compatibility_api".utf8),
                      Data(upload.url.absoluteString.utf8), Data(preflight.url.absoluteString.utf8),
                      Data(scopeID.utf8), Data(calendarTimeZone.utf8), frozenOutputSettings]
        fields.append(Data(String(credentials.count).utf8))
        for name in credentials.keys.sorted() {
            fields.append(Data(name.utf8))
            fields.append(Data(credentials[name, default: ""].utf8))
        }
        let transcript = fields.reduce(into: Data()) { result, field in
            result.append(Data("\(field.count):".utf8))
            result.append(field)
        }
        let digest = HMAC<SHA256>.authenticationCode(for: transcript, using: SymmetricKey(data: installationKey))
        var headers = credentials
        headers["accept"] = "application/json"
        headers["content-type"] = "application/json"
        return Self(uploadURL: upload.url, preflightURL: preflight.url, headers: headers,
                    destinationBinding: digest.map { String(format: "%02x", $0) }.joined(),
                    scopeID: scopeID, calendarTimeZone: zone, calendarTimeZoneIdentifier: calendarTimeZone, refreshRecentDays: refreshRecentDays)
    }

    func requireOriginalDestination(_ binding: String) throws {
        guard binding == destinationBinding else { throw BoundaryError.destinationChanged }
    }

    /// The execution clock supplies today's owner date, independently of the intended fire date.
    /// Persist these exact bytes/context with the operation ID before starting preflight.
    func requestBody(requestID: String, candidates: [String], now: Date) throws -> Data {
        var ownerCalendar = Calendar(identifier: .gregorian)
        ownerCalendar.timeZone = calendarTimeZone
        let owner = ownerCalendar.dateComponents([.year, .month, .day], from: now)
        guard let ownerYear = owner.year, let ownerMonth = owner.month, let ownerDay = owner.day else {
            throw BoundaryError.invalidOccurrence
        }
        let today = String(format: "%04d-%02d-%02d", ownerYear, ownerMonth, ownerDay)
        // Validate civil labels in UTC so a timezone's skipped/repeated midnight cannot change
        // the request interval or make a valid Gregorian owner date disappear on one platform.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard Self.identifier(requestID), (1...30).contains(candidates.count),
              candidates == Array(Set(candidates)).sorted() else { throw BoundaryError.invalidOccurrence }
        let dates = try candidates.map { value -> Date in
            guard value.utf8.count == 10, value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
                throw BoundaryError.invalidOccurrence
            }
            let parts = value.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, parts[0] >= 1,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  calendar.component(.year, from: date) == parts[0], calendar.component(.month, from: date) == parts[1],
                  calendar.component(.day, from: date) == parts[2], value < today else {
                throw BoundaryError.invalidOccurrence
            }
            return date
        }
        guard let first = dates.first, let last = dates.last,
              let span = calendar.dateComponents([.day], from: first, to: last).day, span < 30,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { throw BoundaryError.invalidOccurrence }
        let components = calendar.dateComponents([.year, .month, .day], from: end)
        guard let year = components.year, year <= 9999, let month = components.month, let day = components.day else {
            throw BoundaryError.invalidOccurrence
        }
        let body: [String: Any] = ["schema": "healthmd.receiver_coverage.request", "schema_version": 1,
            "request_id": requestID, "scope_id": scopeID, "calendar_timezone": calendarTimeZoneIdentifier,
            "start": candidates[0], "end_exclusive": String(format: "%04d-%02d-%02d", year, month, day)]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func identifier(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
        }
    }

    private static let headerToken = Set("!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
    private static let reservedHeaders: Set<String> = ["accept", "content-type", "content-length", "content-encoding",
        "transfer-encoding", "host", "connection", "trailer", "te", "upgrade", "expect", "proxy-authorization", "proxy-connection"]

    private static let pathToken = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/".utf8)

    private static func validHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.utf8.count <= 253, !labels.isEmpty,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") &&
                  label.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 })
              }) else { return false }
        if labels.last?.utf8.allSatisfy({ (48...57).contains($0) }) == true {
            return labels.count == 4 && labels.allSatisfy { label in
                guard label.count == 1 || !label.hasPrefix("0"), let number = Int(label) else { return false }
                return (0...255).contains(number)
            }
        }
        return true
    }

    private static func endpoint(_ text: String) -> (url: URL, host: String, port: Int)? {
        // A deliberately conservative shared URL subset avoids Foundation/OkHttp disagreement.
        // No inferred routes, query credentials, IDNA reinterpretation, or dot-segment rewriting.
        guard text.utf8.allSatisfy({ $0 > 32 && $0 < 127 }), !text.contains("\\"), !text.contains("%"),
              var parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let host = parts.host?.lowercased(), !host.isEmpty,
              validHost(host), parts.path.utf8.allSatisfy({ pathToken.contains($0) }),
              !parts.percentEncodedPath.contains("%"),
              !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              (1...65535).contains(parts.port ?? 443) else { return nil }
        parts.scheme = "https"
        parts.host = host
        let port = parts.port ?? 443
        if port == 443 { parts.port = nil }
        if parts.path.isEmpty { parts.path = "/" }
        guard let url = parts.url else { return nil }
        return (url, host, port)
    }
}

/// Streaming transport seam: reject metadata before reading and enforce the decompressed cap
/// before retaining each chunk. A rejection poisons the buffer; partial bodies are never evidence.
/// The future transport must cancel its exact call on cancellation/deadline/redirect; no retries.
struct ReceiverCoverageResponseBuffer {
    private var body = Data()
    private var rejected = false

    init(statusCode: Int, contentType: String?) throws {
        guard statusCode == 200, contentType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else {
            throw ReceiverCoveragePreflight.BoundaryError.invalidResponse
        }
    }

    mutating func append(_ chunk: Data) throws {
        guard !rejected, chunk.count <= ReceiverCoveragePreflight.maximumResponseBytes - body.count else {
            rejected = true
            body.removeAll()
            throw ReceiverCoveragePreflight.BoundaryError.invalidResponse
        }
        body.append(chunk)
    }

    /// Bounded bytes still require the strict v1 parser. This is never validated coverage.
    func finish() throws -> Data {
        guard !rejected else { throw ReceiverCoveragePreflight.BoundaryError.invalidResponse }
        return body
    }
}
