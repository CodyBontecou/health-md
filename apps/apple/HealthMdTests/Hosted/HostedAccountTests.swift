import XCTest

@testable import HealthMd

final class HostedAccountTests: XCTestCase {
  private static let ownerBinding = String(repeating: "a", count: 64)
  private static let otherOwnerBinding = String(repeating: "b", count: 64)
  private static let journalBinding = HostedSyncJournalBinding(
    resourceURL: URL(string: "https://mcp.example.com/mcp")!,
    clientID: "healthmd-ios",
    issuer: URL(string: "https://auth.example.com")!,
    ownerBinding: ownerBinding
  )

  override func tearDown() {
    HostedURLProtocol.handler = nil
    super.tearDown()
  }

  func testHostedSemanticDigestMatchesRustNumberVector() throws {
    XCTAssertEqual(
      try HostedSemanticDigest.sha256(of: HostedSemanticDigestVector()),
      "5d0d96bafe03fda7bf96bb30e2a2a036c56dc66587199b2b5aaae95b48d63543"
    )
  }

  func testHostedSemanticDigestMatchesRustQueryValueVector() throws {
    let timestamp = ISO8601DateFormatter().date(from: "2026-07-01T12:34:56Z")!
    let vector = HostedSemanticQueryValueVector(values: [
      .quantity(value: 1.5, unit: "kg"),
      .duration(seconds: 60.25),
      .count(-2),
      .string("é"),
      .category(.init(identifier: "high", display: "High", rawValue: 7)),
      .boolean(true),
      .timestamp(timestamp),
      .date("2026-07-01"),
      .array([.count(1), .boolean(false)]),
    ])
    XCTAssertEqual(
      try HostedSemanticDigest.sha256(of: vector),
      "ed073cb3170128c3f5378e81c209434c213514060e144b8affde5bf9624eab08"
    )
  }

  func testHostedSemanticDigestMatchesRustExponentBoundaries() throws {
    XCTAssertEqual(
      try HostedSemanticDigest.sha256(of: HostedSemanticExponentBoundaryVector()),
      "2f565ccf5c4028ef12f5860edf88e34647a3fa9a64e9150a6cdc61ef5bf4e989"
    )
  }

  func testHostedConfigurationRequiresCanonicalCredentialFreeResource() {
    XCTAssertTrue(
      HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      ).isValid)
    for value in [
      "https://mcp.example.com/",
      "https://user@mcp.example.com/mcp",
      "https://mcp.example.com/mcp?target=other",
      "https://mcp.example.com/mcp#fragment",
      "http://mcp.example.com/mcp",
    ] {
      XCTAssertFalse(
        HostedAccountConfiguration(
          resourceURL: URL(string: value)!,
          clientID: "healthmd-ios"
        ).isValid)
    }
  }

  func testOAuthDiscoveryPKCEAndTokenExchangeUseExactResource() async throws {
    let session = Self.session()
    let configuration = HostedAccountConfiguration(
      resourceURL: URL(string: "https://mcp.example.com/mcp")!,
      clientID: "healthmd-ios"
    )
    HostedURLProtocol.handler = { request in
      switch request.url?.path {
      case "/.well-known/oauth-protected-resource/mcp":
        return Self.response(
          request,
          body:
            #"{"resource":"https://mcp.example.com/mcp","authorization_servers":["https://auth.example.com"],"scopes_supported":["health.sync.write","health.account.manage"]}"#
        )
      case "/.well-known/oauth-authorization-server":
        return Self.response(
          request,
          body:
            #"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","code_challenge_methods_supported":["S256"]}"#
        )
      case "/token":
        XCTAssertEqual(request.httpMethod, "POST")
        let body = String(decoding: try Self.requestBody(request), as: UTF8.self)
        XCTAssertTrue(body.contains("grant_type=authorization_code"))
        XCTAssertTrue(body.contains("code_verifier=\(String(repeating: "v", count: 43))"))
        XCTAssertTrue(body.contains("resource=https://mcp.example.com/mcp"))
        return Self.response(
          request,
          body:
            #"{"access_token":"access","refresh_token":"refresh","token_type":"Bearer","expires_in":3600,"scope":"health.sync.write health.account.manage"}"#,
          noStore: true
        )
      default:
        XCTFail("Unexpected URL: \(request.url?.absoluteString ?? "nil")")
        return Self.response(request, status: 404, body: "{}")
      }
    }

    let client = HostedOAuthClient(session: session)
    let authorization = try await client.beginAuthorization(
      configuration: configuration,
      state: String(repeating: "s", count: 32),
      codeVerifier: String(repeating: "v", count: 43)
    )
    let query = try XCTUnwrap(
      URLComponents(
        url: authorization.url,
        resolvingAgainstBaseURL: false
      )?.queryItems)
    XCTAssertEqual(
      query.first(where: { $0.name == "resource" })?.value, configuration.resourceURL.absoluteString
    )
    XCTAssertEqual(
      query.first(where: { $0.name == "state" })?.value,
      String(repeating: "s", count: 32)
    )
    XCTAssertEqual(
      query.first(where: { $0.name == "code_challenge" })?.value,
      HostedOAuthClient.codeChallenge(String(repeating: "v", count: 43))
    )

    let token = try await client.exchange(
      code: "code",
      authorization: authorization,
      configuration: configuration
    )
    XCTAssertTrue(token.canManageAndSync)
    XCTAssertTrue(token.canUse(configuration: configuration))
    XCTAssertEqual(token.issuer, URL(string: "https://auth.example.com")!)
    XCTAssertEqual(token.refreshToken, "refresh")

    HostedURLProtocol.handler = { request in
      let body = String(decoding: try Self.requestBody(request), as: UTF8.self)
      XCTAssertTrue(body.contains("grant_type=refresh_token"))
      XCTAssertTrue(body.contains("refresh_token=refresh"))
      XCTAssertTrue(body.contains("resource=https://mcp.example.com/mcp"))
      return Self.response(
        request,
        body:
          #"{"access_token":"access-rotated","refresh_token":"refresh-rotated","token_type":"Bearer","expires_in":3600,"scope":"health.sync.write health.account.manage"}"#,
        noStore: true
      )
    }
    let boundToken = try token.bound(to: Self.ownerBinding)
    let refreshed = try await client.refresh(
      boundToken,
      endpoints: authorization.endpoints,
      configuration: configuration
    )
    XCTAssertEqual(refreshed.accessToken, "access-rotated")
    XCTAssertEqual(refreshed.refreshToken, "refresh-rotated")
    XCTAssertEqual(refreshed.issuer, token.issuer)
    XCTAssertEqual(refreshed.ownerBinding, Self.ownerBinding)

    HostedURLProtocol.handler = { request in
      Self.response(
        request,
        body:
          #"{"access_token":"access","token_type":"Bearer","scope":"health.sync.write health.account.manage"}"#
      )
    }
    do {
      _ = try await client.exchange(
        code: "code",
        authorization: authorization,
        configuration: configuration
      )
      XCTFail("Token responses without no-store must fail")
    } catch let error as HostedOAuthError {
      XCTAssertEqual(error, .invalidToken)
    }

    HostedURLProtocol.handler = { request in
      Self.response(
        request,
        body:
          #"{"access_token":"over-scoped","refresh_token":"refresh","token_type":"Bearer","expires_in":3600,"scope":"health.sync.write health.account.manage health.summary.read"}"#,
        noStore: true
      )
    }
    do {
      _ = try await client.exchange(
        code: "code",
        authorization: authorization,
        configuration: configuration
      )
      XCTFail("Mobile OAuth tokens with read scopes must fail closed")
    } catch let error as HostedOAuthError {
      XCTAssertEqual(error, .insufficientScope)
    }

    HostedURLProtocol.handler = { request in
      Self.response(
        request,
        status: 400,
        body: #"{"error":"invalid_grant"}"#,
        noStore: true
      )
    }
    do {
      _ = try await client.refresh(
        boundToken,
        endpoints: authorization.endpoints,
        configuration: configuration
      )
      XCTFail("A definitive invalid_grant must be distinguished")
    } catch let error as HostedOAuthError {
      XCTAssertEqual(error, .invalidGrant)
    }
  }

  func testHostedDataClientBindsConsentUploadAndNoStoreResponses() async throws {
    let session = Self.session()
    let configuration = HostedAccountConfiguration(
      resourceURL: URL(string: "https://mcp.example.com/mcp")!,
      clientID: "healthmd-ios"
    )
    let token = HostedOAuthToken(
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      scopes: HostedAccountConfiguration.requiredScopes,
      expiresAt: Date().addingTimeInterval(3_600),
      resourceURL: configuration.resourceURL,
      clientID: configuration.clientID,
      issuer: URL(string: "https://auth.example.com")!
    )
    let requestIndex = HostedLockedBox(0)
    HostedURLProtocol.handler = { request in
      requestIndex.withValue { $0 += 1 }
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
      switch request.url?.path {
      case "/data/v1/consent":
        XCTAssertEqual(request.httpMethod, "PUT")
        return Self.response(
          request,
          body:
            #"{"schema":"healthmd.hosted_consent_result","schema_version":1,"consent_revision":1,"consent_state":"active"}"#,
          noStore: true
        )
      case "/data/v1/days":
        XCTAssertEqual(request.httpMethod, "POST")
        let value =
          try JSONSerialization.jsonObject(with: try Self.requestBody(request)) as? [String: Any]
        XCTAssertEqual(value?["expected_consent_revision"] as? Int, 1)
        return Self.response(
          request,
          body:
            #"{"schema":"healthmd.hosted_sync_result","schema_version":1,"consent_revision":1,"changed_day_count":1,"unchanged_day_count":0}"#,
          noStore: true
        )
      default:
        return Self.response(request, status: 404, body: "{}", noStore: true)
      }
    }
    let client = HostedDataClient(session: session)
    let consent = try await client.replaceConsent(
      HostedConsentRequest(
        revision: 1,
        allowedMetricIDs: ["steps"],
        allowedSourceIDs: ["apple_health", "healthmd_summary"],
        allowedProviderIDs: [],
        maximumDetail: .summary,
        retentionDays: 365,
        expiresAt: nil
      ),
      configuration: configuration,
      token: token
    )
    XCTAssertEqual(consent.consentRevision, 1)

    let day = HealthMdCompactContextDay(
      ownerDate: "2025-07-01",
      intervalStart: Date(timeIntervalSince1970: 1_751_328_000),
      intervalEnd: Date(timeIntervalSince1970: 1_751_414_400),
      calendarTimeZone: "UTC",
      source: .init(
        schema: HealthMdQuerySchemas.compactContextDay,
        schemaVersion: 1,
        digest: String(repeating: "a", count: 64)
      ),
      status: .completeEmpty
    )
    let digest = try HostedSemanticDigest.sha256(of: day)
    let result = try await client.upload(
      .init(
        expectedConsentRevision: 1,
        days: [.init(digestSHA256: digest, day: day)]
      ),
      configuration: configuration,
      token: token
    )
    XCTAssertEqual(result.changedDayCount, 1)
    XCTAssertEqual(requestIndex.value, 2)
  }

  func testHostedStatusRejectsInconsistentUntrustedMetadata() async throws {
    let session = Self.session()
    let configuration = HostedAccountConfiguration(
      resourceURL: URL(string: "https://mcp.example.com/mcp")!,
      clientID: "healthmd-ios"
    )
    let token = HostedOAuthToken(
      accessToken: "access",
      refreshToken: nil,
      tokenType: "Bearer",
      scopes: HostedAccountConfiguration.requiredScopes,
      expiresAt: nil,
      resourceURL: configuration.resourceURL,
      clientID: configuration.clientID,
      issuer: URL(string: "https://auth.example.com")!
    )
    let valid = HostedLockedBox(true)
    HostedURLProtocol.handler = { request in
      if valid.value {
        return Self.response(
          request,
          body:
            #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":null,"consent_state":"missing"}"#,
          noStore: true
        )
      }
      return Self.response(
        request,
        body:
          #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_state":"active"}"#,
        noStore: true
      )
    }
    let client = HostedDataClient(session: session)
    let status = try await client.status(configuration: configuration, token: token)
    XCTAssertEqual(status.consentState, .missing)
    valid.value = false
    do {
      _ = try await client.status(configuration: configuration, token: token)
      XCTFail("Inconsistent hosted status must fail closed")
    } catch let error as HostedDataClientError {
      XCTAssertEqual(error, .invalidResponse)
    }

    HostedURLProtocol.handler = { request in
      Self.response(
        request,
        body:
          #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":null,"consent_state":"missing","dataset_revision":99}"#,
        noStore: true
      )
    }
    do {
      _ = try await client.status(configuration: configuration, token: token)
      XCTFail("Health-bearing or unknown response fields must fail closed")
    } catch let error as HostedDataClientError {
      XCTAssertEqual(error, .invalidResponse)
    }
  }

  func testHostedDataClientRejectsMismatchedDayDigestBeforeDispatch() async throws {
    let session = Self.session()
    HostedURLProtocol.handler = { request in
      XCTFail("A digest-mismatched day must not reach the network")
      return Self.response(request, body: "{}", noStore: true)
    }
    let configuration = HostedAccountConfiguration(
      resourceURL: URL(string: "https://mcp.example.com/mcp")!,
      clientID: "healthmd-ios"
    )
    let token = HostedOAuthToken(
      accessToken: "access",
      refreshToken: nil,
      tokenType: "Bearer",
      scopes: HostedAccountConfiguration.requiredScopes,
      expiresAt: nil,
      resourceURL: configuration.resourceURL,
      clientID: configuration.clientID,
      issuer: URL(string: "https://auth.example.com")!
    )
    let day = HealthMdCompactContextDay(
      ownerDate: "2026-07-01",
      intervalStart: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!,
      intervalEnd: ISO8601DateFormatter().date(from: "2026-07-02T00:00:00Z")!,
      calendarTimeZone: "UTC",
      source: .init(
        schema: HealthMdQuerySchemas.compactContextDay,
        schemaVersion: 1,
        digest: String(repeating: "a", count: 64)
      ),
      status: .completeEmpty
    )
    do {
      _ = try await HostedDataClient(session: session).upload(
        .init(
          expectedConsentRevision: 1,
          days: [
            .init(
              digestSHA256: String(repeating: "b", count: 64),
              day: day
            )
          ]
        ),
        configuration: configuration,
        token: token
      )
      XCTFail("Digest mismatch must fail")
    } catch let error as HostedDataClientError {
      XCTAssertEqual(error, .invalidRequest)
    }

    XCTAssertFalse(HostedOwnerDate.isValid("1899-12-31"))
    XCTAssertTrue(HostedOwnerDate.isValid("1900-01-01"))

    let invalidDateDay = HealthMdCompactContextDay(
      ownerDate: "2026-02-30",
      intervalStart: day.intervalStart,
      intervalEnd: day.intervalEnd,
      calendarTimeZone: day.calendarTimeZone,
      source: day.source,
      status: day.status
    )
    do {
      _ = try await HostedDataClient(session: session).upload(
        .init(
          expectedConsentRevision: 1,
          days: [
            .init(
              digestSHA256: try HostedSemanticDigest.sha256(of: invalidDateDay),
              day: invalidDateDay
            )
          ]
        ),
        configuration: configuration,
        token: token
      )
      XCTFail("Invalid owner dates must fail before dispatch")
    } catch let error as HostedDataClientError {
      XCTAssertEqual(error, .invalidRequest)
    }
  }

  func testHostedSyncDayAppliesMetricSourceProviderAndDetailConsent() throws {
    let source = HealthMdSourceDescriptor(
      schema: HealthMdQuerySchemas.compactContextDay,
      schemaVersion: 1,
      digest: String(repeating: "a", count: 64)
    )
    let allowedEvidence = HealthMdContextEvidence(
      reference: .init(
        evidenceID: "allowed",
        locator: .summaryKey(ownerDate: "2026-07-01", key: "steps"),
        source: source,
        sourceID: "healthmd_summary"
      ),
      value: .count(42),
      note: "detail",
      metricIDs: ["steps"]
    )
    let providerEvidence = HealthMdContextEvidence(
      reference: .init(
        evidenceID: "provider",
        locator: .externalIdentity(ownerDate: "2026-07-01", identifier: "provider"),
        source: source,
        sourceID: "provider_native",
        providerID: "oura"
      ),
      value: .string("private"),
      metricIDs: ["steps"]
    )
    let day = HealthMdCompactContextDay(
      ownerDate: "2026-07-01",
      intervalStart: Date(timeIntervalSince1970: 100),
      intervalEnd: Date(timeIntervalSince1970: 200),
      calendarTimeZone: "UTC",
      source: source,
      status: .available,
      metrics: [
        .init(
          observationID: "steps",
          metricID: "steps",
          displayName: "Steps",
          value: .count(42),
          status: .available,
          evidenceIDs: ["allowed", "provider"]
        ),
        .init(
          observationID: "weight",
          metricID: "weight",
          displayName: "Weight",
          value: .quantity(value: 70, unit: "kg"),
          status: .available,
          evidenceIDs: []
        ),
      ],
      workouts: [
        .init(
          workoutID: "workout",
          activity: "Run",
          start: Date(timeIntervalSince1970: 110),
          end: Date(timeIntervalSince1970: 120),
          details: ["distance": .quantity(value: 1, unit: "km")],
          evidenceIDs: []
        )
      ],
      evidence: [allowedEvidence, providerEvidence]
    )
    let consent = HostedLocalConsent(
      revision: 1,
      metricIDs: ["steps", "workouts"],
      sourceIDs: ["healthmd_summary"],
      providerIDs: [],
      maximumDetail: .summary,
      retentionDays: 30,
      resourceURL: URL(string: "https://mcp.example.com/mcp")!,
      clientID: "healthmd-ios",
      issuer: URL(string: "https://auth.example.com")!,
      ownerBinding: Self.ownerBinding,
      automaticSyncEnabled: false
    )
    let synchronized = try HostedSyncDay(day: day, consent: consent)
    XCTAssertEqual(synchronized.day.metrics.map(\.metricID), ["steps"])
    XCTAssertEqual(synchronized.day.workouts.count, 1)
    XCTAssertTrue(synchronized.day.workouts[0].details.isEmpty)
    XCTAssertEqual(synchronized.day.evidence.map(\.reference.evidenceID), ["allowed"])
    XCTAssertNil(synchronized.day.evidence[0].value)
    XCTAssertNil(synchronized.day.evidence[0].note)
    XCTAssertEqual(synchronized.day.metrics[0].evidenceIDs, ["allowed"])
    XCTAssertEqual(
      synchronized.digestSHA256,
      try HostedSemanticDigest.sha256(of: synchronized.day)
    )

    let changedSource = HealthMdSourceDescriptor(
      schema: source.schema,
      schemaVersion: source.schemaVersion,
      digest: String(repeating: "b", count: 64)
    )
    let changedUnselectedDay = HealthMdCompactContextDay(
      ownerDate: day.ownerDate,
      intervalStart: day.intervalStart,
      intervalEnd: day.intervalEnd,
      calendarTimeZone: day.calendarTimeZone,
      source: changedSource,
      status: day.status,
      metrics: [
        day.metrics[0],
        .init(
          observationID: "weight",
          metricID: "weight",
          displayName: "Weight",
          value: .quantity(value: 99, unit: "kg"),
          status: .available
        ),
      ],
      workouts: day.workouts,
      evidence: day.evidence.map { item in
        HealthMdContextEvidence(
          reference: .init(
            evidenceID: item.reference.evidenceID,
            locator: item.reference.locator,
            source: changedSource,
            sourceID: item.reference.sourceID,
            providerID: item.reference.providerID
          ),
          value: item.value,
          note: item.note,
          metricIDs: item.metricIDs
        )
      }
    )
    let changedUnselected = try HostedSyncDay(
      day: changedUnselectedDay,
      consent: consent
    )
    XCTAssertEqual(changedUnselected.day, synchronized.day)
    XCTAssertEqual(changedUnselected.digestSHA256, synchronized.digestSHA256)
  }

  func testHostedProjectionDropsMixedMetricEvidenceBeforeHashing() throws {
    let source = HealthMdSourceDescriptor(
      schema: HealthMdQuerySchemas.compactContextDay,
      schemaVersion: 1,
      digest: String(repeating: "a", count: 64)
    )
    let evidence = HealthMdContextEvidence(
      reference: .init(
        evidenceID: "mixed",
        locator: .summaryKey(ownerDate: "2026-07-01", key: "mixed"),
        source: source,
        sourceID: "healthmd_summary"
      ),
      value: .string("contains broader evidence"),
      metricIDs: ["steps", "weight"]
    )
    let day = HealthMdCompactContextDay(
      ownerDate: "2026-07-01",
      intervalStart: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!,
      intervalEnd: ISO8601DateFormatter().date(from: "2026-07-02T00:00:00Z")!,
      calendarTimeZone: "UTC",
      source: source,
      status: .available,
      metrics: [
        .init(
          observationID: "steps",
          metricID: "steps",
          displayName: "Steps",
          value: .count(1),
          status: .available,
          evidenceIDs: ["mixed"]
        )
      ],
      evidence: [evidence]
    )
    let consent = HostedLocalConsent(
      revision: 1,
      metricIDs: ["steps"],
      sourceIDs: ["apple_health", "healthmd_summary"],
      providerIDs: [],
      maximumDetail: .lossless,
      retentionDays: 30,
      resourceURL: URL(string: "https://mcp.example.com/mcp")!,
      clientID: "healthmd-ios",
      issuer: URL(string: "https://auth.example.com")!,
      ownerBinding: Self.ownerBinding,
      automaticSyncEnabled: false
    )
    let projected = try HostedSyncDay(day: day, consent: consent).day
    XCTAssertTrue(projected.evidence.isEmpty)
    XCTAssertTrue(projected.metrics[0].evidenceIDs.isEmpty)
  }

  func testHostedSleepProjectionFiltersEveryUnconsentedStage() throws {
    let source = HealthMdSourceDescriptor(
      schema: HealthMdQuerySchemas.compactContextDay,
      schemaVersion: 1,
      digest: String(repeating: "a", count: 64)
    )
    let start = ISO8601DateFormatter().date(from: "2026-07-01T23:00:00Z")!
    let end = ISO8601DateFormatter().date(from: "2026-07-02T07:00:00Z")!
    let day = HealthMdCompactContextDay(
      ownerDate: "2026-07-01",
      intervalStart: ISO8601DateFormatter().date(from: "2026-07-01T00:00:00Z")!,
      intervalEnd: ISO8601DateFormatter().date(from: "2026-07-02T00:00:00Z")!,
      calendarTimeZone: "UTC",
      source: source,
      status: .available,
      sleepSessions: [
        .init(
          sessionID: "sleep",
          start: start,
          end: end,
          classification: .overnight,
          completeness: .complete,
          stageIntervals: [
            .init(stage: "deep", start: start, end: start.addingTimeInterval(3_600)),
            .init(stage: "awake", start: end.addingTimeInterval(-600), end: end),
          ],
          aggregateStageDurations: [
            "asleep_total": 25_200,
            "deep": 3_600,
            "awake": 600,
          ]
        )
      ]
    )
    let summary = HostedLocalConsent(
      revision: 1,
      metricIDs: ["sleep_total"],
      sourceIDs: ["apple_health", "healthmd_summary"],
      providerIDs: [],
      maximumDetail: .summary,
      retentionDays: 30,
      resourceURL: URL(string: "https://mcp.example.com/mcp")!,
      clientID: "healthmd-ios",
      issuer: URL(string: "https://auth.example.com")!,
      ownerBinding: Self.ownerBinding,
      automaticSyncEnabled: false
    )
    XCTAssertTrue(summary.localCaptureMetricIDs.contains("sleep_bedtime"))
    XCTAssertTrue(summary.localCaptureMetricIDs.contains("sleep_wake"))
    XCTAssertFalse(summary.localCaptureMetricIDs.contains("sleep_deep"))
    let summaryDay = try HostedSyncDay(day: day, consent: summary).day
    XCTAssertTrue(summaryDay.sleepSessions[0].stageIntervals.isEmpty)
    XCTAssertEqual(
      summaryDay.sleepSessions[0].aggregateStageDurations,
      ["asleep_total": 25_200]
    )

    let lossless = HostedLocalConsent(
      revision: 2,
      metricIDs: ["sleep_total", "sleep_deep"],
      sourceIDs: summary.sourceIDs,
      providerIDs: [],
      maximumDetail: .lossless,
      retentionDays: 30,
      resourceURL: summary.resourceURL,
      clientID: summary.clientID,
      issuer: summary.issuer,
      ownerBinding: summary.ownerBinding,
      automaticSyncEnabled: false
    )
    let losslessDay = try HostedSyncDay(day: day, consent: lossless).day
    XCTAssertEqual(losslessDay.sleepSessions[0].stageIntervals.map(\.stage), ["deep"])
    XCTAssertEqual(
      losslessDay.sleepSessions[0].aggregateStageDurations,
      ["asleep_total": 25_200, "deep": 3_600]
    )
  }

  func testHostedJournalIsRevisionBoundAndRejectsCorruption() async throws {
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let store = try HostedSyncJournalStore(baseDirectory: temporary)
    let firstDigest = String(repeating: "a", count: 64)
    do {
      try await store.record(
        binding: Self.journalBinding,
        consentRevision: 1,
        days: ["2026-02-30": firstDigest]
      )
      XCTFail("Invalid calendar dates must be rejected")
    } catch let error as HostedSyncJournalError {
      XCTAssertEqual(error, .invalidState)
    }
    try await store.record(
      binding: Self.journalBinding,
      consentRevision: 1,
      days: ["2026-07-01": firstDigest],
      synchronizedAt: Date(timeIntervalSince1970: 100)
    )
    var snapshot = try await store.snapshot(binding: Self.journalBinding)
    XCTAssertEqual(snapshot.consentRevision, 1)
    XCTAssertEqual(snapshot.dayDigests["2026-07-01"], firstDigest)

    let secondDigest = String(repeating: "b", count: 64)
    try await store.record(
      binding: Self.journalBinding,
      consentRevision: 2,
      days: ["2026-07-02": secondDigest]
    )
    snapshot = try await store.snapshot(binding: Self.journalBinding)
    XCTAssertEqual(snapshot.consentRevision, 2)
    XCTAssertNil(snapshot.dayDigests["2026-07-01"])
    XCTAssertEqual(snapshot.dayDigests["2026-07-02"], secondDigest)
    let otherBinding = HostedSyncJournalBinding(
      resourceURL: Self.journalBinding.resourceURL,
      clientID: Self.journalBinding.clientID,
      issuer: Self.journalBinding.issuer,
      ownerBinding: Self.otherOwnerBinding
    )
    do {
      _ = try await store.snapshot(binding: otherBinding)
      XCTFail("A journal from another owner must fail closed")
    } catch let error as HostedSyncJournalError {
      XCTAssertEqual(error, .invalidState)
    }

    let journal =
      temporary
      .appendingPathComponent("Health.md/Hosted/v1/sync-journal.json")
    try Data(#"{"schema":"wrong"}"#.utf8).write(to: journal)
    do {
      _ = try await store.snapshot(binding: Self.journalBinding)
      XCTFail("Corrupt hosted journals must fail closed")
    } catch let error as HostedSyncJournalError {
      XCTAssertEqual(error, .invalidState)
    }
  }

  #if os(iOS)
    @MainActor
    func testPendingDeletionBlocksConsentUntilStatusReconciles() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "access",
        refreshToken: "refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let localConsent = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      try store.save(localConsent)
      try store.save(
        HostedPendingMutation(
          kind: .deleteAccount,
          expectedRevision: nil,
          targetRevision: nil,
          previousConsentState: nil,
          previousConsent: localConsent,
          proposedConsent: nil,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: issuer,
          ownerBinding: Self.ownerBinding,
          createdAt: Date()
        ))
      let requestCount = HostedLockedBox(0)
      HostedURLProtocol.handler = { request in
        requestCount.withValue { $0 += 1 }
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/data/v1/control-status"):
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":null,"consent_state":"missing"}"#,
            noStore: true
          )
        case ("DELETE", "/data/v1/account"):
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_account_deletion","schema_version":1,"status":"deleted"}"#,
            noStore: true
          )
        default:
          XCTFail(
            "Unexpected request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
          return Self.response(request, status: 404, body: "{}", noStore: true)
        }
      }
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let journal = try HostedSyncJournalStore(baseDirectory: temporary)
      try await journal.record(
        binding: Self.journalBinding,
        consentRevision: 1,
        days: ["2026-07-01": String(repeating: "c", count: 64)]
      )
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: journal
      )
      XCTAssertTrue(manager.isConnected)
      XCTAssertTrue(manager.hasPendingMutation)
      XCTAssertNil(manager.consent)

      await manager.activateConsent(metricIDs: ["steps"], detail: .summary, retentionDays: 30)
      XCTAssertEqual(requestCount.value, 0)
      XCTAssertTrue(manager.hasPendingMutation)

      keychain.failRemoval(keySuffix: "oauthToken.v1")
      await manager.refreshStatus()
      XCTAssertEqual(requestCount.value, 2)
      XCTAssertTrue(manager.hasPendingMutation)
      XCTAssertTrue(manager.isConnected)
      XCTAssertNotNil(store.token())
      XCTAssertTrue(store.hasPendingMutationRecord())
      let resetJournal = try await journal.snapshot(binding: Self.journalBinding)
      XCTAssertTrue(resetJournal.dayDigests.isEmpty)

      keychain.allowRemovals()
      await manager.refreshStatus()
      XCTAssertEqual(requestCount.value, 4)
      XCTAssertFalse(manager.hasPendingMutation)
      XCTAssertFalse(manager.isConnected)
      XCTAssertNil(store.token())
      XCTAssertFalse(store.hasPendingMutationRecord())
    }

    @MainActor
    func testConsentPersistenceFailureRetainsTombstoneAndRecovers() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "access",
        refreshToken: "refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let previous = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps", "weight"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      try store.save(previous)
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let journal = try HostedSyncJournalStore(baseDirectory: temporary)
      let requestCount = HostedLockedBox(0)
      HostedURLProtocol.handler = { request in
        requestCount.withValue { $0 += 1 }
        switch (request.httpMethod, request.url?.path) {
        case ("PUT", "/data/v1/consent"):
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_consent_result","schema_version":1,"consent_revision":2,"consent_state":"active"}"#,
            noStore: true
          )
        case ("GET", "/data/v1/control-status"):
          let body =
            requestCount.value == 1
            ? #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":1,"consent_state":"active"}"#
            : #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":2,"consent_state":"active"}"#
          return Self.response(request, body: body, noStore: true)
        default:
          XCTFail("Unexpected request")
          return Self.response(request, status: 404, body: "{}", noStore: true)
        }
      }
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: journal
      )
      keychain.failWrite(afterSuccessfulWrites: 2)
      await manager.activateConsent(
        metricIDs: ["steps"],
        detail: .summary,
        retentionDays: 7
      )
      XCTAssertEqual(requestCount.value, 2)
      XCTAssertTrue(manager.hasPendingMutation)
      XCTAssertNil(manager.consent)
      XCTAssertNotNil(store.pendingMutation())

      keychain.allowWrites()
      await manager.refreshStatus()
      XCTAssertEqual(requestCount.value, 4)
      XCTAssertFalse(manager.hasPendingMutation)
      XCTAssertEqual(manager.consent?.revision, 2)
      XCTAssertEqual(manager.consent?.metricIDs, Set(["steps"]))
      XCTAssertFalse(store.hasPendingMutationRecord())
    }

    @MainActor
    func testPendingConsentReplacementRestoresOnlyMatchingRemoteRevision() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "access",
        refreshToken: "refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let previous = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps", "weight"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let proposed = HostedLocalConsent(
        revision: 2,
        metricIDs: ["steps"],
        sourceIDs: previous.sourceIDs,
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 7,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: true
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      try store.save(previous)
      try store.save(
        HostedPendingMutation(
          kind: .replaceConsent,
          expectedRevision: 1,
          targetRevision: 2,
          previousConsentState: .active,
          previousConsent: previous,
          proposedConsent: proposed,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: issuer,
          ownerBinding: Self.ownerBinding,
          createdAt: Date()
        ))
      let requestCount = HostedLockedBox(0)
      HostedURLProtocol.handler = { request in
        requestCount.withValue { $0 += 1 }
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/data/v1/control-status"):
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":2,"consent_state":"active"}"#,
            noStore: true
          )
        case ("PUT", "/data/v1/consent"):
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_consent_result","schema_version":1,"consent_revision":2,"consent_state":"active"}"#,
            noStore: true
          )
        default:
          XCTFail("Unexpected request")
          return Self.response(request, status: 404, body: "{}", noStore: true)
        }
      }
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let journal = try HostedSyncJournalStore(baseDirectory: temporary)
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: journal
      )
      XCTAssertTrue(manager.hasPendingMutation)
      XCTAssertNil(manager.consent)
      await manager.refreshStatus()
      XCTAssertEqual(requestCount.value, 2)
      XCTAssertFalse(manager.hasPendingMutation)
      XCTAssertEqual(manager.consent, proposed)
      XCTAssertTrue(manager.automaticSyncEnabled)
      XCTAssertEqual(store.consent(), proposed)
    }

    @MainActor
    func testRevocationRetainsRevisionWatermarkForReactivation() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "access",
        refreshToken: "refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let storedConsent = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      try store.save(storedConsent)
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let journal = try HostedSyncJournalStore(baseDirectory: temporary)
      try await journal.reset(binding: Self.journalBinding, consentRevision: 1)
      let requestCount = HostedLockedBox(0)
      HostedURLProtocol.handler = { request in
        requestCount.withValue { $0 += 1 }
        switch (request.httpMethod, request.url?.path) {
        case ("DELETE", "/data/v1/consent"):
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_consent_result","schema_version":1,"consent_revision":2,"consent_state":"revoked"}"#,
            noStore: true
          )
        case ("GET", "/data/v1/control-status"):
          let body =
            requestCount.value == 1
            ? #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":1,"consent_state":"active"}"#
            : #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":2,"consent_state":"missing"}"#
          return Self.response(request, body: body, noStore: true)
        case ("PUT", "/data/v1/consent"):
          let body = try JSONSerialization.jsonObject(with: try Self.requestBody(request))
          XCTAssertEqual((body as? [String: Any])?["revision"] as? Int, 3)
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_consent_result","schema_version":1,"consent_revision":3,"consent_state":"active"}"#,
            noStore: true
          )
        default:
          XCTFail("Unexpected request")
          return Self.response(request, status: 404, body: "{}", noStore: true)
        }
      }
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: journal
      )

      await manager.revokeConsent()
      XCTAssertEqual(requestCount.value, 3)
      XCTAssertFalse(manager.hasPendingMutation)
      XCTAssertNil(manager.consent)
      XCTAssertEqual(manager.remoteStatus?.consentState, .missing)
      XCTAssertEqual(manager.remoteStatus?.consentRevision, 2)

      await manager.activateConsent(
        metricIDs: ["steps"],
        detail: .summary,
        retentionDays: 30
      )
      XCTAssertEqual(requestCount.value, 5)
      XCTAssertEqual(manager.consent?.revision, 3)
      XCTAssertFalse(manager.hasPendingMutation)
    }

    @MainActor
    func testRestartAfterRevocationUsesAuthoritativeRevisionBeforeActivation() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "access",
        refreshToken: "refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let requests = HostedLockedBox(0)
      HostedURLProtocol.handler = { request in
        requests.withValue { $0 += 1 }
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/data/v1/control-status"):
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":2,"consent_state":"missing"}"#,
            noStore: true
          )
        case ("PUT", "/data/v1/consent"):
          let body = try JSONSerialization.jsonObject(with: try Self.requestBody(request))
          XCTAssertEqual((body as? [String: Any])?["revision"] as? Int, 3)
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_consent_result","schema_version":1,"consent_revision":3,"consent_state":"active"}"#,
            noStore: true
          )
        default:
          XCTFail("Unexpected request")
          return Self.response(request, status: 404, body: "{}", noStore: true)
        }
      }
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: try HostedSyncJournalStore(baseDirectory: temporary)
      )
      XCTAssertNil(manager.remoteStatus)
      await manager.activateConsent(metricIDs: ["steps"], detail: .summary, retentionDays: 30)
      XCTAssertEqual(requests.value, 2)
      XCTAssertEqual(manager.consent?.revision, 3)
      XCTAssertFalse(manager.hasPendingMutation)
    }

    @MainActor
    func testAuthoritativeStaleConsentResponseRetiresTombstone() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "access",
        refreshToken: "refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let previous = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      try store.save(previous)
      HostedURLProtocol.handler = { request in
        switch (request.httpMethod, request.url?.path) {
        case ("GET", "/data/v1/control-status"):
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":1,"consent_state":"active"}"#,
            noStore: true
          )
        case ("PUT", "/data/v1/consent"):
          return Self.response(
            request,
            status: 409,
            body:
              #"{"error":"healthmd_consent_revision_stale","message":"stale","retryable":false}"#,
            noStore: true
          )
        default:
          XCTFail("Unexpected request")
          return Self.response(request, status: 404, body: "{}", noStore: true)
        }
      }
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: try HostedSyncJournalStore(baseDirectory: temporary)
      )
      await manager.activateConsent(metricIDs: ["steps"], detail: .summary, retentionDays: 7)
      XCTAssertFalse(manager.hasPendingMutation)
      XCTAssertEqual(manager.consent, previous)
      XCTAssertFalse(store.hasPendingMutationRecord())
    }

    @MainActor
    func testPendingConsentReplacementDoesNotRetryAgainstLowerRevision() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "access",
        refreshToken: "refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let previous = HostedLocalConsent(
        revision: 2,
        metricIDs: ["steps"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let proposed = HostedLocalConsent(
        revision: 3,
        metricIDs: ["steps"],
        sourceIDs: previous.sourceIDs,
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 7,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      try store.save(previous)
      try store.save(
        HostedPendingMutation(
          kind: .replaceConsent,
          expectedRevision: 2,
          targetRevision: 3,
          previousConsentState: .active,
          previousConsent: previous,
          proposedConsent: proposed,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: issuer,
          ownerBinding: Self.ownerBinding,
          createdAt: Date()
        ))
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let journal = try HostedSyncJournalStore(baseDirectory: temporary)
      let requests = HostedLockedBox(0)
      let statusMode = HostedLockedBox(0)
      HostedURLProtocol.handler = { request in
        requests.withValue { $0 += 1 }
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/data/v1/control-status")
        let body =
          switch statusMode.value {
          case 1:
            #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":3,"consent_state":"missing"}"#
          case 2:
            #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":3,"consent_state":"active"}"#
          default:
            #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":1,"consent_state":"active"}"#
          }
        return Self.response(request, body: body, noStore: true)
      }
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: journal
      )

      await manager.refreshStatus()
      XCTAssertEqual(requests.value, 1)
      XCTAssertTrue(manager.hasPendingMutation)
      XCTAssertNil(manager.consent)
      XCTAssertNotNil(store.pendingMutation())

      statusMode.value = 1
      await manager.refreshStatus()
      XCTAssertEqual(requests.value, 2)
      XCTAssertFalse(manager.hasPendingMutation)
      XCTAssertNil(manager.consent)
      XCTAssertNil(store.pendingMutation())

      try store.save(previous)
      try store.save(
        HostedPendingMutation(
          kind: .revokeConsent,
          expectedRevision: 2,
          targetRevision: 3,
          previousConsentState: .active,
          previousConsent: previous,
          proposedConsent: nil,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: issuer,
          ownerBinding: Self.ownerBinding,
          createdAt: Date()
        ))
      statusMode.value = 2
      await manager.refreshStatus()
      XCTAssertEqual(requests.value, 3)
      XCTAssertFalse(manager.hasPendingMutation)
      XCTAssertNil(manager.consent)
      XCTAssertNil(store.pendingMutation())
    }

    @MainActor
    func testFreshAuthorizationClearsAnotherOwnersLocalStateAndLazilyCreatesJournal() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let oldToken = HostedOAuthToken(
        accessToken: "old-access",
        refreshToken: nil,
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(-3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let oldConsent = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: true
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(oldToken)
      try store.save(oldConsent)
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let journal = try HostedSyncJournalStore(baseDirectory: temporary)
      try await journal.record(
        binding: Self.journalBinding,
        consentRevision: 1,
        days: ["2026-07-01": String(repeating: "c", count: 64)]
      )
      let factoryCalls = HostedLockedBox(0)
      Self.installAuthorizationResponses(ownerBinding: Self.otherOwnerBinding)
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: nil,
        journalStoreFactory: {
          factoryCalls.withValue { $0 += 1 }
          return journal
        },
        authenticationSessionRunner: Self.authorizationCallback
      )
      XCTAssertFalse(manager.isConnected)

      await manager.connect()
      XCTAssertTrue(manager.isConnected)
      XCTAssertNil(manager.consent)
      XCTAssertEqual(store.token()?.ownerBinding, Self.otherOwnerBinding)
      XCTAssertNil(store.consent())
      XCTAssertEqual(factoryCalls.value, 1)
      let resetJournal = try await journal.snapshot(binding: Self.journalBinding)
      XCTAssertNil(resetJournal.consentRevision)
      XCTAssertTrue(resetJournal.dayDigests.isEmpty)
    }

    @MainActor
    func testPendingDeletionRejectsFreshAuthorizationForDifferentOwner() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let previous = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(previous)
      try store.save(
        HostedPendingMutation(
          kind: .deleteAccount,
          expectedRevision: nil,
          targetRevision: nil,
          previousConsentState: nil,
          previousConsent: previous,
          proposedConsent: nil,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: issuer,
          ownerBinding: Self.ownerBinding,
          createdAt: Date()
        ))
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let journal = try HostedSyncJournalStore(baseDirectory: temporary)
      let deleteRequests = HostedLockedBox(0)
      HostedURLProtocol.handler = { request in
        switch request.url?.path {
        case "/.well-known/oauth-protected-resource/mcp":
          return Self.response(
            request,
            body:
              #"{"resource":"https://mcp.example.com/mcp","authorization_servers":["https://auth.example.com"],"scopes_supported":["health.sync.write","health.account.manage"]}"#
          )
        case "/.well-known/oauth-authorization-server":
          return Self.response(
            request,
            body:
              #"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","code_challenge_methods_supported":["S256"]}"#
          )
        case "/token":
          return Self.response(
            request,
            body:
              #"{"access_token":"other-access","refresh_token":"other-refresh","token_type":"Bearer","expires_in":3600,"scope":"health.sync.write health.account.manage"}"#,
            noStore: true
          )
        case "/data/v1/control-status":
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","consent_revision":null,"consent_state":"missing"}"#,
            noStore: true
          )
        case "/data/v1/account":
          deleteRequests.withValue { $0 += 1 }
          return Self.response(request, status: 500, body: "{}", noStore: true)
        default:
          XCTFail("Unexpected URL: \(request.url?.absoluteString ?? "nil")")
          return Self.response(request, status: 404, body: "{}")
        }
      }
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: journal,
        authenticationSessionRunner: { authorizationURL in
          let state = try XCTUnwrap(
            URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
              .queryItems?.first(where: { $0.name == "state" })?.value
          )
          return try XCTUnwrap(
            URL(string: "healthmd://hosted/callback?state=\(state)&code=code")
          )
        }
      )
      XCTAssertTrue(manager.hasPendingMutation)
      XCTAssertFalse(manager.isConnected)

      await manager.connect()
      XCTAssertEqual(deleteRequests.value, 0)
      XCTAssertTrue(manager.hasPendingMutation)
      XCTAssertFalse(manager.isConnected)
      XCTAssertNil(store.token())
      XCTAssertNotNil(store.pendingMutation())
    }

    @MainActor
    func testRotatedRefreshCandidateSurvivesStatusFailureAndRelaunch() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "old-access",
        refreshToken: "old-refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date(timeIntervalSince1970: 0),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      let failStatus = HostedLockedBox(true)
      let failTokenRefresh = HostedLockedBox(false)
      HostedURLProtocol.handler = { request in
        switch request.url?.path {
        case "/.well-known/oauth-protected-resource/mcp":
          return Self.response(
            request,
            body:
              #"{"resource":"https://mcp.example.com/mcp","authorization_servers":["https://auth.example.com"],"scopes_supported":["health.sync.write","health.account.manage"]}"#
          )
        case "/.well-known/oauth-authorization-server":
          return Self.response(
            request,
            body:
              #"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","code_challenge_methods_supported":["S256"]}"#
          )
        case "/token":
          let body = String(decoding: try Self.requestBody(request), as: UTF8.self)
          if body.contains("refresh_token=new-refresh") {
            if failTokenRefresh.value {
              return Self.response(
                request,
                status: 503,
                body: #"{"error":"temporarily_unavailable"}"#,
                noStore: true
              )
            }
            return Self.response(
              request,
              body:
                #"{"access_token":"recovered-access","refresh_token":"recovered-refresh","token_type":"Bearer","expires_in":3600,"scope":"health.sync.write health.account.manage"}"#,
              noStore: true
            )
          }
          XCTAssertTrue(body.contains("refresh_token=old-refresh"))
          return Self.response(
            request,
            body:
              #"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"Bearer","expires_in":3600,"scope":"health.sync.write health.account.manage"}"#,
            noStore: true
          )
        case "/data/v1/control-status":
          if failStatus.value {
            return Self.response(
              request,
              status: 503,
              body:
                #"{"error":"healthmd_storage_unavailable","message":"unavailable","retryable":true}"#,
              noStore: true
            )
          }
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":null,"consent_state":"missing"}"#,
            noStore: true
          )
        default:
          XCTFail("Unexpected URL: \(request.url?.absoluteString ?? "nil")")
          return Self.response(request, status: 404, body: "{}")
        }
      }
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let session = Self.session()
      let first = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: try HostedSyncJournalStore(baseDirectory: temporary)
      )
      await first.refreshStatus()
      let candidate = try XCTUnwrap(store.loadRefreshCandidate())
      XCTAssertEqual(candidate.accessToken, "new-access")
      XCTAssertEqual(store.token()?.accessToken, "old-access")
      try store.saveRefreshCandidate(
        HostedOAuthToken(
          accessToken: candidate.accessToken,
          refreshToken: candidate.refreshToken,
          tokenType: candidate.tokenType,
          scopes: candidate.scopes,
          expiresAt: Date(timeIntervalSince1970: 0),
          resourceURL: candidate.resourceURL,
          clientID: candidate.clientID,
          issuer: candidate.issuer,
          ownerBinding: candidate.ownerBinding
        )
      )

      failStatus.value = false
      let relaunched = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: try HostedSyncJournalStore(baseDirectory: temporary)
      )
      XCTAssertTrue(relaunched.isConnected)
      failTokenRefresh.value = true
      await relaunched.refreshStatus()
      XCTAssertEqual(try store.loadRefreshCandidate()?.accessToken, "new-access")
      XCTAssertEqual(store.token()?.accessToken, "old-access")

      failTokenRefresh.value = false
      await relaunched.refreshStatus()
      XCTAssertEqual(store.token()?.accessToken, "recovered-access")
      XCTAssertNil(try store.loadRefreshCandidate())
      XCTAssertTrue(relaunched.isConnected)
    }

    @MainActor
    func testCorruptDetailedTombstoneAllowsSameOwnerDestructiveRecovery() async throws {
      let configuration = HostedAccountConfiguration(
        resourceURL: URL(string: "https://mcp.example.com/mcp")!,
        clientID: "healthmd-ios"
      )
      let issuer = URL(string: "https://auth.example.com")!
      let token = HostedOAuthToken(
        accessToken: "old-access",
        refreshToken: "old-refresh",
        tokenType: "Bearer",
        scopes: HostedAccountConfiguration.requiredScopes,
        expiresAt: Date().addingTimeInterval(3_600),
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding
      )
      let consent = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      try store.save(token)
      try store.save(consent)
      try store.save(
        HostedPendingMutation(
          kind: .deleteAccount,
          expectedRevision: nil,
          targetRevision: nil,
          previousConsentState: nil,
          previousConsent: consent,
          proposedConsent: nil,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: issuer,
          ownerBinding: Self.ownerBinding,
          createdAt: Date()
        ))
      keychain.overwrite(keySuffix: "pendingMutation.v1", value: "{")
      HostedURLProtocol.handler = { request in
        switch request.url?.path {
        case "/.well-known/oauth-protected-resource/mcp":
          return Self.response(
            request,
            body:
              #"{"resource":"https://mcp.example.com/mcp","authorization_servers":["https://auth.example.com"],"scopes_supported":["health.sync.write","health.account.manage"]}"#
          )
        case "/.well-known/oauth-authorization-server":
          return Self.response(
            request,
            body:
              #"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","code_challenge_methods_supported":["S256"]}"#
          )
        case "/token":
          return Self.response(
            request,
            body:
              #"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"Bearer","expires_in":3600,"scope":"health.sync.write health.account.manage"}"#,
            noStore: true
          )
        case "/data/v1/control-status":
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","consent_revision":1,"consent_state":"active"}"#,
            noStore: true
          )
        case "/data/v1/account":
          return Self.response(
            request,
            body:
              #"{"schema":"healthmd.hosted_account_deletion","schema_version":1,"status":"deleted"}"#,
            noStore: true
          )
        default:
          XCTFail("Unexpected URL: \(request.url?.absoluteString ?? "nil")")
          return Self.response(request, status: 404, body: "{}")
        }
      }
      let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
      defer { try? FileManager.default.removeItem(at: temporary) }
      let session = Self.session()
      let manager = HostedAccountManager(
        configuration: configuration,
        tokenStore: store,
        oauthClient: HostedOAuthClient(session: session),
        dataClient: HostedDataClient(session: session),
        journalStore: try HostedSyncJournalStore(baseDirectory: temporary),
        authenticationSessionRunner: Self.authorizationCallback
      )
      XCTAssertTrue(manager.hasCorruptProtectedState)
      XCTAssertTrue(manager.hasPendingMutation)
      await manager.connect()
      XCTAssertFalse(manager.hasCorruptProtectedState)
      XCTAssertFalse(manager.hasPendingMutation)
      XCTAssertFalse(manager.isConnected)
      XCTAssertNil(store.token())
      XCTAssertNil(store.consent())
    }

    func testHostedOAuthCallbackRequiresOneExactStateAndCode() throws {
      let state = String(repeating: "s", count: 32)
      let valid = URL(string: "healthmd://hosted/callback?state=\(state)&code=code")!
      XCTAssertEqual(
        try HostedAccountManager.authorizationCode(valid, expectedState: state),
        "code"
      )
      for invalid in [
        "healthmd://hosted/callback?state=\(state)&state=\(state)&code=code",
        "healthmd://hosted/callback?state=\(state)&code=one&code=two",
        "healthmd://hosted/callback?state=\(state)&state&code=code",
        "healthmd://hosted/callback?state=\(state)&code=code&code",
        "healthmd://hosted/callback?state=\(state)&code=code&unexpected=value",
        "healthmd://hosted/callback?state=\(state)&code=code&error=denied",
        "healthmd://hosted/callback?state=\(state)&code=code#fragment",
      ] {
        XCTAssertThrowsError(
          try HostedAccountManager.authorizationCode(
            URL(string: invalid)!,
            expectedState: state
          ))
      }
    }
  #endif

  func testHostedJournalRejectsLinkedPrivateDirectory() throws {
    let temporary = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let target = temporary.appendingPathComponent("target", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: temporary.appendingPathComponent("Health.md"),
      withDestinationURL: target
    )
    defer { try? FileManager.default.removeItem(at: temporary) }
    XCTAssertThrowsError(try HostedSyncJournalStore(baseDirectory: temporary)) { error in
      XCTAssertEqual(error as? HostedSyncJournalError, .invalidState)
    }
  }

  func testHostedTokenAndConsentPersistenceAreVerified() throws {
    let configuration = HostedAccountConfiguration(
      resourceURL: URL(string: "https://mcp.example.com/mcp")!,
      clientID: "healthmd-ios"
    )
    let issuer = URL(string: "https://auth.example.com")!
    let token = HostedOAuthToken(
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      scopes: HostedAccountConfiguration.requiredScopes,
      expiresAt: nil,
      resourceURL: configuration.resourceURL,
      clientID: configuration.clientID,
      issuer: issuer,
      ownerBinding: Self.ownerBinding
    )
    let invalid = HostedOAuthToken(
      accessToken: "line\nbreak",
      refreshToken: nil,
      tokenType: "Bearer",
      scopes: HostedAccountConfiguration.requiredScopes,
      expiresAt: nil,
      resourceURL: configuration.resourceURL,
      clientID: configuration.clientID,
      issuer: issuer
    )
    XCTAssertTrue(token.isValid)
    XCTAssertTrue(token.canUse(configuration: configuration))
    XCTAssertFalse(
      token.canUse(
        configuration: HostedAccountConfiguration(
          resourceURL: URL(string: "https://other.example.com/mcp")!,
          clientID: configuration.clientID
        )))
    XCTAssertFalse(invalid.isValid)
    let overScoped = HostedOAuthToken(
      accessToken: "access",
      refreshToken: "refresh",
      tokenType: "Bearer",
      scopes: HostedAccountConfiguration.requiredScopes.union(["health.summary.read"]),
      expiresAt: nil,
      resourceURL: configuration.resourceURL,
      clientID: configuration.clientID,
      issuer: issuer,
      ownerBinding: Self.ownerBinding
    )
    XCTAssertFalse(overScoped.canManageAndSync)
    XCTAssertFalse(overScoped.isPersistable)

    #if os(macOS)
      let keychain = HostedMemoryKeychain()
      let store = HostedAccountTokenStore(keychain: keychain)
      XCTAssertNil(try store.loadToken())
      XCTAssertThrowsError(try store.save(overScoped))
      keychain.failReads()
      XCTAssertThrowsError(try store.loadToken())
      keychain.allowReads()
      try store.save(token)
      XCTAssertEqual(store.token(), token)
      let consent = HostedLocalConsent(
        revision: 1,
        metricIDs: ["steps"],
        sourceIDs: ["apple_health", "healthmd_summary"],
        providerIDs: [],
        maximumDetail: .summary,
        retentionDays: 30,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        automaticSyncEnabled: false
      )
      XCTAssertTrue(
        consent.canUse(
          configuration: configuration,
          issuer: issuer,
          ownerBinding: Self.ownerBinding
        ))
      XCTAssertFalse(
        consent.canUse(
          configuration: HostedAccountConfiguration(
            resourceURL: URL(string: "https://other.example.com/mcp")!,
            clientID: configuration.clientID
          ),
          issuer: issuer,
          ownerBinding: Self.ownerBinding
        ))
      try store.save(consent)
      XCTAssertEqual(store.consent(), consent)
      let pending = HostedPendingMutation(
        kind: .revokeConsent,
        expectedRevision: 1,
        targetRevision: 2,
        previousConsentState: .active,
        previousConsent: consent,
        proposedConsent: nil,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: issuer,
        ownerBinding: Self.ownerBinding,
        createdAt: Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
      )
      try store.save(pending)
      XCTAssertTrue(store.hasPendingMutationRecord())
      XCTAssertEqual(store.pendingMutation(), pending)
      try store.removePendingMutation()
      XCTAssertFalse(store.hasPendingMutationRecord())
      try store.removeAll()
      XCTAssertNil(store.token())
      XCTAssertNil(store.consent())
      XCTAssertThrowsError(try store.save(invalid))
    #endif
  }

  private static func installAuthorizationResponses(ownerBinding: String) {
    HostedURLProtocol.handler = { request in
      switch request.url?.path {
      case "/.well-known/oauth-protected-resource/mcp":
        return Self.response(
          request,
          body:
            #"{"resource":"https://mcp.example.com/mcp","authorization_servers":["https://auth.example.com"],"scopes_supported":["health.sync.write","health.account.manage"]}"#
        )
      case "/.well-known/oauth-authorization-server":
        return Self.response(
          request,
          body:
            #"{"issuer":"https://auth.example.com","authorization_endpoint":"https://auth.example.com/authorize","token_endpoint":"https://auth.example.com/token","code_challenge_methods_supported":["S256"]}"#
        )
      case "/token":
        return Self.response(
          request,
          body:
            #"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"Bearer","expires_in":3600,"scope":"health.sync.write health.account.manage"}"#,
          noStore: true
        )
      case "/data/v1/control-status":
        return Self.response(
          request,
          body:
            """
            {"schema":"healthmd.hosted_control_status","schema_version":1,"owner_binding":"\(ownerBinding)","consent_revision":null,"consent_state":"missing"}
            """,
          noStore: true
        )
      default:
        XCTFail("Unexpected URL: \(request.url?.absoluteString ?? "nil")")
        return Self.response(request, status: 404, body: "{}")
      }
    }
  }

  private static func authorizationCallback(_ authorizationURL: URL) async throws -> URL {
    let state = try XCTUnwrap(
      URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "state" })?.value
    )
    return try XCTUnwrap(
      URL(string: "healthmd://hosted/callback?state=\(state)&code=code")
    )
  }

  private static func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HostedURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  private static func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: buffer.count)
      if read < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
      if read == 0 { break }
      result.append(buffer, count: read)
    }
    return result
  }

  private static func response(
    _ request: URLRequest,
    status: Int = 200,
    body: String,
    noStore: Bool = false
  ) -> (HTTPURLResponse, Data) {
    var headers = ["Content-Type": "application/json"]
    if noStore { headers["Cache-Control"] = "no-store" }
    return (
      HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
      )!,
      Data(body.utf8)
    )
  }
}

private final class HostedURLProtocol: URLProtocol, @unchecked Sendable {
  private nonisolated static let handlerLock = NSLock()
  private nonisolated(unsafe) static var storedHandler:
    (
      (URLRequest) throws -> (HTTPURLResponse, Data)
    )?

  nonisolated static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))? {
    get {
      handlerLock.lock()
      defer { handlerLock.unlock() }
      return storedHandler
    }
    set {
      handlerLock.lock()
      storedHandler = newValue
      handlerLock.unlock()
    }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      guard let handler = Self.handler else { throw URLError(.badServerResponse) }
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private nonisolated struct HostedSemanticQueryValueVector: Encodable {
  let values: [HealthMdQueryValue]
}

private nonisolated struct HostedSemanticExponentBoundaryVector: Encodable {
  let values = [0.00001, 0.000001, 1e-7, -0.00001, 1e20, 1.2345678901234567]
}

private nonisolated struct HostedSemanticDigestVector: Encodable {
  private enum CodingKeys: String, CodingKey { case array, bool, null, object }
  private enum ObjectKeys: String, CodingKey { case a, z }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    var array = container.nestedUnkeyedContainer(forKey: .array)
    try array.encode(1)
    try array.encode(1e-7)
    try array.encode(-0.0)
    try array.encode(1e20)
    try array.encode(1.2345)
    try container.encode(true, forKey: .bool)
    try container.encodeNil(forKey: .null)
    var object = container.nestedContainer(keyedBy: ObjectKeys.self, forKey: .object)
    try object.encode("é", forKey: .a)
    try object.encode("line\\nbreak", forKey: .z)
  }
}

private nonisolated final class HostedLockedBox<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: Value

  init(_ value: Value) { storage = value }

  var value: Value {
    get {
      lock.lock()
      defer { lock.unlock() }
      return storage
    }
    set {
      lock.lock()
      storage = newValue
      lock.unlock()
    }
  }

  func withValue(_ operation: (inout Value) -> Void) {
    lock.lock()
    operation(&storage)
    lock.unlock()
  }
}

private nonisolated enum HostedMemoryKeychainError: Error {
  case injected
}

private nonisolated final class HostedMemoryKeychain: ExternalIntegrationSecureStoring,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var values: [String: String] = [:]
  private var successfulWritesBeforeFailure: Int?
  private var readsFail = false
  private var removalFailureSuffix: String?

  func failWrite(afterSuccessfulWrites count: Int) {
    lock.lock()
    successfulWritesBeforeFailure = count
    lock.unlock()
  }

  func allowWrites() {
    lock.lock()
    successfulWritesBeforeFailure = nil
    lock.unlock()
  }

  func overwrite(keySuffix: String, value: String) {
    lock.lock()
    if let key = values.keys.first(where: { $0.hasSuffix(keySuffix) }) {
      values[key] = value
    }
    lock.unlock()
  }

  func failReads() {
    lock.lock()
    readsFail = true
    lock.unlock()
  }

  func allowReads() {
    lock.lock()
    readsFail = false
    lock.unlock()
  }

  func failRemoval(keySuffix: String) {
    lock.lock()
    removalFailureSuffix = keySuffix
    lock.unlock()
  }

  func allowRemovals() {
    lock.lock()
    removalFailureSuffix = nil
    lock.unlock()
  }

  func readString(key: String) -> String? {
    try? readStringOrThrow(key: key)
  }

  func readStringOrThrow(key: String) throws -> String? {
    lock.lock()
    defer { lock.unlock() }
    if readsFail {
      throw HostedMemoryKeychainError.injected
    }
    return values[key]
  }

  func writeStringOrThrow(key: String, value: String) throws {
    lock.lock()
    defer { lock.unlock() }
    if let remaining = successfulWritesBeforeFailure {
      if remaining == 0 {
        throw HostedMemoryKeychainError.injected
      }
      successfulWritesBeforeFailure = remaining - 1
    }
    values[key] = value
  }

  func removeOrThrow(key: String) throws {
    lock.lock()
    defer { lock.unlock() }
    if let removalFailureSuffix, key.hasSuffix(removalFailureSuffix) {
      throw HostedMemoryKeychainError.injected
    }
    values.removeValue(forKey: key)
  }
}
