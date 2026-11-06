import XCTest
@testable import HealthMd

/// The per-profile overlap policy: Queue waits for the running occurrence, Skip drops
/// the new one, and the device-local store only persists non-default choices.
@MainActor
final class ProfileRunOverlapGateTests: XCTestCase {
    private final class Flag { var value = false }

    // MARK: - Gate

    func testQueueWaitsForTheRunningOccurrence() async {
        let gate = ProfileRunOverlapGate()
        let id = UUID()
        let first = await gate.admit(id, policy: .queue)
        XCTAssertEqual(first, .run)

        let admitted = Flag()
        let second = Task { @MainActor in
            let admission = await gate.admit(id, policy: .queue)
            admitted.value = true
            return admission
        }
        for _ in 0..<50 { await Task.yield() }
        XCTAssertFalse(admitted.value, "A queued run must wait for the running one")
        XCTAssertTrue(gate.isRunning(id))

        await gate.finish(id)
        let admission = await second.value
        XCTAssertEqual(admission, .run)
        XCTAssertTrue(admitted.value)
        XCTAssertTrue(gate.isRunning(id))

        await gate.finish(id)
        XCTAssertFalse(gate.isRunning(id))
    }

    func testSkipDropsOnlyWhileTheSameProfileRuns() async {
        let gate = ProfileRunOverlapGate()
        let id = UUID()
        let other = UUID()

        let first = await gate.admit(id, policy: .skip)
        XCTAssertEqual(first, .run)
        let overlapping = await gate.admit(id, policy: .skip)
        XCTAssertEqual(overlapping, .skip)
        // Different automations never wait on each other.
        let otherProfile = await gate.admit(other, policy: .skip)
        XCTAssertEqual(otherProfile, .run)

        await gate.finish(id)
        XCTAssertFalse(gate.isRunning(id))
        let afterwards = await gate.admit(id, policy: .skip)
        XCTAssertEqual(afterwards, .run)

        await gate.finish(id)
        await gate.finish(other)
        XCTAssertFalse(gate.isRunning(id))
        XCTAssertFalse(gate.isRunning(other))
    }

    func testFinishWithoutAdmitIsInert() async {
        let gate = ProfileRunOverlapGate()
        let id = UUID()
        await gate.finish(id)
        XCTAssertFalse(gate.isRunning(id))
        let admission = await gate.admit(id, policy: .skip)
        XCTAssertEqual(admission, .run)
        await gate.finish(id)
    }

    // MARK: - Store

    private func makeDefaults() -> UserDefaults {
        let suite = "ProfileRunOverlapGateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testStoreDefaultsToQueue() {
        let store = ProfileRunOverlapPolicyStore(defaults: makeDefaults())
        XCTAssertEqual(ProfileRunOverlapPolicy.default, .queue)
        XCTAssertEqual(store.policy(for: UUID()), .queue)
    }

    func testStoreRoundTripsAndRemovesTheDefault() {
        let defaults = makeDefaults()
        let store = ProfileRunOverlapPolicyStore(defaults: defaults)
        let id = UUID()
        let other = UUID()

        store.setPolicy(.skip, for: id)
        store.setPolicy(.skip, for: other)
        XCTAssertEqual(ProfileRunOverlapPolicyStore(defaults: defaults).policy(for: id), .skip)
        XCTAssertEqual(
            defaults.dictionary(forKey: ProfileRunOverlapPolicyStore.defaultsKey) as? [String: String],
            [id.uuidString: "skip", other.uuidString: "skip"]
        )

        // Choosing the default removes the entry instead of storing it.
        store.setPolicy(.queue, for: id)
        XCTAssertEqual(store.policy(for: id), .queue)
        XCTAssertEqual(
            defaults.dictionary(forKey: ProfileRunOverlapPolicyStore.defaultsKey) as? [String: String],
            [other.uuidString: "skip"]
        )
        XCTAssertEqual(store.policy(for: other), .skip)
    }

    func testStoreIgnoresUnknownValues() {
        let defaults = makeDefaults()
        let id = UUID()
        defaults.set([id.uuidString: "later"], forKey: ProfileRunOverlapPolicyStore.defaultsKey)
        XCTAssertEqual(ProfileRunOverlapPolicyStore(defaults: defaults).policy(for: id), .queue)
    }
}
