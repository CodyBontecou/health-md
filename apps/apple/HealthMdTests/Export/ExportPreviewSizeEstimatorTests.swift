import XCTest
@testable import HealthMd

final class ExportPreviewSizeEstimatorTests: XCTestCase {
    func testUsesExactSampledDaysWhenEntireRangeWasAttempted() throws {
        let estimate = try XCTUnwrap(ExportPreviewSizeEstimator.estimate(
            totalDateCount: 2,
            attemptedDateCount: 2,
            samples: [
                ExportPreviewSizeSample(aggregateByteCount: 100),
                ExportPreviewSizeSample(aggregateByteCount: 300)
            ],
            renderedAggregateFormatCount: 1,
            selectedAggregateFormatCount: 1,
            fixedByteCount: 50
        ))

        XCTAssertEqual(estimate.byteCount, 450)
        XCTAssertEqual(estimate.projectedDataDayCount, 2)
        XCTAssertEqual(estimate.projectedProcessingDayCount, 2)
        XCTAssertFalse(estimate.isExtrapolated)
    }

    func testProjectsPopulatedDayDensityAcrossLargerRange() throws {
        let estimate = try XCTUnwrap(ExportPreviewSizeEstimator.estimate(
            totalDateCount: 100,
            attemptedDateCount: 10,
            samples: Array(repeating: ExportPreviewSizeSample(aggregateByteCount: 100), count: 5),
            renderedAggregateFormatCount: 1,
            selectedAggregateFormatCount: 1
        ))

        XCTAssertEqual(estimate.projectedDataDayCount, 50)
        XCTAssertEqual(estimate.byteCount, 5_000)
        XCTAssertTrue(estimate.isExtrapolated)
    }

    func testScalesRepresentativeFormatWithoutScalingSupplementalFiles() throws {
        let estimate = try XCTUnwrap(ExportPreviewSizeEstimator.estimate(
            totalDateCount: 10,
            attemptedDateCount: 1,
            samples: [ExportPreviewSizeSample(
                aggregateByteCount: 100,
                supplementalByteCount: 25
            )],
            renderedAggregateFormatCount: 1,
            selectedAggregateFormatCount: 3
        ))

        XCTAssertEqual(estimate.byteCount, 3_250)
        XCTAssertEqual(estimate.projectedDataDayCount, 10)
    }

    func testProjectsAverageRollupFileSizeAndAddsFixedBytes() throws {
        let estimate = try XCTUnwrap(ExportPreviewSizeEstimator.estimate(
            totalDateCount: 1,
            attemptedDateCount: 1,
            samples: [ExportPreviewSizeSample(aggregateByteCount: 0)],
            renderedAggregateFormatCount: 0,
            selectedAggregateFormatCount: 0,
            sampledRollupByteCount: 600,
            sampledRollupFileCount: 3,
            projectedRollupFileCount: 12,
            fixedByteCount: 100
        ))

        XCTAssertEqual(estimate.byteCount, 2_500)
        XCTAssertTrue(estimate.isExtrapolated)
    }

    func testRollupFloorAndExpandedProcessingScopeOverrideSparsePreview() throws {
        let estimate = try XCTUnwrap(ExportPreviewSizeEstimator.estimate(
            totalDateCount: 1,
            attemptedDateCount: 1,
            samples: [ExportPreviewSizeSample(aggregateByteCount: 0)],
            renderedAggregateFormatCount: 0,
            selectedAggregateFormatCount: 0,
            sampledRollupByteCount: 100,
            sampledRollupFileCount: 3,
            projectedRollupFileCount: 3,
            minimumProjectedRollupByteCount: 900_000,
            fixedByteCount: 222_000,
            projectedProcessingDayCount: 365
        ))

        XCTAssertEqual(estimate.byteCount, 1_122_000)
        XCTAssertEqual(estimate.projectedDataDayCount, 1)
        XCTAssertEqual(estimate.projectedProcessingDayCount, 365)
        XCTAssertTrue(estimate.isExtrapolated)
    }

    func testPreviewEstimateReportsCompressedArchiveOutput() throws {
        let loose = try XCTUnwrap(ExportPreviewSizeEstimator.estimate(
            totalDateCount: 1,
            attemptedDateCount: 1,
            samples: [ExportPreviewSizeSample(aggregateByteCount: 1_000)],
            renderedAggregateFormatCount: 1,
            selectedAggregateFormatCount: 1,
            fixedByteCount: 500
        ))
        let archive = try XCTUnwrap(ExportPreviewSizeEstimator.estimate(
            totalDateCount: 1,
            attemptedDateCount: 1,
            samples: [ExportPreviewSizeSample(aggregateByteCount: 1_000)],
            renderedAggregateFormatCount: 1,
            selectedAggregateFormatCount: 1,
            fixedByteCount: 500,
            archiveMode: true
        ))

        XCTAssertEqual(loose.byteCount, 1_500)
        XCTAssertEqual(archive.byteCount, 600)
    }

    func testReturnsNilWhenNoPopulatedDayWasSampled() {
        XCTAssertNil(ExportPreviewSizeEstimator.estimate(
            totalDateCount: 30,
            attemptedDateCount: 14,
            samples: [],
            renderedAggregateFormatCount: 1,
            selectedAggregateFormatCount: 1
        ))
    }

    func testFormatsLargeEstimatesReadably() {
        XCTAssertEqual(ExportPreviewSizeEstimate.sizeLabel(for: 512), "512 B")
        XCTAssertEqual(ExportPreviewSizeEstimate.sizeLabel(for: 1_536), "1.5 KB")
        XCTAssertEqual(ExportPreviewSizeEstimate.sizeLabel(for: 2 * 1_024 * 1_024), "2.0 MB")
        XCTAssertEqual(ExportPreviewSizeEstimate.sizeLabel(for: 3 * 1_024 * 1_024 * 1_024), "3.0 GB")
    }

    func testStatusEstimateUsesJSONPayloadForAPI() throws {
        let estimate = try XCTUnwrap(ExportStatusSizeEstimator.estimate(
            totalDateCount: 2,
            selectedFormats: [.markdown, .csv],
            enabledMetricCount: 10,
            includesLosslessRecords: false,
            includesIndividualEntries: false,
            updatesDailyNotes: false,
            dailyNotesOnly: false,
            summaryOnly: false,
            archiveMode: false,
            projectedRollupFileCount: 0,
            isAPIPayload: true
        ))

        XCTAssertEqual(estimate.byteCount, 14_800)
        XCTAssertEqual(estimate.projectedDataDayCount, 2)
        XCTAssertEqual(estimate.projectedProcessingDayCount, 2)
        XCTAssertTrue(estimate.isExtrapolated)
    }

    func testStatusEstimateUsesProjectedRollupAndExactDictionarySizes() throws {
        let estimate = try XCTUnwrap(ExportStatusSizeEstimator.estimate(
            totalDateCount: 1,
            selectedFormats: [.json],
            enabledMetricCount: 1,
            includesLosslessRecords: false,
            includesIndividualEntries: false,
            updatesDailyNotes: false,
            dailyNotesOnly: false,
            summaryOnly: true,
            archiveMode: false,
            projectedRollupFileCount: 3,
            projectedRollupByteCount: 900_000,
            fixedByteCount: 222_000,
            projectedProcessingDayCount: 365,
            isAPIPayload: false
        ))

        XCTAssertEqual(estimate.byteCount, 1_122_000)
        XCTAssertEqual(estimate.projectedProcessingDayCount, 365)
    }

    func testRollupProjectionUsesSelectedRangeAndFormatAwareCosts() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let rangeStart = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 1,
            day: 1
        )))
        let rangeEnd = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 12,
            day: 31
        )))
        let metricSelection = MetricSelectionState()
        metricSelection.enabledMetrics = [
            "vo2_max", "steps", "weight", "heart_rate_avg", "heart_rate_min",
            "heart_rate_max", "menstrual_flow", "sleep_bedtime", "sleep_total",
            "sleep_wake", "workouts"
        ]

        let selectedDates = (0..<365).compactMap {
            calendar.date(byAdding: .day, value: $0, to: rangeStart)
        }
        let json = ExportRollupOutputSizeEstimator.estimate(
            selectedDates: selectedDates,
            rollupsEnabled: true,
            formats: [.json],
            metricSelection: metricSelection,
            customization: FormatCustomization(),
            latestAllowedDate: rangeEnd,
            calendar: calendar
        )
        let markdown = ExportRollupOutputSizeEstimator.estimate(
            selectedDates: selectedDates,
            rollupsEnabled: true,
            formats: [.markdown],
            metricSelection: metricSelection,
            customization: FormatCustomization(),
            latestAllowedDate: rangeEnd,
            calendar: calendar
        )

        XCTAssertEqual(json.fileCount, 1)
        XCTAssertEqual(json.sourceDateCount, 365)
        XCTAssertGreaterThan(json.byteCount, 50_000)
        XCTAssertGreaterThan(markdown.byteCount, 20_000)
        XCTAssertGreaterThan(json.byteCount, markdown.byteCount)
    }

    func testCurrentDataDictionaryIsNotEstimatedAsLegacySixtyFourKilobytes() {
        XCTAssertGreaterThan(
            ExportDataDictionarySizeEstimator.byteCount(using: FormatCustomization()),
            64 * 1_024
        )
    }

    func testStatusEstimateAccountsForLosslessRecordVolume() throws {
        let aggregate = try XCTUnwrap(ExportStatusSizeEstimator.estimate(
            totalDateCount: 7,
            selectedFormats: [.json],
            enabledMetricCount: 20,
            includesLosslessRecords: false,
            includesIndividualEntries: false,
            updatesDailyNotes: false,
            dailyNotesOnly: false,
            summaryOnly: false,
            archiveMode: false,
            projectedRollupFileCount: 0,
            isAPIPayload: false
        ))
        let lossless = try XCTUnwrap(ExportStatusSizeEstimator.estimate(
            totalDateCount: 7,
            selectedFormats: [.json],
            enabledMetricCount: 20,
            includesLosslessRecords: true,
            includesIndividualEntries: false,
            updatesDailyNotes: false,
            dailyNotesOnly: false,
            summaryOnly: false,
            archiveMode: false,
            projectedRollupFileCount: 0,
            isAPIPayload: false
        ))

        XCTAssertGreaterThan(lossless.byteCount, aggregate.byteCount)
    }

    func testStatusEstimateAppliesTextArchiveCompressionProjection() throws {
        let loose = try XCTUnwrap(ExportStatusSizeEstimator.estimate(
            totalDateCount: 30,
            selectedFormats: [.markdown, .json],
            enabledMetricCount: 25,
            includesLosslessRecords: false,
            includesIndividualEntries: false,
            updatesDailyNotes: false,
            dailyNotesOnly: false,
            summaryOnly: false,
            archiveMode: false,
            projectedRollupFileCount: 0,
            isAPIPayload: false
        ))
        let archive = try XCTUnwrap(ExportStatusSizeEstimator.estimate(
            totalDateCount: 30,
            selectedFormats: [.markdown, .json],
            enabledMetricCount: 25,
            includesLosslessRecords: false,
            includesIndividualEntries: false,
            updatesDailyNotes: false,
            dailyNotesOnly: false,
            summaryOnly: false,
            archiveMode: true,
            projectedRollupFileCount: 0,
            isAPIPayload: false
        ))

        XCTAssertLessThan(archive.byteCount, loose.byteCount)
    }
}
