import Foundation

/// One owner per preview/execution surface. Reentrant assessments cannot publish
/// an obsolete result even if a scope changes away and back while suspended.
@MainActor
final class HealthHistoryAssessmentCoordinator {
    private var revision = UUID()

    /// Shared phone-preview seam. The caller owns the worker across view tasks.
    func assessPreview(
        worker: HealthHistoryAssessmentWorker,
        notCompleted: HealthHistoryAssessment,
        scope: HealthHistoryScope,
        isCurrent: () -> Bool,
        operation: @escaping @MainActor () async -> HealthHistoryAssessment
    ) async -> HealthHistoryAssessment? {
        await assess(scope: scope, isCurrent: isCurrent) {
            // A new task can arrive before the old task's asynchronous
            // cancellation handler. Replace its logical waiter synchronously;
            // the physical owner is still retained until its provider returns.
            worker.cancelLogicalWaiter()
            return await worker.assess(notCompleted: notCompleted,
                                       waitForPhysicalOperation: true, operation: operation)
        }
    }

    /// Shared phone/tablet execution seam; the surface retains its worker.
    func assessExecution(
        requestID: UUID? = nil,
        worker: HealthHistoryAssessmentWorker,
        notCompleted: HealthHistoryAssessment,
        scope: HealthHistoryScope,
        isCurrent: () -> Bool,
        operation: @escaping @MainActor () async -> HealthHistoryAssessment
    ) async -> HealthHistoryAssessment? {
        await assess(requestID: requestID, scope: scope, isCurrent: isCurrent) {
            // A cancelled SDK call still owns the physical slot. Execution does
            // not queue behind it or multiply it; return explicit unverified
            // evidence until the provider actually retires.
            await worker.assess(notCompleted: notCompleted, operation: operation)
        }
    }

    /// Begin ownership before readable-date discovery or delayed scale confirmation.
    func beginExportRequest(selection: HealthHistoryExecutionSelection) -> HealthHistoryExportRequest {
        HealthHistoryExportRequest(id: beginRequest(), selection: selection)
    }

    func isCurrent(_ request: HealthHistoryExportRequest,
                   liveSelection: HealthHistoryExecutionSelection) -> Bool {
        request.id == revision && request.originatingSelection == liveSelection
    }

    /// An obsolete discovery/confirmation cannot cancel a newer operation.
    func invalidate(_ request: HealthHistoryExportRequest) {
        guard request.id == revision else { return }
        invalidate()
    }

    func invalidate() { revision = UUID() }
    func beginRequest() -> UUID {
        invalidate()
        return revision
    }

    func assess(
        requestID: UUID? = nil,
        scope: HealthHistoryScope,
        isCurrent: () -> Bool,
        operation: () async -> HealthHistoryAssessment
    ) async -> HealthHistoryAssessment? {
        guard !Task.isCancelled, isCurrent() else { return nil }
        let token = requestID ?? beginRequest()
        guard token == revision else { return nil }
        let result = await operation()
        guard !Task.isCancelled, token == revision, result.scope == scope, isCurrent() else { return nil }
        return result
    }
}

/// Frozen UI execution identity. No persistence/serialization/wire adoption.
struct HealthHistoryExecutionSelection: Equatable {
    let scope: HealthHistoryScope
    let settings: ExportSettingsSnapshot
    let target: ExportTargetSelection
    let preset: ExportDateRangePreset
    let localDestinationURL: URL?

    init(scope: HealthHistoryScope, settings: ExportSettingsSnapshot, target: ExportTargetSelection,
         preset: ExportDateRangePreset, localDestinationURL: URL? = nil) {
        self.scope = scope
        self.settings = settings
        self.target = target
        self.preset = preset
        self.localDestinationURL = localDestinationURL
    }

    /// Use the existing request-scoped reconstruction without repinning engines,
    /// replaying UI preferences or substituting a later selection during capture.
    func makeCaptureSettings() -> AdvancedExportSettings {
        let frozen = settings.makeAdvancedExportSettings()
        frozen.exportTimeZoneOverride = TimeZone(identifier: scope.timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)
        return frozen
    }
}

/// One immutable interactive action, spanning discovery, confirmation and assessment.
/// Originating UI identity remains strict; resolved bounds belong only to capture.
/// This value never persists date preferences or changes a public wire contract.
struct HealthHistoryExportRequest: Equatable {
    let id: UUID
    let originatingSelection: HealthHistoryExecutionSelection
    let selection: HealthHistoryExecutionSelection

    init(id: UUID, selection: HealthHistoryExecutionSelection) {
        self.init(id: id, originatingSelection: selection, selection: selection)
    }

    private init(id: UUID, originatingSelection: HealthHistoryExecutionSelection,
                 selection: HealthHistoryExecutionSelection) {
        self.id = id
        self.originatingSelection = originatingSelection
        self.selection = selection
    }

    func resolvingAllTime(_ range: ExportDateRange) -> Self? {
        let origin = originatingSelection
        guard origin.preset == .allTime, origin.scope.allAvailable,
              range.startDate.timeIntervalSinceReferenceDate.isFinite,
              range.endDate.timeIntervalSinceReferenceDate.isFinite,
              range.startDate <= range.endDate else { return nil }
        let scope = HealthHistoryScope(metricIDs: origin.scope.metricIDs,
            startDate: range.startDate, endDate: range.endDate,
            timeZoneIdentifier: origin.scope.timeZoneIdentifier,
            allAvailable: true, profileID: origin.scope.profileID,
            rangeSemantics: origin.scope.rangeSemantics)
        return Self(id: id, originatingSelection: origin,
            selection: HealthHistoryExecutionSelection(scope: scope,
                settings: origin.settings, target: origin.target, preset: origin.preset,
                localDestinationURL: origin.localDestinationURL))
    }
}

nonisolated struct HealthHistoryPreviewRequest: Equatable, Hashable, Sendable {
    let scope: HealthHistoryScope
    let refreshID: UUID
}
