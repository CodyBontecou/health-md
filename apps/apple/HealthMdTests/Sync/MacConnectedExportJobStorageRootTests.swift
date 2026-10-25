#if os(macOS)
import Foundation
import XCTest
@testable import HealthMd

final class MacConnectedExportJobStorageRootTests: XCTestCase {
    func testApplicationSupportFailureNeverSelectsTemporaryStorageAndRecoveryRetriesResolution() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let files = ContextStorageFileManager(temporaryURL: directory.appendingPathComponent("purgeable"))
        let root = MacConnectedExportJobStorageRoot(fileManager: files)

        XCTAssertThrowsError(try root.resolve())
        XCTAssertNil(root.url, "A failed resolver must not pin the purgeable fallback")
        XCTAssertThrowsError(try root.resolve())
        XCTAssertEqual(files.resolutionAttempts, 2)

        files.supportURL = directory.appendingPathComponent("stable")
        let expected = files.supportURL!.appendingPathComponent("Health.md/ConnectedExportJobs", isDirectory: true)
        XCTAssertEqual(try root.resolve(), expected)
        XCTAssertEqual(root.url, expected)
        XCTAssertEqual(files.resolutionAttempts, 3)
    }

    func testSuccessfulRootStaysPinnedAndColdRestartResolvesTheSameLocation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let support = directory.appendingPathComponent("stable")
        let files = ContextStorageFileManager(temporaryURL: directory.appendingPathComponent("purgeable"), supportURL: support)
        let root = MacConnectedExportJobStorageRoot(fileManager: files)
        let expected = support.appendingPathComponent("Health.md/ConnectedExportJobs", isDirectory: true)
        XCTAssertEqual(try root.resolve(), expected)
        files.supportURL = directory.appendingPathComponent("different")
        XCTAssertEqual(try root.resolve(), expected, "Never switch an admitted job's root")
        XCTAssertEqual(files.resolutionAttempts, 1)
        files.supportURL = support
        XCTAssertEqual(try MacConnectedExportJobStorageRoot(fileManager: files).resolve(), expected)
    }
}
#endif
