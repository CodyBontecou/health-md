import Foundation
import XCTest
@testable import HealthMd

/// Cross-platform transaction conformance: drives the native Apple Add/Replace/Undo
/// transaction against the frozen language-neutral scenario fixture
/// `packages/contracts/shared-setup/v2/fixtures/transaction-scenarios-v1.json` and asserts the
/// fixture's expected logical states exactly.
///
/// Sentinel mapping: the scenario names synthetic native identities
/// (`native-import-profile-101`, ...). Native tests must not copy those strings into persisted
/// native identity; instead each sentinel maps to one deterministic UUID minted by the injectable
/// ID factories in normalized document order. Expected states are compared by translating their
/// sentinels through the same mapping, so minted IDs stay fresh, distinct, and stable across the
/// comparison exactly as the contract's scenario rules define. `native-import-schedule-101`
/// identifies the disabled schedule row minted for `native-import-profile-101`.
@MainActor
final class SharedSetupV2TransactionScenariosTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings is an ObservableObject
    // with nested observable properties. Static retention avoids the older-simulator-
    // runtimes / Swift 6 deinit crash documented in docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    private enum ScenarioError: Error {
        case unknownSentinel(String)
        case malformedFixture(String)
    }

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cachedScenario: [String: Any]?

    override func setUp() {
        super.setUp()
        suiteName = "SharedSetupV2TransactionScenariosTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        cachedScenario = nil
        super.tearDown()
    }

    // MARK: - Frozen scenario fixture access

    private func scenarioDict() throws -> [String: Any] {
        if let cachedScenario { return cachedScenario }
        let url = try repositoryFileURL(
            "packages/contracts/shared-setup/v2/fixtures/transaction-scenarios-v1.json"
        )
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let scenario = try XCTUnwrap(json?["scenario"] as? [String: Any])
        XCTAssertEqual(
            try XCTUnwrap(scenario["name"] as? String),
            "selection-normalized-add-replace-undo"
        )
        XCTAssertEqual(
            try XCTUnwrap(scenario["scope"] as? String),
            "synthetic_local_transaction_test_only"
        )
        cachedScenario = scenario
        return scenario
    }

    private func repositoryFileURL(_ relativePath: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate \(relativePath)")
    }

    // MARK: - Sentinel -> native identity mapping (proven against the fixture itself)

    private static let sentinelToNativeID: [String: UUID] = [
        "native-existing-profile-001": SharedSetupV2TransactionScenariosTests.uuid(1),
        "native-existing-profile-002": SharedSetupV2TransactionScenariosTests.uuid(2),
        "native-import-profile-101": SharedSetupV2TransactionScenariosTests.uuid(101),
        "native-import-profile-103": SharedSetupV2TransactionScenariosTests.uuid(103),
        // Local destination-binding sentinels seed the existing native state.
        "native-folder-binding-001": SharedSetupV2TransactionScenariosTests.uuid(301),
        "native-endpoint-binding-002": SharedSetupV2TransactionScenariosTests.uuid(302),
    ]

    private var sentinelToNativeID: [String: UUID] { Self.sentinelToNativeID }

    private func nativeID(of sentinel: String?) throws -> UUID {
        guard let sentinel, let id = sentinelToNativeID[sentinel] else {
            throw ScenarioError.unknownSentinel(sentinel ?? "<nil>")
        }
        return id
    }

    private func requireSentinelMappingMatchesFixture() throws {
        let generatedProfiles = try dict("generated_profile_ids")
        XCTAssertEqual(
            try XCTUnwrap(generatedProfiles["profile-001"] as? String),
            "native-import-profile-101"
        )
        XCTAssertEqual(
            try XCTUnwrap(generatedProfiles["profile-003"] as? String),
            "native-import-profile-103"
        )
        let generatedSchedules = try dict("generated_schedule_ids")
        XCTAssertEqual(
            try XCTUnwrap(generatedSchedules["profile-001"] as? String),
            "native-import-schedule-101"
        )
        XCTAssertEqual(Set(generatedSchedules.keys), ["profile-001"])
    }

    // MARK: - Scenario-driven plan construction

    private func scenarioRegistry() -> SharedSetupMetricRegistry {
        SharedSetupMetricRegistry(
            version: 1,
            sha256: String(repeating: "b", count: 64),
            semanticToApple: [
                "steps": "steps",
                "active_energy": "active_energy",
            ],
            semanticToAndroid: [
                "steps": "steps",
                "active_energy": "active_calories",
            ],
            equivalence: [
                "steps": .platformExactOrUnavailable,
                "active_energy": .mappedAlias,
            ]
        )
    }

    private func scenarioDocument() throws -> SharedSetupV2 {
        let data = try JSONSerialization.data(withJSONObject: try dict("source_document"))
        return try SharedSetupV2Codec.decode(data)
    }

    private func scenarioPlan() throws -> SharedSetupV2ImportPlan {
        SharedSetupV2Mapper.preview(try scenarioDocument(), registry: scenarioRegistry())
    }

    // MARK: - Scenario-driven seeding of the existing native state

    private func existingState() throws -> [String: Any] { try dict("existing_state") }

    private func existingProfiles() throws -> [ExportProfile] {
        let rows = try objectRows("profiles", in: existingState())
        return try rows.map { row in
            ExportProfile(
                id: try nativeID(of: row["profile_id"] as? String),
                name: try XCTUnwrap(row["name"] as? String),
                settings: nativeSnapshot(filename: "existing-{date}"),
                target: appleTarget(try XCTUnwrap(row["destination_intent"] as? String)),
                folderVaultID: try (row["folder_binding_id"] as? String).map(nativeID(of:)),
                apiEndpointID: try (row["api_endpoint_binding_id"] as? String).map(nativeID(of:)),
                createdAt: fixedDate(2024, 1, 1),
                updatedAt: fixedDate(2024, 1, 2),
                isMigrationDefault: false
            )
        }
    }

    private func existingSchedules() throws -> [ScheduledExportEntry] {
        let rows = try objectRows("schedules", in: existingState())
        return try rows.map { row in
            ScheduledExportEntry(
                id: Self.uuid(3),
                profileID: try nativeID(of: row["profile_id"] as? String),
                isEnabled: try XCTUnwrap(row["is_enabled"] as? Bool),
                frequency: .weekly,
                customInterval: 3,
                customUnit: .month,
                customAnchorDate: fixedDate(2024, 3, 4),
                preferredHour: 7,
                preferredMinute: 30,
                weekday: 5,
                lookbackDays: 5,
                lastExportDate: fixedDate(2024, 2, 1),
                lastTodayRefreshDate: fixedDate(2024, 2, 2),
                enabledAt: fixedDate(2024, 1, 1)
            )
        }
    }

    private func expectedSidecarRows(in state: [String: Any]) throws -> [(profileID: UUID, bundleID: String, unsupported: [String])] {
        let rows = try objectRows("profiles", in: try dict("sidecar", in: state))
        return try rows.map { row in
            (
                try nativeID(of: row["profile_id"] as? String),
                try XCTUnwrap(row["source_bundle_id"] as? String),
                (row["unsupported_semantic_ids"] as? [String]) ?? []
            )
        }
    }

    private func seedExistingState() throws {
        let expectedRows = try expectedSidecarRows(in: existingState())
        let sidecar: SharedSetupV2AppleProfileState
        if expectedRows.isEmpty {
            sidecar = SharedSetupV2AppleProfileState(profiles: [])
        } else {
            let document = try scenarioDocument()
            sidecar = SharedSetupV2AppleProfileState(
                profiles: try expectedRows.map { row in
                    SharedSetupV2AppleProfileState.Profile(
                        profileID: row.profileID,
                        sourceBundleID: row.bundleID,
                        sourceProfile: try XCTUnwrap(
                            document.profiles.first { $0.bundleID == row.bundleID }
                        ),
                        unsupportedSemanticIDs: row.unsupported
                    )
                }
            )
        }
        let blockedSentinels = try XCTUnwrap(existingState()["blocked_profile_ids"] as? [String])
        seed(
            profiles: try existingProfiles(),
            active: try nativeID(of: existingState()["active_profile_id"] as? String),
            schedules: try existingSchedules(),
            sidecar: sidecar,
            blocked: try blockedSentinels.map(nativeID(of:))
        )
        let environment = try dict("local_environment")
        defaults.set(
            try XCTUnwrap(environment["destination_store_marker"] as? String),
            forKey: destinationMarkerKey
        )
        defaults.set(
            try XCTUnwrap(environment["secure_store_marker"] as? String),
            forKey: secureMarkerKey
        )
    }

    private func makeTransaction(
        profileIDs: [UUID],
        scheduleIDs: [UUID],
        verificationOverride: (() -> Bool)? = nil
    ) -> SharedSetupV2ProfileTransaction {
        var profileIterator = profileIDs.makeIterator()
        var scheduleIterator = scheduleIDs.makeIterator()
        return SharedSetupV2ProfileTransaction(
            userDefaults: defaults,
            now: { self.fixedDate(2026, 9, 4) },
            calendar: utcCalendar(),
            makeProfileID: { profileIterator.next() ?? Self.uuid(8_001) },
            makeScheduleID: { scheduleIterator.next() ?? Self.uuid(8_002) },
            verificationOverride: verificationOverride
        )
    }

    private func scenarioTransaction(
        verificationOverride: (() -> Bool)? = nil
    ) -> SharedSetupV2ProfileTransaction {
        makeTransaction(
            profileIDs: [Self.uuid(101), Self.uuid(103)],
            scheduleIDs: [Self.uuid(201)],
            verificationOverride: verificationOverride
        )
    }

    /// Both platforms project the portable destination kind to the closest native display
    /// intent. On Apple `device_folder` and `cloud` land on the local iPhone folder target;
    /// no imported binding is inherited either way.
    private func appleTarget(_ destinationIntent: String) -> ExportTargetSelection {
        switch destinationIntent {
        case "api_endpoint": .apiEndpoint
        case "connected_mac": .connectedMac
        default: .localIPhoneFolder
        }
    }

    // MARK: - Shared expected-state assertions

    private func assertProfilesMatchExpectedState(_ stateName: String) throws {
        let state = try dict("expected_\(stateName)")
        let expectedRows = try objectRows("profiles", in: state)
        let profiles = try storedProfiles()

        XCTAssertEqual(
            profiles.map(\.id),
            try expectedRows.map { try nativeID(of: $0["profile_id"] as? String) }
        )
        XCTAssertEqual(
            profiles.map(\.name),
            try expectedRows.map { try XCTUnwrap($0["name"] as? String) }
        )
        for (native, expected) in zip(profiles, expectedRows) {
            XCTAssertEqual(
                native.target,
                appleTarget(try XCTUnwrap(expected["destination_intent"] as? String))
            )
            if expected["settings_source_bundle_id"] is String {
                // Imported destination intent is inert: no folder or API binding is inherited.
                XCTAssertNil(native.folderVaultID)
                XCTAssertNil(native.apiEndpointID)
            } else {
                if let sentinel = expected["folder_binding_id"] as? String {
                    XCTAssertEqual(native.folderVaultID, try nativeID(of: sentinel))
                } else {
                    XCTAssertNil(native.folderVaultID)
                }
                if let sentinel = expected["api_endpoint_binding_id"] as? String {
                    XCTAssertEqual(native.apiEndpointID, try nativeID(of: sentinel))
                } else {
                    XCTAssertNil(native.apiEndpointID)
                }
            }
        }
        XCTAssertEqual(
            storedActiveID(),
            try nativeID(of: state["active_profile_id"] as? String)
        )
    }

    private func assertBlockedAndSidecarMatchExpectedState(_ stateName: String) throws {
        let state = try dict("expected_\(stateName)")
        let expectedBlocked = try XCTUnwrap(state["blocked_profile_ids"] as? [String])
            .map(nativeID(of:))
        XCTAssertEqual(try storedBlockedIDs(), expectedBlocked)
        XCTAssertNotNil(defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey))

        let sourceDocument = try scenarioDocument()
        let expectedRows = try expectedSidecarRows(in: state)
        let sidecar = try storedSidecar()
        XCTAssertEqual(sidecar.version, 1)
        XCTAssertEqual(sidecar.profiles.map(\.profileID), expectedRows.map(\.profileID))
        for (row, expected) in zip(sidecar.profiles, expectedRows) {
            XCTAssertEqual(row.sourceBundleID, expected.bundleID)
            XCTAssertEqual(row.unsupportedSemanticIDs, expected.unsupported)
            // The complete closed source v2 DTO is preserved per profile, including any
            // foreign typed extension and unsupported semantic meaning.
            XCTAssertEqual(
                row.sourceProfile,
                sourceDocument.profiles.first { $0.bundleID == expected.bundleID }
            )
        }
    }

    private func assertImportedScheduleRowsMatchExpectedState(_ stateName: String) throws {
        let state = try dict("expected_\(stateName)")
        let expectedRows = try objectRows("schedules", in: state)
        let schedules = try storedSchedules()
        let existingByProfile = Dictionary(
            uniqueKeysWithValues: try existingSchedules().map { ($0.profileID, $0) }
        )

        XCTAssertEqual(
            schedules.map(\.profileID),
            try expectedRows.map { try nativeID(of: $0["profile_id"] as? String) }
        )
        for (native, expected) in zip(schedules, expectedRows) {
            XCTAssertEqual(native.isEnabled, try XCTUnwrap(expected["is_enabled"] as? Bool))
            if (try XCTUnwrap(expected["schedule_id"] as? String)).hasPrefix("native-import-") {
                // Imported schedules are always disabled with empty runtime-local state.
                XCTAssertNil(native.enabledAt)
                XCTAssertNil(native.lastExportDate)
                XCTAssertNil(native.lastTodayRefreshDate)
            } else {
                // Existing schedule rows are preserved exactly, runtime state included.
                XCTAssertEqual(native, existingByProfile[native.profileID])
            }
        }
    }

    private func assertExistingAggregateRestored() throws {
        XCTAssertEqual(try storedProfiles(), try existingProfiles())
        XCTAssertEqual(
            storedActiveID(),
            try nativeID(of: existingState()["active_profile_id"] as? String)
        )
        XCTAssertEqual(try storedSchedules(), try existingSchedules())
        XCTAssertEqual(try storedBlockedIDs(), [])
        XCTAssertEqual(try storedSidecar(), SharedSetupV2AppleProfileState(profiles: []))
    }

    private func assertLocalEnvironmentUnchanged() throws {
        let environment = try dict("expected_unmodified_local_environment")
        XCTAssertEqual(
            defaults.string(forKey: destinationMarkerKey),
            try XCTUnwrap(environment["destination_store_marker"] as? String)
        )
        XCTAssertEqual(
            defaults.string(forKey: secureMarkerKey),
            try XCTUnwrap(environment["secure_store_marker"] as? String)
        )
    }

    // MARK: - Tests

    func testAddReproducesFrozenScenarioExpectedState() throws {
        try requireSentinelMappingMatchesFixture()
        try seedExistingState()
        let callerSelection = try strings("caller_selection")
        let normalizedSelection = try strings("normalized_selection")
        XCTAssertNotEqual(callerSelection, normalizedSelection)

        let result = try scenarioTransaction().apply(
            try scenarioPlan(),
            selectedBundleIDs: callerSelection,
            mode: .add
        )

        // Caller order never determines persistence order: selection is normalized
        // into source document order and fresh IDs follow that order.
        XCTAssertEqual(result.importedProfileIDs, [Self.uuid(101), Self.uuid(103)])
        XCTAssertEqual(result.activeProfileID, Self.uuid(2))
        XCTAssertEqual(result.importedScheduleCount, 1)

        // Existing schedule row is preserved exactly in Add mode.
        XCTAssertEqual(try storedSchedules().first, try existingSchedules().first)

        try assertProfilesMatchExpectedState("add_state")
        try assertBlockedAndSidecarMatchExpectedState("add_state")
        try assertLocalEnvironmentUnchanged()
    }

    func testReplaceReproducesFrozenScenarioExpectedState() throws {
        try requireSentinelMappingMatchesFixture()
        try seedExistingState()

        let result = try scenarioTransaction().apply(
            try scenarioPlan(),
            selectedBundleIDs: try strings("caller_selection"),
            mode: .replace
        )

        XCTAssertEqual(result.importedProfileIDs, [Self.uuid(101), Self.uuid(103)])
        XCTAssertEqual(result.activeProfileID, Self.uuid(103), "selected source active wins")

        try assertProfilesMatchExpectedState("replace_state")
        try assertBlockedAndSidecarMatchExpectedState("replace_state")
        try assertLocalEnvironmentUnchanged()
    }

    func testImportedSchedulesMaterializeDisabledPerFrozenScenario() throws {
        try requireSentinelMappingMatchesFixture()

        try seedExistingState()
        _ = try scenarioTransaction().apply(
            try scenarioPlan(),
            selectedBundleIDs: try strings("caller_selection"),
            mode: .add
        )
        try assertImportedScheduleRowsMatchExpectedState("add_state")

        try seedExistingState()
        _ = try scenarioTransaction().apply(
            try scenarioPlan(),
            selectedBundleIDs: try strings("caller_selection"),
            mode: .replace
        )
        try assertImportedScheduleRowsMatchExpectedState("replace_state")

        // The frozen source intent for profile-001 is daily 08:00, weekday 3, lookback 2,
        // anchored 2025-01-01, with Apple today refresh requested at 6-hour intervals.
        // Import must keep it disabled while materializing the exact configuration.
        let imported = try XCTUnwrap(try storedSchedules().first { $0.profileID == Self.uuid(101) })
        XCTAssertFalse(imported.isEnabled)
        XCTAssertEqual(imported.id, Self.uuid(201))
        XCTAssertEqual(imported.frequency, .daily)
        XCTAssertEqual(imported.customUnit, .day)
        XCTAssertEqual(imported.preferredHour, 8)
        XCTAssertEqual(imported.preferredMinute, 0)
        XCTAssertEqual(imported.weekday, 3)
        XCTAssertEqual(imported.lookbackDays, 2)
        XCTAssertTrue(imported.todayRefreshEnabled)
        XCTAssertEqual(imported.todayRefreshIntervalHours, 6)
    }

    func testFailedApplyRestoresExactExistingStateAndPriorUndo() throws {
        try requireSentinelMappingMatchesFixture()
        try seedExistingState()
        let priorUndo = Data("previous-v2-undo".utf8)
        defaults.set(priorUndo, forKey: SharedSetupV2ProfileTransaction.undoKey)
        let before = fiveKeyState()
        let rollback = try dict("expected_failed_apply_rollback")
        XCTAssertEqual(try XCTUnwrap(rollback["verification_required"] as? Bool), true)
        XCTAssertEqual(try XCTUnwrap(rollback["previous_undo_restored"] as? Bool), true)
        let plan = try scenarioPlan()

        XCTAssertThrowsError(try scenarioTransaction(verificationOverride: { false }).apply(
            plan,
            selectedBundleIDs: try strings("caller_selection"),
            mode: .add
        )) { error in
            XCTAssertEqual(
                error as? SharedSetupV2TransactionError,
                .persistenceVerificationFailed
            )
        }

        XCTAssertEqual(fiveKeyState(), before, "verified rollback restores every prior value")
        XCTAssertEqual(
            defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey),
            priorUndo,
            "the prior Undo value is restored, not destroyed"
        )
        try assertExistingAggregateRestored()
        try assertLocalEnvironmentUnchanged()
    }

    func testUndoRestoresExistingStateOnceThenReportsNoUndo() throws {
        try requireSentinelMappingMatchesFixture()
        try seedExistingState()
        let prior = fiveKeyState()
        let transaction = scenarioTransaction()
        _ = try transaction.apply(
            try scenarioPlan(),
            selectedBundleIDs: try strings("caller_selection"),
            mode: .add
        )
        XCTAssertTrue(transaction.canUndo)

        let undoResult = try transaction.undo()

        XCTAssertEqual(undoResult.restoredProfileIDs, try existingProfiles().map(\.id))
        XCTAssertEqual(
            undoResult.activeProfileID,
            try nativeID(of: existingState()["active_profile_id"] as? String)
        )
        XCTAssertEqual(undoResult.restoredScheduleCount, try existingSchedules().count)
        XCTAssertEqual(fiveKeyState(), prior, "Undo restores exact prior bytes and absence")
        XCTAssertNil(defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey))
        XCTAssertFalse(transaction.canUndo)
        try assertExistingAggregateRestored()
        try assertLocalEnvironmentUnchanged()

        XCTAssertThrowsError(try transaction.undo()) { error in
            XCTAssertEqual(error as? SharedSetupV2TransactionError, .noUndoSnapshot)
        }
        XCTAssertEqual(
            try XCTUnwrap(try dict("expected_undo")["second_attempt"] as? String),
            "no_undo_snapshot"
        )
    }

    func testInvalidSelectionsAreRejectedBeforeAnyWrite() throws {
        try requireSentinelMappingMatchesFixture()
        try seedExistingState()
        let baseline = defaults.dictionaryRepresentation() as NSDictionary
        let plan = try scenarioPlan()
        let transaction = scenarioTransaction()

        for selection: [String] in [[], ["profile-001", "profile-001"], ["profile-999"], [" "]] {
            XCTAssertThrowsError(try transaction.apply(
                plan,
                selectedBundleIDs: selection,
                mode: .add
            ))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, baseline)
        }
    }

    // MARK: - Stored-state helpers

    private var destinationMarkerKey: String { "conformanceDestinationStoreMarker" }
    private var secureMarkerKey: String { "conformanceSecureStoreMarker" }

    private func seed(
        profiles: [ExportProfile],
        active: UUID?,
        schedules: [ScheduledExportEntry],
        sidecar: SharedSetupV2AppleProfileState? = nil,
        blocked: [UUID]? = nil
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
        if let sidecar {
            defaults.set(
                try! encoder.encode(sidecar),
                forKey: SharedSetupV2ProfileTransaction.profileStateKey
            )
        }
        if let blocked {
            defaults.set(
                try! SharedSetupV2ProfileTransaction.encodeBlockedProfileIDs(blocked),
                forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
            )
        }
    }

    private func storedProfiles() throws -> [ExportProfile] {
        try JSONDecoder().decode(
            [ExportProfile].self,
            from: try XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.profileListKey))
        )
    }

    private func storedSchedules() throws -> [ScheduledExportEntry] {
        try JSONDecoder().decode(
            [ScheduledExportEntry].self,
            from: try XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.scheduledEntriesKey))
        )
    }

    private func storedSidecar() throws -> SharedSetupV2AppleProfileState {
        try SharedSetupV2ProfileTransaction.decodeProfileState(
            try XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.profileStateKey))
        )
    }

    private func storedBlockedIDs() throws -> [UUID] {
        try SharedSetupV2ProfileTransaction.decodeBlockedProfileIDs(
            try XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey))
        )
    }

    private func storedActiveID() -> UUID? {
        defaults.string(forKey: SharedSetupV2ProfileTransaction.activeProfileIDKey)
            .flatMap(UUID.init(uuidString:))
    }

    private func fiveKeyState() -> NSDictionary {
        let keys = [
            SharedSetupV2ProfileTransaction.profileListKey,
            SharedSetupV2ProfileTransaction.activeProfileIDKey,
            SharedSetupV2ProfileTransaction.scheduledEntriesKey,
            SharedSetupV2ProfileTransaction.profileStateKey,
            SharedSetupV2ProfileTransaction.blockedProfileIDsKey,
        ]
        return defaults.dictionaryRepresentation().filter { keys.contains($0.key) } as NSDictionary
    }

    private func nativeSnapshot(filename: String) -> ExportSettingsSnapshot {
        let name = "SharedSetupV2TransactionScenariosTests.Settings.\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: name)!
        settingsDefaults.removePersistentDomain(forName: name)
        let settings = AdvancedExportSettings(userDefaults: settingsDefaults)
        settings.filenameFormat = filename
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

    private func dict(_ key: String, in parent: [String: Any]? = nil) throws -> [String: Any] {
        let source: [String: Any]
        if let parent {
            source = parent
        } else {
            source = try scenarioDict()
        }
        guard let value = source[key] as? [String: Any] else {
            throw ScenarioError.malformedFixture("Missing object \(key)")
        }
        return value
    }

    private func objectRows(_ key: String, in parent: [String: Any]) throws -> [[String: Any]] {
        guard let value = parent[key] as? [[String: Any]] else {
            throw ScenarioError.malformedFixture("Missing object array \(key)")
        }
        return value
    }

    private func strings(_ key: String) throws -> [String] {
        guard let value = try scenarioDict()[key] as? [String] else {
            throw ScenarioError.malformedFixture("Missing string array \(key)")
        }
        return value
    }

    private static func uuid(_ value: Int) -> UUID {
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
}
