import Foundation

/// User-selected destination for manual exports initiated from iOS.
enum ExportTargetSelection: String, CaseIterable, Codable, Equatable, Identifiable {
    case localIPhoneFolder
    case connectedMac
    case apiEndpoint
    case agentDataGateway

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
        case .agentDataGateway:
            // Terminology is identical on Android; do not relabel.
            return "Agent Data gateway"
        }
    }

    var requiresNetworkForScheduledExport: Bool {
        switch self {
        case .localIPhoneFolder:
            return false
        case .connectedMac, .apiEndpoint, .agentDataGateway:
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
        apiEndpointConfigured: Bool = false,
        agentDataGatewayConfigured: Bool = false
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
        case .agentDataGateway:
            // The gateway uploads the export's JSON artifacts; it cannot
            // resolve or mutate a filesystem daily note.
            return hasSelectedFormat && !dailyNotesOnlyModeEnabled && agentDataGatewayConfigured
        }
    }
}
