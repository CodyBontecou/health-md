#if os(iOS)
  import AuthenticationServices
  import Combine
  import Foundation
  import UIKit

  @MainActor
  final class HostedAccountManager: NSObject, ObservableObject {
    static let shared = HostedAccountManager()

    @Published private(set) var isConnected: Bool
    @Published private(set) var isBusy = false
    @Published private(set) var consent: HostedLocalConsent?
    @Published private(set) var remoteStatus: HostedControlStatus?
    @Published private(set) var statusMessage: String?
    @Published private(set) var automaticSyncEnabled: Bool
    @Published private(set) var hasPendingMutation: Bool
    @Published private(set) var isProtectedStateAvailable: Bool
    @Published private(set) var hasCorruptProtectedState: Bool

    let configuration: HostedAccountConfiguration?

    private let tokenStore: HostedAccountTokenStore
    private let oauthClient: HostedOAuthClient
    private let dataClient: HostedDataClient
    private var journalStore: HostedSyncJournalStore?
    private let journalStoreFactory: (() throws -> HostedSyncJournalStore)?
    private let authenticationSessionRunner: ((URL) async throws -> URL)?
    private var authSession: ASWebAuthenticationSession?
    private var refreshTask: Task<HostedOAuthToken, Error>?
    private var corruptMutationRecovery: HostedPendingMutationRecovery?

    override convenience init() {
      let configuration = HostedAccountConfiguration.current
      self.init(
        configuration: configuration,
        tokenStore: HostedAccountTokenStore(),
        oauthClient: HostedOAuthClient(),
        dataClient: HostedDataClient(),
        journalStore: nil,
        journalStoreFactory: configuration == nil ? nil : { try HostedSyncJournalStore() }
      )
    }

    init(
      configuration: HostedAccountConfiguration?,
      tokenStore: HostedAccountTokenStore,
      oauthClient: HostedOAuthClient,
      dataClient: HostedDataClient,
      journalStore: HostedSyncJournalStore?,
      journalStoreFactory: (() throws -> HostedSyncJournalStore)? = nil,
      authenticationSessionRunner: ((URL) async throws -> URL)? = nil
    ) {
      self.configuration = configuration
      self.tokenStore = tokenStore
      self.oauthClient = oauthClient
      self.dataClient = dataClient
      self.journalStore = journalStore
      self.journalStoreFactory = journalStoreFactory
      self.authenticationSessionRunner = authenticationSessionRunner
      automaticSyncEnabled = false
      isConnected = false
      hasPendingMutation = false
      isProtectedStateAvailable = configuration == nil
      hasCorruptProtectedState = false
      consent = nil
      corruptMutationRecovery = nil
      super.init()
      _ = rehydrateProtectedState()
    }

    var isConfigured: Bool { configuration != nil }

    @discardableResult
    func reloadProtectedState() -> Bool {
      rehydrateProtectedState()
    }

    func resetInvalidLocalState() async {
      guard !isBusy, hasCorruptProtectedState else { return }
      isBusy = true
      defer { isBusy = false }
      do {
        guard try tokenStore.pendingMutationRecordExists() == false else {
          throw HostedAccountTokenStoreError.corrupt
        }
        let journalStore = try requireJournalStore()
        try await journalStore.reset()
        try tokenStore.removeConsent()
        try tokenStore.removeRefreshCandidate()
        try tokenStore.removeToken()
        consent = nil
        automaticSyncEnabled = false
        remoteStatus = nil
        isConnected = false
        hasPendingMutation = false
        hasCorruptProtectedState = false
        corruptMutationRecovery = nil
        isProtectedStateAvailable = true
        statusMessage = "Invalid local hosted account state was reset; reconnect to continue"
      } catch {
        statusMessage = error.localizedDescription
      }
    }

    @discardableResult
    private func rehydrateProtectedState() -> Bool {
      guard let configuration else {
        isProtectedStateAvailable = true
        hasCorruptProtectedState = false
        isConnected = false
        hasPendingMutation = false
        corruptMutationRecovery = nil
        consent = nil
        automaticSyncEnabled = false
        return true
      }
      var observedPendingRecord: Bool?
      do {
        let pendingRecordExists = try tokenStore.pendingMutationRecordExists()
        observedPendingRecord = pendingRecordExists
        let token = try tokenStore.loadToken()
        let candidate = try tokenStore.loadRefreshCandidate()
        if let token, let candidate,
          token.ownerBinding != candidate.ownerBinding
            || token.issuer != candidate.issuer
            || !candidate.canUse(configuration: configuration)
        {
          throw HostedAccountTokenStoreError.corrupt
        }
        let recoveryToken = candidate ?? token
        let pending = pendingRecordExists ? try tokenStore.loadPendingMutation() : nil
        let pendingRecovery =
          pendingRecordExists ? try tokenStore.loadPendingMutationRecovery() : nil
        let storedConsent = pendingRecordExists ? nil : try tokenStore.loadConsent()
        if pendingRecordExists,
          pending == nil || pendingRecovery == nil || pending?.recovery != pendingRecovery
        {
          throw HostedAccountTokenStoreError.corrupt
        }
        let connected =
          recoveryToken.map {
            $0.canRecoverAuthorization
              && $0.isPersistable
              && $0.canUse(configuration: configuration)
          } ?? false
        if let pending, let recoveryToken {
          guard let ownerBinding = recoveryToken.ownerBinding,
            pending.canUse(
              configuration: configuration,
              issuer: recoveryToken.issuer,
              ownerBinding: ownerBinding
            )
          else {
            throw HostedAccountTokenStoreError.corrupt
          }
        }

        isConnected = connected
        hasPendingMutation = pendingRecordExists
        if connected,
          !pendingRecordExists,
          let recoveryToken,
          let ownerBinding = recoveryToken.ownerBinding,
          let storedConsent,
          storedConsent.canUse(
            configuration: configuration,
            issuer: recoveryToken.issuer,
            ownerBinding: ownerBinding
          )
        {
          consent = storedConsent
          automaticSyncEnabled = storedConsent.automaticSyncEnabled
        } else {
          consent = nil
          automaticSyncEnabled = false
        }
        isProtectedStateAvailable = true
        hasCorruptProtectedState = false
        corruptMutationRecovery = nil
        return true
      } catch let error as HostedAccountTokenStoreError {
        isProtectedStateAvailable = error != .unavailable
        hasCorruptProtectedState = error == .corrupt
        corruptMutationRecovery =
          error == .corrupt && observedPendingRecord == true
          ? try? tokenStore.loadPendingMutationRecovery()
          : nil
        isConnected = false
        hasPendingMutation = observedPendingRecord ?? true
        consent = nil
        automaticSyncEnabled = false
        statusMessage = error.localizedDescription
        return false
      } catch {
        isProtectedStateAvailable = false
        hasCorruptProtectedState = false
        corruptMutationRecovery = nil
        isConnected = false
        hasPendingMutation = observedPendingRecord ?? true
        consent = nil
        automaticSyncEnabled = false
        statusMessage = error.localizedDescription
        return false
      }
    }

    private func requireJournalStore() throws -> HostedSyncJournalStore {
      if journalStore == nil, let journalStoreFactory {
        journalStore = try journalStoreFactory()
      }
      guard let journalStore else { throw HostedSyncJournalError.unavailable }
      return journalStore
    }

    func setAutomaticSyncEnabled(_ enabled: Bool) {
      guard rehydrateProtectedState(),
        !hasPendingMutation,
        let current = consent
      else {
        automaticSyncEnabled = false
        return
      }
      let updated = HostedLocalConsent(
        revision: current.revision,
        metricIDs: current.metricIDs,
        sourceIDs: current.sourceIDs,
        providerIDs: current.providerIDs,
        maximumDetail: current.maximumDetail,
        retentionDays: current.retentionDays,
        resourceURL: current.resourceURL,
        clientID: current.clientID,
        issuer: current.issuer,
        ownerBinding: current.ownerBinding,
        automaticSyncEnabled: enabled
      )
      do {
        try tokenStore.save(updated)
        consent = updated
        automaticSyncEnabled = enabled
      } catch {
        statusMessage = error.localizedDescription
      }
    }

    func connect() async {
      guard !isBusy else { return }
      let requestedWhileDisconnected = !isConnected
      let protectedStateReady = rehydrateProtectedState()
      guard protectedStateReady || corruptMutationRecovery != nil else { return }
      guard let configuration else {
        statusMessage = HostedOAuthError.notConfigured.localizedDescription
        return
      }
      if isConnected, !hasPendingMutation, !requestedWhileDisconnected { return }
      isBusy = true
      statusMessage =
        corruptMutationRecovery != nil
        ? "Reauthorizing the original account for destructive privacy recovery…"
        : hasPendingMutation
          ? "Reauthorizing the original account to finish privacy recovery…"
          : "Opening secure account authorization…"
      defer { isBusy = false }

      do {
        let destructiveRecovery = corruptMutationRecovery
        let pending =
          destructiveRecovery == nil && hasPendingMutation
          ? try tokenStore.loadPendingMutation()
          : nil
        if hasPendingMutation, pending == nil, destructiveRecovery == nil {
          throw HostedAccountTokenStoreError.corrupt
        }
        let authorization = try await oauthClient.beginAuthorization(
          configuration: configuration
        )
        let callback: URL
        if let authenticationSessionRunner {
          callback = try await authenticationSessionRunner(authorization.url)
        } else {
          callback = try await runAuthenticationSession(url: authorization.url)
        }
        let code = try Self.authorizationCode(
          callback,
          expectedState: authorization.state
        )
        let unboundToken = try await oauthClient.exchange(
          code: code,
          authorization: authorization,
          configuration: configuration
        )
        guard unboundToken.canManageAndSync,
          unboundToken.canUse(configuration: configuration)
        else {
          throw HostedOAuthError.insufficientScope
        }
        let status = try await dataClient.status(
          configuration: configuration,
          token: unboundToken
        )
        let token = try unboundToken.bound(to: status.ownerBinding)

        if let destructiveRecovery {
          guard
            destructiveRecovery.canUse(
              configuration: configuration,
              issuer: token.issuer,
              ownerBinding: status.ownerBinding
            )
          else {
            throw HostedOAuthError.invalidToken
          }
          let journalStore = try requireJournalStore()
          try tokenStore.removeRefreshCandidate()
          try tokenStore.save(token)
          _ = try await dataClient.deleteAccount(
            configuration: configuration,
            token: token
          )
          try await finalizeAccountDeletion(journalStore: journalStore)
          corruptMutationRecovery = nil
          hasCorruptProtectedState = false
          isProtectedStateAvailable = true
          statusMessage = "Corrupted privacy recovery state and hosted account data were deleted"
        } else if let pending {
          guard
            pending.canUse(
              configuration: configuration,
              issuer: token.issuer,
              ownerBinding: status.ownerBinding
            )
          else {
            throw HostedOAuthError.invalidToken
          }
          try tokenStore.removeRefreshCandidate()
          try tokenStore.save(token)
          isConnected = true
          remoteStatus = status
          let deleted = try await reconcilePendingMutation(
            pending,
            configuration: configuration,
            token: token
          )
          if !deleted {
            statusMessage = "Hosted account privacy recovery completed"
          }
        } else {
          let journalStore = try requireJournalStore()
          try await journalStore.reset()
          try tokenStore.removeConsent()
          try tokenStore.removeRefreshCandidate()
          try tokenStore.save(token)
          consent = nil
          automaticSyncEnabled = false
          hasPendingMutation = false
          isConnected = true
          remoteStatus = status
          statusMessage = "Hosted Health.md account connected; review synchronization consent"
        }
      } catch {
        if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
          statusMessage = "Hosted account connection cancelled"
        } else {
          statusMessage = error.localizedDescription
        }
      }
    }

    func refreshStatus() async {
      guard !isBusy, rehydrateProtectedState() else { return }
      guard configuration != nil, isConnected else { return }
      isBusy = true
      defer { isBusy = false }
      do {
        let token = try await authorizedToken()
        try await refreshStatus(using: token)
        statusMessage = "Hosted account status refreshed"
      } catch {
        statusMessage = error.localizedDescription
      }
    }

    func activateConsent(
      metricIDs: Set<String>,
      detail: HostedConsentDetail,
      retentionDays: Int
    ) async {
      guard !isBusy, rehydrateProtectedState() else { return }
      guard !hasPendingMutation else {
        statusMessage = "Refresh hosted account status to finish the pending privacy operation."
        return
      }
      guard let configuration, isConnected else {
        statusMessage = HostedDataClientError.unauthorized.localizedDescription
        return
      }
      let journalStore: HostedSyncJournalStore
      do {
        journalStore = try requireJournalStore()
      } catch {
        statusMessage = error.localizedDescription
        return
      }
      let allowedMetrics = metricIDs.intersection(HealthMetrics.availableMetricIDsInCurrentBuild)
      guard !allowedMetrics.isEmpty,
        allowedMetrics.count <= 512,
        (1...3_650).contains(retentionDays),
        let retention = UInt16(exactly: retentionDays)
      else {
        statusMessage = HostedDataClientError.invalidRequest.localizedDescription
        return
      }
      isBusy = true
      statusMessage = "Saving hosted synchronization consent…"
      defer { isBusy = false }

      do {
        let token = try await authorizedToken()
        guard let ownerBinding = token.ownerBinding else {
          throw HostedOAuthError.invalidToken
        }
        let predecessor = try await verifiedStatus(
          configuration: configuration,
          token: token
        )
        remoteStatus = predecessor
        let currentRevision = predecessor.consentRevision ?? 0
        let increment = currentRevision.addingReportingOverflow(1)
        guard !increment.overflow, increment.partialValue > 0 else {
          throw HostedDataClientError.invalidRequest
        }
        let revision = increment.partialValue
        let local = HostedLocalConsent(
          revision: revision,
          metricIDs: allowedMetrics,
          sourceIDs: [
            HealthMdEvidenceSourceIDs.appleHealth,
            HealthMdEvidenceSourceIDs.healthMdSummary,
          ],
          providerIDs: [],
          maximumDetail: detail,
          retentionDays: retention,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: token.issuer,
          ownerBinding: ownerBinding,
          automaticSyncEnabled: automaticSyncEnabled
        )
        try await activateConsent(
          local,
          revision: revision,
          predecessor: predecessor,
          configuration: configuration,
          token: token,
          journalStore: journalStore
        )
      } catch {
        statusMessage = error.localizedDescription
      }
    }

    private func activateConsent(
      _ local: HostedLocalConsent,
      revision: UInt64,
      predecessor: HostedControlStatus,
      configuration: HostedAccountConfiguration,
      token: HostedOAuthToken,
      journalStore: HostedSyncJournalStore
    ) async throws {
      let previousConsent = consent.flatMap {
        $0.revision == revision - 1 && $0.ownerBinding == local.ownerBinding ? $0 : nil
      }
      let pending = HostedPendingMutation(
        kind: .replaceConsent,
        expectedRevision: revision - 1,
        targetRevision: revision,
        previousConsentState: predecessor.consentState,
        previousConsent: previousConsent,
        proposedConsent: local,
        resourceURL: configuration.resourceURL,
        clientID: configuration.clientID,
        issuer: token.issuer,
        ownerBinding: local.ownerBinding,
        createdAt: Date()
      )
      try savePendingMutation(pending)
      consent = nil
      automaticSyncEnabled = false
      let request = consentRequest(for: local)
      let result: HostedConsentResult
      do {
        result = try await dataClient.replaceConsent(
          request,
          configuration: configuration,
          token: token
        )
      } catch {
        if Self.isKnownNoMutationResponse(error) {
          try abandonPendingMutation(pending)
        }
        throw error
      }
      guard result.consentRevision == revision, result.consentState == "active" else {
        throw HostedDataClientError.invalidResponse
      }
      remoteStatus = HostedControlStatus(
        schema: "healthmd.hosted_control_status",
        schemaVersion: 1,
        ownerBinding: local.ownerBinding,
        consentRevision: revision,
        consentState: .active
      )
      try await journalStore.reset(
        binding: journalBinding(for: local),
        consentRevision: revision
      )
      try tokenStore.save(local)
      consent = local
      automaticSyncEnabled = local.automaticSyncEnabled
      try removePendingMutation()
      statusMessage = "Hosted synchronization consent is active"
    }

    func synchronizeRecentDays(
      count: Int = 30,
      healthKitManager suppliedHealthKitManager: HealthKitManager? = nil,
      requiresForeground: Bool = false
    ) async {
      let healthKitManager = suppliedHealthKitManager ?? .shared
      guard !isBusy, rehydrateProtectedState() else { return }
      guard let configuration,
        let consent,
        isConnected,
        !hasPendingMutation,
        (1...Int(consent.retentionDays)).contains(count)
      else {
        statusMessage = HostedDataClientError.consentRequired.localizedDescription
        return
      }
      let journalStore: HostedSyncJournalStore
      do {
        journalStore = try requireJournalStore()
      } catch {
        statusMessage = error.localizedDescription
        return
      }
      do {
        guard let currentToken = try tokenStore.loadToken(),
          let ownerBinding = currentToken.ownerBinding,
          currentToken.canUse(
            configuration: configuration,
            ownerBinding: ownerBinding
          ),
          consent.canUse(
            configuration: configuration,
            issuer: currentToken.issuer,
            ownerBinding: ownerBinding
          )
        else {
          throw HostedDataClientError.consentRequired
        }
      } catch {
        self.consent = nil
        automaticSyncEnabled = false
        statusMessage = error.localizedDescription
        return
      }
      isBusy = true
      statusMessage = "Preparing protected hosted synchronization…"
      defer { isBusy = false }

      do {
        try requireForegroundIfNeeded(requiresForeground)
        let journal = try await journalStore.snapshot(
          binding: journalBinding(for: consent)
        )
        guard journal.consentRevision == consent.revision else {
          throw HostedSyncJournalError.invalidState
        }
        try await refreshStatus(using: try await authorizedToken())
        guard self.consent?.revision == consent.revision,
          remoteStatus?.consentState == .active,
          remoteStatus?.consentRevision == consent.revision
        else {
          throw HostedDataClientError.consentRequired
        }
        let authorized = try await healthKitManager.hasRecordedAuthorizationDecision(
          forMetricIDs: consent.metricIDs
        )
        guard authorized else { throw HostedSyncError.healthAuthorizationRequired }
        let timeZone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: Date())
        guard
          let lastCompleted = calendar.date(
            byAdding: .day,
            value: -1,
            to: today
          )
        else { throw HostedSyncError.noCompletedDays }
        let selection = MetricSelectionState()
        // Sleep session boundaries are structural metadata for `sleep_total`.
        // Preserve them through generic local filtering, then let hosted consent
        // projection remove unselected sleep metrics and stage detail.
        selection.enabledMetrics = consent.localCaptureMetricIDs
        var batch: [HostedSyncDay] = []
        batch.reserveCapacity(HostedDataClient.maximumDaysPerRequest)
        var capturedAnyDay = false
        var changed = 0
        var unchanged = 0

        for offset in (0..<count).reversed() {
          try Task.checkCancellation()
          try requireForegroundIfNeeded(requiresForeground)
          guard
            let date = calendar.date(
              byAdding: .day,
              value: -offset,
              to: lastCompleted
            )
          else { throw HostedSyncError.noCompletedDays }
          guard
            let day = try await captureDay(
              date: date,
              consent: consent,
              selection: selection,
              timeZone: timeZone,
              healthKitManager: healthKitManager
            )
          else { continue }
          try Task.checkCancellation()
          try requireForegroundIfNeeded(requiresForeground)
          capturedAnyDay = true

          if batch.count == HostedDataClient.maximumDaysPerRequest {
            try requireForegroundIfNeeded(requiresForeground)
            let counts = try await uploadBatch(
              batch,
              consent: consent,
              configuration: configuration,
              journalStore: journalStore,
              requiresForeground: requiresForeground
            )
            changed += counts.changed
            unchanged += counts.unchanged
            batch.removeAll(keepingCapacity: true)
          }

          let candidate = batch + [day]
          let candidateRequest = HostedSyncRequest(
            expectedConsentRevision: consent.revision,
            days: candidate
          )
          let candidateBytes = try HealthMdQueryCanonicalSerializer.data(
            for: candidateRequest
          ).count
          if candidateBytes > HostedDataClient.maximumRequestBytes {
            guard !batch.isEmpty else {
              throw HostedDataClientError.payloadTooLarge
            }
            try requireForegroundIfNeeded(requiresForeground)
            let counts = try await uploadBatch(
              batch,
              consent: consent,
              configuration: configuration,
              journalStore: journalStore,
              requiresForeground: requiresForeground
            )
            changed += counts.changed
            unchanged += counts.unchanged
            batch = [day]
          } else {
            batch = candidate
          }
        }

        guard capturedAnyDay else { throw HostedSyncError.noCompletedDays }
        if !batch.isEmpty {
          try requireForegroundIfNeeded(requiresForeground)
          let counts = try await uploadBatch(
            batch,
            consent: consent,
            configuration: configuration,
            journalStore: journalStore,
            requiresForeground: requiresForeground
          )
          changed += counts.changed
          unchanged += counts.unchanged
        }
        try Task.checkCancellation()
        try requireForegroundIfNeeded(requiresForeground)
        try await refreshStatus(using: try await authorizedToken())
        guard self.consent?.revision == consent.revision,
          remoteStatus?.consentState == .active,
          remoteStatus?.consentRevision == consent.revision
        else {
          throw HostedDataClientError.consentRequired
        }
        statusMessage =
          "Hosted synchronization completed: \(changed) updated, \(unchanged) unchanged"
      } catch {
        statusMessage = error.localizedDescription
      }
    }

    func synchronizeLatestCompletedDayIfNeeded(
      healthKitManager suppliedHealthKitManager: HealthKitManager? = nil
    ) async {
      let healthKitManager = suppliedHealthKitManager ?? .shared
      guard !isBusy,
        UIApplication.shared.applicationState == .active,
        UIApplication.shared.isProtectedDataAvailable,
        rehydrateProtectedState(),
        automaticSyncEnabled,
        isConnected,
        !hasPendingMutation,
        let consent
      else {
        return
      }
      do {
        let journalStore = try requireJournalStore()
        let journal = try await journalStore.snapshot(
          binding: journalBinding(for: consent)
        )
        guard journal.consentRevision == consent.revision else {
          throw HostedSyncJournalError.invalidState
        }
        let now = Date()
        if let lastSynchronizedAt = journal.lastSynchronizedAt,
          lastSynchronizedAt <= now.addingTimeInterval(5 * 60),
          lastSynchronizedAt >= now.addingTimeInterval(-15 * 60)
        {
          return
        }
      } catch {
        statusMessage = error.localizedDescription
        return
      }
      await synchronizeRecentDays(
        count: 1,
        healthKitManager: healthKitManager,
        requiresForeground: true
      )
    }

    private func requireForegroundIfNeeded(_ required: Bool) throws {
      guard
        !required
          || (!Task.isCancelled && UIApplication.shared.applicationState == .active)
      else {
        throw CancellationError()
      }
    }

    func revokeConsent() async {
      guard !isBusy,
        rehydrateProtectedState(),
        !hasPendingMutation,
        let configuration,
        let consent
      else { return }
      isBusy = true
      defer { isBusy = false }
      do {
        let journalStore = try requireJournalStore()
        let token = try await authorizedToken()
        guard let ownerBinding = token.ownerBinding,
          ownerBinding == consent.ownerBinding
        else {
          throw HostedOAuthError.invalidToken
        }
        let predecessor = try await verifiedStatus(
          configuration: configuration,
          token: token
        )
        remoteStatus = predecessor
        guard [.active, .expired].contains(predecessor.consentState),
          predecessor.consentRevision == consent.revision
        else {
          throw HostedDataClientError.consentRevisionStale
        }
        let increment = consent.revision.addingReportingOverflow(1)
        guard !increment.overflow, increment.partialValue > 0 else {
          throw HostedDataClientError.invalidRequest
        }
        let revision = increment.partialValue
        let pending = HostedPendingMutation(
          kind: .revokeConsent,
          expectedRevision: consent.revision,
          targetRevision: revision,
          previousConsentState: predecessor.consentState,
          previousConsent: consent,
          proposedConsent: nil,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: token.issuer,
          ownerBinding: ownerBinding,
          createdAt: Date()
        )
        try savePendingMutation(pending)
        automaticSyncEnabled = false
        self.consent = nil
        do {
          _ = try await dataClient.revokeConsent(
            .init(expectedRevision: consent.revision, revision: revision),
            configuration: configuration,
            token: token
          )
        } catch {
          if Self.isKnownNoMutationResponse(error) {
            try abandonPendingMutation(pending)
          }
          throw error
        }
        remoteStatus = try await verifiedStatus(
          configuration: configuration,
          token: token
        )
        guard remoteStatus?.consentState == .missing,
          remoteStatus?.consentRevision == revision
        else {
          throw HostedDataClientError.invalidResponse
        }
        try await journalStore.reset()
        try tokenStore.removeConsent()
        try removePendingMutation()
        statusMessage = "Hosted synchronization consent revoked and synchronized data deleted"
      } catch {
        statusMessage = error.localizedDescription
      }
    }

    func deleteAccount() async {
      guard !isBusy,
        rehydrateProtectedState(),
        !hasPendingMutation,
        let configuration,
        isConnected
      else { return }
      isBusy = true
      defer { isBusy = false }
      do {
        let journalStore = try requireJournalStore()
        let token = try await authorizedToken()
        guard let ownerBinding = token.ownerBinding else {
          throw HostedOAuthError.invalidToken
        }
        let pending = HostedPendingMutation(
          kind: .deleteAccount,
          expectedRevision: nil,
          targetRevision: nil,
          previousConsentState: nil,
          previousConsent: consent,
          proposedConsent: nil,
          resourceURL: configuration.resourceURL,
          clientID: configuration.clientID,
          issuer: token.issuer,
          ownerBinding: ownerBinding,
          createdAt: Date()
        )
        try savePendingMutation(pending)
        automaticSyncEnabled = false
        consent = nil
        do {
          _ = try await dataClient.deleteAccount(
            configuration: configuration,
            token: token
          )
        } catch {
          if Self.isKnownNoMutationResponse(error) {
            try abandonPendingMutation(pending)
          }
          throw error
        }
        try await finalizeAccountDeletion(journalStore: journalStore)
        statusMessage = "Hosted Health.md account data deleted"
      } catch {
        statusMessage = error.localizedDescription
      }
    }

    private func refreshStatus(using suppliedToken: HostedOAuthToken) async throws {
      guard let configuration else { throw HostedOAuthError.notConfigured }
      var token = suppliedToken
      do {
        remoteStatus = try await verifiedStatus(
          configuration: configuration,
          token: token
        )
      } catch HostedDataClientError.unauthorized {
        token = try await authorizedToken(forceRefresh: true)
        remoteStatus = try await verifiedStatus(
          configuration: configuration,
          token: token
        )
      }
      hasPendingMutation = try tokenStore.pendingMutationRecordExists()
      if hasPendingMutation {
        guard let ownerBinding = token.ownerBinding,
          let pending = try tokenStore.loadPendingMutation(),
          pending.canUse(
            configuration: configuration,
            issuer: token.issuer,
            ownerBinding: ownerBinding
          )
        else {
          throw HostedAccountTokenStoreError.persistenceFailed
        }
        if try await reconcilePendingMutation(
          pending,
          configuration: configuration,
          token: token
        ) {
          return
        }
      }
      if let localConsent = consent,
        token.ownerBinding == nil
          || !localConsent.canUse(
            configuration: configuration,
            issuer: token.issuer,
            ownerBinding: token.ownerBinding ?? ""
          )
          || remoteStatus?.consentState != .active
          || remoteStatus?.consentRevision != localConsent.revision
      {
        let journalStore = try requireJournalStore()
        try await journalStore.reset()
        try tokenStore.removeConsent()
        consent = nil
        automaticSyncEnabled = false
      }
    }

    private func journalBinding(for consent: HostedLocalConsent) -> HostedSyncJournalBinding {
      HostedSyncJournalBinding(
        resourceURL: consent.resourceURL,
        clientID: consent.clientID,
        issuer: consent.issuer,
        ownerBinding: consent.ownerBinding
      )
    }

    private func consentRequest(for consent: HostedLocalConsent) -> HostedConsentRequest {
      HostedConsentRequest(
        revision: consent.revision,
        allowedMetricIDs: consent.metricIDs.sorted(),
        allowedSourceIDs: consent.sourceIDs.sorted(),
        allowedProviderIDs: consent.providerIDs.sorted(),
        maximumDetail: consent.maximumDetail,
        retentionDays: consent.retentionDays,
        expiresAt: nil
      )
    }

    private func verifiedStatus(
      configuration: HostedAccountConfiguration,
      token: HostedOAuthToken
    ) async throws -> HostedControlStatus {
      guard let ownerBinding = token.ownerBinding else {
        throw HostedOAuthError.invalidToken
      }
      let status = try await dataClient.status(
        configuration: configuration,
        token: token
      )
      guard status.ownerBinding == ownerBinding else {
        throw HostedOAuthError.invalidToken
      }
      return status
    }

    private func reconcilePendingMutation(
      _ pending: HostedPendingMutation,
      configuration: HostedAccountConfiguration,
      token: HostedOAuthToken
    ) async throws -> Bool {
      guard let ownerBinding = token.ownerBinding,
        pending.canUse(
          configuration: configuration,
          issuer: token.issuer,
          ownerBinding: ownerBinding
        )
      else {
        throw HostedOAuthError.invalidToken
      }
      let journalStore = try requireJournalStore()
      switch pending.kind {
      case .replaceConsent:
        guard let expected = pending.expectedRevision,
          let target = pending.targetRevision,
          let proposed = pending.proposedConsent
        else {
          throw HostedAccountTokenStoreError.persistenceFailed
        }
        let remoteRevision = remoteStatus?.consentRevision ?? 0
        if remoteRevision > target
          || (remoteRevision == target && remoteStatus?.consentState != .active)
        {
          try await resolveSupersededMutation(
            remoteRevision: remoteStatus?.consentRevision,
            journalStore: journalStore
          )
          return false
        }
        if remoteStatus?.consentState == .active, remoteRevision == target {
          let replay: HostedConsentResult
          do {
            replay = try await dataClient.replaceConsent(
              consentRequest(for: proposed),
              configuration: configuration,
              token: token
            )
          } catch HostedDataClientError.consentRevisionStale {
            remoteStatus = try await verifiedStatus(
              configuration: configuration,
              token: token
            )
            if (remoteStatus?.consentRevision ?? 0) >= target {
              try await resolveSupersededMutation(
                remoteRevision: remoteStatus?.consentRevision,
                journalStore: journalStore
              )
              return false
            }
            throw HostedDataClientError.consentRevisionStale
          }
          guard replay.consentRevision == target,
            replay.consentState == "active"
          else {
            throw HostedDataClientError.invalidResponse
          }
          try await journalStore.reset(
            binding: journalBinding(for: proposed),
            consentRevision: target
          )
          try tokenStore.save(proposed)
          consent = proposed
          automaticSyncEnabled = proposed.automaticSyncEnabled
          try removePendingMutation()
          return false
        }
        guard let predecessorState = pending.previousConsentState,
          remoteStatus?.consentState == predecessorState,
          remoteRevision == expected
        else {
          throw HostedDataClientError.consentRevisionStale
        }
        do {
          _ = try await dataClient.replaceConsent(
            consentRequest(for: proposed),
            configuration: configuration,
            token: token
          )
        } catch HostedDataClientError.consentRevisionStale {
          remoteStatus = try await verifiedStatus(
            configuration: configuration,
            token: token
          )
          if (remoteStatus?.consentRevision ?? 0) >= target {
            try await resolveSupersededMutation(
              remoteRevision: remoteStatus?.consentRevision,
              journalStore: journalStore
            )
            return false
          }
          throw HostedDataClientError.consentRevisionStale
        }
        remoteStatus = try await verifiedStatus(
          configuration: configuration,
          token: token
        )
        guard remoteStatus?.consentState == .active,
          remoteStatus?.consentRevision == target
        else {
          throw HostedDataClientError.invalidResponse
        }
        try await journalStore.reset(
          binding: journalBinding(for: proposed),
          consentRevision: target
        )
        try tokenStore.save(proposed)
        consent = proposed
        automaticSyncEnabled = proposed.automaticSyncEnabled
        try removePendingMutation()
        return false

      case .revokeConsent:
        guard let expected = pending.expectedRevision,
          let target = pending.targetRevision
        else {
          throw HostedAccountTokenStoreError.persistenceFailed
        }
        let remoteRevision = remoteStatus?.consentRevision ?? 0
        if remoteRevision > target
          || (remoteRevision == target && remoteStatus?.consentState != .missing)
        {
          try await resolveSupersededMutation(
            remoteRevision: remoteStatus?.consentRevision,
            journalStore: journalStore
          )
          return false
        }
        if remoteStatus?.consentState == .missing, remoteRevision == target {
          try await journalStore.reset()
          try tokenStore.removeConsent()
          try removePendingMutation()
          consent = nil
          automaticSyncEnabled = false
          return false
        }
        guard let predecessorState = pending.previousConsentState,
          remoteStatus?.consentState == predecessorState,
          remoteRevision == expected
        else {
          throw HostedDataClientError.consentRevisionStale
        }
        do {
          _ = try await dataClient.revokeConsent(
            .init(expectedRevision: expected, revision: target),
            configuration: configuration,
            token: token
          )
        } catch HostedDataClientError.consentRevisionStale {
          remoteStatus = try await verifiedStatus(
            configuration: configuration,
            token: token
          )
          if (remoteStatus?.consentRevision ?? 0) >= target {
            try await resolveSupersededMutation(
              remoteRevision: remoteStatus?.consentRevision,
              journalStore: journalStore
            )
            return false
          }
          throw HostedDataClientError.consentRevisionStale
        }
        remoteStatus = try await verifiedStatus(
          configuration: configuration,
          token: token
        )
        guard remoteStatus?.consentState == .missing,
          remoteStatus?.consentRevision == target
        else {
          throw HostedDataClientError.invalidResponse
        }
        try await journalStore.reset()
        try tokenStore.removeConsent()
        try removePendingMutation()
        consent = nil
        automaticSyncEnabled = false
        return false

      case .deleteAccount:
        _ = try await dataClient.deleteAccount(
          configuration: configuration,
          token: token
        )
        try await finalizeAccountDeletion(journalStore: journalStore)
        return true
      }
    }

    private func resolveSupersededMutation(
      remoteRevision: UInt64?,
      journalStore: HostedSyncJournalStore
    ) async throws {
      _ = remoteRevision
      try await journalStore.reset()
      try tokenStore.removeConsent()
      try removePendingMutation()
      consent = nil
      automaticSyncEnabled = false
    }

    private static func isKnownNoMutationResponse(_ error: Error) -> Bool {
      guard let error = error as? HostedDataClientError else { return false }
      switch error {
      case .invalidRequest, .unauthorized, .consentRequired, .consentRevisionStale,
        .payloadTooLarge:
        return true
      case .server(_, let retryable):
        return !retryable
      case .temporarilyUnavailable, .invalidResponse:
        return false
      }
    }

    /// Restore the last verified local state after an authoritative response proves the remote
    /// mutation was rejected before commit. The recovery tombstone is retired last.
    private func abandonPendingMutation(_ mutation: HostedPendingMutation) throws {
      if let previous = mutation.previousConsent {
        try tokenStore.save(previous)
        consent = previous
        automaticSyncEnabled = previous.automaticSyncEnabled
      } else {
        try tokenStore.removeConsent()
        consent = nil
        automaticSyncEnabled = false
      }
      try removePendingMutation()
    }

    private func savePendingMutation(_ mutation: HostedPendingMutation) throws {
      do {
        try tokenStore.save(mutation)
        hasPendingMutation = true
      } catch {
        if (try? tokenStore.pendingMutationRecordExists()) == true {
          hasPendingMutation = true
          corruptMutationRecovery = try? tokenStore.loadPendingMutationRecovery()
          if (try? tokenStore.loadPendingMutation()) == nil {
            hasCorruptProtectedState = true
          }
        }
        throw error
      }
    }

    private func removePendingMutation() throws {
      try tokenStore.removePendingMutation()
      hasPendingMutation = false
    }

    private func finalizeAccountDeletion(
      journalStore: HostedSyncJournalStore
    ) async throws {
      // The tombstone remains authoritative until every local privacy artifact
      // has been removed. A failure at any earlier step is safely retryable.
      try await journalStore.reset()
      try tokenStore.removeConsent()
      try tokenStore.removeRefreshCandidate()
      try tokenStore.removeToken()
      try removePendingMutation()
      consent = nil
      automaticSyncEnabled = false
      remoteStatus = nil
      corruptMutationRecovery = nil
      hasCorruptProtectedState = false
      isConnected = false
    }

    private func refreshCandidate(
      _ candidate: HostedOAuthToken,
      ownerBinding: String,
      configuration: HostedAccountConfiguration
    ) async throws -> HostedOAuthToken {
      if let refreshTask { return try await refreshTask.value }
      let task = Task { [oauthClient, dataClient, tokenStore] in
        let endpoints = try await oauthClient.discoverEndpoints(
          configuration: configuration
        )
        let refreshed = try await oauthClient.refresh(
          candidate,
          endpoints: endpoints,
          configuration: configuration
        )
        guard refreshed.ownerBinding == ownerBinding else {
          throw HostedOAuthError.invalidToken
        }
        try tokenStore.saveRefreshCandidate(refreshed)
        let status = try await dataClient.status(
          configuration: configuration,
          token: refreshed
        )
        guard status.ownerBinding == ownerBinding else {
          throw HostedOAuthError.invalidToken
        }
        try tokenStore.promoteRefreshCandidate(refreshed)
        return refreshed
      }
      refreshTask = task
      defer { refreshTask = nil }
      do {
        return try await task.value
      } catch {
        isConnected = false
        if error as? HostedOAuthError == .invalidGrant {
          try tokenStore.removeRefreshCandidate()
        }
        throw error
      }
    }

    private func authorizedToken(forceRefresh: Bool = false) async throws -> HostedOAuthToken {
      guard let configuration else {
        isConnected = false
        throw HostedDataClientError.unauthorized
      }
      let current = try tokenStore.loadToken()
      if let candidate = try tokenStore.loadRefreshCandidate() {
        guard let candidateBinding = candidate.ownerBinding,
          candidate.isPersistable,
          candidate.canUse(
            configuration: configuration,
            ownerBinding: candidateBinding
          ),
          current.map({
            $0.ownerBinding == candidateBinding && $0.issuer == candidate.issuer
          }) ?? true
        else {
          throw HostedAccountTokenStoreError.corrupt
        }
        if forceRefresh || candidate.needsRefresh() {
          return try await refreshCandidate(
            candidate,
            ownerBinding: candidateBinding,
            configuration: configuration
          )
        }
        do {
          let status = try await dataClient.status(
            configuration: configuration,
            token: candidate
          )
          guard status.ownerBinding == candidateBinding else {
            throw HostedOAuthError.invalidToken
          }
          try tokenStore.promoteRefreshCandidate(candidate)
          return candidate
        } catch HostedDataClientError.unauthorized {
          return try await refreshCandidate(
            candidate,
            ownerBinding: candidateBinding,
            configuration: configuration
          )
        }
      }
      guard let current,
        let ownerBinding = current.ownerBinding,
        current.isPersistable,
        current.canUse(
          configuration: configuration,
          ownerBinding: ownerBinding
        )
      else {
        isConnected = false
        throw HostedDataClientError.unauthorized
      }
      if !forceRefresh, !current.needsRefresh() { return current }
      if let refreshTask { return try await refreshTask.value }
      let task = Task { [oauthClient, dataClient, tokenStore] in
        let endpoints = try await oauthClient.discoverEndpoints(
          configuration: configuration
        )
        let refreshed = try await oauthClient.refresh(
          current,
          endpoints: endpoints,
          configuration: configuration
        )
        guard refreshed.ownerBinding == ownerBinding else {
          throw HostedOAuthError.invalidToken
        }
        // Rotation can invalidate `current` before any later network request. Persist the new
        // owner-bound credential first, then verify its principal and promote it atomically.
        try tokenStore.saveRefreshCandidate(refreshed)
        let status = try await dataClient.status(
          configuration: configuration,
          token: refreshed
        )
        guard status.ownerBinding == ownerBinding else {
          throw HostedOAuthError.invalidToken
        }
        try tokenStore.promoteRefreshCandidate(refreshed)
        return refreshed
      }
      refreshTask = task
      defer { refreshTask = nil }
      do {
        return try await task.value
      } catch {
        isConnected = false
        throw error
      }
    }

    private func uploadBatch(
      _ batch: [HostedSyncDay],
      consent: HostedLocalConsent,
      configuration: HostedAccountConfiguration,
      journalStore: HostedSyncJournalStore,
      requiresForeground: Bool
    ) async throws -> (changed: Int, unchanged: Int) {
      let request = HostedSyncRequest(
        expectedConsentRevision: consent.revision,
        days: batch
      )
      var token = try await authorizedToken()
      let result: HostedSyncResult
      do {
        try Task.checkCancellation()
        try requireForegroundIfNeeded(requiresForeground)
        result = try await dataClient.upload(
          request,
          configuration: configuration,
          token: token
        )
      } catch HostedDataClientError.unauthorized {
        token = try await authorizedToken(forceRefresh: true)
        try Task.checkCancellation()
        try requireForegroundIfNeeded(requiresForeground)
        result = try await dataClient.upload(
          request,
          configuration: configuration,
          token: token
        )
      }
      try await journalStore.record(
        binding: journalBinding(for: consent),
        consentRevision: consent.revision,
        days: Dictionary(
          uniqueKeysWithValues: batch.map {
            ($0.day.ownerDate, $0.digestSHA256)
          })
      )
      return (result.changedDayCount, result.unchangedDayCount)
    }

    private func captureDay(
      date: Date,
      consent: HostedLocalConsent,
      selection: MetricSelectionState,
      timeZone: TimeZone,
      healthKitManager: HealthKitManager
    ) async throws -> HostedSyncDay? {
      let outcome = try await HealthKitDailyCapture.capture(
        date: date,
        includeGranularData: consent.maximumDetail == .lossless,
        metricSelection: selection,
        transform: .sanitizeGranularAndFilter,
        emptyRecordPolicy: .retain,
        fetchExternalRecords: false,
        failurePolicy: .connectedMac,
        fetchHealthData: { date, includeGranularData, metricSelection in
          try await healthKitManager.fetchHealthData(
            for: date,
            includeGranularData: includeGranularData,
            metricSelection: metricSelection,
            timeZone: timeZone
          )
        },
        fetchExternalDailyRecords: nil
      )
      guard let record = outcome.record else { return nil }
      let day = try HealthMdQueryContextProjector.project(
        record,
        options: .init(
          enabledMetricIDs: consent.metricIDs,
          includesAppleHealth: true
        )
      )
      let synchronizedDay = try HostedSyncDay(day: day, consent: consent)
      let data = try HealthMdQueryCanonicalSerializer.data(for: synchronizedDay.day)
      guard data.count <= HostedDataClient.maximumDayBytes else {
        throw HostedDataClientError.payloadTooLarge
      }
      return synchronizedDay
    }

    private func runAuthenticationSession(url: URL) async throws -> URL {
      try Task.checkCancellation()
      let cancellation = HostedAuthenticationSessionCancellation()
      return try await withTaskCancellationHandler {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
          let completion = HostedAuthenticationSessionCompletion(continuation)
          let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "healthmd"
          ) { [weak self] callbackURL, error in
            cancellation.clear()
            Task { @MainActor in self?.authSession = nil }
            if let error {
              completion.resume(.failure(error))
            } else if let callbackURL {
              completion.resume(.success(callbackURL))
            } else {
              completion.resume(.failure(HostedOAuthError.invalidCallback))
            }
          }
          session.presentationContextProvider = self
          session.prefersEphemeralWebBrowserSession = true
          authSession = session
          guard cancellation.store(session) else {
            authSession = nil
            completion.resume(.failure(CancellationError()))
            return
          }
          guard session.start() else {
            cancellation.clear()
            authSession = nil
            completion.resume(.failure(HostedOAuthError.invalidCallback))
            return
          }
        }
      } onCancel: {
        cancellation.cancel()
      }
    }

    nonisolated static func authorizationCode(
      _ url: URL,
      expectedState: String
    ) throws -> String {
      guard url.absoluteString.utf8.count <= 16 * 1_024,
        url.scheme?.lowercased() == "healthmd",
        url.host?.lowercased() == "hosted",
        url.user == nil,
        url.password == nil,
        url.port == nil,
        url.path == "/callback",
        url.fragment == nil,
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        let items = components.queryItems,
        items.count <= 8,
        items.filter({ $0.name == "error" }).isEmpty
      else {
        throw HostedOAuthError.invalidCallback
      }
      let states = items.filter { $0.name == "state" }
      let codes = items.filter { $0.name == "code" }
      guard states.count == 1,
        states[0].value == expectedState,
        codes.count == 1,
        let code = codes[0].value,
        !code.isEmpty,
        code.utf8.count <= 8 * 1_024
      else {
        throw HostedOAuthError.invalidCallback
      }
      guard items.allSatisfy({ ["state", "code"].contains($0.name) }) else {
        throw HostedOAuthError.invalidCallback
      }
      return code
    }
  }

  extension HostedAccountManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
      UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
  }

  private nonisolated final class HostedAuthenticationSessionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var session: ASWebAuthenticationSession?
    private var isCancelled = false

    func store(_ session: ASWebAuthenticationSession) -> Bool {
      lock.lock()
      defer { lock.unlock() }
      guard !isCancelled else { return false }
      self.session = session
      return true
    }

    func clear() {
      lock.lock()
      session = nil
      lock.unlock()
    }

    func cancel() {
      lock.lock()
      isCancelled = true
      let current = session
      session = nil
      lock.unlock()
      current?.cancel()
    }
  }

  private nonisolated final class HostedAuthenticationSessionCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?

    init(_ continuation: CheckedContinuation<URL, Error>) {
      self.continuation = continuation
    }

    func resume(_ result: Result<URL, Error>) {
      lock.lock()
      let continuation = continuation
      self.continuation = nil
      lock.unlock()
      continuation?.resume(with: result)
    }
  }

  nonisolated enum HostedSyncError: LocalizedError, Equatable {
    case healthAuthorizationRequired
    case noCompletedDays

    var errorDescription: String? {
      switch self {
      case .healthAuthorizationRequired:
        return "Review Apple Health access before synchronizing hosted data."
      case .noCompletedDays:
        return "No completed Apple Health days were available to synchronize."
      }
    }
  }

  extension UInt64 {
    fileprivate nonisolated var nonzero: UInt64? { self == 0 ? nil : self }
  }
#endif
