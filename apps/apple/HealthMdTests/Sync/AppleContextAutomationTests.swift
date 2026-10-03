import Foundation
import XCTest
@testable import HealthMd
#if os(iOS)
import AppIntents
#endif

/// Synthetic native tests, not physical authentication/automation qualification.
@MainActor
final class AppleContextAutomationTests: XCTestCase {
    private var root: URL!
    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("context-automation-\(UUID().uuidString)")
    }
    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        super.tearDown()
    }

    private func request(id: UUID = UUID(), phone: UUID = UUID(), mac: UUID = UUID(), metric: String = "steps") -> AppleContextRequest {
        let formatter = AppleContextRequest.formatter(zone: TimeZone(identifier: "UTC")!)
        let day = formatter.date(from: "2026-01-02")!
        return AppleContextRequest(id: id, phoneInstallationID: phone, macInstallationID: mac,
            profileID: UUID(), ownerDates: ["2026-01-02"], timeZoneIdentifier: "UTC",
            startDate: day, endDate: day, selection: .init(metricIDs: [metric]))
    }
    private func service(peerID: UUID) -> SyncService {
        let service = LifecycleHarness.retain(SyncService())
        service.testSetAuthenticatedContextPeer(peerID)
        service.remoteCapabilities = .current(platform: SyncPlatform.current == .iOS ? .macOS : .iOS, installationID: peerID)
        return service
    }

    func testProductAutomationInventoryIsSeparateFromFrozenMetricAuthorityAndHasConcreteParityTargets() throws {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("packages/contracts/product-automation-capabilities-v1.json").path) {
            directory.deleteLastPathComponent()
        }
        let data = try Data(contentsOf: directory.appendingPathComponent("packages/contracts/product-automation-capabilities-v1.json"))
        let inventory = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(inventory["schema"] as? String, "healthmd.product_automation_capabilities")
        XCTAssertEqual(inventory["schema_version"] as? Int, 1)
        XCTAssertEqual(inventory["metric_authority"] as? Bool, false)
        let capabilities = try XCTUnwrap(inventory["capabilities"] as? [[String: Any]])
        XCTAssertEqual(capabilities.count, 1)
        XCTAssertEqual(capabilities.first?["id"] as? String, "automation.refresh-encrypted-desktop-context")
        XCTAssertEqual(capabilities.first?["classification"] as? String, "planned")
        let platforms = try XCTUnwrap(capabilities.first?["platforms"] as? [String: [String: Any]])
        for platform in ["apple", "android"] {
            XCTAssertEqual(platforms[platform]?["state"] as? String, "planned")
            XCTAssertFalse((platforms[platform]?["target"] as? String ?? "").isEmpty)
        }
        let frozen = try String(contentsOf: directory.appendingPathComponent("packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json"), encoding: .utf8)
        XCTAssertFalse(frozen.contains("automation.refresh-encrypted-desktop-context"))
    }

    func testLegacyCapabilityMissingOrFalseAndUnauthenticatedOrWrongRoleNeverSend() throws {
        let peerID = UUID()
        let service = service(peerID: peerID)
        XCTAssertTrue(service.canUsePhoneContextAutomation)
        var sends = 0
        service.testMessageSendObserver = { _ in sends += 1 }
        let request = request()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(service.remoteCapabilities!)) as? [String: Any])
        object.removeValue(forKey: "supportsPhoneContextAutomation")
        service.remoteCapabilities = try JSONDecoder().decode(SyncPeerCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(service.remoteCapabilities!.supportsPhoneContextAutomation)
        service.send(.appleContext(.refresh(request)))
        object["supportsPhoneContextAutomation"] = false
        service.remoteCapabilities = try JSONDecoder().decode(SyncPeerCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
        service.send(.appleContext(.status(request)))
        service.remoteCapabilities = .current(platform: .current, installationID: peerID)
        service.send(.appleContext(.status(request)))
        service.remoteCapabilities = .current(platform: SyncPlatform.current == .iOS ? .macOS : .iOS, installationID: UUID())
        service.send(.appleContext(.status(request)))
        service.testSetAuthenticatedContextPeer(nil)
        service.remoteCapabilities = .current(platform: SyncPlatform.current == .iOS ? .macOS : .iOS, installationID: peerID)
        service.send(.appleContext(.status(request)))
        XCTAssertEqual(sends, 0)
    }

    func testProductionIngressNegotiatesHelloSynchronouslyAndRejectsForeignOrDisabledFamily() throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let capabilities = service.remoteCapabilities!
        service.remoteCapabilities = nil
        var contexts = 0
        service.onMessageReceived = { message in
            if case .appleContext = message { contexts += 1 }
        }
        service.testReceiveDecryptedContextMessage(try JSONEncoder().encode(SyncMessage.hello(capabilities)))
        XCTAssertTrue(service.canUsePhoneContextAutomation)
        service.testReceiveDecryptedContextMessage(try JSONEncoder().encode(SyncMessage.appleContext(.status(request()))))
        XCTAssertEqual(contexts, 1)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(capabilities)) as? [String: Any])
        object["supportsPhoneContextAutomation"] = false
        let disabled = try JSONDecoder().decode(SyncPeerCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
        service.testReceiveDecryptedContextMessage(try JSONEncoder().encode(SyncMessage.hello(disabled)))
        service.testReceiveDecryptedContextMessage(try JSONEncoder().encode(SyncMessage.appleContext(.status(request()))))
        XCTAssertEqual(contexts, 1)
        let foreign = SyncPeerCapabilities.current(platform: capabilities.platform, installationID: UUID())
        service.testReceiveDecryptedContextMessage(try JSONEncoder().encode(SyncMessage.hello(foreign)))
        XCTAssertEqual(service.remoteCapabilities, disabled)
        service.testReceiveDecryptedContextMessage(try JSONEncoder().encode(SyncMessage.appleContext(.status(request()))))
        XCTAssertEqual(contexts, 1)
    }

    func testRequestRejectsHostPathRawPointersUnknownFieldsAndNoncanonicalDates() throws {
        let request = request()
        XCTAssertTrue(request.isValid)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        for key in ["host", "path", "destination", "raw_profile", "url"] {
            var altered = object
            altered[key] = "not-allowed"
            XCTAssertThrowsError(try JSONDecoder().decode(AppleContextRequest.self, from: JSONSerialization.data(withJSONObject: altered)))
        }
        var selection = try XCTUnwrap(object["selection"] as? [String: Any])
        selection["field_pointers"] = ["/activity/steps"]
        object["selection"] = selection
        XCTAssertFalse(try JSONDecoder().decode(AppleContextRequest.self, from: JSONSerialization.data(withJSONObject: object)).isValid)
        selection["field_pointers"] = []
        selection["raw_profile"] = "canonical_source_records_v1"
        object["selection"] = selection
        XCTAssertThrowsError(try JSONDecoder().decode(AppleContextRequest.self, from: JSONSerialization.data(withJSONObject: object)))
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        object["ownerDates"] = ["2026-1-2"]
        XCTAssertFalse(try JSONDecoder().decode(AppleContextRequest.self, from: JSONSerialization.data(withJSONObject: object)).isValid)
    }

    func testDurableIdentityRejectsProfilePeerDateSourceDetailMutationAndRestoresWithoutAck() throws {
        let request = request()
        let journal = AppleContextJournal(root: root)
        try journal.admit(request)
        try journal.admit(request)
        let restored = AppleContextJournal(root: root)
        XCTAssertEqual(restored.record(request.id)?.request, request)
        XCTAssertNil(restored.record(request.id)?.receipt)
        var original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        for key in ["profileID", "phoneInstallationID", "macInstallationID"] {
            var object = original
            object[key] = UUID().uuidString
            let changed = try JSONDecoder().decode(AppleContextRequest.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertThrowsError(try restored.admit(changed))
        }
        original["timeZoneIdentifier"] = "America/New_York"
        XCTAssertThrowsError(try restored.admit(JSONDecoder().decode(AppleContextRequest.self, from: JSONSerialization.data(withJSONObject: original))))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        var selection = try XCTUnwrap(object["selection"] as? [String: Any])
        selection["detail_level"] = "lossless"
        object["selection"] = selection
        XCTAssertThrowsError(try restored.admit(JSONDecoder().decode(AppleContextRequest.self, from: JSONSerialization.data(withJSONObject: object))))
        selection["source_ids"] = ["foreign_source"]
        object["selection"] = selection
        XCTAssertThrowsError(try restored.admit(JSONDecoder().decode(AppleContextRequest.self, from: JSONSerialization.data(withJSONObject: object))))
        XCTAssertEqual(restored.allRecords.count, 1)
    }

    func testReceiptsArePersistedPeerScopeRequestBoundMonotonicAndTerminal() throws {
        let request = request()
        let journal = AppleContextJournal(root: root)
        try journal.admit(request)
        let pending = AppleContextReceipt(request: request, revision: 2, state: .pending)
        XCTAssertFalse(try journal.accept(pending, authenticatedPeer: UUID(), localID: request.phoneInstallationID, onPhone: true))
        XCTAssertTrue(try journal.accept(pending, authenticatedPeer: request.macInstallationID, localID: request.phoneInstallationID, onPhone: true))
        let obsolete = AppleContextReceipt(request: request, revision: 1, state: .completed)
        XCTAssertFalse(try journal.accept(obsolete, authenticatedPeer: request.macInstallationID, localID: request.phoneInstallationID, onPhone: true))
        let foreign = AppleContextReceipt(request: self.request(id: request.id, phone: request.phoneInstallationID, mac: request.macInstallationID), revision: 9, state: .completed)
        XCTAssertFalse(try journal.accept(foreign, authenticatedPeer: request.macInstallationID, localID: request.phoneInstallationID, onPhone: true))
        let terminal = AppleContextReceipt(request: request, revision: 3, state: .completed)
        journal.failWritesForTesting = true
        XCTAssertThrowsError(try journal.accept(terminal, authenticatedPeer: request.macInstallationID, localID: request.phoneInstallationID, onPhone: true))
        XCTAssertEqual(journal.record(request.id)?.receipt, pending)
        journal.failWritesForTesting = false
        XCTAssertTrue(try journal.accept(terminal, authenticatedPeer: request.macInstallationID, localID: request.phoneInstallationID, onPhone: true))
        XCTAssertFalse(try journal.accept(.init(request: request, revision: 4, state: .pending), authenticatedPeer: request.macInstallationID, localID: request.phoneInstallationID, onPhone: true))
        XCTAssertEqual(AppleContextJournal(root: root).record(request.id)?.receipt, terminal)
    }

    #if os(iOS)
    func testPhoneProductionAdapterFreezesProfileBeforeSendAndRecoversLostAckWithoutQuota() throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let defaults = UserDefaults(suiteName: "context-phone-\(UUID().uuidString)")!
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.detailPolicy = .summary
        let profiles = LifecycleHarness.retain(ExportProfileStore(userDefaults: defaults))
        let profile = profiles.add(name: "Context", settings: .from(settings), target: .connectedMac)
        let journalRoot = root.appendingPathComponent("phone")
        let bindings = root.appendingPathComponent("bindings")
        let journal = AppleContextJournal(root: journalRoot)
        let client = AppleContextPhoneClient(journal: journal, bindingRoot: bindings, protectedDataAvailable: { true }, executionBlocked: { _ in false })
        client.install(service)
        try client.bind(profileID: profile.id)
        var sent: [AppleContextRequest] = []
        service.testMessageSendObserver = { message in
            if case .appleContext(.refresh(let request)) = message {
                XCTAssertNotNil(journal.record(request.id), "Identity must already be durable before send")
                sent.append(request)
            }
        }
        let day = request().startDate
        let quotaBefore = PurchaseManager.shared.freeExportsUsed
        let entity = try client.refresh(profileName: "Context", startDate: day, endDate: day, profiles: profiles)
        let frozen = try XCTUnwrap(sent.first)
        XCTAssertEqual(frozen.profileID, profile.id)
        XCTAssertEqual(frozen.selection.metricIDs, ["steps"])
        settings.metricSelection.enabledMetrics = ["heart_rate"]
        profiles.updateSettings(id: profile.id, settings: .from(settings))
        let restarted = AppleContextPhoneClient(journal: AppleContextJournal(root: journalRoot), bindingRoot: bindings, protectedDataAvailable: { true })
        restarted.install(service)
        var statusScope: AppleContextRequest?
        service.testMessageSendObserver = { message in
            if case .appleContext(.status(let request)) = message { statusScope = request }
        }
        XCTAssertEqual(try restarted.status(id: UUID(uuidString: entity.id)!).status, "pending")
        XCTAssertEqual(statusScope, frozen)
        XCTAssertEqual(PurchaseManager.shared.freeExportsUsed, quotaBefore)
        XCTAssertEqual(sent.count, 1)
        service.connectionState = .disconnected
        XCTAssertEqual(try restarted.status(id: frozen.id).status, "unavailable")
    }

    func testPhoneFailedPersistenceUnknownIneligibleUnboundAndLockedProfilesNeverSend() throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let defaults = UserDefaults(suiteName: "context-profile-\(UUID().uuidString)")!
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        settings.metricSelection.enabledMetrics = ["steps"]
        let profiles = LifecycleHarness.retain(ExportProfileStore(userDefaults: defaults))
        let profile = profiles.add(name: "Context", settings: .from(settings), target: .connectedMac)
        let journal = AppleContextJournal(root: root.appendingPathComponent("phone"))
        var locked = false
        let client = AppleContextPhoneClient(journal: journal, bindingRoot: root.appendingPathComponent("bindings"), protectedDataAvailable: { !locked }, executionBlocked: { _ in false })
        client.install(service)
        var sends = 0
        service.testMessageSendObserver = { _ in sends += 1 }
        let day = request().startDate
        XCTAssertThrowsError(try client.refresh(profileName: "missing", startDate: day, endDate: day, profiles: profiles))
        XCTAssertThrowsError(try client.refresh(profileName: "Context", startDate: day, endDate: day, profiles: profiles))
        try client.bind(profileID: profile.id)
        profiles.updateTarget(id: profile.id, target: .localIPhoneFolder)
        XCTAssertThrowsError(try client.refresh(profileName: "Context", startDate: day, endDate: day, profiles: profiles))
        profiles.updateTarget(id: profile.id, target: .connectedMac)
        locked = true
        XCTAssertThrowsError(try client.refresh(profileName: "Context", startDate: day, endDate: day, profiles: profiles))
        locked = false
        journal.failWritesForTesting = true
        XCTAssertThrowsError(try client.refresh(profileName: "Context", startDate: day, endDate: day, profiles: profiles))
        XCTAssertEqual(sends, 0)
        XCTAssertTrue(journal.allRecords.isEmpty)
    }

    func testRealShortcutProviderRetainsSevenActionsAndRegistersBothContextIntents() async throws {
        XCTAssertEqual(HealthMdAppShortcuts.appShortcuts.count, 9)
        _ = RefreshMacHealthContextIntent()
        _ = GetMacContextRefreshStatusIntent()
        // Actual public EntityQuery resolves only persisted IDs, not caller identities.
        let values = try await MacContextRefreshQuery().entities(for: [UUID().uuidString])
        XCTAssertTrue(values.isEmpty)
        var refresh = RefreshMacHealthContextIntent()
        refresh.profile = "unknown-context-profile-\(UUID().uuidString)"
        refresh.startDate = Date()
        refresh.endDate = Date()
        do { _ = try await refresh.perform(); XCTFail("Actual intent must reject unknown profiles") }
        catch { }
        var status = GetMacContextRefreshStatusIntent()
        status.request = MacContextRefreshEntity(id: UUID().uuidString, status: "pending")
        do { _ = try await status.perform(); XCTFail("Actual intent must reject unknown requests") }
        catch { }
    }
    #endif

    #if os(macOS)
    private func destination(_ service: SyncService) -> MacDestinationStatus {
        .init(isConnected: true, isReadyForExports: false, destinationFolderSelected: false,
              folderAccessHealthy: false, destinationDisplayName: nil, destinationPathForDisplay: nil,
              lastError: nil, activeJobID: nil, capabilities: service.localCapabilities)
    }

    func testMacFailedMappingAndJobPersistenceNeverAcknowledgeOrDispatch() async throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let scope = request(phone: peer, mac: service.installationID)
        let journal = AppleContextJournal(root: root.appendingPathComponent("mapping"))
        let adapter = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: journal, contextReadiness: { nil }))
        let jobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: root.appendingPathComponent("jobs")))
        var sends = 0
        service.testMessageSendObserver = { _ in sends += 1 }
        journal.failWritesForTesting = true
        adapter.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
        await Task.yield()
        XCTAssertEqual(sends, 0)
        journal.failWritesForTesting = false
        jobs.failNextPersistForTesting = true
        adapter.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(jobs.jobResponse(jobID: scope.id).failureReason, "job_not_found")
    }

    func testMacRoundTripDoesNotBlockIngressAndCompletesOnlyAfterEncryptedCommitWithoutFiles() async throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let scope = request(phone: peer, mac: service.installationID)
        let mappingRoot = root.appendingPathComponent("mapping")
        let adapter = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: AppleContextJournal(root: mappingRoot), contextReadiness: { nil }))
        let jobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: root.appendingPathComponent("jobs")))
        jobs.contextAutomationPeerAdmission = { adapter.allows(jobID: $0, sync: $1) }
        var acquisitions: [IPhoneExportRequest] = []
        var receipts: [AppleContextReceipt] = []
        service.testMessageSendObserver = { message in
            if case .iphoneExportRequest(let request) = message { acquisitions.append(request) }
            if case .appleContext(.receipt(let receipt)) = message {
                XCTAssertNotNil(jobs.contextRequest(jobID: receipt.request.id), "Job mapping must precede ack")
                receipts.append(receipt)
            }
        }
        adapter.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
        for _ in 0..<20 { await Task.yield() }
        let acquisition = try XCTUnwrap(acquisitions.first)
        XCTAssertTrue(scope.matches(acquisition))
        XCTAssertEqual(receipts.first?.state, .pending)
        adapter.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
        XCTAssertEqual(acquisitions.count, 1, "Replay must not dispatch a second acquisition")
        jobs.handleAccepted(.init(jobID: scope.id, acceptedAt: Date(), message: nil))

        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: UserDefaults(suiteName: "context-commit-\(UUID().uuidString)")!))
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.detailPolicy = .summary
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")
        let manifest = ConnectedCorpusExportManifest(mode: .encryptedContext, createdAt: Date(), sourceDeviceName: "Synthetic iPhone",
            sourceTimeZoneIdentifier: "UTC", dateRangeStart: scope.startDate, dateRangeEnd: scope.endDate,
            requestedDates: [scope.startDate], requestedDateIdentifiers: scope.ownerDates, transferDates: [scope.startDate],
            settingsSnapshot: .from(settings, calendarTimeZoneIdentifier: "UTC"),
            canonicalSelection: scope.selection, selectedSourceIDs: ["apple_health"], requestedTarget: nil)
        let session = ConnectedCorpusTransferSession(sessionID: UUID(), jobID: scope.id,
            requestFingerprint: try .make(for: manifest), partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes,
            createdAt: Date(), peerBinding: .init(sourceInstallationID: peer, destinationInstallationID: service.installationID))
        let assembler = try ConnectedCorpusPartitionAssembler(sessionID: session.sessionID, jobID: scope.id, targetBytes: session.partitionTargetBytes)
        var health = HealthData(date: scope.startDate, timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"))
        health.activity.steps = 4_321
        assembler.append(try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusHealthDayPayload(sourceDate: scope.startDate, isRequestedDate: true, record: health, externalDailyRecords: [], failure: nil),
            kind: .macHealthDay, sourceDate: scope.startDate, isRequestedDate: true))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let contextStore = EncryptedHealthContextStore(rootURL: root.appendingPathComponent("encrypted"), keyProvider: InMemoryHealthContextEncryptionKeyProvider())
        let corpus = MacCorpusExportSessionManager(rootURL: root.appendingPathComponent("corpus"), queryContextStore: contextStore)
        let fileSystem = FakeFileSystem()
        let vault = LifecycleHarness.retain(VaultManager(defaults: FakeUserDefaults(), fileSystem: fileSystem, bookmarkResolver: FakeBookmarkResolver()))
        let open = ConnectedCorpusTransferOpen(session: session, partition: partition.descriptor, exportManifest: manifest)
        XCTAssertTrue(jobs.accepts(open, localInstallationID: service.installationID, remoteInstallationID: peer))
        XCTAssertTrue(adapter.allowsMessage(.connectedCorpusTransferOpen(open), sync: service))
        var wrongZone = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
        wrongZone["sourceTimeZoneIdentifier"] = "America/New_York"
        let changedManifest = try JSONDecoder().decode(ConnectedCorpusExportManifest.self, from: JSONSerialization.data(withJSONObject: wrongZone))
        XCTAssertFalse(adapter.allowsMessage(.connectedCorpusTransferOpen(.init(session: session, partition: partition.descriptor, exportManifest: changedManifest)), sync: service))
        let disposition = corpus.open(open, vaultManager: vault, localInstallationID: service.installationID, remoteInstallationID: peer)
        XCTAssertEqual(disposition.disposition, .accept, disposition.message ?? "No admission reason")
        try await corpus.applyPartition(fileURL: partition.file.url, descriptor: partition.descriptor, vaultManager: vault)
        let stored = try await contextStore.loadDay(ownerDate: "2026-01-02")
        XCTAssertEqual(stored?.metrics.first(where: { $0.metricID == "steps" })?.value, .quantity(value: 4_321, unit: "steps"))
        let finalize = ConnectedCorpusTransferFinalize(sessionID: session.sessionID, jobID: scope.id,
            requestFingerprint: session.requestFingerprint, partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount, finalPartitionSHA256: partition.descriptor.sha256)
        let outcome = try await corpus.finalize(finalize, vaultManager: vault)
        guard case .files(let committedResult, _) = outcome else { return XCTFail("Expected committed encrypted context") }
        XCTAssertEqual(committedResult.totalFilesWritten, 0)
        XCTAssertTrue(fileSystem.files.isEmpty, "Context must never write export files")
        XCTAssertTrue(jobs.complete(with: committedResult))
        for _ in 0..<20 { await Task.yield() }
        adapter.handle(.status(scope), sync: service, jobs: jobs, destination: destination(service))
        XCTAssertEqual(receipts.last?.state, .completed)
        XCTAssertEqual(acquisitions.count, 1)
        let phoneJournal = AppleContextJournal(root: root.appendingPathComponent("phone"))
        try phoneJournal.admit(scope)
        XCTAssertTrue(try phoneJournal.accept(XCTUnwrap(receipts.last), authenticatedPeer: service.installationID, localID: peer, onPhone: true))
        XCTAssertEqual(AppleContextJournal(root: root.appendingPathComponent("phone")).record(scope.id)?.receipt?.state, .completed)
        let restarted = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: AppleContextJournal(root: mappingRoot), contextReadiness: { nil }))
        restarted.handle(.status(scope), sync: service, jobs: jobs, destination: destination(service))
        XCTAssertEqual(receipts.last?.state, .completed)
        service.testSetAuthenticatedContextPeer(UUID())
        XCTAssertFalse(restarted.allowsMessage(.connectedCorpusTransferFinalize(finalize), sync: service))
        restarted.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
        XCTAssertEqual(acquisitions.count, 1)
    }

    func testMacLockedAdmissionAndForeignPeerNeverAcquireOrClaimSuccess() throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let scope = request(phone: peer, mac: service.installationID)
        let adapter = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: AppleContextJournal(root: root), contextReadiness: { .locked }))
        let jobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: root.appendingPathComponent("jobs")))
        var receipts: [AppleContextReceipt] = []
        var acquisitions = 0
        service.testMessageSendObserver = { message in
            if case .appleContext(.receipt(let receipt)) = message { receipts.append(receipt) }
            if case .iphoneExportRequest = message { acquisitions += 1 }
        }
        adapter.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
        XCTAssertEqual(receipts.last?.state, .locked)
        XCTAssertEqual(acquisitions, 0)
        service.testSetAuthenticatedContextPeer(UUID())
        adapter.handle(.status(scope), sync: service, jobs: jobs, destination: destination(service))
        XCTAssertEqual(receipts.count, 1)
        XCTAssertFalse(adapter.allows(jobID: scope.id, sync: service))
    }
    #endif
}
