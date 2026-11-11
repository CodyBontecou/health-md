import XCTest
@testable import HealthMd

final class ArchiveDayFilePreviewTests: XCTestCase {
    private func read(_ data: Data) throws -> ArchiveDayFile? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return ArchiveDayFile.read(fileURL: url, rootURL: nil)
    }

    func testByteLimitKeepsEveryCompleteUnicodeScalarAtEveryAlignment() throws {
        for scalar in ["é", "健", "🩺"] {
            let width = scalar.utf8.count
            for prefixSize in 0..<width {
                let prefix = String(repeating: "a", count: prefixSize)
                let text = prefix + String(repeating: scalar, count: ArchiveDayFile.maximumBytes / width + 5)
                let file = try XCTUnwrap(read(Data(text.utf8)), "\(scalar), prefix \(prefixSize)")
                let completeCount = (ArchiveDayFile.maximumBytes - prefixSize) / width
                XCTAssertEqual(file.source, prefix + String(repeating: scalar, count: completeCount))
                XCTAssertEqual(file.byteCount, text.utf8.count)
                XCTAssertTrue(file.isTruncated)
            }
        }
    }

    func testSmallUnicodeFileRemainsExact() throws {
        let source = "---\nname: 健康 🩺 é\n---\n"
        let file = try XCTUnwrap(read(Data(source.utf8)))
        XCTAssertEqual(file.source, source)
        XCTAssertFalse(file.isTruncated)
    }

    func testCorruptBytesAreNotSilentlyTrimmedOrReplaced() throws {
        XCTAssertNil(try read(Data([0xff])))
        XCTAssertNil(try read(Data([0xff]) + Data(repeating: 0x61, count: ArchiveDayFile.maximumBytes + 1)))
    }

    func testLineLimitWarningDoesNotDependOnFinalNewline() {
        for count in [400, 401] {
            for newline in ["", "\n"] {
                let source = Array(repeating: "value", count: count).joined(separator: "\n") + newline
                let file = ArchiveDayFile(fileURL: URL(fileURLWithPath: "/unused.md"), rootURL: nil,
                                          source: source, byteCount: source.utf8.count)
                XCTAssertEqual(file.lines.count, 400)
                XCTAssertEqual(file.isTruncated, count > 400)
            }
        }
    }

    func testEmptyFileHasNoPhantomLine() throws {
        let file = try XCTUnwrap(read(Data()))
        XCTAssertEqual(file.lines, [])
        XCTAssertFalse(file.isTruncated)
    }
}
