import Foundation

enum ExternalOAuthBrokerError: LocalizedError, Equatable {
    case notConfigured
    case invalidResponse
    case brokerRejected(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "The OAuth broker endpoint is not configured for this build."
        case .invalidResponse:
            return "The OAuth broker returned an invalid response."
        case .brokerRejected(let message):
            return message
        }
    }
}

struct ExternalOAuthAuthorizeURLResponse: Codable, Equatable {
    let authorizationURL: URL
    let provider: ExternalIntegrationProvider

    enum CodingKeys: String, CodingKey {
        case authorizationURL = "authorization_url"
        case provider
    }
}

struct ExternalOAuthTokenResponse: Codable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String?
    let expiresIn: TimeInterval?
    let scope: String?
    let providerUserID: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case providerUserID = "provider_user_id"
    }

    func integrationToken(receivedAt: Date = Date()) -> ExternalIntegrationToken {
        ExternalIntegrationToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: tokenType ?? "Bearer",
            scope: scope,
            expiresAt: expiresIn.map { receivedAt.addingTimeInterval($0) },
            providerUserID: providerUserID
        )
    }
}

struct ExternalOAuthBrokerClient {
    var baseURL: URL?
    var clientToken: String?
    var session: URLSession

    init(
        baseURL: URL? = ExternalOAuthBrokerClient.defaultBaseURL,
        clientToken: String? = ExternalOAuthBrokerClient.defaultClientToken,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.clientToken = clientToken
        self.session = session
    }

    var isConfigured: Bool { baseURL != nil }

    func authorizeURL(
        provider: ExternalIntegrationProvider,
        redirectURI: String,
        state: String,
        codeChallenge: String? = nil
    ) async throws -> ExternalOAuthAuthorizeURLResponse {
        var body: [String: Any] = [
            "provider": provider.rawValue,
            "redirect_uri": redirectURI,
            "state": state,
            "scope": provider.defaultScopes.joined(separator: " ")
        ]
        if let codeChallenge {
            body["code_challenge"] = codeChallenge
        }
        return try await post(path: "/v1/oauth/authorize-url", body: body)
    }

    func exchangeCode(
        provider: ExternalIntegrationProvider,
        code: String,
        redirectURI: String,
        codeVerifier: String? = nil
    ) async throws -> ExternalOAuthTokenResponse {
        var body: [String: Any] = [
            "provider": provider.rawValue,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI
        ]
        if let codeVerifier {
            body["code_verifier"] = codeVerifier
        }
        return try await post(path: "/v1/oauth/token", body: body)
    }

    func refresh(
        provider: ExternalIntegrationProvider,
        refreshToken: String
    ) async throws -> ExternalOAuthTokenResponse {
        try await post(
            path: "/v1/oauth/refresh",
            body: [
                "provider": provider.rawValue,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ]
        )
    }

    private func post<Response: Decodable>(path: String, body: [String: Any]) async throws -> Response {
        guard let baseURL else { throw ExternalOAuthBrokerError.notConfigured }
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw ExternalOAuthBrokerError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Health.md iOS External Integrations", forHTTPHeaderField: "User-Agent")
        if let clientToken, !clientToken.isEmpty {
            request.setValue("Bearer \(clientToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExternalOAuthBrokerError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = Self.errorMessage(from: data) ?? "OAuth broker returned HTTP \(httpResponse.statusCode)."
            throw ExternalOAuthBrokerError.brokerRejected(message)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ExternalOAuthBrokerError.invalidResponse
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? String { return error }
        return nil
    }

    static var defaultBaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "OAUTH_BROKER_ENDPOINT_URL") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return URL(string: trimmed)
    }

    static var defaultClientToken: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "OAUTH_BROKER_CLIENT_TOKEN") as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
