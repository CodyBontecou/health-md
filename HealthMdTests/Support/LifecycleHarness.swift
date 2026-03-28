//
//  LifecycleHarness.swift
//  HealthMdTests
//
//  Reusable lifecycle stress-test utilities for verifying object creation
//  stability, safe retention, and async cancellation cleanup.
//  Part of TODO-1ff7bb36 / E6 lifecycle stress epic (TODO-2b0cd43e).
//
//  CONTEXT: On macOS 26 / Swift 6, deallocating ObservableObject instances
//  triggers a runtime crash (malloc: pointer being freed was not allocated)
//  due to the reentrant-main-actor-deinit bug. Additionally, autoreleasepool
//  usage in the test host causes a malloc crash even for plain classes.
//
//  The harness provides safe lifecycle testing via:
//
//  1. assertCreationStability — creates and exercises objects repeatedly,
//     retaining them statically to avoid the deinit crash. Proves creation
//     and use are stable under repeated allocation.
//
//  2. retain(_:) — centralized static retention to prevent ObservableObject
//     deinit crashes, replacing scattered static vars across test files.
//

import XCTest

enum LifecycleHarness {

    /// Objects retained to prevent the macOS 26 / Swift 6 ObservableObject
    /// deinit crash during tests. Cleared only at process exit.
    private static var retainedObjects: [AnyObject] = []

    // MARK: - Creation stability (ObservableObject-safe)

    /// Creates `iterations` instances via `factory`, exercises each with `use`,
    /// and retains them statically to avoid the ObservableObject deinit crash.
    /// Verifies that repeated creation and use completes without crashing.
    static func assertCreationStability<T: AnyObject>(
        iterations: Int = 10,
        factory: () -> T,
        use: ((T) -> Void)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var lastInstance: T?
        for _ in 0..<iterations {
            let instance = factory()
            use?(instance)
            retainedObjects.append(instance)
            lastInstance = instance
        }
        XCTAssertNotNil(
            lastInstance,
            "Expected at least one instance to be created",
            file: file,
            line: line
        )
    }

    // MARK: - Static retention helper

    /// Retains an object statically to prevent the ObservableObject deinit crash.
    /// Returns the same object for inline use.
    @discardableResult
    static func retain<T: AnyObject>(_ object: T) -> T {
        retainedObjects.append(object)
        return object
    }

    /// Creates an object via `factory`, retains it statically, and returns it.
    /// Convenience for per-test factory patterns that need static retention.
    static func create<T: AnyObject>(
        _ factory: () -> T,
        configure: ((T) -> Void)? = nil
    ) -> T {
        let instance = factory()
        configure?(instance)
        retainedObjects.append(instance)
        return instance
    }

    /// Number of objects currently held in static retention.
    static var retainedCount: Int {
        retainedObjects.count
    }

    // MARK: - Run loop draining

    /// Drains the main run loop to allow pending main-actor-dispatched work
    /// to execute.
    static func drainMainRunLoop(cycles: Int = 2) {
        for _ in 0..<cycles {
            RunLoop.main.run(until: Date())
        }
    }

    // MARK: - Async cancellation

    /// Asserts that an async task can be cancelled cleanly without throwing
    /// non-cancellation errors.
    static func assertCancellationCleanup(
        operation: @escaping @Sendable () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let task = Task { try await operation() }
        await Task.yield()
        task.cancel()

        let result = await task.result
        switch result {
        case .success:
            break // Completed before cancel — acceptable
        case .failure(let error):
            if !(error is CancellationError) {
                XCTFail(
                    "Task threw non-cancellation error after cancel: \(error)",
                    file: file,
                    line: line
                )
            }
        }
    }
}
