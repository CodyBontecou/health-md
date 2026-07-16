import XCTest
@testable import healthmd

final class HealthMdCLITests: XCTestCase {
    func testRawParserRequestsStrictModeAndAllowPartial() throws {
        let parsed = try parse([
            "export", "--yesterday", "--raw", "--allow-partial", "--timeout", "120"
        ])
        guard case .export(let options) = parsed.command else {
            return XCTFail("Expected export command")
        }
        XCTAssertTrue(options.raw)
        XCTAssertTrue(options.allowPartial)
        XCTAssertEqual(options.timeout, 120)

        let body = makeExportRequestBody(
            options: options,
            startDate: "2026-07-14",
            endDate: "2026-07-14"
        )
        XCTAssertEqual(body["response_mode"] as? String, "raw_json")
        XCTAssertEqual(body["raw_profile"] as? String, "canonical_source_records_v1")
    }

    func testParserRejectsUnsafeOrNonFiniteTimeouts() {
        XCTAssertThrowsError(try parseExportOptions(["--yesterday", "--timeout", "4"]))
        XCTAssertThrowsError(try parseExportOptions(["--yesterday", "--timeout", "901"]))
        XCTAssertThrowsError(try parseExportOptions(["--yesterday", "--timeout", "nan"]))
        XCTAssertThrowsError(try parseExportOptions(["--yesterday", "--timeout", "inf"]))
    }

    func testRawPartialRequiresAllowPartialForExitZero() {
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: "partial_success", isRaw: true, allowPartial: false),
            1
        )
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: "partial_success", isRaw: true, allowPartial: true),
            0
        )
    }

    func testFilePartialRetainsLegacyExitBehavior() {
        XCTAssertEqual(
            exportExitCode(httpStatusCode: 200, status: "partial_success", isRaw: false, allowPartial: false),
            0
        )
        XCTAssertEqual(exportExitCode(httpStatusCode: 409, status: "failure", isRaw: true, allowPartial: true), 1)
    }
}
