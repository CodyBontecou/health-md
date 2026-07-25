import Foundation
import MultipeerConnectivity

/// Pure state-machine logic extracted from SyncService for testability.
/// All methods are static and side-effect free.
enum SyncStateMachine {

    /// Resource transfer threshold — payloads larger than this use file-based transfer.
    static let resourceTransferThreshold = 100_000

    /// Compute the new state and peer name from an MCSession state change.
    /// Returns (newConnectionState, newPeerName, shouldClearError).
    static func transition(
        for sessionState: MCSessionState,
        peerName: String
    ) -> (state: SyncConnectionState, peerName: String?, clearError: Bool) {
        switch sessionState {
        case .notConnected:
            return (.disconnected, nil, false)
        case .connecting:
            return (.connecting, nil, false)
        case .connected:
            return (.connected, peerName, true)
        @unknown default:
            return (.disconnected, nil, false)
        }
    }

    /// Returns true if a sync-in-progress should be stopped due to peer disconnection.
    static func shouldStopSyncing(newState: MCSessionState, isSyncing: Bool) -> Bool {
        newState == .notConnected && isSyncing
    }

    /// Returns true if the payload should use resource transfer instead of direct send.
    static func shouldUseResourceTransfer(for data: Data) -> Bool {
        data.count > resourceTransferThreshold
    }

    /// Attempt to decode a SyncMessage from raw data.
    /// Returns the message on success, or an error string on failure.
    static func decodeMessage(from data: Data) -> (message: SyncMessage?, error: String?) {
        do {
            let message = try JSONDecoder().decode(SyncMessage.self, from: data)
            return (message, nil)
        } catch {
            return (nil, "Decode error: \(error.localizedDescription)")
        }
    }
}
