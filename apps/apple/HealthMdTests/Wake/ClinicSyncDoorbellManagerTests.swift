#if os(iOS)
import CryptoKit
import XCTest
@testable import HealthMd

@MainActor
final class ClinicSyncDoorbellManagerTests: XCTestCase {
    private nonisolated final class MemoryStore: ClinicSyncDoorbellStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var doorbell: ClinicSyncDoorbell?

        func load() -> ClinicSyncDoorbell? {
            lock.lock(); defer { lock.unlock() }
            return doorbell
        }

        func save(_ doorbell: ClinicSyncDoorbell) -> Bool {
            lock.lock(); defer { lock.unlock() }
            self.doorbell = doorbell
            return true
        }

        func clear() {
            lock.lock(); defer { lock.unlock() }
            doorbell = nil
        }
    }

    private final class FakeWorker: ClinicSyncWakeServing, @unchecked Sendable {
        var failRegistration = false
        private(set) var registrations: [(hash: String, existing: String?)] = []
        private(set) var unregistered: [String] = []

        func registerDelegatedSync(verificationHash: SHA256.Digest, existingWakeID: String?) async throws -> String {
            registrations.append((Data(verificationHash).map { String(format: "%02x", $0) }.joined(), existingWakeID))
            if failRegistration { throw DirectWakeWorkerError.unexpectedStatus }
            return existingWakeID ?? "wake-0123456789abcdef"
        }

        func unregister(wakeID: String) async throws {
            unregistered.append(wakeID)
        }
    }

    private final class FakeMessenger: ClinicSyncControlSending, @unchecked Sendable {
        var fail = false
        private(set) var sent: [(body: [String: Any], endpoint: URL)] = []

        @MainActor func send(_ body: Data, endpoint: URL) async throws {
            if fail { throw APIExportClientError.accessDenied }
            sent.append(((try JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:], endpoint))
        }
    }

    private let endpoint = "https://intake.clinic.example/upload"
    private var status = ClinicSponsorshipStatus(configured: true, active: true, clinicName: "Example clinic",
                                                 endpoint: "https://intake.clinic.example/upload",
                                                 sharingAuthorized: true)
    private var token: String? = "aa11"
    private var exports: [String] = []
    private var results: [String] = []

    private func makeManager(store: MemoryStore, worker: FakeWorker, messenger: FakeMessenger,
                             notificationsAllowed: Bool = true) -> ClinicSyncDoorbellManager {
        let defaults = UserDefaults(suiteName: "clinic-sync-doorbell-tests")!
        defaults.removePersistentDomain(forName: "clinic-sync-doorbell-tests")
        return ClinicSyncDoorbellManager(
            store: store, worker: worker, messenger: messenger,
            defaults: defaults,
            deviceToken: { [unowned self] in self.token },
            requestNotificationAuthorization: { notificationsAllowed },
            registerForPushNotifications: {},
            clinicStatus: { [unowned self] in self.status },
            runClinicExport: { [unowned self] endpoint in self.exports.append(endpoint); return "sent" },
            postResult: { [unowned self] message in self.results.append(message) })
    }

    func testEnableRequiresAuthorizedSharingAndContactsNothing() async {
        status.sharingAuthorized = false
        let store = MemoryStore(), worker = FakeWorker(), messenger = FakeMessenger()
        let manager = makeManager(store: store, worker: worker, messenger: messenger)

        await manager.enable()

        XCTAssertEqual(manager.state, .unavailable(reason: "Allow sharing with this clinic first."))
        XCTAssertTrue(worker.registrations.isEmpty)
        XCTAssertTrue(messenger.sent.isEmpty)
        XCTAssertNil(store.load())
    }

    func testDeniedNotificationsNeverRegisterADoorbell() async {
        let store = MemoryStore(), worker = FakeWorker(), messenger = FakeMessenger()
        let manager = makeManager(store: store, worker: worker, messenger: messenger, notificationsAllowed: false)

        await manager.enable()

        XCTAssertTrue(worker.registrations.isEmpty)
        XCTAssertNil(store.load())
    }

    func testEnableRegistersHashAndDeliversKeyOnlyToTheClinicEndpoint() async throws {
        let store = MemoryStore(), worker = FakeWorker(), messenger = FakeMessenger()
        let manager = makeManager(store: store, worker: worker, messenger: messenger)

        await manager.enable()

        XCTAssertEqual(manager.state, .enabled)
        let doorbell = try XCTUnwrap(store.load())
        XCTAssertEqual(doorbell.endpoint, endpoint)
        XCTAssertEqual(doorbell.deviceToken, "aa11")
        XCTAssertEqual(worker.registrations.count, 1)
        XCTAssertEqual(worker.registrations[0].hash,
                       Data(SHA256.hash(data: doorbell.wakeKey)).map { String(format: "%02x", $0) }.joined())
        XCTAssertNil(worker.registrations[0].existing)

        let message = try XCTUnwrap(messenger.sent.first)
        XCTAssertEqual(message.endpoint.absoluteString, endpoint)
        XCTAssertEqual(message.body["type"] as? String, "healthmd.clinic_sync_doorbell")
        XCTAssertEqual(message.body["version"] as? Int, 1)
        XCTAssertEqual(message.body["action"] as? String, "enroll")
        XCTAssertEqual(message.body["wakeService"] as? String, ClinicSyncDoorbellManager.wakeService)
        XCTAssertEqual(message.body["wakeId"] as? String, doorbell.wakeID)
        XCTAssertEqual(message.body["wakeKey"] as? String, ClinicSyncDoorbellMessage.base64url(doorbell.wakeKey))
    }

    func testUnreachableClinicLeavesNoDoorbellBehind() async {
        let store = MemoryStore(), worker = FakeWorker(), messenger = FakeMessenger()
        messenger.fail = true
        let manager = makeManager(store: store, worker: worker, messenger: messenger)

        await manager.enable()

        XCTAssertEqual(worker.unregistered, ["wake-0123456789abcdef"])
        XCTAssertNil(store.load())
        XCTAssertNotEqual(manager.state, .enabled)
    }

    func testRevokedSharingOrChangedEndpointRevokesBeforeForgetting() async {
        let store = MemoryStore(), worker = FakeWorker(), messenger = FakeMessenger()
        let manager = makeManager(store: store, worker: worker, messenger: messenger)
        await manager.enable()

        status.endpoint = "https://other.clinic.example/upload"
        await manager.reconcile()

        XCTAssertEqual(worker.unregistered, ["wake-0123456789abcdef"])
        XCTAssertEqual(messenger.sent.last?.body["action"] as? String, "revoke")
        XCTAssertNil(messenger.sent.last?.body["wakeKey"])
        XCTAssertNil(store.load())
        XCTAssertEqual(manager.state, .disabled)
    }

    func testTokenRotationReRegistersTheSameDoorbell() async throws {
        let store = MemoryStore(), worker = FakeWorker(), messenger = FakeMessenger()
        let manager = makeManager(store: store, worker: worker, messenger: messenger)
        await manager.enable()

        token = "bb22"
        await manager.reconcile()

        XCTAssertEqual(worker.registrations.last?.existing, "wake-0123456789abcdef")
        XCTAssertEqual(try XCTUnwrap(store.load()).deviceToken, "bb22")
        XCTAssertEqual(messenger.sent.count, 1, "rotation never re-sends the key to the clinic")
    }

    func testOnlyATapForTheHeldDoorbellRunsTheClinicExport() async {
        let store = MemoryStore(), worker = FakeWorker(), messenger = FakeMessenger()
        let manager = makeManager(store: store, worker: worker, messenger: messenger)
        await manager.enable()

        await manager.handleSyncRequestTap(wakeID: "someone-elses-doorbell")
        XCTAssertTrue(exports.isEmpty)

        await manager.handleSyncRequestTap(wakeID: "wake-0123456789abcdef")
        XCTAssertEqual(exports, [endpoint])
        XCTAssertEqual(results, ["sent"])
    }

    func testTapAfterSharingWasRevokedSendsNothing() async {
        let store = MemoryStore(), worker = FakeWorker(), messenger = FakeMessenger()
        let manager = makeManager(store: store, worker: worker, messenger: messenger)
        await manager.enable()

        status.sharingAuthorized = false
        await manager.handleSyncRequestTap(wakeID: "wake-0123456789abcdef")

        XCTAssertTrue(exports.isEmpty)
        XCTAssertNil(store.load())
    }

    func testParsesOnlyClinicSyncRequestPayloads() {
        XCTAssertEqual(ClinicSyncDoorbellManager.requestedWakeID(from: [
            "aps": ["category": "HEALTHMD_SYNC_REQUEST"],
            "healthmd": ["kind": "delegated-sync-request", "wakeId": "abc"],
        ]), "abc")
        XCTAssertNil(ClinicSyncDoorbellManager.requestedWakeID(from: ["healthmd": ["kind": "direct-cli-wake"]]))
        XCTAssertNil(ClinicSyncDoorbellManager.requestedWakeID(from: ["healthmd": ["kind": "delegated-sync-request"]]))
    }

    func testMessagesMatchTheSharedContractFixture() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("packages/contracts/clinic-sponsorship/v1/sync-doorbell-fixtures.json")
        let fixture = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let enroll = try XCTUnwrap((fixture["enrollMessage"] as? [String: Any])?["body"] as? NSDictionary)
        let revoke = try XCTUnwrap((fixture["revokeMessage"] as? [String: Any])?["body"] as? NSDictionary)
        let wakeID = try XCTUnwrap(enroll["wakeId"] as? String)

        let encodedEnroll = try ClinicSyncDoorbellMessage.enroll(wakeID: wakeID, wakeKey: Data(repeating: 9, count: 32)).encoded()
        let encodedRevoke = try ClinicSyncDoorbellMessage.revoke(wakeID: wakeID).encoded()
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encodedEnroll) as? NSDictionary, enroll)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: encodedRevoke) as? NSDictionary, revoke)
    }
}
#endif
