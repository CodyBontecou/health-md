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
}
