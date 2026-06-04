import XCTest
@testable import HealthMd
import ExportKit

final class ExportPreviewDisplayContentTests: XCTestCase {

    func testSmallContentRendersUnchanged() {
        let content = "{\"steps\":12500}"

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 128,
            headBytes: 96,
            tailBytes: 32
        )

        XCTAssertEqual(display.text, content)
        XCTAssertEqual(display.originalByteCount, content.utf8.count)
        XCTAssertEqual(display.omittedByteCount, 0)
        XCTAssertFalse(display.isTruncated)
    }

    func testEmptyContentUsesPlaceholder() {
        let display = ExportPreviewDisplayContent.make(from: "")

        XCTAssertEqual(display.text, "(empty file)")
        XCTAssertEqual(display.originalByteCount, 0)
        XCTAssertFalse(display.isTruncated)
    }

    func testLargeContentKeepsHeadAndTailWithTruncationMarker() {
        let content = String(repeating: "a", count: 1_000)
            + "CENTER_SENTINEL"
            + String(repeating: "z", count: 1_000)

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 24,
            headBytes: 10,
            tailBytes: 8
        )

        XCTAssertTrue(display.isTruncated)
        XCTAssertEqual(display.originalByteCount, content.utf8.count)
        XCTAssertTrue(display.text.hasPrefix(String(repeating: "a", count: 10)))
        XCTAssertTrue(display.text.hasSuffix(String(repeating: "z", count: 8)))
        XCTAssertTrue(display.text.contains("Preview truncated"))
        XCTAssertFalse(display.text.contains("CENTER_SENTINEL"))
        XCTAssertLessThan(display.text.utf8.count, content.utf8.count)
    }

    func testTruncationDoesNotSplitMultibyteCharacters() {
        let content = String(repeating: "é", count: 80)
            + "middle"
            + String(repeating: "🙂", count: 80)

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 32,
            headBytes: 9,
            tailBytes: 11
        )

        XCTAssertTrue(display.isTruncated)
        XCTAssertTrue(display.text.hasPrefix(String(repeating: "é", count: 4)))
        XCTAssertTrue(display.text.hasSuffix(String(repeating: "🙂", count: 2)))
        XCTAssertTrue(display.text.contains("Preview truncated"))
    }
}
