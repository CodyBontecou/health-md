#if os(iOS)
import UIKit

/// The device Health.md is running on, as user-facing copy names it ("this iPhone", "this iPad").
///
/// Copy picks a whole localized sentence per device instead of splicing the noun into one
/// string, because translations inflect and reorder the words around it.
enum HostDevice: Equatable, Sendable {
    case iPhone
    case iPad

    /// iPad apps running on a Mac report the pad idiom, and they show iPad copy too.
    static func from(idiom: UIUserInterfaceIdiom) -> HostDevice {
        idiom == .pad ? .iPad : .iPhone
    }

    @MainActor static var current: HostDevice { from(idiom: UIDevice.current.userInterfaceIdiom) }

    /// Picks the variant written for this device.
    func pick<T>(iPhone: @autoclosure () -> T, iPad: @autoclosure () -> T) -> T {
        switch self {
        case .iPhone: return iPhone()
        case .iPad: return iPad()
        }
    }

    // MARK: - Shared copy

    /// The local folder destination: "Vault on this iPhone".
    var vaultTitle: String {
        pick(iPhone: String(localized: "Vault on this iPhone"), iPad: String(localized: "Vault on this iPad"))
    }

    /// A local folder with no vault chosen yet: "iPhone folder".
    var folderName: String {
        pick(iPhone: String(localized: "iPhone folder"), iPad: String(localized: "iPad folder"))
    }

    /// The Files app location for this device: "On My iPhone".
    var onMyDeviceTitle: String {
        pick(iPhone: String(localized: "On My iPhone"), iPad: String(localized: "On My iPad"))
    }
}
#endif
