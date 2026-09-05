#if os(iOS)
import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class SharedSetupV2CoordinatorIOTests: XCTestCase {
    func testBoundedExternalReaderAcceptsFourMiBAndStopsAtOneByteOverflowProbe() async throws {
        let directory = temporaryDirectory("SharedSetupV2BoundedReader")
        let exactURL = directory.appendingPathComponent("Exact.healthmdconfig")
        let overflowURL = directory.appendingPathComponent("Overflow.healthmdconfig")
        let exact = Data(repeating: 0x78, count: SharedSetupV2.maximumEncodedBytes)
        try exact.write(to: exactURL, options: .atomic)
        var overflow = exact
        overflow.append(0x79)
        try overflow.write(to: overflowURL, options: .atomic)

        let loaded = try await SharedSetupCoordinator.readBoundedFile(exactURL)
        XCTAssertEqual(loaded.count, SharedSetupV2.maximumEncodedBytes)
        XCTAssertEqual(loaded.first, 0x78)
        XCTAssertEqual(loaded.last, 0x78)

        do {
            _ = try await SharedSetupCoordinator.readBoundedFile(overflowURL)
            XCTFail("Expected the max + 1 overflow probe to reject the file")
        } catch {
            XCTAssertEqual(
                error as? SharedSetupV2Error,
                .oversized(maximumBytes: SharedSetupV2.maximumEncodedBytes)
            )
        }
    }

    func testVersionedLoadIsWriteFreeAndDefaultCoordinatorCannotApplyV2() throws {
        let defaults = isolatedDefaults()
        let data = try fixtureData("apple-shared-setup-v2.json")
        let decoded = try SharedSetupV2Codec.decode(data)
        let coordinator = makeCoordinator(
            defaults: defaults,
            registry: registry(for: decoded)
        )
        let before = defaults.dictionaryRepresentation() as NSDictionary

        try coordinator.load(data)

        guard case .v2(let preview) = coordinator.loadedPreview else {
            return XCTFail("Expected an explicit v2 loaded-preview model")
        }
        XCTAssertEqual(preview.document, decoded)
        XCTAssertEqual(preview.profiles.count, decoded.profiles.count)
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        XCTAssertFalse(coordinator.canApplyV2(selectedBundleIDs: ["profile-001"]))
        XCTAssertThrowsError(
            try coordinator.applyV2(
                selectedBundleIDs: ["profile-001"],
                mode: .add
            )
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .transactionUnavailable
            )
        }
        XCTAssertNil(coordinator.v2Result)

        XCTAssertThrowsError(try coordinator.load(try syntheticV1DocumentData())) { error in
            XCTAssertEqual(error as? SharedSetupV2Error, .unsupportedVersion)
        }
        // A rejected v1 document never replaces the loaded v2 preview, and
        // no v1 preview case exists anymore.
        XCTAssertNotNil(coordinator.v2Preview)
    }

    func testCoordinatorPassesExplicitSelectionAndAddReplaceToAdapterAndUsesOneShotUndo() throws {
        let data = try fixtureData("apple-shared-setup-v2.json")
        let document = try SharedSetupV2Codec.decode(data)
        var calls: [([String], SharedSetupV2CoordinatorApplyMode)] = []
        var undoCount = 0
        var undoAvailable = false
        let adapter = SharedSetupV2CoordinatorAdapter(
            apply: { _, selectedBundleIDs, mode in
                calls.append((selectedBundleIDs, mode))
                undoAvailable = true
                return SharedSetupV2CoordinatorResult(
                    appliedItems: ["Applied \(selectedBundleIDs.count) profiles"],
                    attentionItems: ["Rebind destinations locally"]
                )
            },
            undo: {
                undoCount += 1
                undoAvailable = false
                return SharedSetupV2CoordinatorResult(
                    appliedItems: ["Restored prior profiles"]
                )
            },
            canUndo: { undoAvailable }
        )
        let coordinator = makeCoordinator(
            defaults: isolatedDefaults(),
            registry: registry(for: document),
            adapter: adapter
        )
        try coordinator.load(data)

        XCTAssertFalse(coordinator.canApplyV2(selectedBundleIDs: []))
        XCTAssertFalse(coordinator.canApplyV2(
            selectedBundleIDs: ["profile-001", "profile-001"]
        ))
        XCTAssertFalse(coordinator.canApplyV2(selectedBundleIDs: ["profile-999"]))
        XCTAssertTrue(coordinator.canApplyV2(
            selectedBundleIDs: ["profile-002", "profile-001"]
        ))

        let add = try coordinator.applyV2(
            selectedBundleIDs: ["profile-002", "profile-001"],
            mode: .add
        )
        XCTAssertEqual(add.appliedItems, ["Applied 2 profiles"])
        XCTAssertEqual(
            calls.first?.0,
            ["profile-002", "profile-001"],
            "The transaction adapter owns document-order normalization"
        )
        XCTAssertEqual(calls.first?.1, .add)
        XCTAssertTrue(coordinator.canUndoV2)
        XCTAssertEqual(try coordinator.undoV2().appliedItems, ["Restored prior profiles"])
        XCTAssertFalse(coordinator.canUndoV2)
        XCTAssertThrowsError(try coordinator.undoV2()) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .noUndoSnapshot
            )
        }

        let replace = try coordinator.applyV2(
            selectedBundleIDs: ["profile-004"],
            mode: .replace
        )
        XCTAssertEqual(replace.attentionItems, ["Rebind destinations locally"])
        XCTAssertEqual(calls.map(\.1), [.add, .replace])
        XCTAssertEqual(calls.last?.0, ["profile-004"])
        _ = try coordinator.undoV2()
        XCTAssertEqual(undoCount, 2)
    }

    func testInvalidV2PlanNeverEnablesOrInvokesApply() throws {
        let data = try fixtureData("apple-shared-setup-v2.json")
        let document = try SharedSetupV2Codec.decode(data)
        let exactRegistry = registry(for: document)
        var changedApple = exactRegistry.semanticToApple
        let changedSemanticID = try XCTUnwrap(document.metricAliases.first?.semanticID)
        changedApple[changedSemanticID] = "forged_selection"
        let mismatchedPinnedRegistry = SharedSetupMetricRegistry(
            version: exactRegistry.version,
            sha256: exactRegistry.sha256,
            semanticToApple: changedApple,
            semanticToAndroid: exactRegistry.semanticToAndroid,
            equivalence: exactRegistry.equivalence
        )
        var applyWasCalled = false
        let adapter = SharedSetupV2CoordinatorAdapter(
            apply: { _, _, _ in
                applyWasCalled = true
                return .init()
            },
            undo: { .init() },
            canUndo: { false }
        )
        let coordinator = makeCoordinator(
            defaults: isolatedDefaults(),
            registry: mismatchedPinnedRegistry,
            adapter: adapter
        )

        try coordinator.load(data)

        XCTAssertEqual(coordinator.v2Preview?.hasInvalidItems, true)
        XCTAssertFalse(coordinator.canApplyV2(selectedBundleIDs: ["profile-001"]))
        XCTAssertThrowsError(
            try coordinator.applyV2(
                selectedBundleIDs: ["profile-001"],
                mode: .replace
            )
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .invalidPreview
            )
        }
        XCTAssertFalse(applyWasCalled)
    }

    func testV2ExportContextCopiesInputsUsesMapperAndWritesValidatedAtomicArtifact() async throws {
        let fixtureDocument = try SharedSetupV2Codec.decode(
            fixtureData("apple-shared-setup-v2.json")
        )
        let registry = registry(for: fixtureDocument)
        let defaults = isolatedDefaults()
        let coordinator = makeCoordinator(defaults: defaults, registry: registry)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.metricSelection.enabledMetrics = ["steps"]
        let profileID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let endpointID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
        var profiles = [ExportProfile(
            id: profileID,
            name: "Original profile",
            settings: .from(settings),
            target: .apiEndpoint,
            apiEndpointID: endpointID
        )]
        var endpoints = [SavedAPIEndpoint(
            id: endpointID,
            name: "Private endpoint name",
            endpointURLString: "https://sender:password@Setup.Example.invalid:9443/import?tenant=secret#private"
        )]
        var vaults = [SavedVaultDestination(
            name: "Private vault name",
            standardizedPath: "/private/provider/path",
            bookmarkData: Data("private bookmark".utf8)
        )]
        var schedules = [ScheduledExportEntry(
            profileID: profileID,
            isEnabled: true,
            frequency: .weekly,
            customAnchorDate: fixedDate(year: 2026, month: 8, day: 17),
            preferredHour: 9,
            preferredMinute: 30,
            weekday: 2,
            lookbackDays: 7
        )]
        let androidDocument = try SharedSetupV2Codec.decode(
            fixtureData("android-shared-setup-v2.json")
        )
        let androidExtension = try XCTUnwrap(
            androidDocument.profiles.first?.platformExtensions.android
        )
        var preserved = [profileID: androidExtension]
        let context = SharedSetupV2ExportContext(
            profiles: profiles,
            activeProfileID: profileID,
            destinationVaults: vaults,
            destinationAPIEndpoints: endpoints,
            scheduledEntries: schedules,
            preservedAndroidExtensions: preserved
        )

        profiles[0].name = "Mutated after snapshot"
        endpoints[0].endpointURLString = "https://mutated.invalid/"
        vaults.removeAll()
        schedules.removeAll()
        preserved.removeAll()

        let encoded = try coordinator.exportV2Data(
            context: context,
            appVersion: "v2-coordinator-test",
            calendar: utcCalendar()
        )
        let exported = try SharedSetupVersionedCodec.decode(encoded)
        let exportedProfile = try XCTUnwrap(exported.profiles.first)
        let text = String(decoding: encoded, as: UTF8.self).lowercased()

        XCTAssertEqual(exportedProfile.name, "Original profile")
        XCTAssertEqual(exportedProfile.platformExtensions.android, androidExtension)
        XCTAssertEqual(exportedProfile.destination.kind, .apiEndpoint)
        XCTAssertEqual(
            exportedProfile.destination.apiEndpoint?.validatedURLString,
            "https://setup.example.invalid:9443/import"
        )
        XCTAssertNotNil(exportedProfile.schedule)
        XCTAssertEqual(encoded.last, 0x0A)
        for prohibited in [
            "sender", "password", "tenant=secret", "#private",
            "private endpoint name", "private vault name", "private/provider/path",
            "private bookmark", "mutated.invalid"
        ] {
            XCTAssertFalse(text.contains(prohibited), prohibited)
        }

        // The default production writer is v2 exclusively: schema_version 2,
        // canonical bytes identical to the explicit context API, and a
        // missing production context resolver fails closed instead of
        // falling back to any other writer.
        XCTAssertThrowsError(
            try coordinator.exportData(
                appVersion: "no-resolver",
                calendar: utcCalendar()
            )
        ) { error in
            XCTAssertEqual(
                error as? SharedSetupV2CoordinatorError,
                .v2ExportContextUnavailable
            )
        }
        let defaultWriterCoordinator = makeCoordinator(
            defaults: defaults,
            registry: registry,
            v2ExportContext: { context }
        )
        let defaultWriterData = try defaultWriterCoordinator.exportData(
            appVersion: "v2-coordinator-test",
            calendar: utcCalendar()
        )
        XCTAssertEqual(defaultWriterData, encoded)
        XCTAssertEqual(
            try SharedSetupV2Codec.decode(defaultWriterData).schemaVersion,
            2,
            "The default production writer must be v2"
        )

        var fileDocument = try SharedSetupDocument(data: encoded)
        XCTAssertEqual(try fileDocument.validatedContentsForWriting(), encoded)
        fileDocument.data.append(0x78)
        XCTAssertThrowsError(try fileDocument.validatedContentsForWriting())

        let artifactURL = try coordinator.makeV2ShareArtifact(
            context: context,
            appVersion: "v2-coordinator-test",
            calendar: utcCalendar()
        )
        let artifact = try await SharedSetupCoordinator.readBoundedFile(artifactURL)
        XCTAssertEqual(artifact, encoded)
        XCTAssertEqual(
            try SharedSetupVersionedCodec.decode(artifact).schemaVersion,
            2,
            "Expected a complete validated v2 share artifact"
        )
        coordinator.removeShareArtifact(artifactURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
    }

    func testNewestVersionedReadWinsAndCancellingOldReadCannotReplacePreview() async throws {
        let firstReadStarted = expectation(description: "first read started")
        let firstReadCancelled = expectation(description: "first read cancelled")
        let firstData = try fixtureData("apple-shared-setup-v2.json")
        let secondData = try fixtureData("android-shared-setup-v2.json")
        let secondDocument = try SharedSetupV2Codec.decode(secondData)
        let coordinator = SharedSetupCoordinator(
            registry: registry(for: secondDocument),
            externalFileReader: { url in
                if url.lastPathComponent == "First.healthmdconfig" {
                    firstReadStarted.fulfill()
                    return try await withTaskCancellationHandler {
                        try await Task.sleep(nanoseconds: 30_000_000_000)
                        return firstData
                    } onCancel: {
                        firstReadCancelled.fulfill()
                    }
                }
                return secondData
            }
        )
        let directory = temporaryDirectory("SharedSetupV2LatestRead")
        let firstURL = directory.appendingPathComponent("First.healthmdconfig")
        let secondURL = directory.appendingPathComponent("Second.healthmdconfig")

        coordinator.handleImportedURL(firstURL, source: .coldOpen)
        await fulfillment(of: [firstReadStarted], timeout: 2)
        coordinator.handleImportedURL(secondURL, source: .warmOpen)
        await fulfillment(of: [firstReadCancelled], timeout: 2)
        try await waitForV2Preview(coordinator)

        XCTAssertEqual(coordinator.v2Preview?.document.profiles.count, 2)
        XCTAssertEqual(coordinator.lastRouteSource, .warmOpen)
        XCTAssertTrue(coordinator.isFlowPresented)
    }

    private func makeCoordinator(
        defaults: UserDefaults,
        registry: SharedSetupMetricRegistry,
        adapter: SharedSetupV2CoordinatorAdapter? = nil,
        v2ExportContext: (@MainActor () -> SharedSetupV2ExportContext?)? = nil
    ) -> SharedSetupCoordinator {
        SharedSetupCoordinator(
            registry: registry,
            accessibilityAnnouncer: { _ in },
            v2Adapter: adapter,
            v2ExportContext: v2ExportContext
        )
    }

    private func registry(for document: SharedSetupV2) -> SharedSetupMetricRegistry {
        SharedSetupMetricRegistry(
            version: document.metricRegistry.registryVersion,
            sha256: document.metricRegistry.registrySHA256,
            semanticToApple: Dictionary(
                uniqueKeysWithValues: document.metricAliases.compactMap { alias in
                    alias.appleSelectionID.map { (alias.semanticID, $0) }
                }
            ),
            semanticToAndroid: Dictionary(
                uniqueKeysWithValues: document.metricAliases.compactMap { alias in
                    alias.androidSelectionID.map { (alias.semanticID, $0) }
                }
            ),
            equivalence: Dictionary(
                uniqueKeysWithValues: document.metricAliases.map { alias in
                    let equivalence: SharedSetupEquivalence
                    switch alias.equivalence {
                    case .platformExactOrUnavailable:
                        equivalence = .platformExactOrUnavailable
                    case .mappedAlias:
                        equivalence = .mappedAlias
                    case .platformDistinct:
                        equivalence = .platformDistinct
                    }
                    return (alias.semanticID, equivalence)
                }
            )
        )
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: repositoryFileURL(
            "packages/contracts/shared-setup/v2/fixtures/\(name)"
        ))
    }

    /// Minimal v1-shaped bytes synthesized inline: v1 must fail closed as
    /// unsupported without depending on any v1 fixture file.
    private func syntheticV1DocumentData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "schema": "healthmd.shared_setup",
                "schema_version": 1
            ],
            options: [.sortedKeys]
        )
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

    private func temporaryDirectory(_ prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
        try! FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "SharedSetupV2CoordinatorIOTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func fixedDate(year: Int, month: Int, day: Int) -> Date {
        utcCalendar().date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func waitForV2Preview(_ coordinator: SharedSetupCoordinator) async throws {
        for _ in 0..<100 {
            if coordinator.v2Preview != nil { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for the latest versioned preview")
    }
}
#endif
