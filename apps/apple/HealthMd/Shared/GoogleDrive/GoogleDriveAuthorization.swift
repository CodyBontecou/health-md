import AuthenticationServices
import CryptoKit
import Foundation
import Security
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

nonisolated protocol GoogleDriveHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct SystemGoogleDriveHTTPTransport: GoogleDriveHTTPTransport, Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GoogleDriveError(.ambiguousCommit, isRetryable: true)
            }
            return (data, response)
        } catch let error as GoogleDriveError {
            throw error
        } catch {
            // Offline/DNS/TLS/timeout failures are transient transport failures, never proof that
            // the refresh grant was revoked.
            throw GoogleDriveError(.ambiguousCommit, isRetryable: true)
        }
    }
}

nonisolated struct GoogleDrivePKCE: Equatable, Sendable {
    let verifier: String
    let challenge: String

    init(randomBytes: Data) {
        verifier = randomBytes.base64URLEncodedString()
        challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    static func make() -> GoogleDrivePKCE {
        var bytes = [UInt8](repeating: 0, count: 48)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Secure randomness is required for OAuth PKCE")
        return GoogleDrivePKCE(randomBytes: Data(bytes))
    }
}

nonisolated struct GoogleDriveAuthorizationRequest: Equatable, Sendable {
    let authorizationURL: URL
    let callbackScheme: String
    let state: String
    let pkce: GoogleDrivePKCE

    static func make(
        configuration: GoogleDriveConfiguration,
        state: String = UUID().uuidString.lowercased(),
        pkce: GoogleDrivePKCE = .make()
    ) throws -> GoogleDriveAuthorizationRequest {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleDriveConfiguration.driveFileScope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "include_granted_scopes", value: "false"),
            // Google's mobile Picker controls. Folder authority is accepted only when the
            // callback supplies an immutable folder ID and Drive metadata later validates it.
            URLQueryItem(name: "trigger_onepick", value: "true"),
            URLQueryItem(name: "allow_folder_selection", value: "true"),
            URLQueryItem(name: "mimetypes", value: GoogleDriveFileMetadata.folderMIMEType)
        ]
        guard let url = components.url, let scheme = configuration.redirectURI.scheme else {
            throw GoogleDriveError(.configurationMissing)
        }
        return GoogleDriveAuthorizationRequest(
            authorizationURL: url,
            callbackScheme: scheme,
            state: state,
            pkce: pkce
        )
    }
}

nonisolated struct GoogleDrivePickerSelection: Equatable, Sendable {
    let folderID: String
    let sharedDriveID: String?
    let resourceKey: String?
    let folderLabel: String?
}

nonisolated struct GoogleDriveAuthorizationCallback: Equatable, Sendable {
    let code: String
    let selection: GoogleDrivePickerSelection

    static func parse(url: URL, expectedState: String) throws -> GoogleDriveAuthorizationCallback {
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            throw GoogleDriveError(.reauthorizationRequired)
        }
        let values = Dictionary(query.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard values["error"].nilIfEmpty == nil,
              values["state"] == expectedState,
              let code = values["code"], !code.isEmpty else {
            throw GoogleDriveError(.reauthorizationRequired)
        }
        // Google's mobile Picker returns one comma-separated `picked_file_ids` value.
        // Legacy aliases remain parseable for already-issued test/development callbacks, but
        // multiple selections always fail closed because a destination has one folder authority.
        let rawFolderIDs = values["picked_file_ids"] ?? values["folder_id"] ?? values["id"]
        let folderIDs = rawFolderIDs?
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        guard folderIDs.count == 1, let folderID = folderIDs.first else {
            throw GoogleDriveError(.folderUnavailable)
        }
        return GoogleDriveAuthorizationCallback(
            code: code,
            selection: GoogleDrivePickerSelection(
                folderID: folderID,
                sharedDriveID: values["drive_id"].nilIfEmpty,
                resourceKey: values["resource_key"].nilIfEmpty,
                folderLabel: values["folder_name"].nilIfEmpty
            )
        )
    }
}

@MainActor
protocol GoogleDriveWebAuthorizing {
    func authorize(_ request: GoogleDriveAuthorizationRequest) async throws -> URL
}

@MainActor
final class ASWebGoogleDriveAuthorizer: NSObject, GoogleDriveWebAuthorizing, ASWebAuthenticationPresentationContextProviding {
    nonisolated deinit {}
    private var session: ASWebAuthenticationSession?

    func authorize(_ request: GoogleDriveAuthorizationRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: request.authorizationURL,
                callbackURLScheme: request.callbackScheme
            ) { [weak self] callbackURL, error in
                self?.session = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let authenticationError = error as? ASWebAuthenticationSessionError,
                          authenticationError.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: GoogleDriveError(.reauthorizationRequired))
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            guard session.start() else {
                self.session = nil
                continuation.resume(throwing: GoogleDriveError(.reauthorizationRequired))
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

nonisolated struct GoogleDriveTokenEndpoint: Sendable {
    private struct Response: Decodable {
        let accessToken: String
        let expiresIn: Double
        let refreshToken: String?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case scope
        }
    }

    let transport: any GoogleDriveHTTPTransport
    let now: @Sendable () -> Date

    init(
        transport: any GoogleDriveHTTPTransport = SystemGoogleDriveHTTPTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.now = now
    }

    func exchange(
        code: String,
        pkceVerifier: String,
        configuration: GoogleDriveConfiguration
    ) async throws -> GoogleDriveTokenCredential {
        let body = Self.formBody([
            "client_id": configuration.clientID,
            "code": code,
            "code_verifier": pkceVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": configuration.redirectURI.absoluteString
        ])
        let response: Response = try await requestToken(body: body)
        guard let refreshToken = response.refreshToken, !refreshToken.isEmpty else {
            throw GoogleDriveError(.reauthorizationRequired)
        }
        return try credential(from: response, refreshToken: refreshToken)
    }

    func refresh(
        refreshToken: String,
        configuration: GoogleDriveConfiguration
    ) async throws -> GoogleDriveTokenCredential {
        let body = Self.formBody([
            "client_id": configuration.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        do {
            let response: Response = try await requestToken(body: body)
            return try credential(from: response, refreshToken: refreshToken)
        } catch let error as GoogleDriveError where error.id == .permissionDenied {
            throw GoogleDriveError(.reauthorizationRequired)
        }
    }

    func revoke(token: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(["token": token])
        let (_, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) || response.statusCode == 400 else {
            throw GoogleDriveHTTPErrorMapper.error(statusCode: response.statusCode)
        }
    }

    private func requestToken(body: Data) async throws -> Response {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleDriveHTTPErrorMapper.error(statusCode: response.statusCode, responseData: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw GoogleDriveError(.reauthorizationRequired)
        }
    }

    private func credential(from response: Response, refreshToken: String) throws -> GoogleDriveTokenCredential {
        let scopes = response.scope?.split(separator: " ").map(String.init)
            ?? [GoogleDriveConfiguration.driveFileScope]
        let credential = GoogleDriveTokenCredential(
            accessToken: response.accessToken,
            refreshToken: refreshToken,
            expiresAt: now().addingTimeInterval(max(response.expiresIn - 60, 0)),
            grantedScopes: scopes
        )
        guard credential.isDriveFileOnly else { throw GoogleDriveError(.permissionDenied) }
        return credential
    }

    private static func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let string = values.keys.sorted().map { key in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = values[key]!.addingPercentEncoding(withAllowedCharacters: allowed) ?? values[key]!
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
        return Data(string.utf8)
    }
}

nonisolated enum GoogleDriveHTTPErrorMapper {
    static func error(statusCode: Int, responseData: Data? = nil) -> GoogleDriveError {
        let oauthError = responseData.flatMap { data -> String? in
            (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        }
        if oauthError == "invalid_grant" {
            return GoogleDriveError(.reauthorizationRequired)
        }
        let reason = responseData.flatMap { data -> String? in
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let error = root["error"] as? [String: Any],
                  let errors = error["errors"] as? [[String: Any]] else { return nil }
            return errors.compactMap { $0["reason"] as? String }.first
        }
        if let reason {
            if ["storageQuotaExceeded", "dailyLimitExceeded", "quotaExceeded"].contains(reason) {
                return GoogleDriveError(.quotaExceeded)
            }
            if ["rateLimitExceeded", "userRateLimitExceeded"].contains(reason) {
                return GoogleDriveError(.rateLimited, isRetryable: true)
            }
        }
        return switch statusCode {
        case 401: GoogleDriveError(.reauthorizationRequired)
        case 403: GoogleDriveError(.permissionDenied)
        case 404: GoogleDriveError(.folderUnavailable)
        case 409, 412: GoogleDriveError(.remoteConflict)
        case 429: GoogleDriveError(.rateLimited, isRetryable: true)
        case 500...599: GoogleDriveError(.ambiguousCommit, isRetryable: true)
        default: GoogleDriveError(.permissionDenied)
        }
    }
}

private nonisolated extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private nonisolated extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
