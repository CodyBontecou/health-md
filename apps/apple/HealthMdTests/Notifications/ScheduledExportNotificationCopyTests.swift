import XCTest
@testable import HealthMd

final class ScheduledExportNotificationCopyTests: XCTestCase {
    func testWriteFailuresNameProfileAndFolder() {
        for reason in [ExportFailureReason.noVaultSelected, .accessDenied, .fileWriteError] {
            XCTAssertEqual(
                ScheduledExportNotificationCopy.failureBody(profileName: "Daily", folderName: "Vault", reason: reason),
                "Daily couldn’t write — the Vault folder needs review."
            )
        }
        XCTAssertEqual(
            ScheduledExportNotificationCopy.failureBody(profileName: nil, folderName: nil, reason: .fileWriteError),
            "Scheduled export couldn’t write — the export folder needs review."
        )
    }

    func testEveryCauseClassProducesCopyWithoutDetails() {
        let reasons: [ExportFailureReason?] = [
            .noVaultSelected, .accessDenied, .noHealthData, .healthKitError, .deviceLocked,
            .fileWriteError, .backgroundTaskExpired, .apiEndpointNotConfigured, .apiUploadFailed, .unknown, nil
        ]
        for reason in reasons {
            let body = ScheduledExportNotificationCopy.failureBody(profileName: "Daily", folderName: "Vault", reason: reason)
            XCTAssertTrue(body.hasPrefix("Daily "), body)
            XCTAssertFalse(body.contains(":"), "No appended system detail: \(body)")
        }
    }
}
