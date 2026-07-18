import Foundation
import XCTest
@testable import HealthMd

final class CanonicalRawResultSpoolWriterTests: XCTestCase {
    func testWriterComposesStrictResultFromDailySpoolsIncrementally() async throws {
        let dayFiles = try [
            makeDayFile(.failed(date: "2026-01-01", code: "healthkit_error")),
            makeDayFile(.missing(date: "2026-01-02"))
        ]
        defer { dayFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        let spool = try await CanonicalRawResultSpoolWriter.write(
            createdAt: Date(timeIntervalSince1970: 0),
            sourceDeviceName: "Test iPhone",
            expectedDates: ["2026-01-01", "2026-01-02"],
            dayFiles: dayFiles
        )
        defer { spool.remove() }

        XCTAssertEqual(spool.totalRequestedDays, 2)
        XCTAssertEqual(spool.captureSummary.failedDayCount, 1)
        XCTAssertEqual(spool.captureSummary.missingDayCount, 1)
        XCTAssertEqual(spool.missingDates, ["2026-01-02"])
        XCTAssertTrue(spool.hasPartialResult)
        XCTAssertEqual(try ConnectedTransferFile.inspect(spool.file.url).sha256, spool.file.sha256)

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: spool.file.url)) as? [String: Any]
        )
        XCTAssertEqual(object["schema"] as? String, CanonicalRawResultEnvelope.schemaIdentifier)
        XCTAssertEqual(object["total_requested_days"] as? Int, 2)
        XCTAssertEqual((object["days"] as? [[String: Any]])?.count, 2)
    }

    func testWriterRejectsMissingDailySpool() async throws {
        do {
            _ = try await CanonicalRawResultSpoolWriter.write(
                createdAt: Date(),
                sourceDeviceName: "Test iPhone",
                expectedDates: ["2026-01-01"],
                dayFiles: []
            )
            XCTFail("Expected missing day rejection")
        } catch {
            XCTAssertEqual(error as? CanonicalRawResultSpoolWriter.WriterError, .dayCountMismatch)
        }
    }

    func testAccumulatorMatchesArraySummary() {
        let days: [CanonicalRawDayResult] = [
            .failed(date: "2026-01-01", code: "healthkit_error"),
            .cancelled(date: "2026-01-02"),
            .missing(date: "2026-01-03")
        ]
        var accumulator = CanonicalRawCaptureAccumulator()
        days.forEach { accumulator.append($0) }
        XCTAssertEqual(accumulator.summary, CanonicalRawCaptureSummary(days: days))
    }

    private func makeDayFile(_ day: CanonicalRawDayResult) throws -> URL {
        let url = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "raw-day-test")
        do {
            try JSONEncoder().encode(day).write(to: url)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
