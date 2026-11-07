import Foundation

/// FolderDestG's "Default destination" switch. When on, a new automation starts out
/// writing to the default folder on this device instead of copying the destination of
/// the active automation. Existing automations are never changed.
enum NewAutomationDestinationPreference {
    static let key = "newAutomationsUseDefaultFolder"

    static func usesDefaultFolder(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }
}

/// The folder row's "iCloud Drive › Obsidian" line: where the chosen folder lives,
/// derived from the security-scoped bookmark's resolved URL. The folder itself is not
/// part of the line; the row shows its name separately.
enum FolderLocationDescription {
    static func parentLocation(
        of url: URL,
        iCloudDriveTitle: String = String(localized: "iCloud Drive"),
        onDeviceTitle: String
    ) -> String? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count > 1 else { return nil }
        let parents = Array(components.dropLast())

        if let index = parents.firstIndex(of: "Mobile Documents") {
            var parts = [iCloudDriveTitle]
            var rest = Array(parents.dropFirst(index + 1))
            guard let container = rest.first else { return iCloudDriveTitle }
            rest.removeFirst()
            if container != "com~apple~CloudDocs" {
                // App folders such as "iCloud~md~obsidian/Documents" appear in Files under the app's name.
                if let appName = container.split(separator: "~").last, !appName.isEmpty {
                    parts.append(String(appName).capitalized)
                }
                if rest.first == "Documents" { rest.removeFirst() }
            }
            return (parts + rest).joined(separator: " › ")
        }

        if let index = parents.firstIndex(of: "File Provider Storage") {
            return ([onDeviceTitle] + parents.dropFirst(index + 1)).joined(separator: " › ")
        }

        // An app's own Documents folder on this device: .../Containers/Data/Application/<id>/Documents
        if let index = parents.firstIndex(of: "Application"),
           index + 2 < parents.count, parents[index + 2] == "Documents" {
            return ([onDeviceTitle] + parents.dropFirst(index + 3)).joined(separator: " › ")
        }

        guard let parent = parents.last, parent != "/" else { return nil }
        return parent
    }
}
