import Foundation

/// Executes one physical HealthKit or WorkoutKit read. Debug builds attach the
/// read to the current export query session; Release builds compile directly to
/// the supplied operation with no recorder or logging implementation.
@inline(__always)
nonisolated func executeHealthKitQuery<T>(
    operation: String,
    typeIdentifier: String,
    _ query: () async throws -> T
) async rethrows -> T {
    #if DEBUG
    return try await ExportPerformanceInstrumentation.measureHealthKitQuery(
        operation: operation,
        typeIdentifier: typeIdentifier,
        query: query
    )
    #else
    return try await query()
    #endif
}

/// Synchronous counterpart for HealthKit characteristic reads.
@inline(__always)
nonisolated func executeSynchronousHealthKitQuery<T>(
    operation: String,
    typeIdentifier: String,
    _ query: () throws -> T
) rethrows -> T {
    #if DEBUG
    return try ExportPerformanceInstrumentation.measureSynchronousHealthKitQuery(
        operation: operation,
        typeIdentifier: typeIdentifier,
        query: query
    )
    #else
    return try query()
    #endif
}
