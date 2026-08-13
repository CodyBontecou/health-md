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

    func testStreamedWriterIsByteExactWithLegacyWriter() async throws {
        let canonical = """
        {
          "date" : "2026-01-01",
          "schema" : "healthmd.health_data",
          "schema_version" : 8,
          "text" : "héalth / 🫀",
          "time_context" : {
            "calendar_timezone" : "America/New_York",
            "timestamp_timezone" : "UTC"
          },
          "type" : "health-data",
          "url" : "https:\\/\\/health.md\\/a"
        }
        """
        let day = CanonicalRawDayResult(
            date: "2026-01-01",
            status: .complete,
            captureStatus: .complete,
            sampleCount: 1,
            recordCount: 1,
            queryStatusCounts: .init(),
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            failureCode: nil,
            canonicalDailyJSON: canonical
        )
        let metadataOnly = CanonicalRawDayResult(
            date: day.date,
            status: day.status,
            captureStatus: day.captureStatus,
            sampleCount: day.sampleCount,
            recordCount: day.recordCount,
            queryStatusCounts: day.queryStatusCounts,
            integrityWarningCount: day.integrityWarningCount,
            integrityWarningCodes: day.integrityWarningCodes,
            partialFailureCount: day.partialFailureCount,
            partialFailureTypes: day.partialFailureTypes,
            failureCode: day.failureCode,
            canonicalDailyJSON: nil
        )
        let dayFile = try makeDayFile(day)
        let canonicalURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "canonical-daily-stream-test"
        )
        try Data(canonical.utf8).write(to: canonicalURL)
        let canonicalFile = try ConnectedTransferFile.inspect(canonicalURL)
        defer {
            try? FileManager.default.removeItem(at: dayFile)
            canonicalFile.remove()
        }
        let selection = CanonicalHealthDataSelection(
            metricIDs: ["steps"],
            detailLevel: .summary
        )
        let createdAt = Date(timeIntervalSince1970: 0)
        let legacy = try await CanonicalRawResultSpoolWriter.write(
            profile: .healthDataProjection,
            canonicalSelection: selection,
            createdAt: createdAt,
            sourceDeviceName: "Test iPhone / 🫀",
            expectedDates: [day.date],
            dayFiles: [dayFile]
        )
        defer { legacy.remove() }
        let streamed = try await CanonicalRawResultSpoolWriter.writeStreamed(
            profile: .healthDataProjection,
            canonicalSelection: selection,
            createdAt: createdAt,
            sourceDeviceName: "Test iPhone / 🫀",
            expectedDates: [day.date],
            daySources: [CanonicalRawStoredDaySource(
                day: metadataOnly,
                canonicalJSONFile: canonicalFile
            )]
        )
        defer { streamed.remove() }

        XCTAssertEqual(try Data(contentsOf: streamed.file.url), try Data(contentsOf: legacy.file.url))
        XCTAssertEqual(streamed.file.sha256, legacy.file.sha256)
        XCTAssertEqual(streamed.captureSummary, legacy.captureSummary)
    }

    func testSummaryStreamRejectsUnexpectedLosslessArchive() throws {
        let sourceURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "summary-with-archive-test"
        )
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let canonical = """
        {
          "healthkit_record_archive": {
            "schema": "\(HealthKitRecordArchive.canonicalSchemaIdentifier)",
            "schema_version": \(HealthKitRecordArchive.currentRecordSchemaVersion)
          },
          "schema": "\(HealthMdExportSchema.identifier)",
          "schema_version": \(HealthMdExportSchema.version)
        }
        """
        try Data(canonical.utf8).write(to: sourceURL)
        XCTAssertThrowsError(try CanonicalDailyJSONStream.compactValidated(
            sourceURL: sourceURL,
            expectsLosslessArchive: false
        )) { error in
            XCTAssertEqual(
                error as? CanonicalDailyJSONStream.StreamError,
                .archiveSchemaMismatch
            )
        }
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
