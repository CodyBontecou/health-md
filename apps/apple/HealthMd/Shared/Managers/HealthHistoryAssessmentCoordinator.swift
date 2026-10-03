import Foundation

/// One owner per preview/execution surface. Reentrant assessments cannot publish
/// an obsolete result even if a scope changes away and back while suspended.
@MainActor
final class HealthHistoryAssessmentCoordinator {
    private var revision = UUID()

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

nonisolated struct HealthHistoryPreviewRequest: Equatable, Hashable, Sendable {
    let scope: HealthHistoryScope
    let refreshID: UUID
}
