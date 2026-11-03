import CryptoKit
import Foundation

/// Trust roots come from the app's reviewed configuration, never the invitation or token.
struct ClinicGrantVerifier {
    let issuer: String
    let audience: String
    let trustedKeys: [String: Data]

    private struct Claims: Decodable {
        let issuer: String
        let audience: String
        let installationID: String
        let sponsorshipID: String
        let clinicID: String
        let destinationID: String
        let policyVersion: Int
        let endpoint: String
        let issuedAtMilliseconds: Int64
        let expiresAtMilliseconds: Int64
    }

    /// Versioned compact envelope: v1.keyID.base64url(JSON).base64url(P256 raw signature).
    /// The signature covers the first three components exactly. No key discovery from token input.
    func verify(_ token: String, installationID: String, nowMilliseconds: Int64) -> ClinicExportGrant? {
        guard !installationID.isEmpty, token.utf8.count <= 8_192 else { return nil }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "v1",
              let keyData = trustedKeys[parts[1]],
              let payload = Self.decode(parts[2]), let signatureData = Self.decode(parts[3]),
              signatureData.count == 64,
              let key = try? P256.Signing.PublicKey(derRepresentation: keyData),
              let signature = try? P256.Signing.ECDSASignature(rawRepresentation: signatureData),
              key.isValidSignature(signature, for: Data(parts.prefix(3).joined(separator: ".").utf8)),
              let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              Set(object.keys) == Set(["issuer", "audience", "installationID", "sponsorshipID", "clinicID",
                "destinationID", "policyVersion", "endpoint", "issuedAtMilliseconds", "expiresAtMilliseconds"]),
              let claims = try? JSONDecoder().decode(Claims.self, from: payload),
              claims.issuer == issuer, claims.audience == audience,
              claims.installationID == installationID, !claims.sponsorshipID.isEmpty
        else { return nil }
        let grant = ClinicExportGrant(clinicID: claims.clinicID, destinationID: claims.destinationID,
            policyVersion: claims.policyVersion, endpoint: claims.endpoint,
            issuedAtMilliseconds: claims.issuedAtMilliseconds,
            expiresAtMilliseconds: claims.expiresAtMilliseconds, revoked: false)
        let probe = ClinicExportRequest(isDirectClinicDelivery: true, clinicID: grant.clinicID,
            destinationID: grant.destinationID, policyVersion: grant.policyVersion,
            endpoint: grant.endpoint, sharingAuthorized: true)
        guard ClinicExportAuthorization.decide(independentAccess: false, grant: grant,
            request: probe, nowMilliseconds: nowMilliseconds) == .allowedClinicDestination else { return nil }
        return grant
    }

    private static func decode(_ value: String) -> Data? {
        guard !value.isEmpty, value.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }) else { return nil }
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)),
              data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value
        else { return nil }
        return data
    }
}
