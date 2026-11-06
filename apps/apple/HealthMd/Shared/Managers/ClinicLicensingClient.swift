import Foundation

/// A reviewed trust configuration, never populated from an invitation or a remote key set.
struct ClinicLicensingConfiguration {
    let baseURL: URL
    let issuer: String
    let audience: String
    let trustedKeys: [String: Data]

    init(baseURL: URL, issuer: String, audience: String, trustedKeys: [String: Data]) throws {
        guard ClinicExportAuthorization.canonicalClinicEndpoint(baseURL.absoluteString) == baseURL.absoluteString,
              baseURL.path.isEmpty || baseURL.path == "/", baseURL.absoluteString.hasSuffix("/"),
              !issuer.isEmpty, !audience.isEmpty, !trustedKeys.isEmpty
        else { throw ClinicSponsorshipError.invalidGrant }
        self.baseURL = baseURL; self.issuer = issuer; self.audience = audience; self.trustedKeys = trustedKeys
    }

    var verifier: ClinicGrantVerifier {
        ClinicGrantVerifier(issuer: issuer, audience: audience, trustedKeys: trustedKeys)
    }
}

struct ClinicLicensingReply: Decodable {
    let grant: String
    let clinicName: String
    let sponsorshipID: String
    let refreshToken: String?
}

enum ClinicLicensingError: Error {
    case inactive
    case unavailable
}

private final class ClinicLicensingNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
protocol ClinicLicensingServing {
    func redeem(code: String, installationID: String, enrollmentSecret: String) async throws -> ClinicLicensingReply
    func refresh(token: String, installationID: String) async throws -> ClinicLicensingReply
    func disconnect(token: String, installationID: String) async throws
}

@MainActor
final class ClinicLicensingClient: ClinicLicensingServing {
    private let configuration: ClinicLicensingConfiguration
    private let session: URLSession

    init(configuration: ClinicLicensingConfiguration) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil; settings.urlCredentialStorage = nil; settings.urlCache = nil
        settings.timeoutIntervalForRequest = 15; settings.timeoutIntervalForResource = 15
        session = URLSession(configuration: settings, delegate: ClinicLicensingNoRedirects(), delegateQueue: nil)
    }

    func redeem(code: String, installationID: String, enrollmentSecret: String) async throws -> ClinicLicensingReply {
        try await reply("v2/invitations/redeem", ["invitationCode": code, "installationID": installationID, "enrollmentSecret": enrollmentSecret])
    }

    func refresh(token: String, installationID: String) async throws -> ClinicLicensingReply {
        try await reply("v1/sponsorship/refresh", ["refreshToken": token, "installationID": installationID])
    }

    func disconnect(token: String, installationID: String) async throws {
        _ = try await post("v1/sponsorship/disconnect", ["refreshToken": token, "installationID": installationID])
    }

    private func reply(_ path: String, _ body: [String: String]) async throws -> ClinicLicensingReply {
        try JSONDecoder().decode(ClinicLicensingReply.self, from: await post(path, body))
    }

    static func isDefinitiveDenial(statusCode: Int, data: Data) -> Bool {
        guard let body = try? JSONDecoder().decode([String: String].self, from: data), body.count == 1,
              let code = body["error"] else { return false }
        return (statusCode == 401 && code == "unauthorized") ||
            (statusCode == 403 && ["invitation_unavailable", "sponsorship_inactive"].contains(code))
    }

    private func post(_ path: String, _ body: [String: String]) async throws -> Data {
        let url = configuration.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClinicLicensingError.unavailable }
        guard http.url == url else { throw ClinicLicensingError.unavailable }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 16_384 else { throw ClinicLicensingError.unavailable }
            data.append(byte)
        }
        if Self.isDefinitiveDenial(statusCode: http.statusCode, data: data) { throw ClinicLicensingError.inactive }
        guard (200..<300).contains(http.statusCode) else { throw ClinicLicensingError.unavailable }
        return data
    }
}
