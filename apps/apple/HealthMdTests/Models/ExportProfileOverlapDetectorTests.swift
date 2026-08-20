import XCTest
@testable import HealthMd

final class ExportProfileOverlapDetectorTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested
    // observation state that is unsafe during test teardown on some macOS
    // runtimes. See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let calendar = Calendar.current

    override func setUp() {
        super.setUp()
        suiteName = "ExportProfileOverlapDetectorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func snapshot(
        filenameFormat: String = AdvancedExportSettings.defaultFilenameFormat,
        folderStructure: String = AdvancedExportSettings.defaultFolderStructure,
        formats: Set<ExportFormat> = [.markdown]
    ) -> ExportSettingsSnapshot {
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.filenameFormat = filenameFormat
        settings.folderStructure = folderStructure
        settings.exportFormats = formats
        Self.retainedSettings.append(settings)
        return ExportSettingsSnapshot.from(settings)
    }

    private func identity(
        name: String,
        target: ExportTargetSelection = .localIPhoneFolder,
        root: String?,
        snapshot: ExportSettingsSnapshot
    ) -> ExportProfileOverlapDetector.ProfilePathIdentity {
        ExportProfileOverlapDetector.ProfilePathIdentity(
            profileID: UUID(),
            name: name,
            target: target,
            settings: snapshot,
            destinationRootKey: root
        )
    }

    func testIdenticalSettingsAndRootOverlap() {
        let first = identity(name: "Alpha", root: "/vaults/health", snapshot: snapshot())
        let second = identity(name: "Beta", root: "/vaults/health", snapshot: snapshot())

        XCTAssertEqual(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ),
            ["Alpha"]
        )
        XCTAssertEqual(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: first.profileID,
                among: [first, second]
            ),
            ["Beta"]
        )
        XCTAssertTrue(ExportProfileOverlapDetector.hasAnyOverlap(among: [first, second]))
    }

    func testDifferentDestinationRootsDoNotOverlap() {
        let first = identity(name: "Alpha", root: "/vaults/health", snapshot: snapshot())
        let second = identity(name: "Beta", root: "/vaults/archive", snapshot: snapshot())

        XCTAssertTrue(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ).isEmpty
        )
    }

    func testRootComparisonIsCaseAndCompositionInsensitive() {
        let first = identity(name: "Alpha", root: "/Vaults/Health", snapshot: snapshot())
        let second = identity(
            name: "Beta",
            root: "/vaults/health".precomposedStringWithCompatibilityMapping,
            snapshot: snapshot()
        )

        XCTAssertEqual(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ),
            ["Alpha"]
        )
    }

    func testDifferentFilenameTemplatesDoNotOverlap() {
        let first = identity(
            name: "Alpha",
            root: "/vaults/health",
            snapshot: snapshot(filenameFormat: "{date}")
        )
        let second = identity(
            name: "Beta",
            root: "/vaults/health",
            snapshot: snapshot(filenameFormat: "health-{date}")
        )

        XCTAssertTrue(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ).isEmpty
        )
    }

    func testDateEquivalentTemplatesOverlap() {
        // "{year}-{month}-{day}" renders identically to "{date}" — a raw
        // template comparison would miss this, but rendered sample dates
        // catch it on both sample dates.
        let first = identity(
            name: "Alpha",
            root: "/vaults/health",
            snapshot: snapshot(filenameFormat: "{date}")
        )
        let second = identity(
            name: "Beta",
            root: "/vaults/health",
            snapshot: snapshot(filenameFormat: "{year}-{month}-{day}")
        )

        XCTAssertEqual(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ),
            ["Alpha"]
        )
    }

    func testDifferentFolderStructuresDoNotOverlap() {
        let first = identity(
            name: "Alpha",
            root: "/vaults/health",
            snapshot: snapshot(folderStructure: "Daily")
        )
        let second = identity(
            name: "Beta",
            root: "/vaults/health",
            snapshot: snapshot(folderStructure: "Archive")
        )

        XCTAssertTrue(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ).isEmpty
        )
    }

    func testDisjointFormatSetsDoNotOverlap() {
        let first = identity(
            name: "Alpha",
            root: "/vaults/health",
            snapshot: snapshot(formats: [.markdown])
        )
        let second = identity(
            name: "Beta",
            root: "/vaults/health",
            snapshot: snapshot(formats: [.json])
        )

        XCTAssertTrue(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ).isEmpty
        )
    }

    func testAPIEndpointProfilesNeverParticipate() {
        let first = identity(name: "Alpha", target: .apiEndpoint, root: nil, snapshot: snapshot())
        let second = identity(name: "Beta", target: .apiEndpoint, root: nil, snapshot: snapshot())

        XCTAssertTrue(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ).isEmpty
        )
        XCTAssertFalse(ExportProfileOverlapDetector.hasAnyOverlap(among: [first, second]))
    }

    func testConnectedMacProfilesShareOneRoot() {
        let first = identity(
            name: "Alpha",
            target: .connectedMac,
            root: ExportProfileOverlapDetector.connectedMacRootKey,
            snapshot: snapshot()
        )
        let second = identity(
            name: "Beta",
            target: .connectedMac,
            root: ExportProfileOverlapDetector.connectedMacRootKey,
            snapshot: snapshot()
        )

        XCTAssertEqual(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ),
            ["Alpha"]
        )
    }

    func testMixedTargetsNeverOverlap() {
        let local = identity(
            name: "Alpha",
            target: .localIPhoneFolder,
            root: "/vaults/health",
            snapshot: snapshot()
        )
        let mac = identity(
            name: "Beta",
            target: .connectedMac,
            root: ExportProfileOverlapDetector.connectedMacRootKey,
            snapshot: snapshot()
        )

        XCTAssertTrue(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: mac.profileID,
                among: [local, mac]
            ).isEmpty
        )
    }

    func testNilRootNeverReportsOverlap() {
        // No vault selected yet: the coordinator passes the live root, which
        // is nil until a folder is chosen. Without a destination there is
        // nothing meaningful to warn about.
        let first = identity(name: "Alpha", root: nil, snapshot: snapshot())
        let second = identity(name: "Beta", root: nil, snapshot: snapshot())

        XCTAssertTrue(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: second.profileID,
                among: [first, second]
            ).isEmpty
        )
    }

    func testSortedPresentationOrder() {
        let subject = identity(name: "Subject", root: "/vaults/health", snapshot: snapshot())
        let zulu = identity(name: "Zulu", root: "/vaults/health", snapshot: snapshot())
        let alpha = identity(name: "alpha", root: "/vaults/health", snapshot: snapshot())
        let mid = identity(name: "Middle", root: "/vaults/health", snapshot: snapshot())

        XCTAssertEqual(
            ExportProfileOverlapDetector.overlappingProfileNames(
                for: subject.profileID,
                among: [subject, zulu, alpha, mid]
            ),
            ["alpha", "Middle", "Zulu"]
        )
    }
}
