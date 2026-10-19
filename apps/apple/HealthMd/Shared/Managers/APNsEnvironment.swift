import Foundation
import Security

/// APNs tokens belong to the environment selected by signing, independently
/// of the app's Debug/Release build configuration.
nonisolated enum APNsEnvironment: String, Codable, Sendable {
    case development
    case production

    static func current(in bundle: Bundle = .main) -> APNsEnvironment? {
        #if targetEnvironment(simulator)
        return .development
        #elseif os(macOS)
        // SecTask is a public macOS API, but is not part of the public iOS SDK.
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.aps-environment" as CFString, nil
              ) as? String else { return nil }
        return APNsEnvironment(rawValue: value)
        #else
        guard let profileURL = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else {
            // App Store distribution removes the embedded provisioning profile.
            // TestFlight, ad hoc, and development installs retain their profile.
            return fromProvisioningProfile(nil)
        }
        guard let profile = try? Data(contentsOf: profileURL) else { return nil }
        return fromProvisioningProfile(profile)
        #endif
    }

    /// Read only the APNs entitlement from the bundled provisioning profile.
    /// The OS validates this profile when installing/running the signed app.
    /// Apple's profile format can evolve; an undecodable profile deliberately
    /// returns nil so registration cannot silently guess the wrong APNs host.
    static func fromProvisioningProfile(_ profile: Data?) -> APNsEnvironment? {
        guard let profile else { return .production }
        let plist: Data
        if (try? PropertyListSerialization.propertyList(from: profile, options: [], format: nil)) != nil {
            plist = profile
        } else {
            // Provisioning profiles wrap an XML plist in a CMS signature. No
            // public CMS decoder is available on iOS; extract the plist bytes
            // without loading private APIs or exposing any profile contents.
            let opening = Data("<plist".utf8)
            let closing = Data("</plist>".utf8)
            guard let start = profile.range(of: opening),
                  let end = profile.range(of: closing, in: start.lowerBound..<profile.endIndex) else {
                return nil
            }
            plist = profile.subdata(in: start.lowerBound..<end.upperBound)
        }
        guard let object = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil),
              let dictionary = object as? [String: Any],
              let entitlements = dictionary["Entitlements"] as? [String: Any],
              let value = (entitlements["aps-environment"] ?? entitlements["com.apple.developer.aps-environment"]) as? String else {
            return nil
        }
        return APNsEnvironment(rawValue: value)
    }
}
