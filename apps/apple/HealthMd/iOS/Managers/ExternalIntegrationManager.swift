import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

struct ExternalIntegrationConnectionStatus: Equatable, Identifiable {
    enum Kind: Equatable {
        case progress, success, warning, error
    }

    let id = UUID()
    let kind: Kind
    let message: String
}

@MainActor
final class ExternalIntegrationManager: NSObject, ObservableObject, ExternalIntegrationDailyRecordProviding {
    static let redirectURI = "healthmd://oauth/callback"

    @Published private(set) var accounts: [ExternalIntegrationProvider: ExternalIntegrationAccount] = [:]
    @Published private(set) var isConnectingProvider: ExternalIntegrationProvider?
    @Published private(set) var isDisconnectingProvider: ExternalIntegrationProvider?
    @Published private(set) var connectionStatus: ExternalIntegrationConnectionStatus?

    var statusMessage: String? { connectionStatus?.message }

    private let tokenStore: ExternalIntegrationTokenStore
    private let enabledProviders: Set<ExternalIntegrationProvider>
    private let brokerClient: ExternalOAuthBrokerClient
    private let apiClient: ExternalProviderAPIClient
    private var authSession: ASWebAuthenticationSession?
    private let authenticate: (@MainActor (URL) async throws -> URL)?
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
        apiClient: ExternalProviderAPIClient,
        authenticate: (@MainActor (URL) async throws -> URL)? = nil
    ) {
        self.tokenStore = tokenStore
        self.enabledProviders = enabledProviders
        self.brokerClient = brokerClient
        self.apiClient = apiClient
        self.authenticate = authenticate
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

    func connect(
        provider: ExternalIntegrationProvider,
        commitAllowed: @MainActor () -> Bool = { true }
    ) async {
        guard enabledProviders.contains(provider) else {
            setConnectionStatus(.error, "\(provider.displayName) is not enabled for this build.")
            return
        }
        guard brokerClient.isConfigured else {
            setConnectionStatus(.error, ExternalOAuthBrokerError.notConfigured.localizedDescription)
            return
        }
        guard isConnectingProvider == nil, isDisconnectingProvider == nil else { return }

        isConnectingProvider = provider
        setConnectionStatus(.progress, "Connecting \(provider.displayName)…")
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

            let callbackURL: URL
            if let authenticate {
                callbackURL = try await authenticate(authorize.authorizationURL)
            } else {
                callbackURL = try await runAuthenticationSession(url: authorize.authorizationURL)
            }
            let callback = try Self.parseCallback(callbackURL, expectedState: state)
            let tokenResponse = try await brokerClient.exchangeCode(
                provider: provider,
                code: callback.code,
                redirectURI: Self.redirectURI,
                codeVerifier: codeVerifier
            )
            let token = try validatedToken(from: tokenResponse, provider: provider, replacing: nil)
            guard commitAllowed() else {
                try? await apiClient.revokeAccess(provider: provider, token: token)
                setConnectionStatus(.warning, "Connection not saved because settings are locked")
                return
            }
            do {
                try tokenStore.save(token: token, provider: provider)
            } catch {
                // Do not leave a grant active if local account setup could not
                // be completed and surfaced in Connected Apps.
                try? await apiClient.revokeAccess(provider: provider, token: token)
                throw error
            }
            syncAccounts()
            setConnectionStatus(.success, "Connected \(provider.displayName)")
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                setConnectionStatus(.warning, "Cancelled \(provider.displayName) connection")
            } else {
                setConnectionStatus(.error, "\(provider.displayName) connection failed: \(error.localizedDescription)")
            }
        }
    }

    func disconnect(
        provider: ExternalIntegrationProvider,
        commitAllowed: @MainActor () -> Bool = { true }
    ) async {
        guard isDisconnectingProvider == nil, isConnectingProvider == nil else { return }
        isDisconnectingProvider = provider
        defer { isDisconnectingProvider = nil }

        guard var token = tokenStore.token(for: provider) else {
            guard commitAllowed() else {
                setConnectionStatus(.warning, "Disconnect cancelled because settings are locked")
                return
            }
            do {
                try tokenStore.disconnect(provider: provider)
                syncAccounts()
                setConnectionStatus(.success, "Disconnected \(provider.displayName)")
            } catch {
                setConnectionStatus(.error, "Could not remove \(provider.displayName) credentials: \(error.localizedDescription)")
            }
            return
        }

        setConnectionStatus(.progress, "Revoking \(provider.displayName) access…")
        do {
            if token.needsRefresh(), token.refreshToken != nil {
                token = try await refreshToken(for: provider, replacing: token)
            }
            guard commitAllowed() else {
                setConnectionStatus(.warning, "Disconnect cancelled because settings are locked")
                return
            }
            do {
                try await apiClient.revokeAccess(provider: provider, token: token)
            } catch ExternalProviderAPIError.unauthorized where token.refreshToken != nil {
                token = try await refreshToken(for: provider, replacing: token)
                guard commitAllowed() else {
                    setConnectionStatus(.warning, "Disconnect cancelled because settings are locked")
                    return
                }
                try await apiClient.revokeAccess(provider: provider, token: token)
            }
        } catch {
            setConnectionStatus(.error, "Could not revoke \(provider.displayName) access: \(error.localizedDescription) Try again before removing access in \(provider.displayName).")
            return
        }

        do {
            try tokenStore.disconnect(provider: provider)
            syncAccounts()
            setConnectionStatus(.success, "Disconnected \(provider.displayName) and revoked access")
        } catch {
            syncAccounts()
            setConnectionStatus(.error, "\(provider.displayName) access was revoked, but local Keychain cleanup failed: \(error.localizedDescription)")
        }
    }

    func dismissConnectionStatus(id: UUID) {
        guard connectionStatus?.id == id, connectionStatus?.kind != .progress else { return }
        connectionStatus = nil
    }

    private func setConnectionStatus(_ kind: ExternalIntegrationConnectionStatus.Kind, _ message: String) {
        connectionStatus = ExternalIntegrationConnectionStatus(kind: kind, message: message)
    }

    func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] {
        await fetchDailyRecords(for: date, calendar: .current)
    }

    func fetchDailyRecords(
        for date: Date,
        calendar: Calendar
    ) async -> [ExternalDailyRecord] {
        await fetchDailyRecords(
            for: date,
            providerIDs: Set(accounts.keys.map(\.id)),
            calendar: calendar
        )
    }

    func fetchDailyRecords(
        for date: Date,
        providerIDs: Set<String>
    ) async -> [ExternalDailyRecord] {
        await fetchDailyRecords(for: date, providerIDs: providerIDs, calendar: .current)
    }

    func fetchDailyRecords(
        for date: Date,
        providerIDs: Set<String>,
        calendar: Calendar
    ) async -> [ExternalDailyRecord] {
        guard !providerIDs.isEmpty, !enabledProviders.isEmpty else { return [] }
        var records: [ExternalDailyRecord] = []
        let dateString = ExternalProviderAPIClient.dayString(date, calendar: calendar)
        for provider in enabledProviders
            .filter({ providerIDs.contains($0.id) })
            .sorted(by: { $0.displayName < $1.displayName }) {
            guard accounts[provider] != nil, isDisconnectingProvider != provider else {
                records.append(ExternalDailyRecord(
                    provider: provider,
                    date: dateString,
                    payloads: [],
                    warnings: ["\(provider.displayName) is not connected."]
                ))
                continue
            }
            guard var token = tokenStore.token(for: provider) else {
                records.append(ExternalDailyRecord(
                    provider: provider,
                    date: dateString,
                    payloads: [],
                    warnings: ["\(provider.displayName) credentials are unavailable."]
                ))
                continue
            }
            do {
                if token.needsRefresh(), token.refreshToken != nil {
                    token = try await measureExternalProviderPhase("token-refresh") {
                        try await refreshToken(for: provider, replacing: token)
                    }
                }
                guard shouldKeepFetchResult(for: provider) else { continue }

                do {
                    let record = try await apiClient.fetchDailyRecord(
                        provider: provider,
                        date: date,
                        token: token,
                        calendar: calendar
                    )
                    guard shouldKeepFetchResult(for: provider) else { continue }
                    records.append(record)
                    markSuccessfulFetch(provider: provider)
                } catch ExternalProviderAPIError.unauthorized where token.refreshToken != nil {
                    token = try await measureExternalProviderPhase("token-refresh") {
                        try await refreshToken(for: provider, replacing: token)
                    }
                    guard shouldKeepFetchResult(for: provider) else { continue }
                    let record = try await apiClient.fetchDailyRecord(
                        provider: provider,
                        date: date,
                        token: token,
                        calendar: calendar
                    )
                    guard shouldKeepFetchResult(for: provider) else { continue }
                    records.append(record)
                    markSuccessfulFetch(provider: provider)
                }
            } catch {
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

    func discoverEarliestAvailableDate(
        providerIDs: Set<String>
    ) async -> ExternalProviderHistoryDiscovery {
        let requestedProviders = Set(accounts.keys.filter {
            providerIDs.contains($0.id)
                && enabledProviders.contains($0)
                && isDisconnectingProvider != $0
        })
        var earliest: Date?
        var unresolved = Array(
            providerIDs.subtracting(Set(requestedProviders.map(\.id)))
        ).sorted()

        for provider in requestedProviders.sorted(by: { $0.id < $1.id }) {
            guard var token = tokenStore.token(for: provider) else {
                unresolved.append(provider.id)
                continue
            }
            do {
                if token.needsRefresh(), token.refreshToken != nil {
                    token = try await refreshToken(for: provider, replacing: token)
                }
                let candidate: Date?
                do {
                    candidate = try await apiClient.discoverEarliestAvailableDate(
                        provider: provider,
                        token: token
                    )
                } catch ExternalProviderAPIError.unauthorized where token.refreshToken != nil {
                    token = try await refreshToken(for: provider, replacing: token)
                    candidate = try await apiClient.discoverEarliestAvailableDate(
                        provider: provider,
                        token: token
                    )
                }
                if let candidate, earliest == nil || candidate < earliest! {
                    earliest = candidate
                }
            } catch {
                unresolved.append(provider.id)
            }
        }
        return ExternalProviderHistoryDiscovery(
            earliestDate: earliest,
            unresolvedProviderIDs: unresolved.sorted()
        )
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
        defer { authSession = nil }
        return try await withCheckedThrowingContinuation { continuation in
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
              components.port == nil,
              components.fragment == nil else {
            throw ExternalOAuthBrokerError.brokerRejected("OAuth redirect was rejected.")
        }
        var items: [String: String] = [:]
        // OAuth queries use form encoding. Decode '+' before percent escapes so
        // a literal plus encoded as %2B is preserved in the authorization code.
        for item in components.percentEncodedQueryItems ?? [] {
            let name = Self.decodeFormValue(item.name)
            guard items[name] == nil else {
                throw ExternalOAuthBrokerError.brokerRejected("OAuth callback contained duplicate parameters.")
            }
            items[name] = Self.decodeFormValue(item.value ?? "")
        }
        guard !expectedState.isEmpty, items["state"] == expectedState else {
            throw ExternalOAuthBrokerError.brokerRejected("OAuth state mismatch.")
        }
        guard items["code"] == nil || items["error"] == nil else {
            throw ExternalOAuthBrokerError.invalidResponse
        }
        if let error = items["error"], !error.isEmpty {
            // Upstream descriptions/hints can contain credentials or internal
            // request details. Only expose a stable, actionable message.
            throw ExternalOAuthBrokerError.authorizationRejected(error)
        }
        guard let code = items["code"], !code.isEmpty else {
            throw ExternalOAuthBrokerError.invalidResponse
        }
        return OAuthCallback(code: code)
    }

    private static func decodeFormValue(_ value: String) -> String {
        let formValue = value.replacingOccurrences(of: "+", with: " ")
        return formValue.removingPercentEncoding ?? formValue
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

private func measureExternalProviderPhase<T>(
    _ phase: String,
    operation: () async throws -> T
) async rethrows -> T {
    #if DEBUG
    return try await ExportPerformanceInstrumentation.measureSpan(
        pipeline: "external-provider",
        phase: phase,
        operation: operation
    )
    #else
    return try await operation()
    #endif
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
