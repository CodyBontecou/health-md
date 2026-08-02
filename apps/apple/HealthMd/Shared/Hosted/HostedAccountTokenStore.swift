import Foundation
import Security

nonisolated enum HostedAccountTokenStoreError: LocalizedError, Equatable {
  case unavailable
  case corrupt
  case persistenceFailed

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "Health.md could not access the protected hosted account state in Keychain."
    case .corrupt:
      return "The protected hosted account state is invalid and requires recovery."
    case .persistenceFailed:
      return "Health.md could not verify the hosted account credential in Keychain."
    }
  }
}

final class HostedAccountTokenStore: @unchecked Sendable {
  private static let tokenKey = "hostedAccount.oauthToken.v1"
  private static let consentKey = "hostedAccount.consent.v1"
  private static let pendingMutationKey = "hostedAccount.pendingMutation.v1"
  private static let pendingMutationRecoveryKey = "hostedAccount.pendingMutationRecovery.v1"
  private static let refreshCandidateKey = "hostedAccount.oauthRefreshCandidate.v1"

  private let keychain: any ExternalIntegrationSecureStoring
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    keychain: any ExternalIntegrationSecureStoring = SystemKeychainStore(
      service: "com.codybontecou.healthmd.hosted-account.v1",
      accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    )
  ) {
    self.keychain = keychain
    self.encoder = JSONEncoder()
    self.decoder = JSONDecoder()
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
  }

  func token() -> HostedOAuthToken? {
    try? loadToken()
  }

  func loadToken() throws -> HostedOAuthToken? {
    try load(
      key: Self.tokenKey,
      maximumBytes: 128 * 1_024,
      as: HostedOAuthToken.self,
      validate: Self.isValid
    )
  }

  func save(_ token: HostedOAuthToken) throws {
    try saveToken(token, key: Self.tokenKey)
  }

  private func saveToken(_ token: HostedOAuthToken, key: String) throws {
    guard Self.isValid(token) else { throw HostedAccountTokenStoreError.persistenceFailed }
    let data = try encoder.encode(token)
    guard data.count <= 128 * 1_024,
      let value = String(data: data, encoding: .utf8)
    else {
      throw HostedAccountTokenStoreError.persistenceFailed
    }
    try keychain.writeStringOrThrow(key: key, value: value)
    guard try keychain.readStringOrThrow(key: key) == value else {
      throw HostedAccountTokenStoreError.persistenceFailed
    }
  }

  func loadRefreshCandidate() throws -> HostedOAuthToken? {
    try load(
      key: Self.refreshCandidateKey,
      maximumBytes: 128 * 1_024,
      as: HostedOAuthToken.self,
      validate: Self.isValid
    )
  }

  func saveRefreshCandidate(_ token: HostedOAuthToken) throws {
    try saveToken(token, key: Self.refreshCandidateKey)
  }

  /// Promote a previously persisted rotated token and retire its candidate record last.
  func promoteRefreshCandidate(_ token: HostedOAuthToken) throws {
    try save(token)
    try keychain.removeOrThrow(key: Self.refreshCandidateKey)
  }

  func removeRefreshCandidate() throws {
    try keychain.removeOrThrow(key: Self.refreshCandidateKey)
  }

  func consent() -> HostedLocalConsent? {
    try? loadConsent()
  }

  func loadConsent() throws -> HostedLocalConsent? {
    try load(
      key: Self.consentKey,
      maximumBytes: 128 * 1_024,
      as: HostedLocalConsent.self,
      validate: Self.isValid
    )
  }

  func save(_ consent: HostedLocalConsent) throws {
    guard Self.isValid(consent),
      let value = String(data: try encoder.encode(consent), encoding: .utf8),
      value.utf8.count <= 128 * 1_024
    else {
      throw HostedAccountTokenStoreError.persistenceFailed
    }
    try keychain.writeStringOrThrow(key: Self.consentKey, value: value)
    guard try keychain.readStringOrThrow(key: Self.consentKey) == value else {
      throw HostedAccountTokenStoreError.persistenceFailed
    }
  }

  func hasPendingMutationRecord() -> Bool {
    (try? pendingMutationRecordExists()) ?? false
  }

  func pendingMutationRecordExists() throws -> Bool {
    do {
      let mutation = try keychain.readStringOrThrow(key: Self.pendingMutationKey)
      let recovery = try keychain.readStringOrThrow(key: Self.pendingMutationRecoveryKey)
      return mutation != nil || recovery != nil
    } catch {
      throw HostedAccountTokenStoreError.unavailable
    }
  }

  func pendingMutation() -> HostedPendingMutation? {
    try? loadPendingMutation()
  }

  func loadPendingMutation() throws -> HostedPendingMutation? {
    try load(
      key: Self.pendingMutationKey,
      maximumBytes: 256 * 1_024,
      as: HostedPendingMutation.self,
      validate: Self.isValid
    )
  }

  func loadPendingMutationRecovery() throws -> HostedPendingMutationRecovery? {
    try load(
      key: Self.pendingMutationRecoveryKey,
      maximumBytes: 16 * 1_024,
      as: HostedPendingMutationRecovery.self,
      validate: Self.isValid
    )
  }

  func save(_ mutation: HostedPendingMutation) throws {
    guard Self.isValid(mutation),
      let recoveryValue = String(data: try encoder.encode(mutation.recovery), encoding: .utf8),
      recoveryValue.utf8.count <= 16 * 1_024,
      let value = String(data: try encoder.encode(mutation), encoding: .utf8),
      value.utf8.count <= 256 * 1_024
    else {
      throw HostedAccountTokenStoreError.persistenceFailed
    }
    // The minimal owner binding is established first so a corrupted detailed tombstone can only
    // recover by same-owner reauthorization and destructive server deletion.
    try keychain.writeStringOrThrow(
      key: Self.pendingMutationRecoveryKey,
      value: recoveryValue
    )
    guard try keychain.readStringOrThrow(key: Self.pendingMutationRecoveryKey) == recoveryValue
    else {
      throw HostedAccountTokenStoreError.persistenceFailed
    }
    try keychain.writeStringOrThrow(key: Self.pendingMutationKey, value: value)
    guard try keychain.readStringOrThrow(key: Self.pendingMutationKey) == value else {
      throw HostedAccountTokenStoreError.persistenceFailed
    }
  }

  func removePendingMutation() throws {
    try keychain.removeOrThrow(key: Self.pendingMutationKey)
    try keychain.removeOrThrow(key: Self.pendingMutationRecoveryKey)
  }

  func removeConsent() throws {
    try keychain.removeOrThrow(key: Self.consentKey)
  }

  func removeToken() throws {
    try keychain.removeOrThrow(key: Self.tokenKey)
  }

  /// Stop on the first failure and retire the recovery tombstone last.
  func removeAll() throws {
    try removeConsent()
    try removeRefreshCandidate()
    try removeToken()
    try removePendingMutation()
  }

  private func load<Value: Decodable>(
    key: String,
    maximumBytes: Int,
    as _: Value.Type,
    validate: (Value) -> Bool
  ) throws -> Value? {
    let value: String
    do {
      guard let stored = try keychain.readStringOrThrow(key: key) else { return nil }
      value = stored
    } catch {
      throw HostedAccountTokenStoreError.unavailable
    }
    guard value.utf8.count <= maximumBytes,
      let data = value.data(using: .utf8),
      let decoded = try? decoder.decode(Value.self, from: data),
      validate(decoded)
    else {
      throw HostedAccountTokenStoreError.corrupt
    }
    return decoded
  }

  private static func isValid(_ token: HostedOAuthToken) -> Bool {
    token.isPersistable && token.scopes == HostedAccountConfiguration.requiredScopes
  }

  private static func isValid(_ recovery: HostedPendingMutationRecovery) -> Bool {
    HostedAccountConfiguration(
      resourceURL: recovery.resourceURL,
      clientID: recovery.clientID
    ).isValid
      && isValidIssuer(recovery.issuer)
      && HostedOAuthToken.isValidOwnerBinding(recovery.ownerBinding)
  }

  private static func isValid(_ mutation: HostedPendingMutation) -> Bool {
    guard mutation.createdAt.timeIntervalSinceReferenceDate.isFinite,
      HostedAccountConfiguration(
        resourceURL: mutation.resourceURL,
        clientID: mutation.clientID
      ).isValid,
      isValidIssuer(mutation.issuer),
      HostedOAuthToken.isValidOwnerBinding(mutation.ownerBinding),
      mutation.previousConsent.map(isValidHistorical) ?? true,
      mutation.proposedConsent.map(isValidHistorical) ?? true
    else {
      return false
    }
    switch mutation.kind {
    case .replaceConsent:
      guard let expected = mutation.expectedRevision,
        let target = mutation.targetRevision
      else { return false }
      return mutation.previousConsentState != nil
        && target == mutation.proposedConsent?.revision
        && expected < UInt64.max
        && target == expected + 1
        && (mutation.previousConsent.map { $0.revision == expected } ?? true)
        && mutation.proposedConsent?.resourceURL == mutation.resourceURL
        && mutation.proposedConsent?.clientID == mutation.clientID
        && mutation.proposedConsent?.issuer == mutation.issuer
        && mutation.proposedConsent?.ownerBinding == mutation.ownerBinding
        && (mutation.previousConsent.map { $0.ownerBinding == mutation.ownerBinding } ?? true)
    case .revokeConsent:
      guard let expected = mutation.expectedRevision,
        let target = mutation.targetRevision
      else { return false }
      return mutation.previousConsentState.map {
        [HostedConsentState.active, .expired].contains($0)
      } == true
        && mutation.previousConsent?.revision == expected
        && mutation.previousConsent?.ownerBinding == mutation.ownerBinding
        && expected < UInt64.max
        && target == expected + 1
        && mutation.proposedConsent == nil
    case .deleteAccount:
      return mutation.expectedRevision == nil
        && mutation.targetRevision == nil
        && mutation.previousConsentState == nil
        && mutation.proposedConsent == nil
        && (mutation.previousConsent.map { $0.ownerBinding == mutation.ownerBinding } ?? true)
    }
  }

  private static func isValid(_ consent: HostedLocalConsent) -> Bool {
    isValidConsent(consent, requireCurrentCatalog: true)
  }

  private static func isValidHistorical(_ consent: HostedLocalConsent) -> Bool {
    isValidConsent(consent, requireCurrentCatalog: false)
  }

  private static func isValidConsent(
    _ consent: HostedLocalConsent,
    requireCurrentCatalog: Bool
  ) -> Bool {
    consent.revision > 0
      && !consent.metricIDs.isEmpty
      && consent.metricIDs.count <= 512
      && consent.sourceIDs.count <= 512
      && consent.providerIDs.count <= 512
      && (1...3_650).contains(Int(consent.retentionDays))
      && (!requireCurrentCatalog
        || consent.metricIDs.isSubset(
          of: HealthMetrics.availableMetricIDsInCurrentBuild
        ))
      && consent.sourceIDs == [
        HealthMdEvidenceSourceIDs.appleHealth,
        HealthMdEvidenceSourceIDs.healthMdSummary,
      ]
      && consent.providerIDs.isEmpty
      && HostedAccountConfiguration(
        resourceURL: consent.resourceURL,
        clientID: consent.clientID
      ).isValid
      && Self.isValidIssuer(consent.issuer)
      && HostedOAuthToken.isValidOwnerBinding(consent.ownerBinding)
      && consent.metricIDs
        .union(consent.sourceIDs)
        .union(consent.providerIDs)
        .allSatisfy {
          !$0.isEmpty
            && $0.utf8.count <= 128
            && $0.range(
              of: "^[a-z0-9][a-z0-9._-]*$",
              options: .regularExpression
            ) != nil
        }
  }

  private static func isValidIssuer(_ value: URL) -> Bool {
    guard let components = URLComponents(url: value, resolvingAgainstBaseURL: false) else {
      return false
    }
    return components.scheme?.lowercased() == "https"
      && components.host?.isEmpty == false
      && components.user == nil
      && components.password == nil
      && components.query == nil
      && components.fragment == nil
  }
}
