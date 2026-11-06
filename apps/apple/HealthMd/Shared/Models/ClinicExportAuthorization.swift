import Foundation

/// A verified licensing snapshot, never a decoded invitation or an editable export setting.
/// The licensing adapter must verify signature, audience and installation binding before creating it.
struct ClinicExportGrant: Equatable, Sendable {
    let clinicID: String
    let destinationID: String
    let policyVersion: Int
    let endpoint: String
    let issuedAtMilliseconds: Int64
    let expiresAtMilliseconds: Int64
    let revoked: Bool
}

struct ClinicExportRequest: Equatable, Sendable {
    /// True only for delivery performed by the phone, not a download, share sheet, CLI or Mac transfer.
    let isDirectClinicDelivery: Bool
    let clinicID: String?
    let destinationID: String?
    let policyVersion: Int?
    let endpoint: String?
    let sharingAuthorized: Bool
}

enum ClinicExportDecision: String, Codable, Sendable {
    case allowedPersonal = "allowed_personal"
    case allowedClinicDestination = "allowed_clinic_destination"
    case blockedAccessExpired = "blocked_access_expired"
    case blockedDestinationNotPermitted = "blocked_destination_not_permitted"
    case blockedSharingNotAuthorized = "blocked_sharing_not_authorized"

    var isAllowed: Bool { self == .allowedPersonal || self == .allowedClinicDestination }
}

/// Destination-aware licensing only. Health permission and credential scope are separate checks.
/// Independently acquired access never becomes dependent on a clinic subscription.
enum ClinicExportAuthorization {
    static let maximumGrantDurationMilliseconds: Int64 = 7 * 24 * 60 * 60 * 1_000

    static func decide(
        independentAccess: Bool,
        grant: ClinicExportGrant?,
        request: ClinicExportRequest,
        nowMilliseconds: Int64
    ) -> ClinicExportDecision {
        if independentAccess { return .allowedPersonal }
        guard let grant, !grant.revoked,
              nowMilliseconds >= 0,
              grant.issuedAtMilliseconds >= 0,
              grant.issuedAtMilliseconds <= nowMilliseconds,
              grant.expiresAtMilliseconds > nowMilliseconds,
              grant.expiresAtMilliseconds - grant.issuedAtMilliseconds <= maximumGrantDurationMilliseconds
        else { return .blockedAccessExpired }

        guard request.isDirectClinicDelivery,
              !grant.clinicID.isEmpty, !grant.destinationID.isEmpty, grant.policyVersion > 0,
              request.clinicID == grant.clinicID,
              request.destinationID == grant.destinationID,
              request.policyVersion == grant.policyVersion,
              let approved = canonicalClinicEndpoint(grant.endpoint),
              let requested = request.endpoint.flatMap(canonicalClinicEndpoint),
              approved == requested
        else { return .blockedDestinationNotPermitted }
        guard request.sharingAuthorized else { return .blockedSharingNotAuthorized }
        return .allowedClinicDestination
    }

    /// Intentionally narrow shared URL grammar: HTTPS, ASCII DNS host, exact unescaped path,
    /// no URL credentials, query, fragment, dot segments or alternate slash encodings.
    /// Upload clients must additionally reject redirects and scope credentials to this endpoint.
    static func canonicalClinicEndpoint(_ value: String) -> String? {
        let pattern = #"^https://([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?(/[A-Za-z0-9._~!$&'()*+,;=:@/-]*)?$"#
        guard value.utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }),
              let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let hostRange = Range(match.range(at: 1), in: value)
        else { return nil }
        let host = String(value[hostRange]).lowercased()
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253, labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && !$0.hasPrefix("-") && !$0.hasSuffix("-") }),
              !labels.allSatisfy({ $0.allSatisfy(\.isNumber) })
        else { return nil }
        let port = Range(match.range(at: 2), in: value).flatMap { Int(value[$0]) } ?? 443
        guard (1...65535).contains(port) else { return nil }
        let path = Range(match.range(at: 3), in: value).map { String(value[$0]) } ?? "/"
        guard !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !path.contains("//") else { return nil }
        return "https://\(host)\(port == 443 ? "" : ":\(port)")\(path)"
    }
}
