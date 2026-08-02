import Foundation

nonisolated enum HostedConsentDetail: String, Codable, CaseIterable, Sendable {
  case summary
  case lossless
}

nonisolated struct HostedAccountConfiguration: Codable, Equatable, Sendable {
  static let requiredScopes: Set<String> = ["health.sync.write", "health.account.manage"]
  static let redirectURI = "healthmd://hosted/callback"

  let resourceURL: URL
  let clientID: String

  var isValid: Bool {
    guard let components = URLComponents(url: resourceURL, resolvingAgainstBaseURL: false) else {
      return false
    }
    return components.scheme?.lowercased() == "https"
      && components.host?.isEmpty == false
      && components.user == nil
      && components.password == nil
      && components.path == "/mcp"
      && components.query == nil
      && components.fragment == nil
      && !clientID.isEmpty
      && clientID.utf8.count <= 256
  }

  var apiOrigin: URL? {
    guard isValid,
      var components = URLComponents(url: resourceURL, resolvingAgainstBaseURL: false)
    else {
      return nil
    }
    components.path = ""
    components.query = nil
    components.fragment = nil
    return components.url
  }

  static var current: HostedAccountConfiguration? {
    guard let resource = configurationValue("HEALTHMD_HOSTED_RESOURCE_URL"),
      let resourceURL = URL(string: resource),
      resourceURL.scheme?.lowercased() == "https",
      resourceURL.host != nil,
      let clientID = configurationValue("HEALTHMD_HOSTED_OAUTH_CLIENT_ID"),
      clientID.utf8.count <= 256
    else { return nil }
    let configuration = HostedAccountConfiguration(
      resourceURL: resourceURL,
      clientID: clientID
    )
    return configuration.isValid ? configuration : nil
  }

  private static func configurationValue(_ key: String) -> String? {
    for candidate in [
      ProcessInfo.processInfo.environment[key],
      Bundle.main.object(forInfoDictionaryKey: key) as? String,
    ] {
      guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty,
        !value.contains("$(")
      else { continue }
      return value
    }
    return nil
  }
}

nonisolated struct HostedOAuthToken: Codable, Equatable, Sendable {
  let accessToken: String
  let refreshToken: String?
  let tokenType: String
  let scopes: Set<String>
  let expiresAt: Date?
  let resourceURL: URL
  let clientID: String
  let issuer: URL
  /// Opaque server-issued binding for the authenticated issuer/tenant/subject corpus.
  let ownerBinding: String?

  init(
    accessToken: String,
    refreshToken: String?,
    tokenType: String,
    scopes: Set<String>,
    expiresAt: Date?,
    resourceURL: URL,
    clientID: String,
    issuer: URL,
    ownerBinding: String? = nil
  ) {
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.tokenType = tokenType
    self.scopes = scopes
    self.expiresAt = expiresAt
    self.resourceURL = resourceURL
    self.clientID = clientID
    self.issuer = issuer
    self.ownerBinding = ownerBinding
  }

  var canManageAndSync: Bool {
    isValid && scopes == HostedAccountConfiguration.requiredScopes
  }

  var canRecoverAuthorization: Bool {
    canManageAndSync && (!needsRefresh() || refreshToken != nil)
  }

  var isValid: Bool {
    Self.isValidBearerAccessToken(accessToken)
      && refreshToken.map(Self.isValidRefreshToken) ?? true
      && tokenType.caseInsensitiveCompare("Bearer") == .orderedSame
      && scopes.count <= 32
      && scopes.allSatisfy(Self.isValidScope)
      && expiresAt?.timeIntervalSinceReferenceDate.isFinite != false
      && HostedAccountConfiguration(
        resourceURL: resourceURL,
        clientID: clientID
      ).isValid
      && Self.isValidIssuer(issuer)
      && ownerBinding.map(Self.isValidOwnerBinding) ?? true
  }

  var isPersistable: Bool {
    canManageAndSync && ownerBinding.map(Self.isValidOwnerBinding) == true
  }

  func canUse(configuration: HostedAccountConfiguration) -> Bool {
    isValid
      && resourceURL == configuration.resourceURL
      && clientID == configuration.clientID
  }

  func canUse(
    configuration: HostedAccountConfiguration,
    ownerBinding expectedOwnerBinding: String
  ) -> Bool {
    canUse(configuration: configuration)
      && ownerBinding == expectedOwnerBinding
  }

  func bound(to ownerBinding: String) throws -> HostedOAuthToken {
    guard Self.isValidOwnerBinding(ownerBinding) else {
      throw HostedOAuthError.invalidToken
    }
    return HostedOAuthToken(
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: tokenType,
      scopes: scopes,
      expiresAt: expiresAt,
      resourceURL: resourceURL,
      clientID: clientID,
      issuer: issuer,
      ownerBinding: ownerBinding
    )
  }

  func needsRefresh(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
    expiresAt.isSomeAnd { $0 <= now.addingTimeInterval(leeway) }
  }

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case tokenType = "token_type"
    case scopes
    case expiresAt = "expires_at"
    case resourceURL = "resource_url"
    case clientID = "client_id"
    case issuer
    case ownerBinding = "owner_binding"
  }

  private static func isValidBearerAccessToken(_ value: String) -> Bool {
    guard (1...16 * 1_024).contains(value.utf8.count) else { return false }
    var reachedPadding = false
    for byte in value.utf8 {
      if byte == 61 {
        reachedPadding = true
        continue
      }
      guard !reachedPadding,
        (byte >= 65 && byte <= 90)
          || (byte >= 97 && byte <= 122)
          || (byte >= 48 && byte <= 57)
          || [45, 46, 95, 126, 43, 47].contains(byte)
      else {
        return false
      }
    }
    return true
  }

  private static func isValidRefreshToken(_ value: String) -> Bool {
    (1...64 * 1_024).contains(value.utf8.count)
      && value.utf8.allSatisfy { (0x21...0x7E).contains($0) }
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

  static func isValidOwnerBinding(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy {
        ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
      }
  }

  private static func isValidScope(_ value: String) -> Bool {
    (1...128).contains(value.utf8.count)
      && value.utf8.allSatisfy {
        $0 == 0x21 || (0x23...0x5B).contains($0) || (0x5D...0x7E).contains($0)
      }
  }
}

extension Optional where Wrapped == Date {
  fileprivate nonisolated func isSomeAnd(_ predicate: (Date) -> Bool) -> Bool {
    guard let self else { return false }
    return predicate(self)
  }
}

nonisolated struct HostedProtectedResourceMetadata: Decodable, Equatable, Sendable {
  let resource: URL
  let authorizationServers: [URL]
  let scopesSupported: [String]

  enum CodingKeys: String, CodingKey {
    case resource
    case authorizationServers = "authorization_servers"
    case scopesSupported = "scopes_supported"
  }
}

nonisolated struct HostedAuthorizationServerMetadata: Decodable, Equatable, Sendable {
  let issuer: URL
  let authorizationEndpoint: URL
  let tokenEndpoint: URL
  let codeChallengeMethodsSupported: [String]?

  enum CodingKeys: String, CodingKey {
    case issuer
    case authorizationEndpoint = "authorization_endpoint"
    case tokenEndpoint = "token_endpoint"
    case codeChallengeMethodsSupported = "code_challenge_methods_supported"
  }
}

nonisolated struct HostedLocalConsent: Codable, Equatable, Sendable {
  let revision: UInt64
  let metricIDs: Set<String>
  let sourceIDs: Set<String>
  let providerIDs: Set<String>
  let maximumDetail: HostedConsentDetail
  let retentionDays: UInt16
  let resourceURL: URL
  let clientID: String
  let issuer: URL
  let ownerBinding: String
  let automaticSyncEnabled: Bool

  var localCaptureMetricIDs: Set<String> {
    guard metricIDs.contains("sleep_total") else { return metricIDs }
    return metricIDs.union(["sleep_bedtime", "sleep_wake"])
  }

  func canUse(
    configuration: HostedAccountConfiguration,
    issuer expectedIssuer: URL,
    ownerBinding expectedOwnerBinding: String
  ) -> Bool {
    resourceURL == configuration.resourceURL
      && clientID == configuration.clientID
      && issuer == expectedIssuer
      && ownerBinding == expectedOwnerBinding
  }

  enum CodingKeys: String, CodingKey {
    case revision
    case metricIDs = "metric_ids"
    case sourceIDs = "source_ids"
    case providerIDs = "provider_ids"
    case maximumDetail = "maximum_detail"
    case retentionDays = "retention_days"
    case resourceURL = "resource_url"
    case clientID = "client_id"
    case issuer
    case ownerBinding = "owner_binding"
    case automaticSyncEnabled = "automatic_sync_enabled"
  }
}

nonisolated enum HostedConsentState: String, Codable, Sendable {
  case active
  case expired
  case missing
}

nonisolated enum HostedPendingMutationKind: String, Codable, Sendable {
  case replaceConsent = "replace_consent"
  case revokeConsent = "revoke_consent"
  case deleteAccount = "delete_account"
}

nonisolated struct HostedPendingMutationRecovery: Codable, Equatable, Sendable {
  let resourceURL: URL
  let clientID: String
  let issuer: URL
  let ownerBinding: String

  func canUse(
    configuration: HostedAccountConfiguration,
    issuer expectedIssuer: URL,
    ownerBinding expectedOwnerBinding: String
  ) -> Bool {
    resourceURL == configuration.resourceURL
      && clientID == configuration.clientID
      && issuer == expectedIssuer
      && ownerBinding == expectedOwnerBinding
  }

  enum CodingKeys: String, CodingKey {
    case resourceURL = "resource_url"
    case clientID = "client_id"
    case issuer
    case ownerBinding = "owner_binding"
  }
}

nonisolated struct HostedPendingMutation: Codable, Equatable, Sendable {
  let kind: HostedPendingMutationKind
  let expectedRevision: UInt64?
  let targetRevision: UInt64?
  let previousConsentState: HostedConsentState?
  let previousConsent: HostedLocalConsent?
  let proposedConsent: HostedLocalConsent?
  let resourceURL: URL
  let clientID: String
  let issuer: URL
  let ownerBinding: String
  let createdAt: Date

  func canUse(
    configuration: HostedAccountConfiguration,
    issuer expectedIssuer: URL,
    ownerBinding expectedOwnerBinding: String
  ) -> Bool {
    resourceURL == configuration.resourceURL
      && clientID == configuration.clientID
      && issuer == expectedIssuer
      && ownerBinding == expectedOwnerBinding
  }

  var recovery: HostedPendingMutationRecovery {
    HostedPendingMutationRecovery(
      resourceURL: resourceURL,
      clientID: clientID,
      issuer: issuer,
      ownerBinding: ownerBinding
    )
  }

  enum CodingKeys: String, CodingKey {
    case kind
    case expectedRevision = "expected_revision"
    case targetRevision = "target_revision"
    case previousConsentState = "previous_consent_state"
    case previousConsent = "previous_consent"
    case proposedConsent = "proposed_consent"
    case resourceURL = "resource_url"
    case clientID = "client_id"
    case issuer
    case ownerBinding = "owner_binding"
    case createdAt = "created_at"
  }
}

nonisolated struct HostedConsentRequest: Codable, Equatable, Sendable {
  let revision: UInt64
  let allowedMetricIDs: [String]
  let allowedSourceIDs: [String]
  let allowedProviderIDs: [String]
  let maximumDetail: HostedConsentDetail
  let retentionDays: UInt16
  let expiresAt: Date?

  enum CodingKeys: String, CodingKey {
    case revision
    case allowedMetricIDs = "allowed_metric_ids"
    case allowedSourceIDs = "allowed_source_ids"
    case allowedProviderIDs = "allowed_provider_ids"
    case maximumDetail = "maximum_detail"
    case retentionDays = "retention_days"
    case expiresAt = "expires_at"
  }
}

nonisolated struct HostedConsentRevocationRequest: Codable, Equatable, Sendable {
  let expectedRevision: UInt64
  let revision: UInt64

  enum CodingKeys: String, CodingKey {
    case expectedRevision = "expected_revision"
    case revision
  }
}

nonisolated struct HostedConsentResult: Decodable, Equatable, Sendable {
  let schema: String
  let schemaVersion: Int
  let consentRevision: UInt64
  let consentState: String

  enum CodingKeys: String, CodingKey {
    case schema
    case schemaVersion = "schema_version"
    case consentRevision = "consent_revision"
    case consentState = "consent_state"
  }
}

nonisolated struct HostedControlStatus: Decodable, Equatable, Sendable {
  let schema: String
  let schemaVersion: Int
  let ownerBinding: String
  let consentRevision: UInt64?
  let consentState: HostedConsentState

  enum CodingKeys: String, CodingKey {
    case schema
    case schemaVersion = "schema_version"
    case ownerBinding = "owner_binding"
    case consentRevision = "consent_revision"
    case consentState = "consent_state"
  }
}

nonisolated enum HostedOwnerDate {
  static func isValid(_ value: String) -> Bool {
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard value.utf8.count == 10,
      parts.count == 3,
      parts[0].count == 4,
      parts[1].count == 2,
      parts[2].count == 2,
      let year = Int(parts[0]),
      let month = Int(parts[1]),
      let day = Int(parts[2]),
      (1_900...9_999).contains(year),
      (1...12).contains(month),
      (1...31).contains(day)
    else { return false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    guard
      let date = calendar.date(
        from: DateComponents(
          calendar: calendar,
          timeZone: calendar.timeZone,
          year: year,
          month: month,
          day: day
        ))
    else { return false }
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return components.year == year && components.month == month && components.day == day
  }
}

nonisolated struct HostedSyncDay: Encodable, Sendable {
  let digestSHA256: String
  let day: HealthMdCompactContextDay

  init(day: HealthMdCompactContextDay, consent: HostedLocalConsent) throws {
    let minimized = try day.applyingHostedConsent(consent)
    self.digestSHA256 = try HostedSemanticDigest.sha256(of: minimized)
    self.day = minimized
  }

  init(digestSHA256: String, day: HealthMdCompactContextDay) {
    self.digestSHA256 = digestSHA256
    self.day = day
  }

  enum CodingKeys: String, CodingKey {
    case digestSHA256 = "digest_sha256"
    case day
  }
}

extension HealthMdCompactContextDay {
  fileprivate nonisolated func applyingHostedConsent(
    _ consent: HostedLocalConsent
  ) throws -> HealthMdCompactContextDay {
    let retainedMetrics = metrics.filter { consent.metricIDs.contains($0.metricID) }
    let retainedWorkouts = consent.metricIDs.contains("workouts") ? workouts : []
    let retainedSleep = consent.metricIDs.contains("sleep_total") ? sleepSessions : []
    let referencedEvidenceIDs = Set(
      retainedMetrics.flatMap(\.evidenceIDs)
        + retainedWorkouts.flatMap(\.evidenceIDs)
        + retainedSleep.flatMap(\.evidenceIDs)
    )
    let retainedEvidence = evidence.filter { item in
      let evidenceMetrics = Set(item.metricIDs)
      return referencedEvidenceIDs.contains(item.reference.evidenceID)
        && !evidenceMetrics.isEmpty
        && evidenceMetrics.isSubset(of: consent.metricIDs)
        && consent.sourceIDs.contains(item.reference.sourceID)
        && item.reference.providerID.isNilOrSatisfies(consent.providerIDs.contains)
    }
    let retainedEvidenceIDs = Set(retainedEvidence.map(\.reference.evidenceID))
    let includeDetail = consent.maximumDetail == .lossless
    let projectedMetrics = retainedMetrics.map { metric in
      HealthMdContextMetric(
        observationID: metric.observationID,
        metricID: metric.metricID,
        displayName: metric.displayName,
        value: metric.value,
        status: metric.status,
        dailyAggregation: metric.dailyAggregation,
        evidenceIDs: metric.evidenceIDs.filter(retainedEvidenceIDs.contains),
        limitations: metric.limitations
      )
    }
    let projectedWorkouts = retainedWorkouts.map { workout in
      HealthMdContextWorkout(
        workoutID: workout.workoutID,
        activity: workout.activity,
        start: workout.start,
        end: workout.end,
        details: includeDetail ? workout.details : [:],
        evidenceIDs: workout.evidenceIDs.filter(retainedEvidenceIDs.contains)
      )
    }
    let projectedSleep = retainedSleep.map { session in
      HealthMdContextSleepSession(
        sessionID: session.sessionID,
        start: session.start,
        end: session.end,
        classification: session.classification,
        completeness: session.completeness,
        stageIntervals: includeDetail
          ? session.stageIntervals.filter {
            Self.sleepStageMetricID($0.stage).map(consent.metricIDs.contains) == true
          }
          : [],
        aggregateStageDurations: session.aggregateStageDurations.filter {
          Self.sleepStageMetricID($0.key).map(consent.metricIDs.contains) == true
        },
        evidenceIDs: session.evidenceIDs.filter(retainedEvidenceIDs.contains),
        limitations: session.limitations
      )
    }
    let placeholderSource = HealthMdSourceDescriptor(
      schema: source.schema,
      schemaVersion: source.schemaVersion,
      digest: String(repeating: "0", count: 64)
    )
    let placeholderEvidence = retainedEvidence.map { item in
      HealthMdContextEvidence(
        reference: Self.reference(item.reference, source: placeholderSource),
        value: includeDetail ? item.value : nil,
        note: includeDetail ? item.note : nil,
        metricIDs: item.metricIDs
      )
    }
    let placeholderDay = HealthMdCompactContextDay(
      ownerDate: ownerDate,
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      calendarTimeZone: calendarTimeZone,
      source: placeholderSource,
      status: status,
      metrics: projectedMetrics,
      workouts: projectedWorkouts,
      sleepSessions: projectedSleep,
      evidence: placeholderEvidence,
      limitations: limitations
    )
    let projectedSource = HealthMdSourceDescriptor(
      schema: source.schema,
      schemaVersion: source.schemaVersion,
      digest: try HostedSemanticDigest.sha256(of: placeholderDay)
    )
    let projectedEvidence = placeholderEvidence.map { item in
      HealthMdContextEvidence(
        reference: Self.reference(item.reference, source: projectedSource),
        value: item.value,
        note: item.note,
        metricIDs: item.metricIDs
      )
    }
    return HealthMdCompactContextDay(
      ownerDate: ownerDate,
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      calendarTimeZone: calendarTimeZone,
      source: projectedSource,
      status: status,
      metrics: projectedMetrics,
      workouts: projectedWorkouts,
      sleepSessions: projectedSleep,
      evidence: projectedEvidence,
      limitations: limitations
    )
  }

  fileprivate nonisolated static func sleepStageMetricID(_ stage: String) -> String? {
    switch stage.lowercased() {
    case "deep": "sleep_deep"
    case "rem": "sleep_rem"
    case "core": "sleep_core"
    case "awake": "sleep_awake"
    case "inbed", "in_bed": "sleep_in_bed"
    case "asleepunspecified", "asleep_unspecified", "unspecified", "asleep_total": "sleep_total"
    default: nil
    }
  }

  fileprivate nonisolated static func reference(
    _ reference: HealthMdEvidenceReference,
    source: HealthMdSourceDescriptor
  ) -> HealthMdEvidenceReference {
    HealthMdEvidenceReference(
      evidenceID: reference.evidenceID,
      locator: reference.locator,
      source: source,
      sourceID: reference.sourceID,
      providerID: reference.providerID
    )
  }
}

extension Optional where Wrapped == String {
  fileprivate nonisolated func isNilOrSatisfies(_ predicate: (String) -> Bool) -> Bool {
    guard let self else { return true }
    return predicate(self)
  }
}

nonisolated struct HostedSyncRequest: Encodable, Sendable {
  let expectedConsentRevision: UInt64
  let days: [HostedSyncDay]

  enum CodingKeys: String, CodingKey {
    case expectedConsentRevision = "expected_consent_revision"
    case days
  }
}

nonisolated struct HostedSyncResult: Decodable, Equatable, Sendable {
  let schema: String
  let schemaVersion: Int
  let consentRevision: UInt64
  let changedDayCount: Int
  let unchangedDayCount: Int

  enum CodingKeys: String, CodingKey {
    case schema
    case schemaVersion = "schema_version"
    case consentRevision = "consent_revision"
    case changedDayCount = "changed_day_count"
    case unchangedDayCount = "unchanged_day_count"
  }
}

nonisolated struct HostedAccountDeletion: Decodable, Equatable, Sendable {
  let schema: String
  let schemaVersion: Int
  let status: String

  enum CodingKeys: String, CodingKey {
    case schema
    case schemaVersion = "schema_version"
    case status
  }
}

nonisolated struct HostedAPIErrorEnvelope: Decodable, Equatable, Sendable {
  let error: String
  let message: String
  let retryable: Bool
}
