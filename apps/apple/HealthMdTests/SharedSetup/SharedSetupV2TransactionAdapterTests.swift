import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class SharedSetupV2TransactionAdapterTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings is an ObservableObject
    // with nested observable properties. Static retention avoids the older-simulator-
    // runtimes / Swift 6 deinit crash documented in docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SharedSetupV2TransactionAdapterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Pure review mapping

    func testReviewsNeverClaimMisalignedPlanIdentityPairs() throws {
        let plan = try applePlan()
        // Three generated identities cannot be paired with one selected plan
        // row; the mapper must report no structured claims instead.
        let fabricated = SharedSetupV2TransactionResult(
            mode: .add,
            importedProfileIDs: [uuid(1), uuid(2), uuid(3)],
            activeProfileID: nil,
            importedScheduleCount: 0
        )
        XCTAssertTrue(SharedSetupV2ImportedProfileReview.reviews(
            plan: plan,
            selectedBundleIDs: ["profile-001"],
            result: fabricated
        ).isEmpty)

        let aligned = SharedSetupV2TransactionResult(
            mode: .replace,
            importedProfileIDs: [uuid(4)],
            activeProfileID: uuid(4),
            importedScheduleCount: 0
        )
        let reviews = SharedSetupV2ImportedProfileReview.reviews(
            plan: plan,
            selectedBundleIDs: ["profile-001"],
            result: aligned
        )
        XCTAssertEqual(reviews.map(\.sourceBundleID), ["profile-001"])
        XCTAssertEqual(reviews.map(\.sourceName), ["Summary"])
        XCTAssertEqual(reviews.map(\.destinationKind), [.deviceFolder])
    }

    // MARK: - Service over the real transaction and execution gate

    func testServiceAppliesThroughRealTransactionAndGateFailsClosedUntilVerifiedTypedRebind() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let plan = try applePlan()

        let result = try service.apply(
            plan,
            selectedBundleIDs: ["profile-002"],
            mode: .add
        )
        let macProfileID = try XCTUnwrap(result.importedProfileIDs.first)

        // Imported profiles enter the blocked set and every imported schedule
        // stays disabled, exactly as the transaction persisted them.
        XCTAssertTrue(service.isExecutionBlocked(profileID: macProfileID))
        XCTAssertEqual(try storedBlockedIDs(), [macProfileID])
        let schedules = try storedSchedules()
        XCTAssertEqual(schedules.count, 1)
        XCTAssertFalse(schedules[0].isEnabled)

        // A kind-mismatched confirmation must fail closed and stay blocked.
        XCTAssertThrowsError(try service.confirmRebind(
            profileID: macProfileID,
            confirmation: .deviceFolder(destinationID: uuid(301))
        )) { error in
            XCTAssertEqual(error as? SharedSetupV2ExecutionGateError, .rebindNotConfirmed)
        }
        XCTAssertTrue(service.isExecutionBlocked(profileID: macProfileID))

        // An unconfirmed pairing attestation must fail closed too.
        XCTAssertThrowsError(try service.confirmRebind(
            profileID: macProfileID,
            confirmation: .connectedMac(pairingConfirmed: false)
        )) { error in
            XCTAssertEqual(error as? SharedSetupV2ExecutionGateError, .rebindNotConfirmed)
        }
        XCTAssertTrue(service.isExecutionBlocked(profileID: macProfileID))

        // The verified production path clears exactly one blocked identity
        // while retaining the sidecar review row.
        XCTAssertTrue(try service.confirmRebind(
            profileID: macProfileID,
            confirmation: .connectedMac(pairingConfirmed: true)
        ))
        XCTAssertFalse(service.isExecutionBlocked(profileID: macProfileID))
        XCTAssertTrue(try storedBlockedIDs().isEmpty)
        XCTAssertEqual(try storedSidecar().profiles.map(\.profileID), [macProfileID])

        // Confirming an already-rebound profile is a no-op, not an error.
        XCTAssertFalse(try service.confirmRebind(
            profileID: macProfileID,
            confirmation: .connectedMac(pairingConfirmed: true)
        ))

        // One-shot Undo through the service keeps the transaction's honesty.
        XCTAssertTrue(service.canUndo)
        let undoResult = try service.undo()
        XCTAssertEqual(undoResult.restoredProfileIDs, [])
        XCTAssertEqual(undoResult.restoredScheduleCount, 0)
        XCTAssertNil(undoResult.activeProfileID)
        XCTAssertNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.undoKey))
        XCTAssertFalse(service.canUndo)
        XCTAssertThrowsError(try service.undo()) { error in
            XCTAssertEqual(error as? SharedSetupV2TransactionError, .noUndoSnapshot)
        }
        // The prior state was total absence, and Undo restores that exactly:
        // every aggregate key is removed rather than left holding empty data.
        XCTAssertNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.profileListKey))
        XCTAssertNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.activeProfileIDKey))
        XCTAssertNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.scheduledEntriesKey))
        XCTAssertNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.profileStateKey))
        XCTAssertNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey))
    }

    // MARK: - Production coordinator bridge (iOS coordinator seam)

    #if os(iOS)
    func testProductionBridgeMapsAddResultWithOrderedReviewsAndHonestStrings() throws {
        let existingID = uuid(1)
        seed(profiles: [existingProfile(id: existingID, name: "Existing Profile")], active: nil)

        let service = makeService(
            profileIDs: [uuid(101), uuid(102)],
            scheduleIDs: [uuid(201), uuid(202)]
        )
        let bridge = SharedSetupV2CoordinatorAdapter.production(service)
        let plan = try applePlan()

        // Caller order is shuffled; the transaction owns normalization.
        let result = try bridge.apply(plan, ["profile-004", "profile-002"], .add)

        XCTAssertEqual(result.importedProfiles.map(\.sourceBundleID), ["profile-002", "profile-004"])
        XCTAssertEqual(
            result.importedProfiles.map(\.destinationKind),
            [.connectedMac, .deviceFolder]
        )
        XCTAssertEqual(result.importedProfiles.map(\.unsupportedSemanticIDCount), [0, 0])
        XCTAssertTrue(result.appliedItems.contains("Imported 2 profiles (Add)"))
        XCTAssertTrue(result.appliedItems.contains("Imported 2 schedules; all remain disabled"))
        XCTAssertTrue(result.appliedItems.contains("Active profile: Lossless"))
        XCTAssertTrue(result.attentionItems.contains(
            "Detailed Time-Series: blocked — confirm Mac pairing locally before this profile can export"
        ))
        XCTAssertTrue(result.attentionItems.contains(
            "Lossless: blocked — choose a local folder destination before this profile can export"
        ))

        XCTAssertEqual(
            try storedProfiles().map(\.name),
            ["Existing Profile", "Detailed Time-Series", "Lossless"]
        )
        XCTAssertEqual(try storedBlockedIDs().count, 2)
        XCTAssertTrue(bridge.canUndo())
    }

    func testProductionBridgeMapsReplaceAndUnsupportedPreservation() throws {
        let service = makeService(profileIDs: [uuid(201)], scheduleIDs: [uuid(301)])
        let bridge = SharedSetupV2CoordinatorAdapter.production(service)

        // The Android-origin fixture exercises an unsupported platform-distinct
        // meaning plus the api_endpoint/device_folder destination kinds.
        let plan = SharedSetupV2Mapper.preview(
            try fixtureDocument(named: "android-shared-setup-v2.json"),
            registry: fixtureRegistry()
        )
        let result = try bridge.apply(plan, ["profile-001", "profile-002"], .replace)

        XCTAssertTrue(result.appliedItems.contains("Imported 2 profiles (Replace)"))
        XCTAssertTrue(result.appliedItems.contains("Active profile: Raw Snapshot"))
        XCTAssertEqual(result.importedProfiles.map(\.sourceBundleID), ["profile-001", "profile-002"])
        XCTAssertEqual(
            result.importedProfiles.map(\.destinationKind),
            [.apiEndpoint, .deviceFolder]
        )
        XCTAssertTrue(result.attentionItems.contains(
            "Raw Snapshot: 1 unsupported meaning is preserved for review only"
        ))
        XCTAssertTrue(result.attentionItems.contains(
            "Compatibility Export: blocked — confirm the API endpoint with a new local credential before this profile can export"
        ))

        // Replace leaves only the selected imports behind.
        let profiles = try storedProfiles()
        XCTAssertEqual(profiles.map(\.name), ["Compatibility Export", "Raw Snapshot"])
        XCTAssertEqual(try storedBlockedIDs().count, 2)
    }

    func testProductionBridgeUndoMappingAndUndoUndoUnavailability() throws {
        let existingID = uuid(1)
        let existingScheduleID = uuid(2)
        seed(
            profiles: [existingProfile(id: existingID, name: "Existing Profile")],
            active: existingID,
            schedules: [ScheduledExportEntry(
                id: existingScheduleID,
                profileID: existingID,
                isEnabled: true,
                frequency: .daily,
                preferredHour: 5
            )]
        )
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let bridge = SharedSetupV2CoordinatorAdapter.production(service)
        _ = try bridge.apply(try applePlan(), ["profile-002"], .add)
        XCTAssertEqual(try storedProfiles().count, 2)

        let undone = try bridge.undo()
        XCTAssertTrue(undone.appliedItems.contains(
            "Restored 1 profile and 1 schedule to the exact previous state"
        ))
        XCTAssertTrue(undone.appliedItems.contains("Active profile restored"))
        XCTAssertTrue(undone.importedProfiles.isEmpty)
        XCTAssertEqual(try storedProfiles().map(\.id), [existingID])
        XCTAssertFalse(bridge.canUndo())

        // The one-shot honesty survives the bridge mapping.
        XCTAssertThrowsError(try bridge.undo()) { error in
            XCTAssertEqual(error as? SharedSetupV2CoordinatorError, .noUndoSnapshot)
        }
    }

    func testCoordinatorWithProductionAdapterAppliesRebindsAndUndonesHonestly() throws {
        let service = makeService(profileIDs: [uuid(101)], scheduleIDs: [uuid(201)])
        let adapter = SharedSetupV2CoordinatorAdapter.production(service)
        let coordinator = makeCoordinator(adapter: adapter)

        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))

        XCTAssertTrue(coordinator.isV2TransactionAvailable)
        XCTAssertTrue(coordinator.isV2RebindAvailable)
        XCTAssertTrue(coordinator.canApplyV2(selectedBundleIDs: ["profile-002"]))
        XCTAssertFalse(coordinator.canApplyV2(selectedBundleIDs: []))
        XCTAssertNil(coordinator.errorMessage)

        let outcome = try coordinator.applyV2(selectedBundleIDs: ["profile-002"], mode: .add)
        XCTAssertEqual(outcome.importedProfiles.count, 1)
        XCTAssertEqual(coordinator.v2Result?.importedProfiles.count, 1)
        XCTAssertFalse(coordinator.v2ResultWasUndo)
        let importedID = try XCTUnwrap(outcome.importedProfiles.first?.id)
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: importedID))

        // An unconfirmed pairing attestation fails closed and is reported.
        XCTAssertThrowsError(try coordinator.confirmV2Rebind(
            profileID: importedID,
            confirmation: .connectedMac(pairingConfirmed: false)
        )) { error in
            XCTAssertEqual(error as? SharedSetupV2ExecutionGateError, .rebindNotConfirmed)
        }
        XCTAssertNotNil(coordinator.errorMessage)
        XCTAssertTrue(coordinator.isV2ProfileExecutionBlocked(profileID: importedID))

        // The verified rebind clears the blocked identity and is observable.
        XCTAssertTrue(try coordinator.confirmV2Rebind(
            profileID: importedID,
            confirmation: .connectedMac(pairingConfirmed: true)
        ))
        XCTAssertTrue(coordinator.v2ReboundProfileIDs.contains(importedID))
        XCTAssertFalse(coordinator.isV2ProfileExecutionBlocked(profileID: importedID))
        XCTAssertNil(coordinator.errorMessage)

        // One-shot Undo is surfaced honestly through the coordinator.
        XCTAssertTrue(coordinator.canUndoV2)
        _ = try coordinator.undoV2()
        XCTAssertTrue(coordinator.v2ResultWasUndo)
        XCTAssertFalse(coordinator.canUndoV2)
        XCTAssertThrowsError(try coordinator.undoV2()) { error in
            XCTAssertEqual(error as? SharedSetupV2CoordinatorError, .noUndoSnapshot)
        }
    }

    func testCoordinatorWithoutAdapterKeepsFailClosedV2Behavior() throws {
        let coordinator = makeCoordinator(adapter: nil)
        try coordinator.load(try fixtureData("apple-shared-setup-v2.json"))

        XCTAssertFalse(coordinator.isV2TransactionAvailable)
        XCTAssertFalse(coordinator.isV2RebindAvailable)
        XCTAssertFalse(coordinator.canApplyV2(selectedBundleIDs: ["profile-002"]))
        XCTAssertFalse(coordinator.isV2ProfileExecutionBlocked(profileID: uuid(1)))
        XCTAssertThrowsError(
            try coordinator.applyV2(selectedBundleIDs: ["profile-002"], mode: .add)
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .transactionUnavailable
            )
        }
        XCTAssertThrowsError(
            try coordinator.confirmV2Rebind(
                profileID: uuid(1),
                confirmation: .connectedMac(pairingConfirmed: true)
            )
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .transactionUnavailable
            )
        }
        XCTAssertThrowsError(try coordinator.undoV2()) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .transactionUnavailable
            )
        }
    }
    #endif

    // MARK: - Helpers

    private func makeService(
        profileIDs: [UUID],
        scheduleIDs: [UUID]
    ) -> SharedSetupV2TransactionAdapter {
        var profileIterator = profileIDs.makeIterator()
        var scheduleIterator = scheduleIDs.makeIterator()
        let transaction = SharedSetupV2ProfileTransaction(
            userDefaults: defaults,
            now: { self.fixedDate(2026, 9, 4) },
            calendar: utcCalendar(),
            makeProfileID: { profileIterator.next() ?? self.uuid(8_001) },
            makeScheduleID: { scheduleIterator.next() ?? self.uuid(8_002) }
        )
        return SharedSetupV2TransactionAdapter(
            transaction: transaction,
            executionGate: SharedSetupV2ExecutionGate(userDefaults: defaults)
        )
    }

    private func applePlan() throws -> SharedSetupV2ImportPlan {
        SharedSetupV2Mapper.preview(
            try fixtureDocument(named: "apple-shared-setup-v2.json"),
            registry: fixtureRegistry()
        )
    }

    private func fixtureDocument(named name: String) throws -> SharedSetupV2 {
        try SharedSetupV2Codec.decode(Data(contentsOf: try fixtureURL(named: name)))
    }

    private func fixtureRegistry() -> SharedSetupMetricRegistry {
        SharedSetupMetricRegistry(
            version: 1,
            sha256: "4597c2f197c25e6e6a0ec1976e3b5de930edffa2ca61fd4779d47b465075bae2",
            semanticToApple: [
                "active_energy": "active_energy",
                "blood_pressure_systolic": "blood_pressure_systolic",
                "heart_rate_avg": "heart_rate_avg",
                "hrv": "hrv",
                "sleep_core": "sleep_core",
                "steps": "steps"
            ],
            semanticToAndroid: [
                "active_energy": "active_calories",
                "blood_pressure_systolic": "bp_systolic",
                "heart_rate_avg": "avg_hr",
                "sleep_core": "sleep_light",
                "steps": "steps",
                "android.hrv_rmssd": "hrv"
            ],
            equivalence: [
                "active_energy": .mappedAlias,
                "blood_pressure_systolic": .mappedAlias,
                "heart_rate_avg": .mappedAlias,
                "hrv": .platformExactOrUnavailable,
                "sleep_core": .mappedAlias,
                "steps": .platformExactOrUnavailable,
                "android.hrv_rmssd": .platformDistinct
            ]
        )
    }

    private func existingProfile(id: UUID, name: String) -> ExportProfile {
        ExportProfile(
            id: id,
            name: name,
            settings: nativeSnapshot(),
            target: .localIPhoneFolder
        )
    }

    private func nativeSnapshot() -> ExportSettingsSnapshot {
        let name = "SharedSetupV2TransactionAdapterTests.Settings.\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: name)!
        settingsDefaults.removePersistentDomain(forName: name)
        let settings = AdvancedExportSettings(userDefaults: settingsDefaults)
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

    private func seed(
        profiles: [ExportProfile],
        active: UUID?,
        schedules: [ScheduledExportEntry] = []
    ) {
        let encoder = JSONEncoder()
        defaults.set(
            try! encoder.encode(profiles),
            forKey: SharedSetupV2ProfileTransaction.profileListKey
        )
        if let active {
            defaults.set(
                active.uuidString,
                forKey: SharedSetupV2ProfileTransaction.activeProfileIDKey
            )
        }
        defaults.set(
            try! encoder.encode(schedules),
            forKey: SharedSetupV2ProfileTransaction.scheduledEntriesKey
        )
    }

    private func storedProfiles() throws -> [ExportProfile] {
        try JSONDecoder().decode(
            [ExportProfile].self,
            from: XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.profileListKey))
        )
    }

    private func storedSchedules() throws -> [ScheduledExportEntry] {
        try JSONDecoder().decode(
            [ScheduledExportEntry].self,
            from: XCTUnwrap(
                defaults.data(forKey: SharedSetupV2ProfileTransaction.scheduledEntriesKey)
            )
        )
    }

    private func storedSidecar() throws -> SharedSetupV2AppleProfileState {
        try SharedSetupV2ProfileTransaction.decodeProfileState(
            XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.profileStateKey))
        )
    }

    private func storedBlockedIDs() throws -> [UUID] {
        try SharedSetupV2ProfileTransaction.decodeBlockedProfileIDs(
            XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey))
        )
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: try fixtureURL(named: name))
    }

    private func fixtureURL(named name: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(
                "packages/contracts/shared-setup/v2/fixtures/\(name)"
            )
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate the Shared Setup v2 fixture \(name)")
    }

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }

    private func fixedDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        utcCalendar().date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    #if os(iOS)
    private func makeCoordinator(
        adapter: SharedSetupV2CoordinatorAdapter?
    ) -> SharedSetupCoordinator {
        SharedSetupCoordinator(
            settings: AdvancedExportSettings(userDefaults: defaults),
            apiExportSettings: APIExportSettings(
                userDefaults: defaults,
                keychain: FakeKeychainStore()
            ),
            schedulingManager: SchedulingManager(
                initialSchedule: ExportSchedule(),
                persistScheduleChanges: false,
                systemSideEffectsEnabled: false
            ),
            userDefaults: defaults,
            registry: fixtureRegistry(),
            accessibilityAnnouncer: { _ in },
            v2Adapter: adapter
        )
    }
    #endif
}
