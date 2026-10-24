import Foundation
import XCTest
@testable import HealthMd

final class AppContainerStagingRootTests: XCTestCase {
    private func withRoots(_ body: (URL, URL, URL) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-staging-root-test-" + UUID().uuidString, isDirectory: true)
        let allowed = base.appendingPathComponent("allowed", isDirectory: true)
        let outside = base.appendingPathComponent("allowed-sibling", isDirectory: true)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try body(base, allowed, outside)
    }

    func testAcceptsUncreatedDescendantThroughRootAlias() throws {
        try withRoots { base, allowed, _ in
            let alias = base.appendingPathComponent("root-alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: allowed)
            let requested = alias.appendingPathComponent("run/generated", isDirectory: true)
            let result = try XCTUnwrap(AppContainerStagingRoot.validated(requested, allowedRoots: [allowed]))
            let expected = allowed.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent("run/generated", isDirectory: true)
            XCTAssertEqual(result.pathComponents, expected.pathComponents)
            XCTAssertTrue(result.hasDirectoryPath)
            XCTAssertFalse(FileManager.default.fileExists(atPath: requested.path), "Validation must not create staging directories")
        }
    }

    func testAcceptsCanonicalCandidateWithAliasedAllowedRoot() throws {
        try withRoots { base, allowed, _ in
            let alias = base.appendingPathComponent("root-alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: allowed)
            let requested = allowed.appendingPathComponent("generated", isDirectory: true)
            let result = try XCTUnwrap(AppContainerStagingRoot.validated(requested, allowedRoots: [alias]))
            let expected = allowed.resolvingSymlinksInPath().standardizedFileURL.appendingPathComponent("generated", isDirectory: true)
            XCTAssertEqual(result.pathComponents, expected.pathComponents)
        }
    }

    func testRejectsSymlinkEscapeWithoutWritingOutsideRoot() throws {
        try withRoots { _, allowed, outside in
            let escape = allowed.appendingPathComponent("escape", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
            XCTAssertNil(AppContainerStagingRoot.validated(escape.appendingPathComponent("generated"), allowedRoots: [allowed]))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        }
    }

    func testRejectsDanglingSymlinkWithoutCreatingItsTarget() throws {
        try withRoots { base, allowed, _ in
            let missing = base.appendingPathComponent("missing-target", isDirectory: true)
            let link = allowed.appendingPathComponent("dangling", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: missing)
            XCTAssertNil(AppContainerStagingRoot.validated(link.appendingPathComponent("generated"), allowedRoots: [allowed]))
            XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        }
    }

    func testRejectsSiblingWithMatchingStringPrefix() throws {
        try withRoots { _, allowed, outside in
            XCTAssertNil(AppContainerStagingRoot.validated(outside.appendingPathComponent("generated"), allowedRoots: [allowed]))
        }
    }

    func testRejectsParentTraversal() throws {
        try withRoots { _, allowed, _ in
            let requested = URL(fileURLWithPath: allowed.path + "/../allowed-sibling/generated")
            XCTAssertNil(AppContainerStagingRoot.validated(requested, allowedRoots: [allowed]))
        }
    }

    func testAcceptsTheAllowedRootItself() throws {
        try withRoots { _, allowed, _ in
            XCTAssertEqual(AppContainerStagingRoot.validated(allowed, allowedRoots: [allowed]), allowed.resolvingSymlinksInPath().standardizedFileURL)
        }
    }

    func testRejectsNonFileCandidateAndMissingRoots() throws {
        let remote = try XCTUnwrap(URL(string: "https://gateway.example.test/generated"))
        XCTAssertNil(AppContainerStagingRoot.validated(remote, allowedRoots: [remote]))
        XCTAssertNil(AppContainerStagingRoot.validated(FileManager.default.temporaryDirectory, allowedRoots: []))
    }
}
