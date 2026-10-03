import Foundation
import XCTest
@testable import HealthMd
#if os(iOS)
import AppIntents
import HealthKit
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

    func testPostWriteFailuresNeverBecomeAuthorityByLookupOrRestartAndRetryKeepsIdentity() throws {
        let points: [AppleContextJournal.WriteFailurePoint] = [.afterFinalAtomicWrite, .finalFileSync, .afterFinalDirectorySync]
        for point in points {
            let directory = root.appendingPathComponent(UUID().uuidString)
            let journal = AppleContextJournal(root: directory)
            let scope = request()
            journal.writeFailurePointForTesting = point
            XCTAssertThrowsError(try journal.admit(scope))
            let candidate = try JSONDecoder().decode(AppleContextJournal.Record.self,
                from: Data(contentsOf: directory.appendingPathComponent(scope.id.uuidString + ".json")))
            XCTAssertEqual(candidate.request, scope) // REAL final atomic write happened
            XCTAssertNil(journal.record(scope.id))
            XCTAssertTrue(journal.allRecords.isEmpty)
            XCTAssertTrue(journal.hasUncertainAuthority(scope.id))
            let restarted = AppleContextJournal(root: directory)
            XCTAssertNil(restarted.record(scope.id))
            XCTAssertEqual(restarted.recoverableIDs, [scope.id])
            XCTAssertThrowsError(try restarted.admit(scope))
            XCTAssertThrowsError(try restarted.retryDurability(scope.id, expectedRequest: request(id: scope.id)))
            restarted.writeFailurePointForTesting = point
            XCTAssertThrowsError(try restarted.retryDurability(scope.id, expectedRequest: scope))
            XCTAssertNil(restarted.record(scope.id))
            restarted.writeFailurePointForTesting = nil
            XCTAssertTrue(try restarted.retryDurability(scope.id, expectedRequest: scope))
            XCTAssertEqual(AppleContextJournal(root: directory).record(scope.id)?.request, scope)
            XCTAssertFalse(restarted.hasUncertainAuthority(scope.id))
        }
    }

    func testPostWriteCompletionFailurePreservesPriorReceiptAndCorruptMarkerCannotBeAbsence() throws {
        let journal = AppleContextJournal(root: root)
        let scope = request()
        try journal.admit(scope)
        let pending = AppleContextReceipt(request: scope, revision: 1, state: .pending)
        XCTAssertTrue(try journal.accept(pending, authenticatedPeer: scope.macInstallationID, localID: scope.phoneInstallationID, onPhone: true))
        journal.writeFailurePointForTesting = .finalFileSync
        let completion = AppleContextReceipt(request: scope, revision: 2, state: .completed)
        XCTAssertThrowsError(try journal.accept(completion, authenticatedPeer: scope.macInstallationID, localID: scope.phoneInstallationID, onPhone: true))
        XCTAssertEqual(journal.record(scope.id)?.receipt, pending)
        XCTAssertEqual(AppleContextJournal(root: root).record(scope.id)?.receipt, pending)
        journal.writeFailurePointForTesting = nil
        XCTAssertTrue(try journal.retryDurability(scope.id, expectedRequest: scope))
        XCTAssertEqual(AppleContextJournal(root: root).record(scope.id)?.receipt, completion)

        let other = request()
        journal.writeFailurePointForTesting = .afterFinalAtomicWrite
        XCTAssertThrowsError(try journal.admit(other))
        try Data("corrupt transaction".utf8).write(to: root.appendingPathComponent(other.id.uuidString + ".pending.json"))
        let restarted = AppleContextJournal(root: root)
        XCTAssertNil(restarted.record(other.id))
        XCTAssertTrue(restarted.hasUncertainAuthority(other.id))
        XCTAssertThrowsError(try restarted.admit(other))
        XCTAssertThrowsError(try restarted.retryDurability(other.id, expectedRequest: other))
        XCTAssertEqual(restarted.record(scope.id)?.receipt, completion)
    }

    func testColdDirectoryErrorIsUnavailableNotAbsenceAndRestorationPreservesContents() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockedRoot = root.appendingPathComponent("not-a-directory")
        let original = Data("preserve this obstruction".utf8)
        try original.write(to: blockedRoot)
        let journal = AppleContextJournal(root: blockedRoot)
        let id = UUID()
        XCTAssertFalse(journal.isKnown(id), "Unavailable must not label all unknown UUIDs as known")
        XCTAssertEqual(journal.authorityState(id), .unavailable)
        XCTAssertThrowsError(try journal.admit(request(id: id)))
        XCTAssertEqual(try Data(contentsOf: blockedRoot), original)
        let retained = root.appendingPathComponent("retained-obstruction")
        try FileManager.default.moveItem(at: blockedRoot, to: retained)
        try FileManager.default.createDirectory(at: blockedRoot, withIntermediateDirectories: false)
        XCTAssertEqual(journal.authorityState(id), .absent)
        XCTAssertEqual(try Data(contentsOf: retained), original)
        let firstRun = AppleContextJournal(root: root.appendingPathComponent("genuine-enoent"))
        XCTAssertEqual(firstRun.authorityState(id), .absent)
        XCTAssertFalse(firstRun.isKnown(id))
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
        settings.detailPolicy = .summary
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

    func testPhonePostAtomicAdmissionAndReceiptFailuresRequireExplicitDurabilityRepairBeforeStatus() throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let defaults = UserDefaults(suiteName: "context-postwrite-\(UUID().uuidString)")!
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.detailPolicy = .summary
        let profiles = LifecycleHarness.retain(ExportProfileStore(userDefaults: defaults))
        let profile = profiles.add(name: "Context", settings: .from(settings), target: .connectedMac)
        let directory = root.appendingPathComponent("phone")
        let bindings = root.appendingPathComponent("bindings")
        let journal = AppleContextJournal(root: directory)
        let client = AppleContextPhoneClient(journal: journal, bindingRoot: bindings, protectedDataAvailable: { true }, executionBlocked: { _ in false })
        client.install(service)
        try client.bind(profileID: profile.id)
        var sends = 0
        service.testMessageSendObserver = { _ in sends += 1 }
        journal.writeFailurePointForTesting = .afterFinalAtomicWrite
        XCTAssertThrowsError(try client.refresh(profileName: "Context", startDate: Date(), endDate: Date(), profiles: profiles))
        let id = try XCTUnwrap(journal.recoverableIDs.first)
        let scope = try XCTUnwrap(journal.recoveryRequest(id))
        XCTAssertEqual(sends, 0)
        XCTAssertNil(journal.record(id))
        XCTAssertEqual(client.entity(for: id).status, "unavailable")
        XCTAssertThrowsError(try client.status(id: id))
        XCTAssertEqual(sends, 0)
        let restartedJournal = AppleContextJournal(root: directory)
        let restarted = AppleContextPhoneClient(journal: restartedJournal, bindingRoot: bindings, protectedDataAvailable: { true }, executionBlocked: { _ in false })
        restarted.install(service)
        XCTAssertEqual(restarted.entity(for: id).status, "unavailable")
        restartedJournal.writeFailurePointForTesting = .finalFileSync
        XCTAssertThrowsError(try restarted.status(id: id))
        XCTAssertEqual(sends, 0)
        restartedJournal.writeFailurePointForTesting = nil
        XCTAssertEqual(try restarted.status(id: id).id, id.uuidString)
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(restartedJournal.record(id)?.request, scope)
        let pending = AppleContextReceipt(request: scope, revision: 1, state: .pending)
        restarted.receive(.receipt(pending))
        restartedJournal.writeFailurePointForTesting = .finalFileSync
        restarted.receive(.receipt(.init(request: scope, revision: 2, state: .completed)))
        XCTAssertEqual(restartedJournal.record(id)?.receipt, pending)
        XCTAssertNotEqual(restarted.entity(for: id).status, "completed")
        XCTAssertThrowsError(try restarted.status(id: id))
        XCTAssertEqual(sends, 1)
        restartedJournal.writeFailurePointForTesting = nil
        XCTAssertEqual(try restarted.status(id: id).status, "completed")
        XCTAssertEqual(restartedJournal.record(id)?.request, scope)
        XCTAssertEqual(AppleContextJournal(root: directory).record(id)?.receipt?.state, .completed)
    }

    func testProductionPhoneHandlerPinsManifestAndRechecksLeaseAcrossAuthorizationAndCaptureAwait() async throws {
        let scenarios = ["summary", "lossless", "peer-after-auth", "cap-after-auth", "peer-at-capture", "cap-at-capture", "ordinary-context"]
        for scenario in scenarios {
            let peer = UUID()
            let service = service(peerID: peer)
            let journal = AppleContextJournal(root: root.appendingPathComponent(UUID().uuidString))
            let client = AppleContextPhoneClient(journal: journal, bindingRoot: root.appendingPathComponent("bindings"), protectedDataAvailable: { true }, executionBlocked: { _ in false })
            client.install(service)
            let zone = TimeZone(identifier: "America/Phoenix")!
            let formatter = AppleContextRequest.formatter(zone: zone)
            let day = formatter.date(from: "2026-01-02")!
            let scope = AppleContextRequest(phoneInstallationID: service.installationID, macInstallationID: peer,
                profileID: UUID(), ownerDates: ["2026-01-02"], timeZoneIdentifier: zone.identifier,
                startDate: day, endDate: day,
                selection: .init(metricIDs: ["steps"], detailLevel: scenario == "lossless" ? .lossless : .summary))
            let ordinary = scenario == "ordinary-context"
            if !ordinary { try journal.admit(scope) }
            let native = IPhoneExportRequest(jobID: scope.id, createdAt: Date(),
                dateRangeStart: day, dateRangeEnd: day, requestedDateIdentifiers: scope.ownerDates,
                requestedBy: .cli, settingsPolicy: .requestedDatesOnly, responseMode: .contextStore, canonicalSelection: scope.selection)
            let store = FakeHealthStore()
            store.authRequestStatus = .unnecessary
            let health = LifecycleHarness.retain(HealthKitManager(store: store, userDefaults: UserDefaults(suiteName: "handler-health-\(UUID().uuidString)")!))
            health.isAuthorized = true
            let handler = LifecycleHarness.retain(IPhoneExportRequestHandler(automationClient: client))
            var manifests: [ConnectedCorpusExportManifest] = []
            var leasePasses = 0
            let disableCapability: () -> Void = {
                var object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(service.remoteCapabilities!)) as! [String: Any]
                object["supportsPhoneContextAutomation"] = false
                service.remoteCapabilities = try! JSONDecoder().decode(SyncPeerCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
            }
            if ordinary { disableCapability() }
            handler.contextAuthorizationCompletedForTesting = {
                await Task.yield()
                if scenario == "peer-after-auth" { service.testSetAuthenticatedContextPeer(UUID()) }
                if scenario == "cap-after-auth" { disableCapability() }
            }
            handler.contextManifestForTesting = { manifest in
                manifests.append(manifest)
                await Task.yield()
                if scenario == "peer-at-capture" { service.testSetAuthenticatedContextPeer(UUID()) }
                if scenario == "cap-at-capture" { disableCapability() }
            }
            handler.contextCaptureLeasePassedForTesting = {
                leasePasses += 1
                throw CancellationError() // no live transport or HealthKit capture
            }
            await handler.handle(native, syncService: service, healthKitManager: health)
            XCTAssertEqual(Set(store.statusReadTypes.map(\.identifier)), ["HKQuantityTypeIdentifierStepCount"])
            XCTAssertFalse(store.authRequested)
            if scenario.hasSuffix("after-auth") {
                XCTAssertTrue(manifests.isEmpty)
                XCTAssertEqual(leasePasses, 0)
            } else {
                let manifest = try XCTUnwrap(manifests.first)
                XCTAssertEqual(manifests.count, 1)
                XCTAssertEqual(manifest.mode, .encryptedContext)
                XCTAssertEqual(manifest.canonicalSelection, scope.selection)
                XCTAssertEqual(manifest.selectedSourceIDs, ["apple_health"])
                XCTAssertNil(manifest.rawProfile)
                XCTAssertNil(manifest.requestedTarget)
                if !ordinary {
                    XCTAssertTrue(scope.matches(manifest))
                    XCTAssertEqual(manifest.sourceTimeZoneIdentifier, "America/Phoenix")
                    XCTAssertEqual(manifest.settingsSnapshot.calendarTimeZoneIdentifier, "America/Phoenix")
                    XCTAssertEqual(manifest.settingsSnapshot.detailPolicy, scenario == "lossless" ? .lossless : .summary)
                }
                XCTAssertEqual(leasePasses, scenario.hasSuffix("at-capture") ? 0 : 1)
            }
            XCTAssertTrue(store.queriedSumIdentifiers.isEmpty)
        }
    }

    func testActualFakeHealthKitCaptureAwaitRechecksPeerCapabilityAndUncertainAuthority() async throws {
        for scenario in ["stable", "peer", "capability", "uncertain"] {
            let peer = UUID()
            let service = service(peerID: peer)
            let scope = request(phone: service.installationID, mac: peer)
            let journal = AppleContextJournal(root: root.appendingPathComponent(UUID().uuidString))
            try journal.admit(scope)
            let client = AppleContextPhoneClient(journal: journal, bindingRoot: root.appendingPathComponent("capture-bindings"), protectedDataAvailable: { true }, executionBlocked: { _ in false })
            client.install(service)
            let store = FakeHealthStore()
            store.authRequestStatus = .unnecessary
            store.querySumAsyncResult = { identifier, _ in
                await Task.yield() // actual fake HealthKit async query, not a pre-capture checkpoint
                try await MainActor.run {
                    if scenario == "peer" { service.testSetAuthenticatedContextPeer(UUID()) }
                    if scenario == "capability" {
                        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(service.remoteCapabilities!)) as! [String: Any]
                        object["supportsPhoneContextAutomation"] = false
                        service.remoteCapabilities = try JSONDecoder().decode(SyncPeerCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
                    }
                    if scenario == "uncertain" {
                        journal.writeFailurePointForTesting = .afterFinalAtomicWrite
                        XCTAssertThrowsError(try journal.accept(.init(request: scope, revision: 1, state: .pending),
                            authenticatedPeer: peer, localID: service.installationID, onPhone: true))
                    }
                }
                return identifier == .stepCount ? 4_321 : nil
            }
            let health = LifecycleHarness.retain(HealthKitManager(store: store, userDefaults: UserDefaults(suiteName: "capture-\(UUID().uuidString)")!))
            health.isAuthorized = true
            let handler = LifecycleHarness.retain(IPhoneExportRequestHandler(automationClient: client))
            var passedCaptureReturnLease = 0
            handler.contextCaptureCompletedForTesting = {
                passedCaptureReturnLease += 1
                throw CancellationError() // stop before spool encoding/network; real fake-store capture already occurred
            }
            let native = IPhoneExportRequest(jobID: scope.id, createdAt: Date(), dateRangeStart: scope.startDate, dateRangeEnd: scope.endDate,
                requestedDateIdentifiers: scope.ownerDates, requestedBy: .cli, settingsPolicy: .requestedDatesOnly,
                responseMode: .contextStore, canonicalSelection: scope.selection)
            await handler.handle(native, syncService: service, healthKitManager: health)
            XCTAssertTrue(store.queriedSumIdentifiers.contains("HKQuantityTypeIdentifierStepCount"), scenario)
            XCTAssertEqual(passedCaptureReturnLease, scenario == "stable" ? 1 : 0, scenario)
            _ = await IPhoneCorpusExportRecoveryManager.shared.cancel(jobID: scope.id, notifyPeer: false)
        }
    }

    func testColdUnavailablePhoneAuthorityBlocksActualHandlerButPreservesOrdinaryFilesAndFirstRunContext() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockedRoot = root.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blockedRoot)
        let journal = AppleContextJournal(root: blockedRoot)
        let peer = UUID()
        let service = service(peerID: peer)
        let scope = request(phone: service.installationID, mac: peer)
        let client = AppleContextPhoneClient(journal: journal, protectedDataAvailable: { true }, executionBlocked: { _ in false })
        client.install(service)
        let native = IPhoneExportRequest(jobID: scope.id, createdAt: Date(), dateRangeStart: scope.startDate,
            dateRangeEnd: scope.endDate, requestedDateIdentifiers: scope.ownerDates, requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly, responseMode: .contextStore, canonicalSelection: scope.selection)
        let ordinaryFile = IPhoneExportRequest(jobID: UUID(), createdAt: Date(), dateRangeStart: scope.startDate,
            dateRangeEnd: scope.endDate, requestedBy: .macApp, settingsPolicy: .currentIPhoneSettings)
        XCTAssertFalse(client.allowsAcquisition(native, sync: service))
        XCTAssertTrue(client.allowsAcquisition(ordinaryFile, sync: service))
        let store = FakeHealthStore()
        store.authRequestStatus = .unnecessary
        let health = LifecycleHarness.retain(HealthKitManager(store: store, userDefaults: UserDefaults(suiteName: "cold-handler-\(UUID().uuidString)")!))
        health.isAuthorized = true
        let handler = LifecycleHarness.retain(IPhoneExportRequestHandler(automationClient: client))
        var manifests = 0
        var sends = 0
        service.testMessageSendObserver = { _ in sends += 1 }
        handler.contextManifestForTesting = { _ in manifests += 1 }
        handler.contextCaptureLeasePassedForTesting = { throw CancellationError() }
        await handler.handle(native, syncService: service, healthKitManager: health)
        XCTAssertEqual(manifests, 0)
        XCTAssertTrue(store.statusReadTypes.isEmpty, "Cold failure must stop before authorization/capture")
        XCTAssertEqual(sends, 0)
        XCTAssertThrowsError(try client.status(id: scope.id))
        XCTAssertEqual(sends, 0)
        let retained = root.appendingPathComponent("retained")
        try FileManager.default.moveItem(at: blockedRoot, to: retained)
        try FileManager.default.createDirectory(at: blockedRoot, withIntermediateDirectories: false)
        XCTAssertTrue(client.allowsAcquisition(native, sync: service))
        await handler.handle(native, syncService: service, healthKitManager: health)
        XCTAssertEqual(manifests, 1, "Readable proven absence preserves the ordinary context path")
        let fresh = AppleContextPhoneClient(journal: AppleContextJournal(root: root.appendingPathComponent("enoent")), protectedDataAvailable: { true }, executionBlocked: { _ in false })
        fresh.install(service)
        XCTAssertTrue(fresh.allowsAcquisition(native, sync: service))
        XCTAssertTrue(fresh.allowsAcquisition(ordinaryFile, sync: service))
    }

    func testProtectedStatusCannotTransmitEvenWithProvenAdmission() throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let journal = AppleContextJournal(root: root)
        let scope = request(phone: service.installationID, mac: peer)
        try journal.admit(scope)
        let client = AppleContextPhoneClient(journal: journal, protectedDataAvailable: { false }, executionBlocked: { _ in false })
        client.install(service)
        var sends = 0
        service.testMessageSendObserver = { _ in sends += 1 }
        XCTAssertThrowsError(try client.status(id: scope.id))
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(journal.record(scope.id)?.request, scope)
    }

    func testRealShortcutProviderRetainsSevenActionsAndRegistersBothContextIntents() async throws {
        XCTAssertEqual(HealthMdAppShortcuts.appShortcuts.count, 9)
        _ = RefreshMacHealthContextIntent()
        _ = GetMacContextRefreshStatusIntent()
        // Actual public EntityQuery resolves only persisted IDs, not caller identities.
        let values = try await MacContextRefreshQuery().entities(for: [UUID().uuidString])
        XCTAssertTrue(values.isEmpty)
        let refresh = RefreshMacHealthContextIntent()
        refresh.profile = "unknown-context-profile-\(UUID().uuidString)"
        refresh.startDate = Date()
        refresh.endDate = Date()
        do { _ = try await refresh.perform(); XCTFail("Actual intent must reject unknown profiles") }
        catch { }
        let status = GetMacContextRefreshStatusIntent()
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
        jobs.contextAutomationPeerAdmission = { adapter.allows(jobID: $0, sync: $1, requiresContextAuthority: $2 == .contextStore) }
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
        let receiver = ConnectedTransferReceiver()
        let bytes = try Data(contentsOf: partition.file.url)
        let partitionStart = ConnectedTransferStart(protocolVersion: ConnectedTransferStart.corpusPartitionProtocolVersion,
            transferID: partition.transferID, manifest: .init(kind: .connectedCorpusPartitionV1, jobID: scope.id,
                payloadSchemaVersion: ConnectedCorpusPartitionFileManifest.currentVersion, corpusPartition: partition.descriptor),
            totalBytes: partition.file.totalBytes, totalChunks: 1, chunkBytes: bytes.count, sha256: partition.file.sha256)
        let fileBypass = ConnectedTransferStart(protocolVersion: 1, transferID: UUID(),
            manifest: .init(kind: .macExportJobV1, jobID: scope.id, payloadSchemaVersion: 1),
            totalBytes: partition.file.totalBytes, totalChunks: 1, chunkBytes: bytes.count, sha256: partition.file.sha256)
        XCTAssertNil(adapter.receiveTransferStart(fileBypass, sync: service, receiver: receiver), "Actual app-root delegate must reject ordinary file kind")
        XCTAssertTrue(receiver.activeTransferIDs.isEmpty)
        guard case .acknowledgement(let startAck)? = adapter.receiveTransferStart(partitionStart, sync: service, receiver: receiver) else {
            return XCTFail("Legitimate context corpus partition must remain routable")
        }
        XCTAssertTrue(adapter.allowsMessage(.connectedTransferAck(startAck), sync: service, inbound: false))
        guard case .acknowledgement = receiver.receive(ConnectedTransferChunk(transferID: partition.transferID, sequence: 1,
            data: bytes, sha256: ConnectedTransferFile.sha256Hex(bytes))) else { return XCTFail("Native partition chunk rejected") }
        let transportComplete = ConnectedTransferComplete(transferID: partition.transferID, totalBytes: partition.file.totalBytes,
            totalChunks: 1, sha256: partition.file.sha256)
        guard case .ready(let ready) = receiver.receive(transportComplete) else { return XCTFail("Native partition completion rejected") }
        corpus.afterEncryptedContextApplyForTesting = {
            await Task.yield()
            service.testSetAuthenticatedContextPeer(UUID()) // switch during REAL encrypted apply await
        }
        try await corpus.applyPartition(fileURL: ready.fileURL, descriptor: partition.descriptor, vaultManager: vault)
        let transportFinalAck = ConnectedTransferFinalAck(transferID: partition.transferID, accepted: true, sha256: partition.file.sha256, message: nil)
        XCTAssertFalse(adapter.allowsMessage(.connectedTransferComplete(transportComplete), sync: service))
        XCTAssertFalse(adapter.allowsMessage(.connectedTransferAck(startAck), sync: service, inbound: false))
        XCTAssertFalse(adapter.allowsMessage(.connectedTransferFinalAck(transportFinalAck), sync: service, inbound: false))
        XCTAssertFalse(adapter.allowsMessage(.connectedCorpusTransferDisposition(disposition), sync: service, inbound: false))
        service.testSetAuthenticatedContextPeer(peer)
        let corpusFinalAck = ConnectedCorpusTransferFinalAck(sessionID: session.sessionID, jobID: scope.id, accepted: true,
            requestFingerprint: session.requestFingerprint, finalPartitionSHA256: partition.descriptor.sha256, message: nil)
        let cancelAck = ConnectedCorpusTransferCancelAck(sessionID: session.sessionID, jobID: scope.id, accepted: true, acknowledgedAt: Date(), message: nil)
        for ack in [SyncMessage.connectedTransferAck(startAck), .connectedTransferFinalAck(transportFinalAck),
                    .connectedCorpusTransferDisposition(disposition), .connectedCorpusTransferFinalAck(corpusFinalAck), .connectedCorpusTransferCancelAck(cancelAck)] {
            XCTAssertTrue(adapter.allowsMessage(ack, sync: service, inbound: false))
        }
        adapter.journal.writeFailurePointForTesting = .afterFinalAtomicWrite
        XCTAssertThrowsError(try adapter.journal.accept(.init(request: scope, revision: 100, state: .pending),
            authenticatedPeer: peer, localID: service.installationID, onPhone: false))
        for ack in [SyncMessage.connectedTransferAck(startAck), .connectedTransferFinalAck(transportFinalAck),
                    .connectedCorpusTransferDisposition(disposition), .connectedCorpusTransferFinalAck(corpusFinalAck), .connectedCorpusTransferCancelAck(cancelAck)] {
            XCTAssertFalse(adapter.allowsMessage(ack, sync: service, inbound: false))
        }
        adapter.journal.writeFailurePointForTesting = nil
        XCTAssertTrue(try adapter.journal.retryDurability(scope.id, expectedRequest: scope))
        XCTAssertNotNil(receiver.finish(transferID: partition.transferID, accepted: true))
        let stored = try await contextStore.loadDay(ownerDate: "2026-01-02")
        XCTAssertEqual(stored?.metrics.first(where: { $0.metricID == "steps" })?.value, .quantity(value: 4_321, unit: "steps"))
        let finalize = ConnectedCorpusTransferFinalize(sessionID: session.sessionID, jobID: scope.id,
            requestFingerprint: session.requestFingerprint, partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount, finalPartitionSHA256: partition.descriptor.sha256)
        let outcome = try await corpus.finalize(finalize, vaultManager: vault)
        guard case .files(let committedResult, _) = outcome else { return XCTFail("Expected committed encrypted context") }
        XCTAssertEqual(committedResult.totalFilesWritten, 0)
        XCTAssertTrue(fileSystem.files.isEmpty, "Context must never write export files")
        XCTAssertFalse(jobs.complete(with: committedResult), "Ordinary file result cannot complete context even with zero files")
        let proof = try XCTUnwrap(corpus.encryptedContextCommitEvidence(for: finalize))
        XCTAssertTrue(jobs.completeEncryptedContext(with: proof))
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

    func testMacPostWriteMappingFailureNeverAcksOrAcquiresAndExplicitStatusRepairsSameIdentity() async throws {
        let points: [AppleContextJournal.WriteFailurePoint] = [.afterFinalAtomicWrite, .finalFileSync, .afterFinalDirectorySync]
        for point in points {
            let peer = UUID()
            let service = service(peerID: peer)
            let scope = request(phone: peer, mac: service.installationID)
            let directory = root.appendingPathComponent(UUID().uuidString)
            let journal = AppleContextJournal(root: directory)
            let adapter = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: journal, contextReadiness: { nil }))
            let jobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: root.appendingPathComponent(UUID().uuidString)))
            var acknowledgements = 0
            var acquisitions: [IPhoneExportRequest] = []
            service.testMessageSendObserver = {
                if case .appleContext(.receipt) = $0 { acknowledgements += 1 }
                if case .iphoneExportRequest(let request) = $0 { acquisitions.append(request) }
            }
            journal.writeFailurePointForTesting = point
            adapter.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
            await Task.yield()
            XCTAssertEqual(acknowledgements, 0)
            XCTAssertTrue(acquisitions.isEmpty)
            XCTAssertNil(journal.record(scope.id))
            XCTAssertEqual(jobs.jobResponse(jobID: scope.id).failureReason, "job_not_found")
            let candidate = try JSONDecoder().decode(AppleContextJournal.Record.self,
                from: Data(contentsOf: directory.appendingPathComponent(scope.id.uuidString + ".json")))
            XCTAssertEqual(candidate.request, scope)
            let restartedJournal = AppleContextJournal(root: directory)
            let restarted = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: restartedJournal, contextReadiness: { nil }))
            service.contextAutomationOutboundAdmission = { restarted.allowsMessage($0, sync: service, inbound: false) }
            jobs.contextAutomationPeerAdmission = { restarted.allows(jobID: $0, sync: $1, requiresContextAuthority: $2 == .contextStore) }
            jobs.contextAutomationOwnsJob = { restartedJournal.isKnown($0) }
            restartedJournal.writeFailurePointForTesting = point
            restarted.handle(.status(scope), sync: service, jobs: jobs, destination: destination(service))
            XCTAssertEqual(acknowledgements, 0)
            XCTAssertTrue(acquisitions.isEmpty)
            restartedJournal.writeFailurePointForTesting = nil
            restarted.handle(.status(scope), sync: service, jobs: jobs, destination: destination(service))
            for _ in 0..<100 where acquisitions.isEmpty { await Task.yield() }
            XCTAssertEqual(acquisitions.count, 1)
            XCTAssertTrue(scope.matches(try XCTUnwrap(acquisitions.first)))
            XCTAssertEqual(restartedJournal.record(scope.id)?.request, scope)
            XCTAssertGreaterThan(acknowledgements, 0)
            jobs.cancelRequestForDisconnectedClient(jobID: scope.id)
            for _ in 0..<10 { await Task.yield() }
        }
    }

    func testMacPostWriteJobMappingUpdateFailureSuppressesDispatchUntilExplicitRepair() async throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let scope = request(phone: peer, mac: service.installationID)
        let journal = AppleContextJournal(root: root.appendingPathComponent("mapping"))
        journal.writeFailurePointForTesting = .afterFinalAtomicWrite
        journal.failFinalWriteNumberForTesting = 2 // admission succeeds; native-job mapping update fails
        let adapter = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: journal, contextReadiness: { nil }))
        let jobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: root.appendingPathComponent("jobs")))
        service.contextAutomationOutboundAdmission = { adapter.allowsMessage($0, sync: service, inbound: false) }
        jobs.contextAutomationPeerAdmission = { adapter.allows(jobID: $0, sync: $1, requiresContextAuthority: $2 == .contextStore) }
        jobs.contextAutomationOwnsJob = { journal.isKnown($0) }
        var acknowledgements = 0
        var acquisitions: [IPhoneExportRequest] = []
        service.testMessageSendObserver = {
            if case .appleContext(.receipt) = $0 { acknowledgements += 1 }
            if case .iphoneExportRequest(let request) = $0 { acquisitions.append(request) }
        }
        adapter.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
        for _ in 0..<100 where !journal.hasUncertainAuthority(scope.id) { await Task.yield() }
        XCTAssertTrue(journal.hasUncertainAuthority(scope.id))
        XCTAssertEqual(acknowledgements, 0)
        XCTAssertTrue(acquisitions.isEmpty)
        XCTAssertEqual(journal.record(scope.id)?.request, scope)
        XCTAssertEqual(journal.record(scope.id)?.jobWasAdmitted, false)
        XCTAssertNotNil(jobs.contextRequest(jobID: scope.id))
        adapter.handle(.status(scope), sync: service, jobs: jobs, destination: destination(service))
        for _ in 0..<100 where acquisitions.isEmpty { await Task.yield() }
        XCTAssertEqual(acquisitions.count, 1)
        XCTAssertTrue(scope.matches(try XCTUnwrap(acquisitions.first)))
        XCTAssertGreaterThan(acknowledgements, 0)
        XCTAssertEqual(journal.record(scope.id)?.request, scope)
        jobs.cancelRequestForDisconnectedClient(jobID: scope.id)
        for _ in 0..<10 { await Task.yield() }
    }

    func testColdNativeSentJobStatusResumesOriginalScopeWithoutJournalRepairOrDuplicateWaiter() async throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let scope = request(phone: peer, mac: service.installationID)
        let journalRoot = root.appendingPathComponent("restart-journal")
        let jobsRoot = root.appendingPathComponent("restart-jobs")
        let initial = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: AppleContextJournal(root: journalRoot), contextReadiness: { nil }))
        let originalJobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: jobsRoot))
        var acquisitions: [IPhoneExportRequest] = []
        service.testMessageSendObserver = { if case .iphoneExportRequest(let native) = $0 { acquisitions.append(native) } }
        initial.handle(.refresh(scope), sync: service, jobs: originalJobs, destination: destination(service))
        for _ in 0..<100 where acquisitions.isEmpty { await Task.yield() }
        let originalRequest = try XCTUnwrap(acquisitions.first)
        originalJobs.cancelRequestForDisconnectedClient(jobID: scope.id) // drain old in-memory waiter without altering persisted sent job
        for _ in 0..<20 { await Task.yield() }
        let restartedJournal = AppleContextJournal(root: journalRoot)
        let restarted = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: restartedJournal, contextReadiness: { nil }))
        let restoredJobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: jobsRoot))
        XCTAssertFalse(restartedJournal.hasUncertainAuthority(scope.id))
        XCTAssertTrue(restartedJournal.record(scope.id)?.jobWasAdmitted == true)
        XCTAssertEqual(restoredJobs.jobResponse(jobID: scope.id).durableState, "sent")
        XCTAssertTrue(restoredJobs.canExplicitlyResumeContext(jobID: scope.id))
        restoredJobs.resumePausedJobsAfterHello(syncService: service, destinationStatus: destination(service))
        XCTAssertEqual(acquisitions.count, 1, "Hello alone does not resume persisted sent/unpaused work")
        restarted.handle(.status(scope), sync: service, jobs: restoredJobs, destination: destination(service))
        restarted.handle(.status(scope), sync: service, jobs: restoredJobs, destination: destination(service))
        for _ in 0..<100 where acquisitions.count < 2 { await Task.yield() }
        XCTAssertEqual(acquisitions.count, 2)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(acquisitions[1]), try encoder.encode(originalRequest))
        XCTAssertEqual(restartedJournal.record(scope.id)?.request, scope)
        XCTAssertFalse(restoredJobs.canExplicitlyResumeContext(jobID: scope.id), "Resumed live waiter must not be duplicated")
        restarted.handle(.status(scope), sync: service, jobs: restoredJobs, destination: destination(service))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(acquisitions.count, 2)
        restoredJobs.cancelRequestForDisconnectedClient(jobID: scope.id)
        for _ in 0..<20 { await Task.yield() }
    }

    func testColdUnavailableJournalAndRestoredNativeContextJobExcludeDirectAndBoundedFilesButAllowUnownedFiles() async throws {
        let peer = UUID()
        let service = service(peerID: peer)
        let scope = request(phone: peer, mac: service.installationID)
        let jobsRoot = root.appendingPathComponent("cold-file-jobs")
        let initial = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: AppleContextJournal(root: root.appendingPathComponent("cold-file-journal")), contextReadiness: { nil }))
        let originalJobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: jobsRoot))
        var sent = false
        service.testMessageSendObserver = { if case .iphoneExportRequest = $0 { sent = true } }
        initial.handle(.refresh(scope), sync: service, jobs: originalJobs, destination: destination(service))
        for _ in 0..<100 where !sent { await Task.yield() }
        XCTAssertTrue(sent)
        originalJobs.cancelRequestForDisconnectedClient(jobID: scope.id)
        for _ in 0..<20 { await Task.yield() }
        let blockedRoot = root.appendingPathComponent("unreadable-private-journal")
        try Data("retained obstruction".utf8).write(to: blockedRoot)
        let adapter = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: AppleContextJournal(root: blockedRoot), contextReadiness: { nil }))
        let restoredJobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: jobsRoot))
        adapter.nativeJobs = restoredJobs // exact production app-root ownership wiring
        XCTAssertEqual(adapter.journal.authorityState(scope.id), .unavailable)
        XCTAssertFalse(adapter.journal.isKnown(scope.id))
        XCTAssertEqual(restoredJobs.contextRequest(jobID: scope.id)?.responseMode, .contextStore)
        let fileSystem = FakeFileSystem()
        let resolver = FakeBookmarkResolver()
        resolver.accessGranted = true
        let vault = LifecycleHarness.retain(VaultManager(defaults: FakeUserDefaults(), fileSystem: fileSystem,
            bookmarkResolver: resolver, identityProbe: FakeVaultFolderIdentityProbe()))
        vault.setVaultFolder(root.appendingPathComponent("ordinary-vault"))
        let executor = LifecycleHarness.retain(MacExportJobExecutor())
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: UserDefaults(suiteName: "file-exclusion-\(UUID().uuidString)")!))
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")
        var record = HealthData(date: scope.startDate)
        record.activity.steps = 4_321
        func fileJob(_ id: UUID) -> MacExportJob {
            .init(jobID: id, createdAt: Date(), sourceDeviceName: "Synthetic iPhone", dateRangeStart: scope.startDate, dateRangeEnd: scope.endDate,
                requestedDates: [scope.startDate], records: [record], settingsSnapshot: .from(settings, calendarTimeZoneIdentifier: "UTC"),
                requestedTarget: .init(kind: .connectedMac, displayName: "Connected Mac", destinationDisplayName: "ordinary-vault"))
        }
        let sameID = fileJob(scope.id)
        XCTAssertFalse(adapter.allowsMessage(.macExportRequest(sameID), sync: service))
        let denied = await adapter.executeOrdinaryFileJob(sameID, sync: service, executor: executor, vault: vault)
        XCTAssertNil(denied, "Actual app-root file execution delegate must refuse before executor writes")
        let receiver = ConnectedTransferReceiver()
        let bytes = try JSONEncoder().encode(sameID)
        let bounded = ConnectedTransferStart(protocolVersion: 1, transferID: UUID(),
            manifest: .init(kind: .macExportJobV1, jobID: scope.id, payloadSchemaVersion: 1), totalBytes: Int64(bytes.count),
            totalChunks: 1, chunkBytes: bytes.count, sha256: ConnectedTransferFile.sha256Hex(bytes))
        XCTAssertNil(adapter.receiveTransferStart(bounded, sync: service, receiver: receiver))
        XCTAssertTrue(receiver.activeTransferIDs.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
        XCTAssertEqual(restoredJobs.jobResponse(jobID: scope.id).durableState, "sent")
        let ordinary = fileJob(UUID())
        XCTAssertTrue(adapter.allowsMessage(.macExportRequest(ordinary), sync: service))
        let positive = await adapter.executeOrdinaryFileJob(ordinary, sync: service, executor: executor, vault: vault)
        guard case .success(let result)? = positive else { return XCTFail("Genuinely unowned ordinary file export must still execute: \(String(describing: positive))") }
        XCTAssertGreaterThan(result.totalFilesWritten, 0)
        XCTAssertFalse(fileSystem.files.isEmpty)
        XCTAssertEqual(restoredJobs.jobResponse(jobID: scope.id).durableState, "sent")
        XCTAssertEqual(try String(contentsOf: blockedRoot, encoding: .utf8), "retained obstruction")
    }

    func testColdUnavailableMacAuthorityBlocksContextButNotOrdinaryFilesAndRecoversWithoutErase() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockedRoot = root.appendingPathComponent("blocked")
        try Data("retained obstruction".utf8).write(to: blockedRoot)
        let peer = UUID()
        let service = service(peerID: peer)
        let scope = request(phone: peer, mac: service.installationID)
        let journal = AppleContextJournal(root: blockedRoot)
        let adapter = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: journal, contextReadiness: { nil }))
        let jobs = LifecycleHarness.retain(MacIPhoneExportRequestCoordinator(rootURL: root.appendingPathComponent("jobs")))
        var sends = 0
        service.testMessageSendObserver = { _ in sends += 1 }
        XCTAssertFalse(adapter.allows(jobID: scope.id, sync: service))
        XCTAssertTrue(adapter.allows(jobID: UUID(), sync: service, requiresContextAuthority: false))
        let context = IPhoneExportRequest(jobID: scope.id, createdAt: Date(), dateRangeStart: scope.startDate,
            dateRangeEnd: scope.endDate, requestedDateIdentifiers: scope.ownerDates, requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly, responseMode: .contextStore, canonicalSelection: scope.selection)
        let ordinary = IPhoneExportRequest(jobID: UUID(), createdAt: Date(), dateRangeStart: scope.startDate,
            dateRangeEnd: scope.endDate, requestedBy: .macApp, settingsPolicy: .currentIPhoneSettings)
        XCTAssertFalse(adapter.allowsMessage(.iphoneExportRequest(context), sync: service, inbound: false))
        XCTAssertTrue(adapter.allowsMessage(.iphoneExportRequest(ordinary), sync: service, inbound: false))
        adapter.handle(.refresh(scope), sync: service, jobs: jobs, destination: destination(service))
        XCTAssertEqual(sends, 0)
        XCTAssertNil(jobs.contextRequest(jobID: scope.id))
        let retained = root.appendingPathComponent("retained")
        try FileManager.default.moveItem(at: blockedRoot, to: retained)
        try FileManager.default.createDirectory(at: blockedRoot, withIntermediateDirectories: false)
        XCTAssertTrue(adapter.allows(jobID: scope.id, sync: service))
        XCTAssertTrue(adapter.allowsMessage(.iphoneExportRequest(context), sync: service, inbound: false))
        let fresh = LifecycleHarness.retain(MacContextAutomationCoordinator(journal: AppleContextJournal(root: root.appendingPathComponent("enoent")), contextReadiness: { nil }))
        XCTAssertTrue(fresh.allows(jobID: scope.id, sync: service))
        XCTAssertEqual(try String(contentsOf: retained, encoding: .utf8), "retained obstruction")
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
