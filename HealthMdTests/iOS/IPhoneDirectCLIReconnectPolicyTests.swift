#if os(iOS)
import XCTest
@testable import HealthMd

final class IPhoneDirectCLIReconnectPolicyTests: XCTestCase {
    func testProductionRetriesStayInsideOneShotCLIListenerWindow() {
        let policy = IPhoneDirectCLIReconnectPolicy.production
        var delay = policy.initialRetryDelayNanoseconds
        var observed: [UInt64] = []

        for _ in 0..<6 {
            observed.append(delay)
            delay = policy.nextRetryDelay(after: delay)
        }

        XCTAssertEqual(observed, [
            250_000_000,
            500_000_000,
            1_000_000_000,
            2_000_000_000,
            2_000_000_000,
            2_000_000_000
        ])

        let worstCaseDiscoverySeconds = policy.manualConnectionTimeout
            + Double(policy.maximumRetryDelayNanoseconds) / 1_000_000_000
        XCTAssertLessThan(worstCaseDiscoverySeconds, 10)
    }

    func testRetryDelaySaturatesWithoutOverflow() {
        let policy = IPhoneDirectCLIReconnectPolicy(
            initialRetryDelayNanoseconds: 1,
            maximumRetryDelayNanoseconds: 2_000_000_000,
            connectedPollDelayNanoseconds: 1,
            manualConnectionTimeout: 1
        )

        XCTAssertEqual(
            policy.nextRetryDelay(after: UInt64.max),
            policy.maximumRetryDelayNanoseconds
        )
        XCTAssertEqual(
            policy.nextRetryDelay(after: policy.maximumRetryDelayNanoseconds),
            policy.maximumRetryDelayNanoseconds
        )
    }

    func testBackgroundContinuationRequiresConnectedActiveExport() {
        XCTAssertEqual(
            IPhoneDirectCLIBackgroundPolicy.action(
                hasActiveExport: true,
                hasLiveChannel: true
            ),
            .continueActiveExport
        )
        XCTAssertEqual(
            IPhoneDirectCLIBackgroundPolicy.action(
                hasActiveExport: false,
                hasLiveChannel: true
            ),
            .disconnect
        )
        XCTAssertEqual(
            IPhoneDirectCLIBackgroundPolicy.action(
                hasActiveExport: true,
                hasLiveChannel: false
            ),
            .disconnect
        )
    }

    func testBackgroundCancellationIsBoundToActiveExport() {
        let activeJobID = UUID()
        XCTAssertTrue(IPhoneDirectCLIBackgroundPolicy.allowsCancellation(
            requestedJobID: activeJobID,
            activeJobID: activeJobID,
            appIsActive: false
        ))
        XCTAssertFalse(IPhoneDirectCLIBackgroundPolicy.allowsCancellation(
            requestedJobID: UUID(),
            activeJobID: activeJobID,
            appIsActive: false
        ))
        XCTAssertTrue(IPhoneDirectCLIBackgroundPolicy.allowsCancellation(
            requestedJobID: UUID(),
            activeJobID: activeJobID,
            appIsActive: true
        ))
    }
}
#endif
