#if os(iOS)
import UIKit

/// iPad "Auto-sync after export" (3.5 `iPadSyncView` / `iPadContentView`): after a
/// successful manual export to the local folder, push the exported days to the
/// connected Mac.
///
/// 3.5 showed the toggle and ran the push on iPad only, so 4.0 keeps that scope.
/// The effective 3.5 default was off: `HealthMdApp` registers `false` for the key,
/// and that registration shadows the `@AppStorage` fallback of `true`. Upgraders keep
/// whatever value they stored.
enum AutoSyncAfterExportPolicy {
    static let key = "autoSyncAfterExport"
    static let registeredDefault = false

    static func isAvailable(idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .pad
    }

    /// The 3.5 trigger: something was written, a Mac is connected, the Mac
    /// destination is on, and the user enabled auto-sync.
    static func shouldAutoSync(
        successCount: Int,
        connectionState: SyncConnectionState,
        syncEnabled: Bool,
        autoSyncAfterExport: Bool,
        idiom: UIUserInterfaceIdiom
    ) -> Bool {
        isAvailable(idiom: idiom)
            && successCount > 0
            && connectionState == .connected
            && syncEnabled
            && autoSyncAfterExport
    }

    static func shouldAutoSync(
        successCount: Int,
        connectionState: SyncConnectionState,
        defaults: UserDefaults = .standard,
        idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom
    ) -> Bool {
        shouldAutoSync(
            successCount: successCount,
            connectionState: connectionState,
            syncEnabled: defaults.bool(forKey: "syncEnabled"),
            autoSyncAfterExport: defaults.bool(forKey: key),
            idiom: idiom
        )
    }
}
#endif
