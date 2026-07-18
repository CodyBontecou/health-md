import Foundation

/// User-selected destination for manual exports initiated from iOS.
enum ExportTargetSelection: String, CaseIterable, Codable, Equatable, Identifiable {
    case localIPhoneFolder
    case connectedMac
    case apiEndpoint

    static let storageKey = "exportTargetSelection"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localIPhoneFolder:
            return "Local iPhone Folder"
        case .connectedMac:
            return "Connected Mac"
        case .apiEndpoint:
            return "API Endpoint"
        }
    }

    var requiresNetworkForScheduledExport: Bool {
        switch self {
        case .localIPhoneFolder:
            return false
        case .connectedMac, .apiEndpoint:
            return true
        }
    }
}

/// Pure export gating helper so UI and tests share the same target-specific rules.
struct ExportTargetReadiness {
    static func canExport(
        isHealthKitAuthorized: Bool,
        hasSelectedFormat: Bool,
        dailyNotesOnlyModeEnabled: Bool = false,
        target: ExportTargetSelection,
        hasLocalFolder: Bool,
        canExportToConnectedMac: Bool,
        apiEndpointConfigured: Bool = false
    ) -> Bool {
        guard isHealthKitAuthorized else { return false }

        switch target {
        case .localIPhoneFolder:
            return (hasSelectedFormat || dailyNotesOnlyModeEnabled) && hasLocalFolder
        case .connectedMac:
            return (hasSelectedFormat || dailyNotesOnlyModeEnabled) && canExportToConnectedMac
        case .apiEndpoint:
            // API destinations cannot resolve or mutate a filesystem daily note.
            return hasSelectedFormat && !dailyNotesOnlyModeEnabled && apiEndpointConfigured
        }
    }
}
