import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor
final class ExternalIntegrationManager: NSObject, ObservableObject, ExternalIntegrationDailyRecordProviding {
    static let redirectURI = "healthmd://oauth/callback"

    @Published private(set) var accounts: [ExternalIntegrationProvider: ExternalIntegrationAccount] = [:]
    @Published private(set) var isConnectingProvider: ExternalIntegrationProvider?
    @Published private(set) var isDisconnectingProvider: ExternalIntegrationProvider?
    @Published var statusMessage: String?

    private let tokenStore: ExternalIntegrationTokenStore
    private let enabledProviders: Set<ExternalIntegrationProvider>
    private let brokerClient: ExternalOAuthBrokerClient
    private let apiClient: ExternalProviderAPIClient
    private var authSession: ASWebAuthenticationSession?
    private var refreshTasks: [ExternalIntegrationProvider: Task<ExternalIntegrationToken, Error>] = [:]
    private var exportActionDepth = 0
    private var exportActionDidFail = false
    private var providersWithSuccessfulActionFetch: Set<ExternalIntegrationProvider> = []

    override convenience init() {
        self.init(
            tokenStore: ExternalIntegrationTokenStore(),
            enabledProviders: Set(ConnectedAppsFeature.enabledProviders),
            brokerClient: ExternalOAuthBrokerClient(),
            apiClient: ExternalProviderAPIClient()
        )
    }

    init(
        tokenStore: ExternalIntegrationTokenStore,
        enabledProviders: Set<ExternalIntegrationProvider>,
        brokerClient: ExternalOAuthBrokerClient,
        apiClient: ExternalProviderAPIClient
    ) {
        self.tokenStore = tokenStore
        self.enabledProviders = enabledProviders
        self.brokerClient = brokerClient
        self.apiClient = apiClient
        self.accounts = tokenStore.accounts.filter { enabledProviders.contains($0.key) }
        super.init()
    }

    var connectedProviderCount: Int { accounts.count }

    func beginExportAction() {
        if exportActionDepth == 0 {
            exportActionDidFail = false
            providersWithSuccessfulActionFetch.removeAll(keepingCapacity: true)
        }
        exportActionDepth += 1
    }

    func endExportAction(succeeded: Bool) {
        guard exportActionDepth > 0 else { return }
        if !succeeded { exportActionDidFail = true }
        exportActionDepth -= 1
        guard exportActionDepth == 0 else { return }

        if !exportActionDidFail {
            let exportedAt = Date()
            for provider in providersWithSuccessfulActionFetch.sorted(by: {
                $0.rawValue < $1.rawValue
            }) {
                tokenStore.markSuccessfulExport(provider: provider, at: exportedAt)
            }
            if !providersWithSuccessfulActionFetch.isEmpty { syncAccounts() }
        }
        exportActionDidFail = false
        providersWithSuccessfulActionFetch.removeAll(keepingCapacity: true)
    }

    func isConnected(_ provider: ExternalIntegrationProvider) -> Bool {
        accounts[provider] != nil
    }

    func connect(provider: ExternalIntegrationProvider) async {
        guard enabledProviders.contains(provider) else {
            statusMessage = "\(provider.displayName) is not enabled for this build."
            return
        }
        guard brokerClient.isConfigured else {
            statusMessage = ExternalOAuthBrokerError.notConfigured.localizedDescription
            return
        }
        guard isConnectingProvider == nil, isDisconnectingProvider == nil else { return }

        isConnectingProvider = provider
        statusMessage = "Connecting \(provider.displayName)…"
        defer { isConnectingProvider = nil }

        do {
            let state = Self.makeState(for: provider)
            let codeVerifier = provider.usesPKCE ? Self.makeCodeVerifier() : nil
            let codeChallenge = codeVerifier.map(Self.codeChallenge(for:))
            let authorize = try await brokerClient.authorizeURL(
                provider: provider,
                redirectURI: Self.redirectURI,
                state: state,
                codeChallenge: codeChallenge
            )

            let callbackURL = try await runAuthenticationSession(url: authorize.authorizationURL)
            let callback = try Self.parseCallback(callbackURL, expectedState: state)
            let tokenResponse = try await brokerClient.exchangeCode(
                provider: provider,
                code: callback.code,
                redirectURI: Self.redirectURI,
                codeVerifier: codeVerifier
            )
            let token = try validatedToken(from: tokenResponse, provider: provider, replacing: nil)
            do {
                try tokenStore.save(token: token, provider: provider)
            } catch {
                // Do not leave a grant active if local account setup could not
                // be completed and surfaced in Connected Apps.
                try? await apiClient.revokeAccess(provider: provider, token: token)
                throw error
            }
            syncAccounts()
            statusMessage = "Connected \(provider.displayName)"
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                statusMessage = "Cancelled \(provider.displayName) connection"
            } else {
                statusMessage = "\(provider.displayName) connection failed: \(error.localizedDescription)"
            }
        }
    }

    func disconnect(provider: ExternalIntegrationProvider) async {
        guard isDisconnectingProvider == nil, isConnectingProvider == nil else { return }
        isDisconnectingProvider = provider
        defer { isDisconnectingProvider = nil }

        guard var token = tokenStore.token(for: provider) else {
            do {
                try tokenStore.disconnect(provider: provider)
                syncAccounts()
                statusMessage = "Disconnected \(provider.displayName)"
            } catch {
                statusMessage = "Could not remove \(provider.displayName) credentials: \(error.localizedDescription)"
            }
            return
        }

        statusMessage = "Revoking \(provider.displayName) access…"
        do {
            if token.needsRefresh(), token.refreshToken != nil {
                token = try await refreshToken(for: provider, replacing: token)
            }
            do {
                try await apiClient.revokeAccess(provider: provider, token: token)
            } catch ExternalProviderAPIError.unauthorized where token.refreshToken != nil {
                token = try await refreshToken(for: provider, replacing: token)
                try await apiClient.revokeAccess(provider: provider, token: token)
            }
        } catch {
            statusMessage = "Could not revoke \(provider.displayName) access: \(error.localizedDescription) Try again before removing access in WHOOP."
            return
        }

        do {
            try tokenStore.disconnect(provider: provider)
            syncAccounts()
            statusMessage = "Disconnected \(provider.displayName) and revoked access"
        } catch {
            syncAccounts()
            statusMessage = "\(provider.displayName) access was revoked, but local Keychain cleanup failed: \(error.localizedDescription)"
        }
    }

    func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] {
        guard !enabledProviders.isEmpty else { return [] }
        var records: [ExternalDailyRecord] = []
        for provider in accounts.keys
            .filter({ enabledProviders.contains($0) && isDisconnectingProvider != $0 })
            .sorted(by: { $0.displayName < $1.displayName }) {
            guard var token = tokenStore.token(for: provider) else { continue }
            do {
                if token.needsRefresh(), token.refreshToken != nil {
                    token = try await refreshToken(for: provider, replacing: token)
                }
                guard shouldKeepFetchResult(for: provider) else { continue }

                do {
                    let record = try await apiClient.fetchDailyRecord(provider: provider, date: date, token: token)
                    guard shouldKeepFetchResult(for: provider) else { continue }
                    records.append(record)
                    markSuccessfulFetch(provider: provider)
                } catch ExternalProviderAPIError.unauthorized where token.refreshToken != nil {
                    token = try await refreshToken(for: provider, replacing: token)
                    guard shouldKeepFetchResult(for: provider) else { continue }
                    let record = try await apiClient.fetchDailyRecord(provider: provider, date: date, token: token)
                    guard shouldKeepFetchResult(for: provider) else { continue }
                    records.append(record)
                    markSuccessfulFetch(provider: provider)
                }
            } catch {
                let dateString = ExternalProviderAPIClient.dayString(date)
                records.append(ExternalDailyRecord(
                    provider: provider,
                    date: dateString,
                    payloads: [],
                    warnings: [error.localizedDescription]
                ))
            }
        }
        return records
    }

    // MARK: - OAuth Helpers

    private func syncAccounts() {
        accounts = tokenStore.accounts.filter { enabledProviders.contains($0.key) }
    }

    private func markSuccessfulFetch(provider: ExternalIntegrationProvider) {
        if exportActionDepth > 0 {
            providersWithSuccessfulActionFetch.insert(provider)
        } else {
            tokenStore.markSuccessfulExport(provider: provider)
            syncAccounts()
        }
    }

    private func shouldKeepFetchResult(for provider: ExternalIntegrationProvider) -> Bool {
        isDisconnectingProvider != provider && accounts[provider] != nil
    }

    func refreshToken(
        for provider: ExternalIntegrationProvider,
        replacing currentToken: ExternalIntegrationToken
    ) async throws -> ExternalIntegrationToken {
        if let task = refreshTasks[provider] {
            return try await task.value
        }

        var tokenToRefresh = currentToken
        if let storedToken = tokenStore.token(for: provider),
           storedToken.accessToken != currentToken.accessToken
            || storedToken.refreshToken != currentToken.refreshToken {
            // A concurrent request may have already completed WHOOP's strict
            // rotation after this caller captured the old pair. Reuse that pair
            // instead of submitting the now-invalid old refresh token.
            if !storedToken.needsRefresh() { return storedToken }
            tokenToRefresh = storedToken
        }
        guard let refreshToken = tokenToRefresh.refreshToken, !refreshToken.isEmpty else {
            throw ExternalProviderAPIError.unauthorized
        }

        let brokerClient = brokerClient
        let task = Task {
            let response = try await brokerClient.refresh(provider: provider, refreshToken: refreshToken)
            return try Self.validatedToken(from: response, provider: provider, replacing: tokenToRefresh)
        }
        refreshTasks[provider] = task
        defer { refreshTasks[provider] = nil }

        let token = try await task.value
        try tokenStore.saveRotatedToken(token, provider: provider)
        syncAccounts()
        return token
    }

    private func validatedToken(
        from response: ExternalOAuthTokenResponse,
        provider: ExternalIntegrationProvider,
        replacing currentToken: ExternalIntegrationToken?
    ) throws -> ExternalIntegrationToken {
        try Self.validatedToken(from: response, provider: provider, replacing: currentToken)
    }

    static func validatedToken(
        from response: ExternalOAuthTokenResponse,
        provider: ExternalIntegrationProvider,
        replacing currentToken: ExternalIntegrationToken?
    ) throws -> ExternalIntegrationToken {
        var token = response.integrationToken()
        guard !token.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExternalOAuthBrokerError.invalidResponse
        }
        if token.refreshToken?.isEmpty != false {
            if provider == .whoop {
                throw ExternalOAuthBrokerError.invalidResponse
            }
            token.refreshToken = currentToken?.refreshToken
        }
        if token.scope == nil { token.scope = currentToken?.scope }
        if token.providerUserID == nil { token.providerUserID = currentToken?.providerUserID }
        return token
    }

    private func runAuthenticationSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "healthmd") { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: ExternalOAuthBrokerError.invalidResponse)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            if !session.start() {
                continuation.resume(throwing: ExternalOAuthBrokerError.invalidResponse)
            }
        }
    }

    struct OAuthCallback {
        let code: String
    }

    static func parseCallback(_ url: URL, expectedState: String) throws -> OAuthCallback {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "healthmd",
              components.host?.lowercased() == "oauth",
              components.path == "/callback",
              components.user == nil,
              components.password == nil,
              components.port == nil else {
            throw ExternalOAuthBrokerError.brokerRejected("OAuth redirect was rejected.")
        }
        var items: [String: String] = [:]
        for item in components.queryItems ?? [] where items[item.name] == nil {
            items[item.name] = item.value ?? ""
        }
        guard items["state"] == expectedState else {
            throw ExternalOAuthBrokerError.brokerRejected("OAuth state mismatch.")
        }
        if let error = items["error"], !error.isEmpty {
            let description = items["error_description"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ExternalOAuthBrokerError.brokerRejected(description?.isEmpty == false ? description! : error)
        }
        guard let code = items["code"], !code.isEmpty else {
            throw ExternalOAuthBrokerError.invalidResponse
        }
        return OAuthCallback(code: code)
    }

    static func makeState(for provider: ExternalIntegrationProvider) -> String {
        guard provider == .whoop else { return UUID().uuidString }
        // WHOOP's OAuth documentation currently requires state to be exactly
        // eight characters long (despite a conflicting tutorial saying 8+).
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var bytes = [UInt8](repeating: 0, count: 8)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return String(UUID().uuidString.filter(\.isHexDigit).prefix(8))
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func makeCodeVerifier() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }
}

extension ExternalIntegrationManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
