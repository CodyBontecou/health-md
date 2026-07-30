#if os(iOS)
import XCTest
@testable import HealthMd

final class IPhoneConnectedCorpusProgressTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    func testFirstDayStartsAtZeroBeforeCapture() {
        let update = IPhoneConnectedCorpusProgressUpdate.preparing(
            itemIndex: 0,
            totalDays: 31,
            date: date,
            includesGranularData: false,
            transferredDays: 0
        )

        XCTAssertEqual(update.phase, .preparing)
        XCTAssertEqual(update.preparedDays, 0)
        XCTAssertEqual(update.transferredDays, 0)
        XCTAssertEqual(update.activeDayNumber, 1)
        XCTAssertEqual(update.presentationFraction(), 0)
        XCTAssertEqual(update.message, "Capturing HealthKit summary for day 1 of 31…")
    }

    func testFirstDayCountsOnlyAfterItemPreparation() {
        let update = IPhoneConnectedCorpusProgressUpdate.prepared(
            itemIndex: 0,
            totalDays: 31,
            date: date,
            includesGranularData: false,
            transferredDays: 0
        )

        XCTAssertEqual(update.phase, .prepared)
        XCTAssertEqual(update.preparedDays, 1)
        XCTAssertEqual(update.transferredDays, 0)
        XCTAssertEqual(update.presentationFraction(), 0.75 / 31, accuracy: 0.000_000_1)
        XCTAssertEqual(update.message, "Prepared HealthKit summary for day 1 of 31.")
    }

    func testWeightedFractionMathAndCountClamping() {
        XCTAssertEqual(
            IPhoneConnectedCorpusProgressUpdate.presentationFraction(
                preparedDays: 15,
                transferredDays: 5,
                totalDays: 20
            ),
            0.6,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(
            IPhoneConnectedCorpusProgressUpdate.presentationFraction(
                preparedDays: -4,
                transferredDays: -2,
                totalDays: 31
            ),
            0
        )
        XCTAssertEqual(
            IPhoneConnectedCorpusProgressUpdate.presentationFraction(
                preparedDays: 50,
                transferredDays: 40,
                totalDays: 20
            ),
            0.9,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(
            IPhoneConnectedCorpusProgressUpdate.presentationFraction(
                preparedDays: 1,
                transferredDays: 1,
                totalDays: 0
            ),
            0
        )
    }

    func testValidatedTransferAddsOnlyItsReservedContribution() {
        let fraction = IPhoneConnectedCorpusProgressUpdate.presentationFraction(
            preparedDays: 31,
            transferredDays: 1,
            totalDays: 31
        )

        XCTAssertEqual(fraction, 0.75 + (0.15 / 31), accuracy: 0.000_000_1)
    }

    func testFinalizationHasNinetyPercentFloorAndConsumerUseIsMonotonic() {
        XCTAssertEqual(
            IPhoneConnectedCorpusProgressUpdate.presentationFraction(
                preparedDays: 0,
                transferredDays: 0,
                totalDays: 31,
                isFinalizing: true
            ),
            0.9,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(
            IPhoneConnectedCorpusProgressUpdate.presentationFraction(
                preparedDays: 1,
                transferredDays: 0,
                totalDays: 31,
                previousFraction: 0.7
            ),
            0.7,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(
            IPhoneConnectedCorpusProgressUpdate.presentationFraction(
                preparedDays: 31,
                transferredDays: 31,
                totalDays: 31,
                isFinalizing: true,
                previousFraction: 0.95
            ),
            0.95,
            accuracy: 0.000_000_1
        )
    }

    func testStartedDayNeverCountsAsPreparedAndTransferTextIsPhaseSpecific() {
        let preparing = IPhoneConnectedCorpusProgressUpdate.preparing(
            itemIndex: 11,
            totalDays: 31,
            date: date,
            includesGranularData: true,
            transferredDays: 4
        )
        let prepared = IPhoneConnectedCorpusProgressUpdate.prepared(
            itemIndex: 11,
            totalDays: 31,
            date: date,
            includesGranularData: true,
            transferredDays: 4
        )
        let transferring = IPhoneConnectedCorpusProgressUpdate.transferring(
            preparedDays: 12,
            transferredDays: 5,
            totalDays: 31,
            date: date,
            dayNumber: 5
        )

        XCTAssertEqual(preparing.preparedDays, 11)
        XCTAssertEqual(prepared.preparedDays, 12)
        XCTAssertEqual(
            preparing.message,
            "Capturing lossless HealthKit records for day 12 of 31…"
        )
        XCTAssertEqual(
            prepared.message,
            "Prepared lossless HealthKit records for day 12 of 31."
        )
        XCTAssertEqual(
            transferring.message,
            "Transferring validated corpus data for day 5 of 31…"
        )
        XCTAssertFalse(transferring.message.localizedCaseInsensitiveContains("prepar"))
    }
}
#endif
