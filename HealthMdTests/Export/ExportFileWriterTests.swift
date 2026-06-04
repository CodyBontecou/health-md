import XCTest
@testable import HealthMd
import ExportKit

private final class RecordingExportFileSystem: ExportFileSystem {
    var files: [String: String] = [:]
    var directories: Set<String> = []
    var atomicWrites: [String: Bool] = [:]

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil || directories.contains(url.path)
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func readString(at url: URL) throws -> String {
        guard let value = files[url.path] else {
            throw NSError(domain: "RecordingExportFileSystem", code: 1)
        }
        return value
    }

    func writeString(_ value: String, to url: URL, atomically: Bool) throws {
        files[url.path] = value
        atomicWrites[url.path] = atomically
    }
}

private struct MarkerMergeStrategy: ExportMergeStrategy {
    func merge(existing: String, new: String, file: PlannedExportFile) throws -> String {
        existing + "\nMERGED:\(file.relativePath)\n" + new
    }
}

final class ExportFileWriterTests: XCTestCase {
    func testWriterCreatesParentDirectoryAndWritesPlannedFileWithFakeFileSystem() throws {
        let fileSystem = RecordingExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(
            rootURL: URL(fileURLWithPath: "/tmp/Exports"),
            displayName: "Exports",
            baseRelativePath: "Base"
        )
        let plannedFile = PlannedExportFile(
            id: "daily-report",
            role: .aggregate(formatID: "plainText"),
            relativePath: "reports/day.txt",
            content: "hello"
        )

        let result = try writer.write(plannedFile, to: destination)

        let expectedParent = "/tmp/Exports/Base/reports"
        let expectedFile = "/tmp/Exports/Base/reports/day.txt"
        XCTAssertTrue(fileSystem.directories.contains(expectedParent))
        XCTAssertEqual(fileSystem.files[expectedFile], "hello")
        XCTAssertEqual(fileSystem.atomicWrites[expectedFile], true)
        XCTAssertEqual(result.fileID, "daily-report")
        XCTAssertEqual(result.relativePath, "reports/day.txt")
        XCTAssertEqual(result.url.path, expectedFile)
        XCTAssertEqual(result.bytesWritten, 5)
        XCTAssertTrue(result.createdParentDirectory)
        XCTAssertEqual(result.writeMode, .overwrite)
        XCTAssertEqual(result.action, .exported)
    }

    func testWriteModeOverwriteReplacesExistingContent() throws {
        let fileSystem = RecordingExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/Exports"))
        let existingPath = "/tmp/Exports/day.txt"
        fileSystem.files[existingPath] = "old"
        let plannedFile = PlannedExportFile(
            id: "day",
            role: .aggregate(formatID: "plainText"),
            relativePath: "day.txt",
            content: "new"
        )

        let result = try writer.write(plannedFile, to: destination, mode: .overwrite)

        XCTAssertEqual(fileSystem.files[existingPath], "new")
        XCTAssertEqual(result.writeMode, .overwrite)
        XCTAssertEqual(result.action, .exported)
        XCTAssertEqual(result.bytesWritten, 3)
    }

    func testWriteModeAppendAddsDoubleNewline() throws {
        let fileSystem = RecordingExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/Exports"))
        let existingPath = "/tmp/Exports/day.txt"
        fileSystem.files[existingPath] = "old"
        let plannedFile = PlannedExportFile(
            id: "day",
            role: .aggregate(formatID: "plainText"),
            relativePath: "day.txt",
            content: "new"
        )

        let result = try writer.write(plannedFile, to: destination, mode: .append)

        XCTAssertEqual(fileSystem.files[existingPath], "old\n\nnew")
        XCTAssertEqual(result.writeMode, .append)
        XCTAssertEqual(result.action, .appended)
    }

    func testWriteModeNoExistingFileWritesNewContentForAppend() throws {
        let fileSystem = RecordingExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/Exports"))
        let plannedFile = PlannedExportFile(
            id: "day",
            role: .aggregate(formatID: "plainText"),
            relativePath: "day.txt",
            content: "new"
        )

        let result = try writer.write(plannedFile, to: destination, mode: .append)

        XCTAssertEqual(fileSystem.files["/tmp/Exports/day.txt"], "new")
        XCTAssertEqual(result.action, .exported)
    }

    func testWriteModeUpdateUsesMergeStrategy() throws {
        let fileSystem = RecordingExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/Exports"))
        let existingPath = "/tmp/Exports/day.txt"
        fileSystem.files[existingPath] = "old"
        let plannedFile = PlannedExportFile(
            id: "day",
            role: .aggregate(formatID: "plainText"),
            relativePath: "day.txt",
            content: "new"
        )

        let result = try writer.write(
            plannedFile,
            to: destination,
            mode: .update,
            mergeStrategy: MarkerMergeStrategy()
        )

        XCTAssertEqual(fileSystem.files[existingPath], "old\nMERGED:day.txt\nnew")
        XCTAssertEqual(result.writeMode, .update)
        XCTAssertEqual(result.action, .updated)
    }

    func testWriteModeUpdateWithoutMergeStrategyFallsBackToOverwrite() throws {
        let fileSystem = RecordingExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/Exports"))
        let existingPath = "/tmp/Exports/data.json"
        fileSystem.files[existingPath] = "{\"old\":true}"
        let plannedFile = PlannedExportFile(
            id: "json",
            role: .aggregate(formatID: "json"),
            relativePath: "data.json",
            content: "{\"new\":true}"
        )

        let result = try writer.write(plannedFile, to: destination, mode: .update)

        XCTAssertEqual(fileSystem.files[existingPath], "{\"new\":true}")
        XCTAssertEqual(result.writeMode, .update)
        XCTAssertEqual(result.action, .exported)
    }

    func testMarkdownMergeStrategyPreservesUserSectionsAndFrontmatter() throws {
        let fileSystem = RecordingExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/Exports"))
        let existingPath = "/tmp/Exports/day.md"
        fileSystem.files[existingPath] = """
        ---
        date: 2026-03-15
        custom: keep-me
        ---
        # Old Title

        ## Sleep
        - Total: 6h

        ## Personal Notes
        This should stay.
        """
        let plannedFile = PlannedExportFile(
            id: "markdown",
            role: .aggregate(formatID: "markdown"),
            relativePath: "day.md",
            content: """
            ---
            date: 2026-03-15
            steps: 10000
            ---
            # New Title

            ## Sleep
            - Total: 8h
            """
        )

        let result = try writer.write(
            plannedFile,
            to: destination,
            mode: .update,
            mergeStrategy: MarkdownMergeStrategy()
        )
        let merged = try XCTUnwrap(fileSystem.files[existingPath])

        XCTAssertTrue(merged.contains("custom: keep-me"))
        XCTAssertTrue(merged.contains("steps: 10000"))
        XCTAssertTrue(merged.contains("# New Title"))
        XCTAssertTrue(merged.contains("Personal Notes"))
        XCTAssertTrue(merged.contains("This should stay."))
        XCTAssertTrue(merged.contains("Total: 8h"))
        XCTAssertFalse(merged.contains("Total: 6h"))
        XCTAssertEqual(result.action, .updated)
    }

    func testWriterUsesRealTemporaryDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExportFileWriterTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = ExportFileWriter(fileSystem: FileManagerExportFileSystem())
        let destination = ExportDestination(rootURL: tempDir, baseRelativePath: "Local")
        let plannedFile = PlannedExportFile(
            id: "real-file",
            role: .aggregate(formatID: "plainText"),
            relativePath: "nested/output.txt",
            content: "real content"
        )

        let result = try writer.write(plannedFile, to: destination)
        let written = try String(contentsOf: result.url, encoding: .utf8)

        XCTAssertEqual(written, "real content")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.url.deletingLastPathComponent().path))
        XCTAssertEqual(result.url.lastPathComponent, "output.txt")
    }

    func testWriterRejectsTraversalRelativePath() throws {
        let fileSystem = RecordingExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/Exports"))
        let plannedFile = PlannedExportFile(
            id: "unsafe",
            role: .aggregate(formatID: "plainText"),
            relativePath: "../outside.txt",
            content: "nope"
        )

        XCTAssertThrowsError(try writer.write(plannedFile, to: destination)) { error in
            XCTAssertTrue(error is ExportPathTemplateError)
        }
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testDestinationStoreRestoresAndRefreshesStaleBookmark() throws {
        let defaults = FakeUserDefaults()
        let resolver = FakeBookmarkResolver()
        let folderURL = URL(fileURLWithPath: "/tmp/SelectedFolder")
        defaults.storage["bookmark"] = Data("old".utf8)
        defaults.storage["base"] = "Exports"
        resolver.resolvedURL = folderURL
        resolver.resolvedIsStale = true
        resolver.createdBookmarkData = Data("new".utf8)

        let store = ExportDestinationBookmarkStore(
            storage: defaults,
            bookmarkAccess: resolver,
            keys: ExportDestinationStoreKeys(bookmarkKey: "bookmark", baseRelativePathKey: "base"),
            defaultBaseRelativePath: "Default"
        )

        let destination = try store.loadDestination()

        XCTAssertEqual(destination?.rootURL, folderURL)
        XCTAssertEqual(destination?.displayName, "SelectedFolder")
        XCTAssertEqual(destination?.baseRelativePath, "Exports")
        XCTAssertEqual(defaults.storage["bookmark"] as? Data, Data("new".utf8))
        XCTAssertEqual(resolver.startAccessCalls, [folderURL])
        XCTAssertEqual(resolver.stopAccessCalls, [folderURL])
    }

    func testSecurityScopedDestinationAccessDeniesWhenAccessCannotStart() {
        let resolver = FakeBookmarkResolver()
        resolver.accessGranted = false
        let access = SecurityScopedDestinationAccess(bookmarkAccess: resolver)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/Denied"))

        XCTAssertThrowsError(try access.withAccess(to: destination) {}) { error in
            XCTAssertEqual(error as? ExportDestinationAccessError, .accessDenied(destination.rootURL))
        }
        XCTAssertTrue(resolver.stopAccessCalls.isEmpty)
    }

    func testGenericDestinationWriterSourceDoesNotReferenceAppSpecificExportDomains() throws {
        let source = try exportKitSource(named: "ExportDestinationWriting.swift")
        for forbidden in ["HealthData", "HealthKit", "Obsidian", "Vault"] {
            XCTAssertFalse(source.contains(forbidden), "Generic destination/writer code must not reference \(forbidden)")
        }
    }

    private func exportKitSource(named filename: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory
                .appendingPathComponent("ExportKit")
                .appendingPathComponent("Sources")
                .appendingPathComponent("ExportKit")
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "ExportFileWriterTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate \(filename) from \(#filePath)."]
        )
    }
}
