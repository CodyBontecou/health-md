import Foundation

/// One owned physical metadata operation, with an independently bounded logical
/// waiter. Cancellation/deadline releases the caller, NOT the SDK owner. A losing
/// unstructured task is retained/accounted until the actual provider returns.
/// Subsequent callers get explicit not-completed evidence without another RPC.
/// No TaskGroup timeout, SDK-stop promise, permission epoch, or late relabeling.
@MainActor
final class HealthHistoryAssessmentWorker {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<HealthHistoryAssessment, Never>
        let notCompleted: HealthHistoryAssessment
    }
    private let logicalDeadline: TimeInterval
    private var physicalID: UUID?
    private var physicalTask: Task<Void, Never>?
    private var waiter: Waiter?
    private var deadlineTask: Task<Void, Never>?

    init(logicalDeadline: TimeInterval = 5) {
        precondition(logicalDeadline.isFinite && logicalDeadline > 0 && logicalDeadline <= 60)
        self.logicalDeadline = logicalDeadline
    }

    var hasUnresolvedPhysicalOperation: Bool { physicalID != nil }

    func assess(notCompleted: HealthHistoryAssessment,
                operation: @escaping @MainActor () async -> HealthHistoryAssessment) async -> HealthHistoryAssessment {
        guard !Task.isCancelled, physicalID == nil else { return notCompleted }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: notCompleted); return }
                physicalID = id
                waiter = Waiter(id: id, continuation: continuation, notCompleted: notCompleted)
                // Retain the owner until actual completion, even if its logical
                // caller/lifecycle is released while the SDK ignores cancellation.
                physicalTask = Task { @MainActor [self] in
                    let result = await operation()
                    finishPhysical(id: id, result: result)
                }
                let delay = UInt64(logicalDeadline * 1_000_000_000)
                deadlineTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(nanoseconds: delay) } catch { return }
                    self?.finishLogical(id: id)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishLogical(id: id) }
        }
    }

    /// Lifecycle invalidation releases only the logical waiter. Physical ownership
    /// remains occupied, including an SDK await that ignores task cancellation.
    func cancelLogicalWaiter() {
        guard let id = waiter?.id else { return }
        finishLogical(id: id)
    }

    private func finishLogical(id: UUID) {
        guard let owned = waiter, owned.id == id else { return }
        waiter = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        physicalTask?.cancel()
        owned.continuation.resume(returning: owned.notCompleted)
    }

    private func finishPhysical(id: UUID, result: HealthHistoryAssessment) {
        guard physicalID == id else { return }
        physicalID = nil
        physicalTask = nil
        guard let owned = waiter, owned.id == id else { return }
        waiter = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        owned.continuation.resume(returning: result)
    }
}
