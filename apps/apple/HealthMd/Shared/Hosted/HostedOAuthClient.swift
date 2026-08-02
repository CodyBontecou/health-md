import CryptoKit
import Foundation
import Security

nonisolated enum HostedOAuthError: LocalizedError, Equatable {
  case notConfigured
  case invalidMetadata
  case authorizationRejected
  case invalidGrant
  case invalidCallback
  case invalidToken
  case insufficientScope
  case responseTooLarge

  var errorDescription: String? {
    switch self {
    case .notConfigured:
      return "Hosted Health.md account access is not configured for this build."
    case .invalidMetadata:
      return "The hosted authorization service returned invalid metadata."
    case .authorizationRejected:
      return "The hosted authorization service rejected the request."
    case .invalidGrant:
      return "Hosted Health.md account authorization must be renewed."
    case .invalidCallback:
      return "Health.md could not verify the authorization response."
    case .invalidToken:
      return "The hosted authorization service returned an invalid credential."
    case .insufficientScope:
      return "The account grant does not include hosted synchronization access."
    case .responseTooLarge:
      return "The hosted authorization response exceeded its safety limit."
    }
  }
}

nonisolated struct HostedOAuthEndpoints: Equatable, Sendable {
  let issuer: URL
  let authorizationEndpoint: URL
  let tokenEndpoint: URL
}

nonisolated struct HostedOAuthAuthorization: Equatable, Sendable {
  let url: URL
  let state: String
  let codeVerifier: String
  let endpoints: HostedOAuthEndpoints
  let resourceURL: URL
  let clientID: String
}

nonisolated struct HostedOAuthClient: Sendable {
  private nonisolated static let maximumResponseBytes = 64 * 1_024
  private let loader: BoundedURLSessionDataLoader

  init(session: URLSession? = nil) {
    if let session {
      loader = BoundedURLSessionDataLoader(session: session)
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 30
      configuration.timeoutIntervalForResource = 60
      configuration.httpCookieStorage = nil
      configuration.urlCache = nil
      loader = BoundedURLSessionDataLoader(
        configuration: configuration,
        redirectHandler: { _, _ in nil }
      )
    }
  }

  func beginAuthorization(
    configuration: HostedAccountConfiguration,
    state suppliedState: String? = nil,
    codeVerifier suppliedCodeVerifier: String? = nil
  ) async throws -> HostedOAuthAuthorization {
    let state = try suppliedState ?? Self.randomURLSafe(byteCount: 32)
    let codeVerifier = try suppliedCodeVerifier ?? Self.randomURLSafe(byteCount: 48)
    guard configuration.isValid else { throw HostedOAuthError.notConfigured }
    guard Self.isValidState(state),
      Self.isValidCodeVerifier(codeVerifier)
    else {
      throw HostedOAuthError.invalidCallback
    }
    let metadata = try await protectedResourceMetadata(configuration: configuration)
    guard let issuer = metadata.authorizationServers.first else {
      throw HostedOAuthError.invalidMetadata
    }
    let authorizationMetadata = try await authorizationServerMetadata(issuer: issuer)
    guard authorizationMetadata.codeChallengeMethodsSupported?.contains("S256") == true else {
      throw HostedOAuthError.invalidMetadata
    }
    let endpoints = HostedOAuthEndpoints(
      issuer: authorizationMetadata.issuer,
      authorizationEndpoint: authorizationMetadata.authorizationEndpoint,
      tokenEndpoint: authorizationMetadata.tokenEndpoint
    )
    guard
      var components = URLComponents(
        url: endpoints.authorizationEndpoint,
        resolvingAgainstBaseURL: false
      )
    else { throw HostedOAuthError.invalidMetadata }
    components.queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: configuration.clientID),
      URLQueryItem(name: "redirect_uri", value: HostedAccountConfiguration.redirectURI),
      URLQueryItem(
        name: "scope",
        value: HostedAccountConfiguration.requiredScopes.sorted().joined(separator: " ")),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "code_challenge", value: Self.codeChallenge(codeVerifier)),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "resource", value: configuration.resourceURL.absoluteString),
    ]
    guard let url = components.url, url.absoluteString.utf8.count <= 8 * 1_024 else {
      throw HostedOAuthError.invalidMetadata
    }
    return HostedOAuthAuthorization(
      url: url,
      state: state,
      codeVerifier: codeVerifier,
      endpoints: endpoints,
      resourceURL: configuration.resourceURL,
      clientID: configuration.clientID
    )
  }

  func exchange(
    code: String,
    authorization: HostedOAuthAuthorization,
    configuration: HostedAccountConfiguration
  ) async throws -> HostedOAuthToken {
    guard authorization.resourceURL == configuration.resourceURL,
      authorization.clientID == configuration.clientID,
      !code.isEmpty,
      code.utf8.count <= 8 * 1_024
    else {
      throw HostedOAuthError.invalidCallback
    }
    return try await tokenRequest(
      endpoint: authorization.endpoints.tokenEndpoint,
      configuration: configuration,
      parameters: [
        URLQueryItem(name: "grant_type", value: "authorization_code"),
        URLQueryItem(name: "code", value: code),
        URLQueryItem(name: "redirect_uri", value: HostedAccountConfiguration.redirectURI),
        URLQueryItem(name: "code_verifier", value: authorization.codeVerifier),
      ],
      previousRefreshToken: nil,
      ownerBinding: nil,
      issuer: authorization.endpoints.issuer
    )
  }

  func refresh(
    _ token: HostedOAuthToken,
    endpoints: HostedOAuthEndpoints,
    configuration: HostedAccountConfiguration
  ) async throws -> HostedOAuthToken {
    guard token.canUse(configuration: configuration),
      token.issuer == endpoints.issuer,
      let refreshToken = token.refreshToken,
      !refreshToken.isEmpty
    else {
      throw HostedOAuthError.invalidToken
    }
    return try await tokenRequest(
      endpoint: endpoints.tokenEndpoint,
      configuration: configuration,
      parameters: [
        URLQueryItem(name: "grant_type", value: "refresh_token"),
        URLQueryItem(name: "refresh_token", value: refreshToken),
      ],
      previousRefreshToken: refreshToken,
      ownerBinding: token.ownerBinding,
      issuer: endpoints.issuer
    )
  }

  func discoverEndpoints(
    configuration: HostedAccountConfiguration
  ) async throws -> HostedOAuthEndpoints {
    let metadata = try await protectedResourceMetadata(configuration: configuration)
    guard let issuer = metadata.authorizationServers.first else {
      throw HostedOAuthError.invalidMetadata
    }
    let authorizationMetadata = try await authorizationServerMetadata(issuer: issuer)
    return HostedOAuthEndpoints(
      issuer: authorizationMetadata.issuer,
      authorizationEndpoint: authorizationMetadata.authorizationEndpoint,
      tokenEndpoint: authorizationMetadata.tokenEndpoint
    )
  }

  private func protectedResourceMetadata(
    configuration: HostedAccountConfiguration
  ) async throws -> HostedProtectedResourceMetadata {
    guard
      var components = URLComponents(
        url: configuration.resourceURL,
        resolvingAgainstBaseURL: false
      ), components.scheme?.lowercased() == "https", components.host != nil
    else {
      throw HostedOAuthError.notConfigured
    }
    let resourcePath = components.path == "/" ? "" : components.path
    components.path = "/.well-known/oauth-protected-resource\(resourcePath)"
    components.query = nil
    components.fragment = nil
    guard let url = components.url else { throw HostedOAuthError.invalidMetadata }
    let metadata: HostedProtectedResourceMetadata = try await getJSON(url)
    guard metadata.resource == configuration.resourceURL,
      (1...4).contains(metadata.authorizationServers.count),
      HostedAccountConfiguration.requiredScopes.isSubset(
        of: Set(metadata.scopesSupported)
      ),
      metadata.authorizationServers.allSatisfy(Self.isSecureURL)
    else {
      throw HostedOAuthError.invalidMetadata
    }
    return metadata
  }

  private func authorizationServerMetadata(
    issuer: URL
  ) async throws -> HostedAuthorizationServerMetadata {
    guard Self.isSecureURL(issuer),
      issuer.query == nil,
      issuer.fragment == nil,
      var components = URLComponents(url: issuer, resolvingAgainstBaseURL: false)
    else {
      throw HostedOAuthError.invalidMetadata
    }
    let issuerPath = components.path == "/" ? "" : components.path
    components.path = "/.well-known/oauth-authorization-server\(issuerPath)"
    components.query = nil
    components.fragment = nil
    guard let url = components.url else { throw HostedOAuthError.invalidMetadata }
    let metadata: HostedAuthorizationServerMetadata = try await getJSON(url)
    guard metadata.issuer == issuer,
      Self.isSecureURL(metadata.authorizationEndpoint),
      Self.isSecureURL(metadata.tokenEndpoint),
      Self.sameOrigin(metadata.authorizationEndpoint, issuer),
      Self.sameOrigin(metadata.tokenEndpoint, issuer)
    else {
      throw HostedOAuthError.invalidMetadata
    }
    return metadata
  }

  private func getJSON<Response: Decodable>(_ url: URL) async throws -> Response {
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await load(request)
    guard response.statusCode == 200,
      Self.isJSON(response)
    else { throw HostedOAuthError.invalidMetadata }
    do {
      return try JSONDecoder().decode(Response.self, from: data)
    } catch {
      throw HostedOAuthError.invalidMetadata
    }
  }

  private func tokenRequest(
    endpoint: URL,
    configuration: HostedAccountConfiguration,
    parameters: [URLQueryItem],
    previousRefreshToken: String?,
    ownerBinding: String?,
    issuer: URL
  ) async throws -> HostedOAuthToken {
    var form = URLComponents()
    form.queryItems =
      parameters + [
        URLQueryItem(name: "client_id", value: configuration.clientID),
        URLQueryItem(
          name: "scope",
          value: HostedAccountConfiguration.requiredScopes.sorted().joined(separator: " ")),
        URLQueryItem(name: "resource", value: configuration.resourceURL.absoluteString),
      ]
    guard let body = form.percentEncodedQuery?.data(using: .utf8), body.count <= 96 * 1_024 else {
      throw HostedOAuthError.invalidToken
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = body
    let (data, response) = try await load(request)
    guard response.statusCode == 200 else {
      if response.statusCode == 400,
        Self.isJSON(response),
        Self.hasNoStore(response),
        let error = try? JSONDecoder().decode(TokenErrorResponse.self, from: data),
        error.error == "invalid_grant"
      {
        throw HostedOAuthError.invalidGrant
      }
      throw HostedOAuthError.authorizationRejected
    }
    guard Self.isJSON(response) else { throw HostedOAuthError.invalidToken }
    guard Self.hasNoStore(response) else {
      throw HostedOAuthError.invalidToken
    }
    let wire: TokenResponse
    do {
      wire = try JSONDecoder().decode(TokenResponse.self, from: data)
    } catch {
      throw HostedOAuthError.invalidToken
    }
    let scopes =
      wire.scope.map { Set($0.split(separator: " ").map(String.init)) }
      ?? HostedAccountConfiguration.requiredScopes
    if let expiresIn = wire.expiresIn, !expiresIn.isFinite || expiresIn <= 0 {
      throw HostedOAuthError.invalidToken
    }
    let token = HostedOAuthToken(
      accessToken: wire.accessToken,
      refreshToken: wire.refreshToken ?? previousRefreshToken,
      tokenType: wire.tokenType,
      scopes: scopes,
      expiresAt: wire.expiresIn.map { Date().addingTimeInterval($0) },
      resourceURL: configuration.resourceURL,
      clientID: configuration.clientID,
      issuer: issuer,
      ownerBinding: ownerBinding
    )
    guard token.isValid else { throw HostedOAuthError.invalidToken }
    guard scopes == HostedAccountConfiguration.requiredScopes else {
      throw HostedOAuthError.insufficientScope
    }
    return token
  }

  private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    do {
      let (data, response) = try await loader.data(
        for: request,
        maximumBytes: Self.maximumResponseBytes
      )
      guard let response = response as? HTTPURLResponse,
        response.url == request.url
      else { throw HostedOAuthError.invalidMetadata }
      return (data, response)
    } catch is BoundedURLSessionDataLoaderError {
      throw HostedOAuthError.responseTooLarge
    }
  }

  private static func hasNoStore(_ response: HTTPURLResponse) -> Bool {
    response.value(forHTTPHeaderField: "Cache-Control")?
      .lowercased().split(separator: ",")
      .map({ $0.trimmingCharacters(in: .whitespaces) })
      .contains("no-store") == true
  }

  private static func isJSON(_ response: HTTPURLResponse) -> Bool {
    response.value(forHTTPHeaderField: "Content-Type")?
      .lowercased().split(separator: ";", maxSplits: 1).first?
      .trimmingCharacters(in: .whitespaces) == "application/json"
  }

  private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
    lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
      && lhs.host?.lowercased() == rhs.host?.lowercased()
      && lhs.port == rhs.port
  }

  private static func isSecureURL(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https"
      && url.host?.isEmpty == false
      && url.user == nil
      && url.password == nil
      && url.fragment == nil
  }

  private static func isValidState(_ value: String) -> Bool {
    (32...256).contains(value.utf8.count) && value.utf8.allSatisfy(isUnreserved)
  }

  private static func isValidCodeVerifier(_ value: String) -> Bool {
    (43...128).contains(value.utf8.count) && value.utf8.allSatisfy(isUnreserved)
  }

  private static func isUnreserved(_ byte: UInt8) -> Bool {
    (byte >= 65 && byte <= 90)
      || (byte >= 97 && byte <= 122)
      || (byte >= 48 && byte <= 57)
      || [45, 46, 95, 126].contains(byte)
  }

  static func codeChallenge(_ verifier: String) -> String {
    Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
  }

  static func randomURLSafe(byteCount: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw HostedOAuthError.invalidCallback
    }
    return Data(bytes).base64URLEncodedString()
  }

  private struct TokenErrorResponse: Decodable {
    let error: String
  }

  private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: TimeInterval?
    let scope: String?

    enum CodingKeys: String, CodingKey {
      case accessToken = "access_token"
      case refreshToken = "refresh_token"
      case tokenType = "token_type"
      case expiresIn = "expires_in"
      case scope
    }
  }
}

extension Data {
  fileprivate nonisolated func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
