import Foundation
import Security

/// One secure record, kept outside portable settings, profiles, backup exports and diagnostics.
struct ClinicSponsorshipRecord: Codable, Equatable {
    let installationID: String
    var grantToken: String?
    var refreshToken: String?
    var clinicName: String?
    var consentBinding: String?
    var pendingEnrollment: ClinicPendingEnrollment?
    var uploadAuthorization: String?
    var highestObservedMilliseconds: Int64 = 0
}

struct ClinicPendingEnrollment: Codable, Equatable {
    let invitationCode: String
    let enrollmentSecret: String
}

enum ClinicSponsorshipError: Error {
    case invalidGrant
    case inactive
    case invalidCredential
}

/// Serialized by its native owner. Storage failures never become a fresh identity or new access.
@MainActor
final class ClinicSponsorshipSession {
    private let read: () throws -> String?
    private let write: (String) throws -> Void
    private let verifier: ClinicGrantVerifier
    private let clock: () -> Int64
    private var record: ClinicSponsorshipRecord

    init(verifier: ClinicGrantVerifier, read: @escaping () throws -> String?,
         write: @escaping (String) throws -> Void,
         clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }) throws {
        self.read = read; self.write = write; self.verifier = verifier; self.clock = clock
        if let existing = try read() {
            record = try JSONDecoder().decode(ClinicSponsorshipRecord.self, from: Data(existing.utf8))
        } else {
            record = ClinicSponsorshipRecord(installationID: UUID().uuidString)
            try write(String(decoding: JSONEncoder().encode(record), as: UTF8.self))
        }
    }

    var installationID: String { record.installationID }
    var refreshToken: String? { record.refreshToken }
    var clinicName: String? { record.clinicName }
    var pendingEnrollment: ClinicPendingEnrollment? { record.pendingEnrollment }

    func beginEnrollment(code: String) throws -> ClinicPendingEnrollment {
        guard code.range(of: #"^[A-Za-z0-9_-]{32,128}$"#, options: .regularExpression) != nil else {
            throw ClinicSponsorshipError.invalidCredential
        }
        if let pending = record.pendingEnrollment {
            guard pending.invitationCode == code else { throw ClinicSponsorshipError.invalidCredential }
            return pending
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ClinicSponsorshipError.invalidCredential
        }
        let secret = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let pending = ClinicPendingEnrollment(invitationCode: code, enrollmentSecret: secret)
        var updated = record; updated.pendingEnrollment = pending
        try replace(updated) // Must succeed before the manager starts any network request.
        return pending
    }

    func cancelEnrollment(secret: String) throws {
        guard record.pendingEnrollment?.enrollmentSecret == secret else { return }
        var updated = record; updated.pendingEnrollment = nil
        try replace(updated)
    }

    private func replace(_ value: ClinicSponsorshipRecord) throws {
        try write(String(decoding: JSONEncoder().encode(value), as: UTF8.self))
        record = value
    }

    private func now() throws -> Int64 {
        let current = max(clock(), record.highestObservedMilliseconds)
        guard current >= 0 else { throw ClinicSponsorshipError.invalidGrant }
        if current > record.highestObservedMilliseconds {
            var updated = record; updated.highestObservedMilliseconds = current
            try replace(updated)
        }
        return current
    }

    func grant() throws -> ClinicExportGrant? {
        guard let token = record.grantToken else { return nil }
        return verifier.verify(token, installationID: installationID, nowMilliseconds: try now())
    }

    func accept(grantToken: String, refreshToken: String?, clinicName: String, completingEnrollmentSecret: String? = nil) throws {
        if let secret = completingEnrollmentSecret, record.pendingEnrollment?.enrollmentSecret != secret {
            throw ClinicSponsorshipError.invalidCredential
        }
        guard !clinicName.isEmpty, clinicName.count <= 120,
              !clinicName.unicodeScalars.contains(where: { $0.value < 32 }),
              let verified = verifier.verify(grantToken, installationID: installationID, nowMilliseconds: try now())
        else { throw ClinicSponsorshipError.invalidGrant }
        guard let credential = refreshToken ?? record.refreshToken,
              credential.range(of: #"^[A-Za-z0-9_-]{32,128}$"#, options: .regularExpression) != nil
        else { throw ClinicSponsorshipError.invalidCredential }
        let old = try grant()
        var updated = record
        updated.grantToken = grantToken; updated.refreshToken = credential; updated.clinicName = clinicName
        if completingEnrollmentSecret != nil { updated.pendingEnrollment = nil }
        if old.map(binding) != binding(verified) {
            updated.consentBinding = nil
            updated.uploadAuthorization = nil
        }
        try replace(updated)
    }

    func setSharingAuthorized(_ authorized: Bool) throws {
        var updated = record
        if authorized {
            guard let grant = try grant() else { throw ClinicSponsorshipError.inactive }
            updated.consentBinding = binding(grant)
        } else { updated.consentBinding = nil }
        try replace(updated)
    }

    func authorize(endpoint: String) throws -> ClinicExportDecision {
        let grant = try grant()
        return ClinicExportAuthorization.decide(independentAccess: false, grant: grant,
            request: ClinicExportRequest(isDirectClinicDelivery: true, clinicID: grant?.clinicID,
                destinationID: grant?.destinationID, policyVersion: grant?.policyVersion, endpoint: endpoint,
                sharingAuthorized: grant.map { record.consentBinding == binding($0) } ?? false),
            nowMilliseconds: try now())
    }

    func setUploadAuthorization(_ value: String) throws {
        guard try grant() != nil, value.utf8.count <= 4_096,
              value.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { throw ClinicSponsorshipError.invalidCredential }
        var updated = record
        updated.uploadAuthorization = value.isEmpty ? nil : value
        try replace(updated)
    }

    func uploadAuthorization(endpoint: String) throws -> String? {
        guard try authorize(endpoint: endpoint) == .allowedClinicDestination else { return nil }
        return record.uploadAuthorization
    }

    func disconnect() throws {
        try replace(ClinicSponsorshipRecord(installationID: installationID,
            highestObservedMilliseconds: record.highestObservedMilliseconds))
    }

    private func binding(_ grant: ClinicExportGrant) -> String {
        [grant.clinicID, grant.destinationID, String(grant.policyVersion),
         ClinicExportAuthorization.canonicalClinicEndpoint(grant.endpoint) ?? ""]
            .map { "\($0.utf8.count):\($0)" }.joined()
    }
}
