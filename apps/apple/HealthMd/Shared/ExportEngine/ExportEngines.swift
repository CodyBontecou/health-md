/// Immutable input shared by native and Rust renderers. Payload ownership is deliberately generic at
/// this foundation layer; no HealthData, vault, filesystem, or network type crosses the protocol.
nonisolated struct ExportEngineOperationInput<Payload: Sendable>: Sendable {
    let pin: AppleExportEnginePin
    let payload: Payload

    init(pin: AppleExportEnginePin, payload: Payload) {
        self.pin = pin
        self.payload = payload
    }
}

/// Handwritten native rendering boundary. Implementations render only and cannot commit.
nonisolated protocol NativeExportEngine: Sendable {
    associatedtype Payload: Sendable

    func render(
        _ input: ExportEngineOperationInput<Payload>
    ) async throws -> NativeExportArtifactPlan
}

/// Handwritten Rust rendering boundary. Implementations adapt one immutable operation to UniFFI and
/// return the validated native plan; they cannot commit.
nonisolated protocol RustExportEngine: Sendable {
    associatedtype Payload: Sendable

    func render(
        _ input: ExportEngineOperationInput<Payload>
    ) async throws -> NativeExportArtifactPlan
}

/// Health-free shadow evidence. Renderer errors are reduced to a fixed kind instead of preserving
/// an arbitrary Error description that could contain health fields or paths.
nonisolated enum ShadowExportDiagnostic: Equatable, Sendable {
    case comparisonCompleted(ShadowExportComparisonCompletedDiagnostic)
    case planMismatch(NativeExportPlanMismatchDiagnostic)
    case rustRenderFailed(ShadowExportFailureDiagnostic)
}

/// One denominator event per completed dual render. It intentionally carries no operation identity,
/// date, path, payload digest, byte count, or destination data.
nonisolated struct ShadowExportComparisonCompletedDiagnostic: Equatable, Sendable {
    let profile: String
    let semanticProfileRevision: UInt32
    let renderProfileRevision: UInt32
    let matches: Bool
    let mismatchCount: UInt32
}

nonisolated struct ShadowExportFailureDiagnostic: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case rustRenderFailed = "rust_render_failed"
    }

    let profile: String
    let semanticProfileRevision: UInt32
    let renderProfileRevision: UInt32
    let kind: Kind
}

/// Runs both renderers from the same immutable input, reports health-free evidence, and always
/// returns the native plan. No commit API is present, so shadow execution cannot open or mutate a
/// destination.
nonisolated struct ShadowExportEngine<Native: NativeExportEngine, Rust: RustExportEngine>:
    NativeExportEngine, Sendable where Native.Payload == Rust.Payload
{
    typealias Payload = Native.Payload
    typealias DiagnosticSink = @Sendable (ShadowExportDiagnostic) async -> Void

    private let nativeEngine: Native
    private let rustEngine: Rust
    private let comparisonOptions: NativeExportComparisonOptions
    private let diagnosticSink: DiagnosticSink

    init(
        native: Native,
        rust: Rust,
        comparisonOptions: NativeExportComparisonOptions = NativeExportComparisonOptions(),
        diagnosticSink: @escaping DiagnosticSink = ShadowExportEvidenceRecorder.productionSink
    ) {
        nativeEngine = native
        rustEngine = rust
        self.comparisonOptions = comparisonOptions
        self.diagnosticSink = diagnosticSink
    }

    func render(
        _ input: ExportEngineOperationInput<Payload>
    ) async throws -> NativeExportArtifactPlan {
        let nativePlan = try await nativeEngine.render(input)
        do {
            let rustPlan = try await rustEngine.render(input)
            let mismatches = NativeExportPlanComparator.compare(
                native: nativePlan,
                rust: rustPlan,
                pin: input.pin,
                options: comparisonOptions
            )
            await diagnosticSink(.comparisonCompleted(
                ShadowExportComparisonCompletedDiagnostic(
                    profile: AppleExportEnginePin.profileID,
                    semanticProfileRevision: input.pin.semanticProfileRevision,
                    renderProfileRevision: input.pin.renderProfileRevision,
                    matches: mismatches.isEmpty,
                    mismatchCount: UInt32(clamping: mismatches.count)
                )
            ))
            for mismatch in mismatches {
                await diagnosticSink(.planMismatch(mismatch))
            }
        } catch {
            await diagnosticSink(.rustRenderFailed(ShadowExportFailureDiagnostic(
                profile: AppleExportEnginePin.profileID,
                semanticProfileRevision: input.pin.semanticProfileRevision,
                renderProfileRevision: input.pin.renderProfileRevision,
                kind: .rustRenderFailed
            )))
        }
        return nativePlan
    }
}
