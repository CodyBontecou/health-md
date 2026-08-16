import Foundation

/// Minimal async semaphore used to serialize local-folder profile runs.
///
/// Profile-bound folder destinations are adopted by writing persisted vault
/// state that a fresh `VaultManager()` resolves at run time, so two
/// local-folder profile runs must not overlap. Non-folder targets do not
/// pass through the gate and stay fully concurrent.
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int = 1) {
        self.permits = permits
    }

    func acquire() async {
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            permits += 1
        }
    }

    /// Runs `operation` while holding the single permit.
    func withPermit<T: Sendable>(_ operation: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }
}
