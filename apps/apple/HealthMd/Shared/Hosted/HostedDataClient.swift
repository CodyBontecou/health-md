import Foundation

nonisolated enum HostedDataClientError: LocalizedError, Equatable {
  case invalidRequest
  case unauthorized
  case consentRequired
  case consentRevisionStale
  case payloadTooLarge
  case temporarilyUnavailable
  case invalidResponse
  case server(code: String, retryable: Bool)

  var errorDescription: String? {
    switch self {
    case .invalidRequest:
      return "The hosted synchronization request is invalid."
    case .unauthorized:
      return "Hosted Health.md account authorization is required."
    case .consentRequired:
      return "Hosted synchronization consent must be reviewed before uploading."
    case .consentRevisionStale:
      return "Hosted synchronization consent changed. Refresh the account before retrying."
    case .payloadTooLarge:
      return "The hosted synchronization batch exceeded its safety limit."
    case .temporarilyUnavailable:
      return "Hosted Health.md synchronization is temporarily unavailable."
    case .invalidResponse:
      return "The hosted Health.md service returned an invalid response."
    case .server:
      return "The hosted Health.md service rejected the request."
    }
  }
}

nonisolated struct HostedDataClient: Sendable {
  nonisolated static let maximumDaysPerRequest = 31
  nonisolated static let maximumDayBytes = 2 * 1_024 * 1_024
  nonisolated static let maximumRequestBytes = 8 * 1_024 * 1_024
  private nonisolated static let maximumResponseBytes = 128 * 1_024

  private let loader: BoundedURLSessionDataLoader

  init(session: URLSession? = nil) {
    if let session {
      loader = BoundedURLSessionDataLoader(session: session)
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 60
      configuration.timeoutIntervalForResource = 120
      configuration.httpCookieStorage = nil
      configuration.urlCache = nil
      loader = BoundedURLSessionDataLoader(
        configuration: configuration,
        redirectHandler: { _, _ in nil }
      )
    }
  }

  func status(
    configuration: HostedAccountConfiguration,
    token: HostedOAuthToken
  ) async throws -> HostedControlStatus {
    let result: HostedControlStatus = try await request(
      method: "GET",
      path: "/data/v1/control-status",
      body: Optional<HostedConsentRequest>.none,
      configuration: configuration,
      token: token
    )
    guard result.schema == "healthmd.hosted_control_status",
      result.schemaVersion == 1,
      HostedOAuthToken.isValidOwnerBinding(result.ownerBinding),
      result.consentState == .missing || result.consentRevision != nil,
      result.consentRevision != 0
    else {
      throw HostedDataClientError.invalidResponse
    }
    return result
  }

  func replaceConsent(
    _ consent: HostedConsentRequest,
    configuration: HostedAccountConfiguration,
    token: HostedOAuthToken
  ) async throws -> HostedConsentResult {
    guard consent.revision > 0,
      !consent.allowedMetricIDs.isEmpty,
      consent.allowedMetricIDs.count <= 512,
      consent.allowedSourceIDs.count <= 512,
      consent.allowedProviderIDs.count <= 512,
      (1...3_650).contains(Int(consent.retentionDays)),
      Self.validIdentifiers(consent.allowedMetricIDs),
      Self.validIdentifiers(consent.allowedSourceIDs),
      Self.validIdentifiers(consent.allowedProviderIDs)
    else {
      throw HostedDataClientError.invalidRequest
    }
    let result: HostedConsentResult = try await request(
      method: "PUT",
      path: "/data/v1/consent",
      body: consent,
      configuration: configuration,
      token: token
    )
    try validate(result)
    return result
  }

  func upload(
    _ upload: HostedSyncRequest,
    configuration: HostedAccountConfiguration,
    token: HostedOAuthToken
  ) async throws -> HostedSyncResult {
    guard upload.expectedConsentRevision > 0,
      !upload.days.isEmpty,
      upload.days.count <= Self.maximumDaysPerRequest
    else {
      throw HostedDataClientError.invalidRequest
    }
    var ownerDates = Set<String>()
    for item in upload.days {
      let canonicalDay = try HealthMdQueryCanonicalSerializer.data(for: item.day)
      guard Self.validDayEnvelope(item.day),
        item.digestSHA256.range(
          of: "^[0-9a-f]{64}$",
          options: .regularExpression
        ) != nil,
        item.digestSHA256 == (try HostedSemanticDigest.sha256(of: item.day)),
        ownerDates.insert(item.day.ownerDate).inserted,
        canonicalDay.count <= Self.maximumDayBytes
      else {
        throw HostedDataClientError.invalidRequest
      }
    }
    let body = try HealthMdQueryCanonicalSerializer.data(for: upload)
    guard body.count <= Self.maximumRequestBytes else {
      throw HostedDataClientError.payloadTooLarge
    }
    let result: HostedSyncResult = try await request(
      method: "POST",
      path: "/data/v1/days",
      encodedBody: body,
      configuration: configuration,
      token: token
    )
    let accepted = result.changedDayCount.addingReportingOverflow(
      result.unchangedDayCount
    )
    guard result.schema == "healthmd.hosted_sync_result",
      result.schemaVersion == 1,
      result.consentRevision == upload.expectedConsentRevision,
      result.changedDayCount >= 0,
      result.unchangedDayCount >= 0,
      !accepted.overflow,
      accepted.partialValue == upload.days.count
    else {
      throw HostedDataClientError.invalidResponse
    }
    return result
  }

  func revokeConsent(
    _ revocation: HostedConsentRevocationRequest,
    configuration: HostedAccountConfiguration,
    token: HostedOAuthToken
  ) async throws -> HostedConsentResult {
    guard revocation.expectedRevision > 0,
      revocation.expectedRevision < UInt64.max,
      revocation.revision == revocation.expectedRevision + 1
    else {
      throw HostedDataClientError.invalidRequest
    }
    let result: HostedConsentResult = try await request(
      method: "DELETE",
      path: "/data/v1/consent",
      body: revocation,
      configuration: configuration,
      token: token
    )
    try validate(result)
    guard result.consentRevision == revocation.revision,
      result.consentState == "revoked"
    else {
      throw HostedDataClientError.invalidResponse
    }
    return result
  }

  func deleteAccount(
    configuration: HostedAccountConfiguration,
    token: HostedOAuthToken
  ) async throws -> HostedAccountDeletion {
    let result: HostedAccountDeletion = try await request(
      method: "DELETE",
      path: "/data/v1/account",
      body: Optional<HostedConsentRequest>.none,
      configuration: configuration,
      token: token
    )
    guard result.schema == "healthmd.hosted_account_deletion",
      result.schemaVersion == 1,
      result.status == "deleted"
    else {
      throw HostedDataClientError.invalidResponse
    }
    return result
  }

  private func request<Body: Encodable, Response: Decodable>(
    method: String,
    path: String,
    body: Body?,
    configuration: HostedAccountConfiguration,
    token: HostedOAuthToken
  ) async throws -> Response {
    let encoded = try body.map { try HealthMdQueryCanonicalSerializer.data(for: $0) }
    return try await request(
      method: method,
      path: path,
      encodedBody: encoded,
      configuration: configuration,
      token: token
    )
  }

  private func request<Response: Decodable>(
    method: String,
    path: String,
    encodedBody: Data?,
    configuration: HostedAccountConfiguration,
    token: HostedOAuthToken
  ) async throws -> Response {
    guard configuration.isValid,
      token.canUse(configuration: configuration),
      let origin = configuration.apiOrigin,
      let url = URL(string: path, relativeTo: origin)?.absoluteURL,
      url.scheme == origin.scheme,
      url.host == origin.host,
      url.port == origin.port,
      encodedBody?.count ?? 0 <= Self.maximumRequestBytes
    else {
      throw HostedDataClientError.invalidRequest
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
    if let encodedBody {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = encodedBody
    }
    let data: Data
    let response: HTTPURLResponse
    do {
      let loaded = try await loader.data(
        for: request,
        maximumBytes: Self.maximumResponseBytes
      )
      guard let http = loaded.1 as? HTTPURLResponse,
        http.url == url
      else { throw HostedDataClientError.invalidResponse }
      data = loaded.0
      response = http
    } catch is BoundedURLSessionDataLoaderError {
      throw HostedDataClientError.invalidResponse
    }
    guard
      response.value(forHTTPHeaderField: "Content-Type")?
        .lowercased().split(separator: ";", maxSplits: 1).first?
        .trimmingCharacters(in: .whitespaces) == "application/json",
      response.value(forHTTPHeaderField: "Cache-Control")?
        .lowercased().split(separator: ",")
        .map({ $0.trimmingCharacters(in: .whitespaces) })
        .contains("no-store") == true
    else {
      throw HostedDataClientError.invalidResponse
    }
    guard (200..<300).contains(response.statusCode) else {
      throw Self.error(from: data, status: response.statusCode)
    }
    do {
      try Self.validateResponseKeys(data, responseType: Response.self)
      return try JSONDecoder.healthMdHosted.decode(Response.self, from: data)
    } catch {
      throw HostedDataClientError.invalidResponse
    }
  }

  private static func validateResponseKeys<Response>(
    _ data: Data,
    responseType: Response.Type
  ) throws {
    let expectedKeys: Set<String>
    if responseType == HostedControlStatus.self {
      expectedKeys = [
        "schema", "schema_version", "owner_binding", "consent_revision", "consent_state",
      ]
    } else if responseType == HostedConsentResult.self {
      expectedKeys = ["schema", "schema_version", "consent_revision", "consent_state"]
    } else if responseType == HostedSyncResult.self {
      expectedKeys = [
        "schema", "schema_version", "consent_revision", "changed_day_count",
        "unchanged_day_count",
      ]
    } else if responseType == HostedAccountDeletion.self {
      expectedKeys = ["schema", "schema_version", "status"]
    } else {
      throw HostedDataClientError.invalidResponse
    }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(object.keys) == expectedKeys
    else {
      throw HostedDataClientError.invalidResponse
    }
  }

  private func validate(_ result: HostedConsentResult) throws {
    guard result.schema == "healthmd.hosted_consent_result",
      result.schemaVersion == 1,
      result.consentRevision > 0,
      ["active", "revoked"].contains(result.consentState)
    else {
      throw HostedDataClientError.invalidResponse
    }
  }

  private static func error(from data: Data, status: Int) -> HostedDataClientError {
    guard data.count <= maximumResponseBytes,
      let envelope = try? JSONDecoder().decode(HostedAPIErrorEnvelope.self, from: data),
      !envelope.error.isEmpty,
      envelope.error.utf8.count <= 128
    else {
      return status == 401 ? .unauthorized : .invalidResponse
    }
    switch envelope.error {
    case "healthmd_scope_required", "healthmd_identity_invalid": return .unauthorized
    case "healthmd_consent_required", "healthmd_consent_expired": return .consentRequired
    case "healthmd_consent_revision_stale": return .consentRevisionStale
    case "healthmd_sync_too_large", "healthmd_sync_day_too_large": return .payloadTooLarge
    case "healthmd_storage_unavailable": return .temporarilyUnavailable
    default: return .server(code: envelope.error, retryable: envelope.retryable)
    }
  }

  private static func validDayEnvelope(_ day: HealthMdCompactContextDay) -> Bool {
    guard day.schema == HealthMdQuerySchemas.compactContextDay,
      day.schemaVersion == 1,
      HostedOwnerDate.isValid(day.ownerDate),
      let timeZone = TimeZone(identifier: day.calendarTimeZone),
      day.intervalStart < day.intervalEnd,
      day.intervalEnd <= Date().addingTimeInterval(5 * 60)
    else {
      return false
    }
    let duration = day.intervalEnd.timeIntervalSince(day.intervalStart)
    guard (23 * 60 * 60...25 * 60 * 60).contains(duration) else { return false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard calendar.startOfDay(for: day.intervalStart) == day.intervalStart,
      calendar.startOfDay(for: day.intervalEnd) == day.intervalEnd,
      let expectedEnd = calendar.date(byAdding: .day, value: 1, to: day.intervalStart),
      expectedEnd == day.intervalEnd
    else {
      return false
    }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: day.intervalStart) == day.ownerDate
  }

  private static func validIdentifiers(_ values: [String]) -> Bool {
    values.allSatisfy {
      !$0.isEmpty
        && $0.utf8.count <= 128
        && $0.range(of: "^[a-z0-9][a-z0-9._-]*$", options: .regularExpression) != nil
    }
  }
}

extension JSONDecoder {
  fileprivate nonisolated static var healthMdHosted: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}
