import Foundation
import MultipeerConnectivity

/// Ordered, side-effect-free candidate selection for nearby connections.
///
/// A browser can briefly report both a stale Bonjour record and the current
/// advertiser for the same device. Only one invitation may be active at a
/// time, so each distinct peer is tried once per round before any peer is
/// retried.
struct NearbyPeerAttemptPlanner<Peer: Equatable> {
    private(set) var discoveredPeers: [Peer] = []
    private(set) var attemptedPeers: [Peer] = []
    private(set) var pendingPeer: Peer?

    mutating func reset(clearDiscoveredPeers: Bool) {
        pendingPeer = nil
        attemptedPeers = []
        if clearDiscoveredPeers {
            discoveredPeers = []
        }
    }

    @discardableResult
    mutating func discover(_ peer: Peer) -> Bool {
        guard !discoveredPeers.contains(peer) else { return false }
        discoveredPeers.append(peer)
        return true
    }

    /// Selects the most recently discovered unattempted peer. Bonjour commonly
    /// delivers a cached stale record before the newly active advertiser.
    mutating func nextCandidate() -> Peer? {
        guard pendingPeer == nil,
              let peer = discoveredPeers.last(where: { !attemptedPeers.contains($0) }) else {
            return nil
        }
        pendingPeer = peer
        attemptedPeers.append(peer)
        return peer
    }

    /// Prioritizes a user-selected peer and returns an invitation that should be
    /// cancelled before starting the selected one.
    mutating func prioritize(_ peer: Peer) -> Peer? {
        let previous = pendingPeer == peer ? nil : pendingPeer
        if !discoveredPeers.contains(peer) {
            discoveredPeers.append(peer)
        }
        if !attemptedPeers.contains(peer) {
            attemptedPeers.append(peer)
        }
        pendingPeer = peer
        return previous
    }

    mutating func cancelPending() -> Peer? {
        defer { pendingPeer = nil }
        return pendingPeer
    }

    /// Records a failure only when it belongs to the current invitation. Late
    /// callbacks from an earlier invitation cannot displace a newer attempt.
    mutating func failPending(_ peer: Peer) -> Peer? {
        guard pendingPeer == peer else { return nil }
        pendingPeer = nil
        return nextCandidate()
    }

    /// Removes exactly one peer identity and advances if it was pending.
    mutating func lose(_ peer: Peer) -> Peer? {
        discoveredPeers.removeAll { $0 == peer }
        guard pendingPeer == peer else { return nil }
        pendingPeer = nil
        return nextCandidate()
    }

    mutating func connected(_ peer: Peer) {
        pendingPeer = nil
        attemptedPeers = []
        if !discoveredPeers.contains(peer) {
            discoveredPeers.append(peer)
        }
    }

    /// Prevents an unexpectedly disconnected active peer from immediately
    /// starving another already-discovered candidate.
    mutating func activePeerDisconnected(_ peer: Peer) -> Peer? {
        pendingPeer = nil
        if !attemptedPeers.contains(peer) {
            attemptedPeers.append(peer)
        }
        return nextCandidate()
    }

    mutating func beginNewRound() -> Peer? {
        pendingPeer = nil
        attemptedPeers = []
        return nextCandidate()
    }
}

/// Pure state-machine logic extracted from SyncService for testability.
/// All methods are static and side-effect free.
enum SyncStateMachine {
    /// Transport verification and application are separate phases. Preserve that
    /// distinction when surfacing a Mac export failure instead of labeling a
    /// destination/journal rejection as a payload decode problem.
    static func macExportFailureReason(
        for abortReason: ConnectedTransferAbortReason
    ) -> MacExportFailureReason {
        switch abortReason {
        case .cancelled:
            return .cancelled
        case .applicationRejected:
            return .exportWriteFailure
        default:
            return .payloadDecodeFailure
        }
    }


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
