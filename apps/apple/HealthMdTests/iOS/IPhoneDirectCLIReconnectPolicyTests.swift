#if os(iOS)
import HealthMdConnectionCore
import XCTest
@testable import HealthMd

final class IPhoneDirectCLIReconnectPolicyTests: XCTestCase {
    func testScannedPairingLinkConnectsWithoutASecondApprovalWhenActive() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let now = receivedAt.addingTimeInterval(1)
        XCTAssertEqual(
            IPhoneDirectCLIPairingHandoffPolicy.action(
                appIsActive: true,
                hasActiveOperation: false,
                receivedAt: receivedAt,
                now: now
            ),
            .connect
        )
        XCTAssertEqual(
            IPhoneDirectCLIPairingHandoffPolicy.action(
                appIsActive: false,
                hasActiveOperation: false,
                receivedAt: receivedAt,
                now: now
            ),
            .deferUntilActive
        )
        XCTAssertEqual(
            IPhoneDirectCLIPairingHandoffPolicy.action(
                appIsActive: true,
                hasActiveOperation: true,
                receivedAt: receivedAt,
                now: now
            ),
            .waitForActiveOperation
        )
    }

    func testScannedPairingLinkExpiresBeforeDeferredOrRetriedConnection() {
        let receivedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertEqual(
            IPhoneDirectCLIPairingHandoffPolicy.action(
                appIsActive: true,
                hasActiveOperation: false,
                receivedAt: receivedAt,
                now: receivedAt.addingTimeInterval(
                    DirectPairingSecurity.pairingCodeLifetime
                )
            ),
            .expired
        )
    }

    func testInterruptedPairingRestoresSettingsUnlessNewTrustCommitted() {
        let previousID = UUID()
        let previousPairedAt = Date(timeIntervalSinceReferenceDate: 200)
        let snapshot = IPhoneDirectCLIService.PairingConfigurationSnapshot(
            host: "192.168.1.4",
            port: "17647",
            transport: DirectTransportKind.nearby.rawValue,
            enabled: false,
            previousTrustedMacInstallationID: previousID,
            previousTrustedMacPairedAt: previousPairedAt
        )
        let previousTrust = ManualIPTrustedMac(
            installationID: previousID,
            displayName: "previous CLI",
            host: "192.168.1.4",
            port: 17_647,
            reconnectSecret: Data(repeating: 0x2a, count: 32),
            pairedAt: previousPairedAt
        )
        let committedReplacement = ManualIPTrustedMac(
            installationID: previousID,
            displayName: "replacement CLI",
            host: "100.64.0.7",
            port: 17_647,
            reconnectSecret: Data(repeating: 0x3b, count: 32),
            pairedAt: previousPairedAt.addingTimeInterval(1)
        )

        XCTAssertTrue(snapshot.stillHasPreviousTrust(previousTrust))
        XCTAssertTrue(snapshot.stillHasPreviousTrust(nil))
        XCTAssertFalse(snapshot.stillHasPreviousTrust(committedReplacement))

        let firstPairingSnapshot = IPhoneDirectCLIService.PairingConfigurationSnapshot(
            host: nil,
            port: nil,
            transport: nil,
            enabled: nil,
            previousTrustedMacInstallationID: nil,
            previousTrustedMacPairedAt: nil
        )
        XCTAssertTrue(firstPairingSnapshot.stillHasPreviousTrust(nil))
        XCTAssertFalse(firstPairingSnapshot.stillHasPreviousTrust(committedReplacement))
    }

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
