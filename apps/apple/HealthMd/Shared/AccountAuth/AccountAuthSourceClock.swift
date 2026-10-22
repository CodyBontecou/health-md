import Foundation

/// In-process observed-clock fence only, NOT a qualified OS/monotonic/network clock adapter.
/// Shared by the actor and actual synchronous vault commit so rollback between seams denies too.
nonisolated final class AccountAuthSourceClock: AccountAuthClock, @unchecked Sendable {
    private let lock = NSLock()
    private let source: any AccountAuthClock
    private var lastObserved: UInt64?
    init(source: any AccountAuthClock) { self.source = source } // Zero reads during construction.
    func seconds() throws -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        let time = try source.seconds()
        guard time <= AccountAuthWire.maximumSafeInteger - 300 else { throw AccountAuthSourceError.uncertain }
        if let lastObserved, time < lastObserved { throw AccountAuthSourceError.uncertain }
        lastObserved = time
        return time
    }
}
