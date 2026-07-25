#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class ExportedMarkdownViewerTests: XCTestCase {
    func testMarkdownExtensionsUseInAppViewer() {
        XCTAssertEqual(
            ExportFilePreviewRoute.route(for: URL(fileURLWithPath: "/tmp/export.md")),
            .inAppMarkdown
        )
        XCTAssertEqual(
            ExportFilePreviewRoute.route(for: URL(fileURLWithPath: "/tmp/export.MD")),
            .inAppMarkdown
        )
        XCTAssertEqual(
            ExportFilePreviewRoute.route(for: URL(fileURLWithPath: "/tmp/export.markdown")),
            .inAppMarkdown
        )
    }

    func testNonMarkdownFilesContinueUsingQuickLook() {
        for path in ["export.zip", "export.json", "export.csv", "export.txt"] {
            XCTAssertEqual(
                ExportFilePreviewRoute.route(for: URL(fileURLWithPath: "/tmp/\(path)")),
                .quickLook
            )
        }
    }

    func testParserRecognizesHealthExportStructure() {
        let source = """
        ---
        schema_version: 7
        date: 2026-03-28
        ---

        # Health Data

        ## Activity

        - **Steps:** 12,500 steps
        1. First numbered item

        | Metric | Value |
        |---|---|
        | Steps | 12,500 |

        ```json
        {"steps": 12500}
        ```
        """

        let blocks = ExportedMarkdownParser.parse(source)

        XCTAssertEqual(blocks.first?.kind, .metadata)
        XCTAssertEqual(blocks.first?.text, "schema_version: 7\ndate: 2026-03-28")
        XCTAssertTrue(blocks.contains { $0.kind == .heading(level: 1) && $0.text == "Health Data" })
        XCTAssertTrue(blocks.contains { $0.kind == .heading(level: 2) && $0.text == "Activity" })
        XCTAssertTrue(blocks.contains { $0.kind == .bullet(level: 0) && $0.text == "**Steps:** 12,500 steps" })
        XCTAssertTrue(blocks.contains { $0.kind == .numbered(marker: "1.", level: 0) })
        XCTAssertTrue(blocks.contains { $0.kind == .table && $0.text.contains("12,500") })
        XCTAssertTrue(blocks.contains { $0.kind == .code(language: "json") && $0.text == "{\"steps\": 12500}" })
    }

    func testParserPreservesPlainParagraphText() {
        let blocks = ExportedMarkdownParser.parse("A first line\nthat continues.\n\nA second paragraph.")

        XCTAssertEqual(
            blocks,
            [
                ExportedMarkdownBlock(id: 0, kind: .paragraph, text: "A first line that continues."),
                ExportedMarkdownBlock(id: 1, kind: .paragraph, text: "A second paragraph.")
            ]
        )
    }
}
#endif
