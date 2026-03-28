//
//  LifecycleTracker.swift
//  Health.md
//
//  DEBUG-only lifecycle tracking for ObservableObject instances.
//  Tracks creation and deinit counts so tests can assert teardown behavior.
//  Part of TODO-32c61b8b / E6 lifecycle stress epic (TODO-2b0cd43e).
//
//  Usage in model classes:
//    init() { ... LifecycleTracker.trackCreation(of: "ClassName") }
//    deinit { LifecycleTracker.trackDeinit(of: "ClassName") }
//
//  Usage in tests:
//    LifecycleTracker.reset()
//    let obj = SomeClass()
//    XCTAssertEqual(LifecycleTracker.creationCount(for: "SomeClass"), 1)
//

#if DEBUG
import Foundation

enum LifecycleTracker {
    private static let lock = NSLock()
    private static var _creationCounts: [String: Int] = [:]
    private static var _deinitCounts: [String: Int] = [:]

    static func trackCreation(of type: String) {
        lock.withLock { _creationCounts[type, default: 0] += 1 }
    }

    static func trackDeinit(of type: String) {
        lock.withLock { _deinitCounts[type, default: 0] += 1 }
    }

    static func creationCount(for type: String) -> Int {
        lock.withLock { _creationCounts[type, default: 0] }
    }

    static func deinitCount(for type: String) -> Int {
        lock.withLock { _deinitCounts[type, default: 0] }
    }

    static func reset() {
        lock.withLock {
            _creationCounts.removeAll()
            _deinitCounts.removeAll()
        }
    }
}
#endif
