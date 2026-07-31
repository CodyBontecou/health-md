#if os(macOS)
import Foundation
import XCTest
@testable import HealthMd

final class LegacyLocalAgentArtifactCleanupTests: XCTestCase {
    func testRemovesOnlyLegacyDirectoriesOnceWithoutCredentialAccess() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyLocalAgentArtifactCleanupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        for name in LegacyLocalAgentArtifactCleanup.legacyDirectoryNames {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("legacy".utf8).write(to: directory.appendingPathComponent("state.json"))
        }
        let retainedNames = ["EncryptedHealthContext", "ConnectedCorpus", "ProviderCredentials"]
        for name in retainedNames {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("retain".utf8).write(to: directory.appendingPathComponent("state"))
        }

        let suiteName = "LegacyLocalAgentArtifactCleanupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(LegacyLocalAgentArtifactCleanup.performIfNeeded(
            healthMdRoot: root,
            fileManager: .default,
            defaults: defaults
        ))
        XCTAssertTrue(defaults.bool(forKey: LegacyLocalAgentArtifactCleanup.migrationMarkerKey))
        for name in LegacyLocalAgentArtifactCleanup.legacyDirectoryNames {
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: root.appendingPathComponent(name).path
            ))
        }
        for name in retainedNames {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: root.appendingPathComponent(name).appendingPathComponent("state").path
            ))
        }

        let recreatedLegacyDirectory = root.appendingPathComponent(
            LegacyLocalAgentArtifactCleanup.legacyDirectoryNames[0],
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: recreatedLegacyDirectory,
            withIntermediateDirectories: true
        )
        XCTAssertTrue(LegacyLocalAgentArtifactCleanup.performIfNeeded(
            healthMdRoot: root,
            fileManager: .default,
            defaults: defaults
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recreatedLegacyDirectory.path))
    }
}
#endif
