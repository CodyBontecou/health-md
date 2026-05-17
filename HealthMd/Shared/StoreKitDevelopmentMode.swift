import Foundation

/// Keeps local simulator launches away from StoreKit APIs that can surface the
/// system "Sign in to Apple Account" sheet before a developer explicitly asks
/// to test purchases.
enum StoreKitDevelopmentMode {
    static let enableStoreKitInSimulatorEnvironmentKey = "HEALTHMD_ENABLE_STOREKIT_IN_SIMULATOR"
    static let enableStoreKitInSimulatorDefaultsKey = "debugEnableStoreKitInSimulator"

    /// True when the app should avoid automatic StoreKit reads/listeners.
    ///
    /// Default behavior: DEBUG simulator builds skip StoreKit so local launches
    /// do not show Apple's account sign-in sheet. Set
    /// `HEALTHMD_ENABLE_STOREKIT_IN_SIMULATOR=1` in the scheme environment, or
    /// `debugEnableStoreKitInSimulator = true` in UserDefaults, to opt back in
    /// when actively testing IAP with a local `.storekit` configuration.
    static var shouldSkipStoreKitAccess: Bool {
        shouldSkipStoreKitAccess(
            isDebugBuild: isDebugBuild,
            isSimulator: isSimulator,
            isUITesting: TestMode.isUITesting,
            isExplicitlyEnabledInSimulator: isExplicitlyEnabledInSimulator
        )
    }

    static var isExplicitlyEnabledInSimulator: Bool {
        if isTruthy(ProcessInfo.processInfo.environment[enableStoreKitInSimulatorEnvironmentKey]) {
            return true
        }
        return UserDefaults.standard.bool(forKey: enableStoreKitInSimulatorDefaultsKey)
    }

    static func shouldSkipStoreKitAccess(
        isDebugBuild: Bool,
        isSimulator: Bool,
        isUITesting: Bool,
        isExplicitlyEnabledInSimulator: Bool
    ) -> Bool {
        if isUITesting { return true }
        return isDebugBuild && isSimulator && !isExplicitlyEnabledInSimulator
    }

    static func isTruthy(_ value: String?) -> Bool {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return ["1", "true", "yes", "y", "on"].contains(normalized)
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
