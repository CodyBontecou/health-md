#if os(macOS)
import Foundation
import Testing
@testable import HealthMd

/// M-16: the Mac destination's System Status rows (receiver version, permissions, last check).
struct MacDestinationSystemStatusTests {
    private func status(
        paused: Bool = false,
        folderOK: Bool = true,
        active: Bool = false,
        connected: Bool = false
    ) -> MacDestinationSystemStatus {
        MacDestinationSystemStatus(
            appVersion: "4.0.0",
            receivingPaused: paused,
            folderAccessHealthy: folderOK,
            hasActiveExport: active,
            isConnected: connected
        )
    }

    @Test
    func receiverShowsTheVersionAndListeningState() {
        let listening = status()
        #expect(listening.receiverValue.contains("4.0.0"))
        #expect(listening.receiverValue.hasSuffix(String(localized: "Listening")))
        #expect(listening.receiverIsHealthy)

        let paused = status(paused: true)
        #expect(paused.receiverValue.hasSuffix(String(localized: "Paused")))
        #expect(!paused.receiverIsHealthy)
    }

    @Test
    func permissionsFollowFolderAccess() {
        #expect(status(folderOK: true).permissionsGranted)
        #expect(status(folderOK: true).permissionsValue.contains(String(localized: "Granted")))
        #expect(!status(folderOK: false).permissionsGranted)
        #expect(status(folderOK: false).permissionsValue.contains(String(localized: "Needs Access")))
    }

    @Test
    func lastCheckPrefersActiveExportThenConnectionThenPause() {
        #expect(status(active: true, connected: true).lastCheckValue == String(localized: "In Progress"))
        #expect(status(connected: true).lastCheckValue == String(localized: "Just Now"))
        #expect(status(paused: true).lastCheckValue == String(localized: "Paused"))
        #expect(status().lastCheckValue == String(localized: "Scanning"))
    }
}
#endif
