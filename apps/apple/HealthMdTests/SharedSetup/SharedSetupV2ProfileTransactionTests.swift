import Foundation
import XCTest
@testable import HealthMd
#if os(iOS)
import HealthMdConnectionCore
#endif

@MainActor
final class SharedSetupV2ProfileTransactionTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings (and retained transaction
    // collaborators) are ObservableObjects with nested observable properties. Static
    // retention avoids the older-simulator-runtimes / Swift 6 deinit crash documented
    // in docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []
    private static var retainedInstances: [AnyObject] = []

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "SharedSetupV2ProfileTransactionTests.\(UUID().uuidString)"
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

    func testAddNormalizesSelectionMaterializesExactFreshProfilesAndKeepsSchedulesInert() throws {
        let existingID = uuid(1)
        let existingScheduleID = uuid(2)
        let existing = ExportProfile(
            id: existingID,
            name: "Detailed Time-Series",
            settings: nativeSnapshot(filename: "existing-{date}"),
            target: .apiEndpoint,
            folderVaultID: uuid(90),
            apiEndpointID: uuid(91),
            createdAt: fixedDate(2024, 1, 1),
            updatedAt: fixedDate(2024, 1, 2),
            isMigrationDefault: true
        )
        let existingSchedule = ScheduledExportEntry(
            id: existingScheduleID,
            profileID: existingID,
            isEnabled: true,
            frequency: .daily,
            preferredHour: 5,
            lastExportDate: fixedDate(2024, 2, 1),
            enabledAt: fixedDate(2024, 1, 1)
        )
        seed(profiles: [existing], active: existingID, schedules: [existingSchedule])

        let importedIDs = [uuid(101), uuid(102)]
        let scheduleIDs = [uuid(201), uuid(202)]
        let transaction = makeTransaction(
            profileIDs: importedIDs,
            scheduleIDs: scheduleIDs
        )
        let result = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-004", "profile-002"],
            mode: .add
        )

        let profiles = try storedProfiles()
        XCTAssertEqual(profiles.map(\.id), [existingID] + importedIDs)
        XCTAssertEqual(
            profiles.map(\.name),
            ["Detailed Time-Series", "Detailed Time-Series 2", "Lossless"]
        )
        XCTAssertEqual(result.importedProfileIDs, importedIDs)
        XCTAssertEqual(result.activeProfileID, existingID)
        XCTAssertEqual(storedActiveID(), existingID)
        XCTAssertTrue(transaction.canUndo)

        let detailed = profiles[1]
        XCTAssertEqual(detailed.target, .connectedMac)
        XCTAssertNil(detailed.folderVaultID)
        XCTAssertNil(detailed.apiEndpointID)
        XCTAssertNil(detailed.settings.healthSubfolder)
        XCTAssertNil(detailed.settings.appleExportEnginePin)
        XCTAssertTrue(detailed.settings.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(detailed.settings.calendarTimeZoneIdentifier)
        XCTAssertEqual(detailed.settings.compatibilityDetail, .selectedTimeSeries)
        XCTAssertEqual(detailed.settings.healthKitSourceArchivePolicy, .none)
        XCTAssertEqual(detailed.settings.metricSelection.enabledMetricIDs, ["heart_rate_avg", "sleep_core"])
        XCTAssertEqual(detailed.settings.metricSelection.enabledCategoryIDs, [])

        let lossless = profiles[2]
        XCTAssertEqual(lossless.settings.compatibilityDetail, .selectedTimeSeries)
        XCTAssertEqual(lossless.settings.healthKitSourceArchivePolicy, .canonicalV1)
        XCTAssertTrue(lossless.settings.generateRangeSummary)
        XCTAssertNil(lossless.folderVaultID)
        XCTAssertNil(lossless.apiEndpointID)

        let schedules = try storedSchedules()
        XCTAssertEqual(schedules.map(\.id), [existingScheduleID] + scheduleIDs)
        XCTAssertTrue(schedules[0].isEnabled, "Add preserves the existing row exactly")
        XCTAssertEqual(schedules.dropFirst().map(\.profileID), importedIDs)
        for schedule in schedules.dropFirst() {
            XCTAssertFalse(schedule.isEnabled)
            XCTAssertNil(schedule.enabledAt)
            XCTAssertNil(schedule.lastExportDate)
            XCTAssertNil(schedule.lastTodayRefreshDate)
        }
        XCTAssertEqual(schedules[1].frequency, .daily)
        XCTAssertEqual(schedules[1].todayRefreshIntervalHours, 6)
        XCTAssertEqual(schedules[2].frequency, .custom)
        XCTAssertEqual(schedules[2].customInterval, 2)
        XCTAssertEqual(schedules[2].customUnit, .month)

        let sidecar = try storedSidecar()
        XCTAssertEqual(sidecar.version, 1)
        XCTAssertEqual(sidecar.profiles.map(\.profileID), importedIDs)
        XCTAssertEqual(
            sidecar.profiles.map(\.sourceBundleID),
            ["profile-002", "profile-004"]
        )
        XCTAssertEqual(sidecar.profiles.map(\.unsupportedSemanticIDs), [[], []])
        XCTAssertEqual(sidecar.profiles[0].sourceProfile.destination.kind, .connectedMac)
        XCTAssertEqual(sidecar.profiles[1].sourceProfile.schedule?.activationRequested, true)
        XCTAssertLessThanOrEqual(
            try XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.profileStateKey)).count,
            SharedSetupV2ProfileTransaction.maximumProfileStateBytes
        )
        XCTAssertEqual(try storedBlockedIDs(), importedIDs)
    }

    func testForeignExtensionAndUnavailableMeaningRemainSidecarOnly() throws {
        var document = try fixtureDocument(named: "android-shared-setup-v2.json")
        document.profiles[1].presentation.markdown.originDialect = .android
        document.profiles[1].presentation.markdown.customText = "{{android_only_token}}"
        document.profiles[1].presentation.markdown.headerLevel = 4
        document.profiles[1].presentation.markdown.useEmoji = true
        document.profiles[1].presentation.markdown.includeSummary = false
        document.profiles[1].presentation.markdown.bulletStyle = .plus
        let plan = SharedSetupV2Mapper.preview(document, registry: fixtureRegistry())
        XCTAssertFalse(plan.hasInvalidItems)
        XCTAssertFalse(plan.profiles[1].installCustomTemplate)
        XCTAssertEqual(
            plan.profiles[1].unsupportedPreservedSemanticIDs,
            ["android.hrv_rmssd"]
        )

        let profileID = uuid(105)
        let transaction = makeTransaction(profileIDs: [profileID], scheduleIDs: [])
        _ = try transaction.apply(
            plan,
            selectedBundleIDs: ["profile-002"],
            mode: .replace
        )

        let native = try XCTUnwrap(storedProfiles().first)
        XCTAssertEqual(native.id, profileID)
        XCTAssertEqual(native.settings.metricSelection.enabledMetricIDs, [])
        XCTAssertEqual(
            native.settings.individualTracking.metricConfigs,
            [
                "sleep_core": MetricTrackingConfig(
                    trackIndividually: false,
                    customFolder: "entries/sleep"
                )
            ]
        )
        XCTAssertNil(native.settings.individualTracking.metricConfigs["android.hrv_rmssd"])
        let installedMarkdown = native.settings.formatCustomization.markdownTemplate
        XCTAssertEqual(installedMarkdown.style, .standard)
        XCTAssertNotEqual(
            installedMarkdown.customTemplate,
            document.profiles[1].presentation.markdown.customText
        )
        XCTAssertEqual(installedMarkdown.sectionHeaderLevel, 4)
        XCTAssertTrue(installedMarkdown.useEmoji)
        XCTAssertFalse(installedMarkdown.includeSummary)
        XCTAssertEqual(installedMarkdown.bulletStyle, .plus)
        XCTAssertNil(native.folderVaultID)
        XCTAssertNil(native.apiEndpointID)

        let row = try XCTUnwrap(storedSidecar().profiles.first)
        XCTAssertEqual(row.sourceProfile, document.profiles[1])
        XCTAssertNotNil(row.sourceProfile.platformExtensions.android)
        XCTAssertNil(row.sourceProfile.platformExtensions.apple)
        XCTAssertEqual(row.unsupportedSemanticIDs, ["android.hrv_rmssd"])
    }

    func testReplaceUsesSelectedOnlySourceActiveFallbackAndUndoRestoresExactFiveKeyStateOnce() throws {
        let oldID = uuid(10)
        let oldScheduleID = uuid(11)
        let oldProfile = ExportProfile(
            id: oldID,
            name: "Old",
            settings: nativeSnapshot(filename: "old-{date}"),
            target: .localIPhoneFolder,
            createdAt: fixedDate(2023, 1, 1),
            updatedAt: fixedDate(2023, 1, 2)
        )
        let oldSchedule = ScheduledExportEntry(
            id: oldScheduleID,
            profileID: oldID,
            isEnabled: true,
            lastExportDate: fixedDate(2023, 2, 1)
        )
        let document = try appleDocument()
        let oldSidecar = SharedSetupV2AppleProfileState(profiles: [
            .init(
                profileID: oldID,
                sourceBundleID: document.profiles[0].bundleID,
                sourceProfile: document.profiles[0],
                unsupportedSemanticIDs: []
            )
        ])
        seed(
            profiles: [oldProfile],
            active: oldID,
            schedules: [oldSchedule],
            sidecar: oldSidecar,
            blocked: [oldID]
        )
        let prior = fiveKeyState()

        let importedIDs = [uuid(111), uuid(112)]
        let transaction = makeTransaction(
            profileIDs: importedIDs,
            scheduleIDs: [uuid(211)]
        )
        let result = try transaction.apply(
            SharedSetupV2Mapper.preview(document, registry: fixtureRegistry()),
            selectedBundleIDs: ["profile-003", "profile-001"],
            mode: .replace
        )

        XCTAssertEqual(try storedProfiles().map(\.id), importedIDs)
        XCTAssertEqual(try storedProfiles().map(\.name), ["Summary", "Archive Only"])
        XCTAssertEqual(result.activeProfileID, importedIDs[0], "source active was not selected")
        XCTAssertEqual(storedActiveID(), importedIDs[0])
        XCTAssertEqual(try storedSchedules().map(\.profileID), [importedIDs[1]])
        XCTAssertEqual(try storedBlockedIDs(), importedIDs)
        XCTAssertNotEqual(fiveKeyState(), prior)
        XCTAssertTrue(transaction.canUndo)

        let undoResult = try transaction.undo()

        XCTAssertEqual(undoResult.restoredProfileIDs, [oldID])
        XCTAssertEqual(undoResult.activeProfileID, oldID)
        XCTAssertEqual(undoResult.restoredScheduleCount, 1)
        XCTAssertEqual(fiveKeyState(), prior, "Undo restores exact prior bytes and absence")
        XCTAssertFalse(transaction.canUndo)
        XCTAssertThrowsError(try transaction.undo()) { error in
            XCTAssertEqual(error as? SharedSetupV2TransactionError, .noUndoSnapshot)
        }
    }

    func testSelectionFailuresAndFailedVerifiedApplyPerformNoMutationAndPreservePreviousUndo() throws {
        let oldID = uuid(20)
        seed(
            profiles: [ExportProfile(
                id: oldID,
                name: "Old",
                settings: nativeSnapshot(filename: "old-{date}"),
                target: .localIPhoneFolder
            )],
            active: oldID,
            schedules: []
        )
        let plan = try applePlan()
        let baseline = defaults.dictionaryRepresentation() as NSDictionary
        let normal = makeTransaction(profileIDs: [uuid(121)], scheduleIDs: [])

        for selection in [[], ["profile-001", "profile-001"], ["profile-999"]] {
            XCTAssertThrowsError(try normal.apply(
                plan,
                selectedBundleIDs: selection,
                mode: .replace
            ))
            XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, baseline)
        }

        let previousUndo = Data("previous-v2-undo".utf8)
        defaults.set(previousUndo, forKey: SharedSetupV2ProfileTransaction.undoKey)
        let beforeFailedApply = defaults.dictionaryRepresentation() as NSDictionary
        let failing = makeTransaction(
            profileIDs: [uuid(122)],
            scheduleIDs: [],
            verificationOverride: { false }
        )

        XCTAssertThrowsError(try failing.apply(
            plan,
            selectedBundleIDs: ["profile-001"],
            mode: .replace
        )) { error in
            XCTAssertEqual(
                error as? SharedSetupV2TransactionError,
                .persistenceVerificationFailed
            )
        }
        XCTAssertEqual(
            defaults.dictionaryRepresentation() as NSDictionary,
            beforeFailedApply,
            "verified rollback restores every value, including the prior Undo bytes"
        )
        XCTAssertEqual(
            defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey),
            previousUndo
        )
    }

    func testCompactAfterProfileDeletionRemovesRowAndBlockedEntryAndKeepsRemainingRows() throws {
        let importedIDs = [uuid(161), uuid(162)]
        let transaction = makeTransaction(profileIDs: importedIDs, scheduleIDs: [uuid(261)])
        _ = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-003", "profile-001"],
            mode: .replace
        )
        // Simulate the native stores' deletion of the second imported profile:
        // the profile row and its scheduled entry disappear from their keys
        // while the sidecar keys still hold the stale references.
        let deletedID = importedIDs[1]
        let remaining = try storedProfiles().filter { $0.id != deletedID }
        seed(
            profiles: remaining,
            active: remaining.first?.id,
            schedules: try storedSchedules().filter { $0.profileID != deletedID }
        )
        let priorUndoData = defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey)

        XCTAssertTrue(try transaction.compactAfterProfileDeletion(profileID: deletedID))

        XCTAssertEqual(try storedSidecar().profiles.map(\.profileID), [importedIDs[0]])
        XCTAssertEqual(try storedBlockedIDs(), [importedIDs[0]])
        XCTAssertNotNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.profileStateKey))
        XCTAssertNotNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey))
        XCTAssertEqual(
            defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey),
            priorUndoData,
            "compaction never touches the one-shot Undo snapshot"
        )

        // Idempotent: nothing references the id anymore, so a second pass is
        // a clean no-op that rewrites no key.
        let compactedState = fiveKeyState()
        XCTAssertFalse(try transaction.compactAfterProfileDeletion(profileID: deletedID))
        XCTAssertEqual(fiveKeyState(), compactedState)
    }

    func testCompactAfterProfileDeletionRemovesBothKeysWhenNoRowsRemain() throws {
        let importedID = uuid(171)
        let transaction = makeTransaction(profileIDs: [importedID], scheduleIDs: [])
        _ = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-003"],
            mode: .replace
        )
        XCTAssertNotNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.profileStateKey))
        XCTAssertNotNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey))
        seed(profiles: [], active: nil, schedules: [])

        XCTAssertTrue(try transaction.compactAfterProfileDeletion(profileID: importedID))

        XCTAssertNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.profileStateKey))
        XCTAssertNil(defaults.object(forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey))
    }

    func testCompactAfterProfileDeletionDropsLegacyStaleRowsInSamePass() throws {
        // A sidecar row (and blocked id) for a profile deleted by an older
        // build is inert but still occupies the bounded store. Compacting an
        // unrelated deletion rewrites the canonical live state, so the legacy
        // bytes are dropped in the same pass.
        let importedIDs = [uuid(181), uuid(182)]
        let transaction = makeTransaction(profileIDs: importedIDs, scheduleIDs: [])
        _ = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-003", "profile-001"],
            mode: .replace
        )
        let legacyID = uuid(183)
        let legacyRow = SharedSetupV2AppleProfileState.Profile(
            profileID: legacyID,
            sourceBundleID: "profile-002",
            sourceProfile: try appleDocument().profiles[1],
            unsupportedSemanticIDs: []
        )
        var rawSidecar = try storedSidecar()
        rawSidecar.profiles.insert(legacyRow, at: 0)
        defaults.set(
            try JSONEncoder().encode(rawSidecar),
            forKey: SharedSetupV2ProfileTransaction.profileStateKey
        )
        defaults.set(
            try SharedSetupV2ProfileTransaction.encodeBlockedProfileIDs(
                [legacyID] + storedBlockedIDsUnwrapped()
            ),
            forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
        )
        let deletedID = importedIDs[1]
        seed(
            profiles: try storedProfiles().filter { $0.id != deletedID },
            active: importedIDs[0],
            schedules: []
        )

        XCTAssertTrue(try transaction.compactAfterProfileDeletion(profileID: deletedID))

        XCTAssertEqual(try storedSidecar().profiles.map(\.profileID), [importedIDs[0]])
        XCTAssertEqual(try storedBlockedIDs(), [importedIDs[0]])
    }

    func testCompactAfterProfileDeletionIsCleanNoOpForUnreferencedID() throws {
        let transaction = makeTransaction(profileIDs: [uuid(191)], scheduleIDs: [])
        _ = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-003"],
            mode: .replace
        )
        let before = fiveKeyState()

        XCTAssertFalse(try transaction.compactAfterProfileDeletion(profileID: uuid(999)))

        XCTAssertEqual(fiveKeyState(), before)
    }

    func testCompactAfterProfileDeletionVerificationFailureRestoresPriorBytesAndUndoStaysExact() throws {
        let importedIDs = [uuid(201), uuid(202)]
        let normal = makeTransaction(profileIDs: importedIDs, scheduleIDs: [])
        _ = try normal.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-003", "profile-001"],
            mode: .replace
        )
        let deletedID = importedIDs[1]
        seed(
            profiles: try storedProfiles().filter { $0.id != deletedID },
            active: importedIDs[0],
            schedules: []
        )
        let priorState = fiveKeyState()
        let priorUndoData = defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey)
        let failing = makeTransaction(
            profileIDs: [],
            scheduleIDs: [],
            verificationOverride: { false }
        )

        XCTAssertThrowsError(try failing.compactAfterProfileDeletion(profileID: deletedID)) { error in
            XCTAssertEqual(
                error as? SharedSetupV2TransactionError,
                .persistenceVerificationFailed
            )
        }

        XCTAssertEqual(
            fiveKeyState(),
            priorState,
            "failed verified compaction restores the exact prior bytes and absence"
        )
        XCTAssertEqual(
            defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey),
            priorUndoData
        )
    }

    func testCompactAfterProfileDeletionRefusesLiveProfileWithoutMutation() throws {
        let importedIDs = [uuid(211), uuid(212)]
        let transaction = makeTransaction(profileIDs: importedIDs, scheduleIDs: [])
        _ = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-003", "profile-001"],
            mode: .replace
        )
        let before = fiveKeyState()

        XCTAssertThrowsError(
            try transaction.compactAfterProfileDeletion(profileID: importedIDs[0])
        ) { error in
            guard case .invalidSelection = error as? SharedSetupV2TransactionError else {
                return XCTFail("Expected invalidSelection misuse refusal, got \(error)")
            }
        }

        XCTAssertEqual(fiveKeyState(), before)
    }

    func testCompactAfterProfileDeletionLeavesUndoSnapshotRestorableToExactPriorState() throws {
        // Undo honesty end-to-end: an Undo snapshot taken before a deletion
        // still contains the deleted profile's sidecar bytes, and undoing
        // restores that exact prior five-key state — the snapshot's truth —
        // even after compaction removed the same bytes from the live keys.
        let oldID = uuid(220)
        let oldSidecar = SharedSetupV2AppleProfileState(profiles: [
            .init(
                profileID: oldID,
                sourceBundleID: "profile-002",
                sourceProfile: try appleDocument().profiles[1],
                unsupportedSemanticIDs: []
            )
        ])
        seed(
            profiles: [ExportProfile(
                id: oldID,
                name: "Old",
                settings: nativeSnapshot(filename: "old-{date}"),
                target: .localIPhoneFolder
            )],
            active: oldID,
            schedules: [],
            sidecar: oldSidecar,
            blocked: [oldID]
        )
        let preImportState = fiveKeyState()
        let importedID = uuid(221)
        let transaction = makeTransaction(profileIDs: [importedID], scheduleIDs: [])
        _ = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-003"],
            mode: .add
        )
        XCTAssertTrue(transaction.canUndo)

        // Native deletion of the pre-existing profile, then compaction: its
        // sidecar row and blocked entry leave the live keys.
        seed(
            profiles: try storedProfiles().filter { $0.id != oldID },
            active: importedID,
            schedules: []
        )
        XCTAssertTrue(try transaction.compactAfterProfileDeletion(profileID: oldID))
        XCTAssertEqual(try storedSidecar().profiles.map(\.profileID), [importedID])
        XCTAssertEqual(try storedBlockedIDs(), [importedID])

        let undoResult = try transaction.undo()

        XCTAssertEqual(undoResult.restoredProfileIDs, [oldID])
        XCTAssertEqual(
            fiveKeyState(),
            preImportState,
            "undo restores the exact pre-import bytes, including the deleted profile's sidecar row"
        )
        XCTAssertFalse(transaction.canUndo)
    }

    func testGateRequiresTypedLocalConfirmationKeepsCloudBlockedAndFailsClosedOnCorruption() throws {
        var document = try appleDocument()
        document.profiles[3].destination = .init(kind: .cloud, apiEndpoint: nil)
        let plan = SharedSetupV2Mapper.preview(document, registry: fixtureRegistry())
        let importedIDs = [uuid(131), uuid(132), uuid(133), uuid(134)]
        let transaction = makeTransaction(
            profileIDs: importedIDs,
            scheduleIDs: [uuid(231), uuid(232), uuid(233)]
        )
        _ = try transaction.apply(
            plan,
            selectedBundleIDs: document.profiles.map(\.bundleID),
            mode: .replace
        )
        let gate = SharedSetupV2ExecutionGate(userDefaults: defaults)
        XCTAssertTrue(importedIDs.allSatisfy { gate.isExecutionBlocked(profileID: $0) })

        XCTAssertThrowsError(try gate.confirmRebind(
            profileID: importedIDs[0],
            confirmation: .apiEndpoint(endpointID: uuid(300), credentialsConfirmed: true)
        ))
        XCTAssertTrue(gate.isExecutionBlocked(profileID: importedIDs[0]))
        XCTAssertTrue(try gate.confirmRebind(
            profileID: importedIDs[0],
            confirmation: .deviceFolder(destinationID: uuid(301))
        ))
        XCTAssertFalse(gate.isExecutionBlocked(profileID: importedIDs[0]))

        XCTAssertThrowsError(try gate.confirmRebind(
            profileID: importedIDs[1],
            confirmation: .connectedMac(pairingConfirmed: false)
        ))
        XCTAssertTrue(try gate.confirmRebind(
            profileID: importedIDs[1],
            confirmation: .connectedMac(pairingConfirmed: true)
        ))

        XCTAssertThrowsError(try gate.confirmRebind(
            profileID: importedIDs[2],
            confirmation: .apiEndpoint(endpointID: uuid(302), credentialsConfirmed: false)
        ))
        XCTAssertTrue(try gate.confirmRebind(
            profileID: importedIDs[2],
            confirmation: .apiEndpoint(endpointID: uuid(302), credentialsConfirmed: true)
        ))

        XCTAssertThrowsError(try gate.confirmRebind(
            profileID: importedIDs[3],
            confirmation: .deviceFolder(destinationID: uuid(303))
        )) { error in
            XCTAssertEqual(error as? SharedSetupV2ExecutionGateError, .cloudUnsupported)
        }
        XCTAssertTrue(gate.isExecutionBlocked(profileID: importedIDs[3]))
        XCTAssertEqual(try storedBlockedIDs(), [importedIDs[3]])
        XCTAssertEqual(try storedSidecar().profiles.count, 4, "rebind never discards retained intent")

        defaults.set(
            Data("not-json".utf8),
            forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
        )
        XCTAssertTrue(gate.isExecutionBlocked(profileID: uuid(999)))
        XCTAssertThrowsError(try gate.requireExecutionAllowed(profileID: uuid(999)))
    }

    func testCoordinatorBlocksActivationAndDuplicationUntilExplicitFolderRebind() throws {
        let profileID = uuid(141)
        let transaction = makeTransaction(profileIDs: [profileID], scheduleIDs: [])
        _ = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-001"],
            mode: .replace
        )

        let liveSettings = AdvancedExportSettings(userDefaults: defaults)
        liveSettings.filenameFormat = "live-before-rebind-{date}"
        Self.retainedSettings.append(liveSettings)
        let dependencies = coordinatorDependencies(settings: liveSettings)
        let coordinator = dependencies.coordinator
        let gate = SharedSetupV2ExecutionGate(userDefaults: defaults)

        XCTAssertNil(coordinator.activeProfileName)
        XCTAssertFalse(coordinator.activate(profileID: profileID))
        XCTAssertEqual(liveSettings.filenameFormat, "live-before-rebind-{date}")
        XCTAssertEqual(coordinator.renameProfile(id: profileID, to: "Renamed Import"), "Renamed Import")
        XCTAssertNil(coordinator.duplicateProfile(id: profileID))
        XCTAssertTrue(gate.isExecutionBlocked(profileID: profileID))

        let destination = coordinator.destinationStore.upsertVault(
            name: "Imported",
            standardizedPath: "/Users/x/Imported",
            bookmarkData: Data("fake-bookmark-Imported".utf8)
        )
        try coordinator.confirmFolderRebind(
            profileID: profileID,
            destinationID: destination.id
        )

        XCTAssertFalse(gate.isExecutionBlocked(profileID: profileID))
        XCTAssertEqual(
            coordinator.profileStore.profile(id: profileID)?.folderVaultID,
            destination.id
        )
        XCTAssertEqual(coordinator.activeProfileName, "Renamed Import")
        XCTAssertEqual(
            liveSettings.filenameFormat,
            coordinator.profileStore.profile(id: profileID)?.settings.filenameFormat
        )
    }

    func testCoordinatorRollsBackAPIBindingWhenGateVerificationFails() throws {
        let profileID = uuid(151)
        let transaction = makeTransaction(profileIDs: [profileID], scheduleIDs: [])
        _ = try transaction.apply(
            try applePlan(),
            selectedBundleIDs: ["profile-003"],
            mode: .replace
        )

        let failingGate = SharedSetupV2ExecutionGate(
            userDefaults: defaults,
            verificationOverride: { false }
        )
        let dependencies = coordinatorDependencies(executionGate: failingGate)
        let coordinator = dependencies.coordinator
        let endpoint = coordinator.destinationStore.upsertAPIEndpoint(
            name: "Local",
            endpointURLString: "https://local.example.test/upload",
            bearerToken: "local-credential"
        )

        XCTAssertThrowsError(try coordinator.confirmAPIEndpointRebind(
            profileID: profileID,
            endpointID: endpoint.id,
            credentialsConfirmed: true
        )) { error in
            XCTAssertEqual(
                error as? SharedSetupV2ExecutionGateError,
                .persistenceVerificationFailed
            )
        }
        XCTAssertNil(coordinator.profileStore.profile(id: profileID)?.apiEndpointID)
        XCTAssertTrue(failingGate.isExecutionBlocked(profileID: profileID))
    }

    #if os(iOS)
    func testDirectProfileGateRejectsBlockedReferenceBeforeProducerWork() throws {
        let store = ExportProfileStore(userDefaults: defaults)
        let profile = store.add(
            name: "Direct Import",
            settings: nativeSnapshot(filename: "direct-{date}"),
            target: .connectedMac
        )
        defaults.set(
            try SharedSetupV2ProfileTransaction.encodeBlockedProfileIDs([profile.id]),
            forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey
        )
        let request = DirectExportRequest(
            jobID: uuid(401),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-09-01", end: "2026-09-01"),
            settingsPolicy: .profile,
            profileReference: DirectProfileReference(
                profileID: profile.id.uuidString,
                name: profile.name
            ),
            responseMode: .writeFiles,
            destination: DirectExportDestination(rootPath: "Health.md")
        )
        let gate = SharedSetupV2ExecutionGate(userDefaults: defaults)

        XCTAssertThrowsError(try IPhoneDirectFileExportProducer.enforceBlockedProfileGate(
            for: request,
            profileStore: store,
            isBlocked: gate.isExecutionBlocked
        )) { error in
            guard let producerError = error as? IPhoneDirectFileProducerError,
                  case .profileRequiresRebind = producerError else {
                return XCTFail("Expected profileRequiresRebind, got \(error)")
            }
        }
    }

    func testAppIntentBlockedProfileStopsBeforeDestinationOrExportWork() async throws {
        let store = ExportProfileStore(userDefaults: defaults)
        let profile = store.add(
            name: "Imported",
            settings: nativeSnapshot(filename: "imported-{date}"),
            target: .localIPhoneFolder
        )
        var events: [String] = []
        let dependencies = ExportIntentRunner.Dependencies(
            refreshPurchaseStatus: { events.append("purchase") },
            canExport: { true },
            trackExportBlockedByQuota: {},
            hasVaultAccess: {
                events.append("vault")
                return true
            },
            requiresVaultReselection: { false },
            refreshVaultAccess: { events.append("refresh") },
            withVaultAccess: { operation in await operation() },
            targetLabel: { "test" },
            makeSettings: { AdvancedExportSettings() },
            profileStore: store,
            isProfileExecutionBlocked: { $0 == profile.id },
            exportDatesBackground: { _, _ in
                events.append("export")
                return ExportOrchestrator.ExportResult(
                    successCount: 1,
                    totalCount: 1,
                    failedDateDetails: []
                )
            },
            recordResult: { _, _, _, _, _, _ in },
            recordExportUse: {},
            trackExportSucceeded: { _ in },
            updateScheduleLastExport: {},
            pendingExportStore: InMemoryPendingExportStore(),
            exportNotificationScheduler: InspectableExportNotificationScheduler(),
            now: Date.init,
            calendar: .current
        )

        let outcome = await ExportIntentRunner.run(
            dates: [Date()],
            profileName: "Imported",
            dependencies: dependencies
        )

        guard case .profileRequiresRebind = outcome else {
            return XCTFail("Expected blocked profile outcome, got \(outcome)")
        }
        XCTAssertEqual(events, [])
        XCTAssertEqual(
            ExportIntentRunner.dialog(for: outcome),
            SharedSetupV2ExecutionGate.blockedExecutionMessage
        )
    }
    #endif

    // MARK: - Helpers

    private func coordinatorDependencies(
        settings: AdvancedExportSettings? = nil,
        executionGate: SharedSetupV2ExecutionGate? = nil
    ) -> (
        coordinator: ExportProfileCoordinator,
        vaultManager: VaultManager,
        resolver: PathMappingBookmarkResolver
    ) {
        let keychain = FakeKeychainStore()
        let resolver = PathMappingBookmarkResolver()
        let vaultManager = VaultManager(
            defaults: SystemUserDefaults(defaults: defaults),
            bookmarkResolver: resolver,
            identityProbe: FakeVaultFolderIdentityProbe()
        )
        let resolvedSettings = settings ?? AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(resolvedSettings)
        let coordinator = ExportProfileCoordinator(
            profileStore: ExportProfileStore(userDefaults: defaults),
            destinationStore: ProfileDestinationStore(
                userDefaults: defaults,
                keychain: keychain
            ),
            scheduledEntryStore: ScheduledExportEntryStore(userDefaults: defaults),
            settings: resolvedSettings,
            vaultManager: vaultManager,
            apiExportSettings: APIExportSettings(
                userDefaults: defaults,
                keychain: keychain
            ),
            initialTarget: .localIPhoneFolder,
            sharedSetupV2ExecutionGate: executionGate
                ?? SharedSetupV2ExecutionGate(userDefaults: defaults)
        )
        Self.retainedInstances.append(coordinator)
        Self.retainedInstances.append(vaultManager)
        return (coordinator, vaultManager, resolver)
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
            makeProfileID: { profileIterator.next() ?? self.uuid(8_001) },
            makeScheduleID: { scheduleIterator.next() ?? self.uuid(8_002) },
            verificationOverride: verificationOverride
        )
    }

    private func applePlan() throws -> SharedSetupV2ImportPlan {
        SharedSetupV2Mapper.preview(try appleDocument(), registry: fixtureRegistry())
    }

    private func appleDocument() throws -> SharedSetupV2 {
        try fixtureDocument(named: "apple-shared-setup-v2.json")
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

    private func nativeSnapshot(filename: String) -> ExportSettingsSnapshot {
        let name = "SharedSetupV2ProfileTransactionTests.Settings.\(UUID().uuidString)"
        let settingsDefaults = UserDefaults(suiteName: name)!
        settingsDefaults.removePersistentDomain(forName: name)
        let settings = AdvancedExportSettings(userDefaults: settingsDefaults)
        settings.filenameFormat = filename
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

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
            from: XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.profileListKey))
        )
    }

    private func storedSchedules() throws -> [ScheduledExportEntry] {
        try JSONDecoder().decode(
            [ScheduledExportEntry].self,
            from: XCTUnwrap(defaults.data(forKey: SharedSetupV2ProfileTransaction.scheduledEntriesKey))
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

    private func storedBlockedIDsUnwrapped() -> [UUID] {
        (try? storedBlockedIDs()) ?? []
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
            SharedSetupV2ProfileTransaction.blockedProfileIDsKey
        ]
        return defaults.dictionaryRepresentation().filter { keys.contains($0.key) } as NSDictionary
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
        throw XCTSkip("Could not locate the Shared Setup v2 Apple fixture")
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
}
