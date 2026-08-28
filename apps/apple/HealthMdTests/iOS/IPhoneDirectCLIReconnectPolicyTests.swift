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

    func testIdleHeartbeatProbesSilentChannelsAndDeclaresUnreachablePeers() {
        let policy = IPhoneDirectCLIIdleHeartbeatPolicy(
            pingIdleThreshold: .seconds(5),
            pongTimeout: .seconds(10)
        )
        let lastInboundAt = ContinuousClock().now

        XCTAssertEqual(
            policy.action(
                lastInboundAt: lastInboundAt,
                pingSentAt: nil,
                now: lastInboundAt.advanced(by: .seconds(1))
            ),
            .none,
            "recent inbound traffic needs no probe"
        )
        XCTAssertEqual(
            policy.action(
                lastInboundAt: lastInboundAt,
                pingSentAt: nil,
                now: lastInboundAt.advanced(by: .seconds(5))
            ),
            .sendPing,
            "an idle channel must be probed"
        )
        XCTAssertEqual(
            policy.action(
                lastInboundAt: lastInboundAt,
                pingSentAt: lastInboundAt.advanced(by: .seconds(5)),
                now: lastInboundAt.advanced(by: .seconds(10))
            ),
            .none,
            "a ping inside the pong window stays patient"
        )
        XCTAssertEqual(
            policy.action(
                lastInboundAt: lastInboundAt,
                pingSentAt: lastInboundAt.advanced(by: .seconds(5)),
                now: lastInboundAt.advanced(by: .seconds(16))
            ),
            .declareUnreachable,
            "an unanswered ping must fail the wedged channel"
        )
        XCTAssertEqual(
            policy.action(
                lastInboundAt: lastInboundAt,
                pingSentAt: nil,
                now: lastInboundAt.advanced(by: .seconds(-1))
            ),
            .none,
            "an invalid future activity instant must not synthesize a probe"
        )
    }

    func testProductionIdleHeartbeatRecoversBeforeCLICommandsGiveUp() {
        let policy = IPhoneDirectCLIIdleHeartbeatPolicy.production
        let lastInboundAt = ContinuousClock().now

        // Worst case: idle threshold fires, pong window expires, then the reconnect
        // loop redials. The whole cycle must stay well inside a short CLI command
        // timeout so a stuck channel self-heals without a manual disconnect.
        XCTAssertGreaterThan(
            policy.pingIdleThreshold,
            .seconds(10),
            "legacy status clients need their complete response window before an unsolicited ping"
        )
        XCTAssertLessThanOrEqual(
            policy.pingIdleThreshold + policy.pongTimeout,
            .seconds(18)
        )

        XCTAssertEqual(
            policy.action(
                lastInboundAt: lastInboundAt,
                pingSentAt: nil,
                now: lastInboundAt.advanced(by: policy.pingIdleThreshold)
            ),
            .sendPing
        )
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
