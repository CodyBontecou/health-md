#if os(iOS)
import CryptoKit
import HealthMdConnectionCore
import XCTest
@testable import HealthMd

final class IPhoneDirectWakeManagerTests: XCTestCase {
    private nonisolated final class MemoryKeychain: DirectWakeCredentialStoring, @unchecked Sendable {
        private var credential: DirectWakeCredential?
        private let lock = NSLock()

        func load() -> DirectWakeCredential? {
            lock.lock()
            defer { lock.unlock() }
            return credential
        }

        func save(_ credential: DirectWakeCredential) {
            lock.lock()
            defer { lock.unlock() }
            self.credential = credential
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            credential = nil
        }
    }

    private final class FakeWorker: DirectWakeWorkerRegistering, @unchecked Sendable {
        enum Behavior {
            case succeed(wakeID: String)
            case fail
        }

        let behavior: Behavior
        private(set) var registrations: [String] = []
        private(set) var unregistered: [String] = []

        init(behavior: Behavior) {
            self.behavior = behavior
        }

        func register(verificationHash: SHA256.Digest) async throws -> String {
            registrations.append(Data(verificationHash).map { String(format: "%02x", $0) }.joined())
            switch behavior {
            case .succeed(let wakeID): return wakeID
            case .fail: throw DirectWakeWorkerError.unexpectedStatus
            }
        }

        func unregister(wakeID: String) async throws {
            unregistered.append(wakeID)
        }
    }

    @MainActor
    func testEnableWithoutWorkerStaysHonestlyUnavailableAndForwardsNothing() async {
        let defaults = UserDefaults(suiteName: "wake-manager-unavailable-test")!
        defaults.removePersistentDomain(forName: "wake-manager-unavailable-test")
        let keychain = MemoryKeychain()
        let worker = FakeWorker(behavior: .fail)
        let manager = IPhoneDirectWakeManager(
            defaults: defaults,
            keychain: keychain,
            worker: worker,
            requestNotificationAuthorization: { true }
        )

        await manager.enable()

        guard case .unavailable = manager.state else {
            return XCTFail("expected unavailable, got \(manager.state)")
        }
        XCTAssertFalse(manager.advertisesWake)
        XCTAssertNil(manager.currentEnrollment())
        XCTAssertNil(keychain.load())
        XCTAssertFalse(defaults.bool(forKey: IPhoneDirectWakeManager.enabledKey))
        XCTAssertEqual(worker.registrations.count, 1, "one registration attempt, no retries")
    }

    @MainActor
    func testDeniedNotificationsNeverContactTheWorker() async {
        let defaults = UserDefaults(suiteName: "wake-manager-denied-test")!
        defaults.removePersistentDomain(forName: "wake-manager-denied-test")
        let worker = FakeWorker(behavior: .succeed(wakeID: "wake-ok"))
        let manager = IPhoneDirectWakeManager(
            defaults: defaults,
            keychain: MemoryKeychain(),
            worker: worker,
            requestNotificationAuthorization: { false }
        )

        await manager.enable()

        guard case .unavailable = manager.state else {
            return XCTFail("expected unavailable, got \(manager.state)")
        }
        XCTAssertTrue(worker.registrations.isEmpty)
    }

    @MainActor
    func testSuccessfulEnrollmentForwardsAValidEnrollmentAndDisableRevokes() async throws {
        let defaults = UserDefaults(suiteName: "wake-manager-enrolled-test")!
        defaults.removePersistentDomain(forName: "wake-manager-enrolled-test")
        let keychain = MemoryKeychain()
        let worker = FakeWorker(behavior: .succeed(wakeID: "wake-opaque-1"))
        let manager = IPhoneDirectWakeManager(
            defaults: defaults,
            keychain: keychain,
            worker: worker,
            requestNotificationAuthorization: { true }
        )

        await manager.enable()

        XCTAssertEqual(manager.state, .enrolled)
        XCTAssertTrue(manager.advertisesWake)
        let enrollment = try XCTUnwrap(manager.currentEnrollment())
        XCTAssertEqual(enrollment.wakeID, "wake-opaque-1")
        XCTAssertTrue(enrollment.isValid)
        let storedKey = try XCTUnwrap(keychain.load()).wakeKey
        XCTAssertEqual(enrollment.wakeKey, storedKey.base64EncodedString())
        // The registered verification hash is SHA-256 of the exact key the CLI receives.
        let expectedHash = Data(SHA256.hash(data: storedKey))
            .map { String(format: "%02x", $0) }
            .joined()
        XCTAssertEqual(worker.registrations, [expectedHash])

        await manager.disable()

        XCTAssertEqual(manager.state, .disabled)
        XCTAssertNil(manager.currentEnrollment())
        XCTAssertNil(keychain.load())
        XCTAssertEqual(worker.unregistered, ["wake-opaque-1"])
    }
}
#endif
