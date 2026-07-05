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
    @Published var statusMessage: String?

    private let tokenStore: ExternalIntegrationTokenStore
    private let brokerClient: ExternalOAuthBrokerClient
    private let apiClient: ExternalProviderAPIClient
    private var authSession: ASWebAuthenticationSession?

    init(
        tokenStore: ExternalIntegrationTokenStore = ExternalIntegrationTokenStore(),
        brokerClient: ExternalOAuthBrokerClient = ExternalOAuthBrokerClient(),
        apiClient: ExternalProviderAPIClient = ExternalProviderAPIClient()
    ) {
        self.tokenStore = tokenStore
        self.brokerClient = brokerClient
        self.apiClient = apiClient
        self.accounts = tokenStore.accounts
        super.init()
    }

    var connectedProviderCount: Int { accounts.count }

    func isConnected(_ provider: ExternalIntegrationProvider) -> Bool {
        accounts[provider] != nil
    }

    func connect(provider: ExternalIntegrationProvider) async {
        guard brokerClient.isConfigured else {
            statusMessage = ExternalOAuthBrokerError.notConfigured.localizedDescription
            return
        }
        guard isConnectingProvider == nil else { return }

        isConnectingProvider = provider
        statusMessage = "Connecting \(provider.displayName)…"
        defer { isConnectingProvider = nil }

        do {
            let state = UUID().uuidString
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
            tokenStore.save(token: tokenResponse.integrationToken(), provider: provider)
            accounts = tokenStore.accounts
            statusMessage = "Connected \(provider.displayName)"
        } catch {
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                statusMessage = "Cancelled \(provider.displayName) connection"
            } else {
                statusMessage = "\(provider.displayName) connection failed: \(error.localizedDescription)"
            }
        }
    }

    func disconnect(provider: ExternalIntegrationProvider) {
        tokenStore.disconnect(provider: provider)
        accounts = tokenStore.accounts
        statusMessage = "Disconnected \(provider.displayName)"
    }

    func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] {
        var records: [ExternalDailyRecord] = []
        for provider in accounts.keys.sorted(by: { $0.displayName < $1.displayName }) {
            guard var token = tokenStore.token(for: provider) else { continue }
            do {
                if token.needsRefresh(), let refreshToken = token.refreshToken {
                    let refreshed = try await brokerClient.refresh(provider: provider, refreshToken: refreshToken)
                    token = refreshed.integrationToken()
                    tokenStore.save(token: token, provider: provider)
                    accounts = tokenStore.accounts
                }

                do {
                    let record = try await apiClient.fetchDailyRecord(provider: provider, date: date, token: token)
                    records.append(record)
                    tokenStore.markSuccessfulExport(provider: provider)
                    accounts = tokenStore.accounts
                } catch ExternalProviderAPIError.unauthorized where token.refreshToken != nil {
                    guard let refreshToken = token.refreshToken else { throw ExternalProviderAPIError.unauthorized }
                    let refreshed = try await brokerClient.refresh(provider: provider, refreshToken: refreshToken)
                    token = refreshed.integrationToken()
                    tokenStore.save(token: token, provider: provider)
                    accounts = tokenStore.accounts
                    let record = try await apiClient.fetchDailyRecord(provider: provider, date: date, token: token)
                    records.append(record)
                    tokenStore.markSuccessfulExport(provider: provider)
                    accounts = tokenStore.accounts
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

    private struct OAuthCallback {
        let code: String
    }

    private static func parseCallback(_ url: URL, expectedState: String) throws -> OAuthCallback {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ExternalOAuthBrokerError.invalidResponse
        }
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = items["error"], !error.isEmpty {
            throw ExternalOAuthBrokerError.brokerRejected(error)
        }
        guard items["state"] == expectedState else {
            throw ExternalOAuthBrokerError.brokerRejected("OAuth state mismatch.")
        }
        guard let code = items["code"], !code.isEmpty else {
            throw ExternalOAuthBrokerError.invalidResponse
        }
        return OAuthCallback(code: code)
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
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        DispatchQueue.main.sync {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
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
