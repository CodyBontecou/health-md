import Foundation
import HealthMdCoreRust

/// Resolves renderer authority for one explicit Apple output profile.
///
/// Release builds never inspect a runtime value. Internal builds may use an injected value, the
/// profile-scoped UserDefaults key, or the profile-scoped environment key, in that order.
nonisolated struct AppleExportEnginePolicyResolver: Sendable {
    static let userDefaultsKey = "HealthMd.exportEngine.apple_health_data_v8"
    static let environmentKey = "HEALTHMD_EXPORT_ENGINE_APPLE_HEALTH_DATA_V8"

    private let internalRuntimeOverride: String?

    init(
        injectedOverride: String? = nil,
        userDefaults: UserDefaults? = .standard,
        environment: [String: String]? = nil
    ) {
#if DEBUG || HEALTHMD_INTERNAL_TESTING
        internalRuntimeOverride = injectedOverride
            ?? userDefaults?.string(forKey: Self.userDefaultsKey)
            ?? (environment ?? ProcessInfo.processInfo.environment)[Self.environmentKey]
#else
        // Runtime switches are not a release control surface. Keep the parameters so internal
        // dependency injection does not require conditional call sites, but never inspect them.
        internalRuntimeOverride = nil
#endif
    }

    static var compileTimeDefault: ExportEngineMode {
#if HEALTHMD_APPLE_EXPORT_ENGINE_RUST && HEALTHMD_APPLE_EXPORT_ENGINE_SHADOW
        // Conflicting authority flags are a packaging error and must never select Rust.
        .legacy
#elseif HEALTHMD_APPLE_EXPORT_ENGINE_RUST
        .rust
#elseif HEALTHMD_APPLE_EXPORT_ENGINE_SHADOW
        .shadow
#else
        .legacy
#endif
    }

    /// Reads the Apple-v8 authority request without requiring model-layer callers to import the
    /// generated UniFFI module.
    func requestedAppleModeForNewOperation() -> ExportEngineMode {
        requestedModeForNewOperation(profile: .appleHealthDataV8)
    }

    /// Reads the profile-scoped authority request exactly once without opening the packaged core.
    /// Compatibility remains a separate gate because loading build/registry metadata is itself
    /// synchronous UniFFI work and must be dispatched away from MainActor by application planners.
    func requestedModeForNewOperation(
        profile: CoreMetricRegistryProfile
    ) -> ExportEngineMode {
        guard profile == .appleHealthDataV8 else { return .legacy }
        return internalRuntimeOverride.map(ExportEngineMode.init(persistedValue:))
            ?? Self.compileTimeDefault
    }

    /// Selects authority for a newly planned operation. An incompatible packaged core can never be
    /// selected for shadow or Rust authority; native legacy remains available independently.
    func modeForNewOperation(
        profile: CoreMetricRegistryProfile,
        buildInfo: CoreBuildInfo,
        registrySnapshot: CoreMetricRegistrySnapshot
    ) -> ExportEngineMode {
        let configured = requestedModeForNewOperation(profile: profile)
        guard configured != .legacy else { return .legacy }
        guard AppleExportEnginePin.coreIsCompatible(
            buildInfo: buildInfo,
            registrySnapshot: registrySnapshot
        ) else {
            return .legacy
        }
        return configured
    }

    /// Captures renderer authority for a newly planned durable operation. Failure to load or
    /// validate the packaged core leaves the operation explicitly legacy (a nil pin).
    /// Decoding persisted state never calls this method or UniFFI.
    func pinForNewOperation(
        calendarTimeZoneIdentifier: String,
        requestedMode frozenRequestedMode: ExportEngineMode? = nil,
        coreExecutor: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor()
    ) async -> AppleExportEnginePin? {
        // Legacy authority persists as nil without loading the packaged core. Capture the request
        // once so a mutable internal override can never split one operation's authority decision.
        let requestedMode = frozenRequestedMode
            ?? requestedModeForNewOperation(profile: .appleHealthDataV8)
        guard requestedMode != .legacy,
              AppleExportEnginePin.isIANAIdentifier(calendarTimeZoneIdentifier),
              let context = try? await coreExecutor.loadContext(),
              AppleExportEnginePin.coreIsCompatible(
                  buildInfo: context.buildInfo,
                  registrySnapshot: context.registry
              ) else {
            return nil
        }
        return try? AppleExportEnginePin(
            engine: requestedMode,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
            buildInfo: context.buildInfo,
            registrySnapshot: context.registry
        )
    }

    /// Resolves a durable operation. Missing pins are legacy journals. A pin never inherits a new
    /// process-wide override, and an incompatible non-legacy pin fails closed to legacy.
    func modeForPersistedOperation(
        pin: AppleExportEnginePin?,
        profile: CoreMetricRegistryProfile,
        buildInfo: CoreBuildInfo,
        registrySnapshot: CoreMetricRegistrySnapshot
    ) -> ExportEngineMode {
        guard profile == .appleHealthDataV8,
              let pin,
              pin.profile == AppleExportEnginePin.profileID else {
            return .legacy
        }
        guard pin.engine != .legacy else { return .legacy }
        guard pin.isCompatible(
            buildInfo: buildInfo,
            registrySnapshot: registrySnapshot
        ) else {
            return .legacy
        }
        return pin.engine
    }
}
