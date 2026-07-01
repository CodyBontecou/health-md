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
}

/// Pure export gating helper so UI and tests share the same target-specific rules.
struct ExportTargetReadiness {
    static func canExport(
        isHealthKitAuthorized: Bool,
        hasSelectedFormat: Bool,
        target: ExportTargetSelection,
        hasLocalFolder: Bool,
        canExportToConnectedMac: Bool,
        apiEndpointConfigured: Bool = false
    ) -> Bool {
        guard isHealthKitAuthorized, hasSelectedFormat else { return false }

        switch target {
        case .localIPhoneFolder:
            return hasLocalFolder
        case .connectedMac:
            return canExportToConnectedMac
        case .apiEndpoint:
            return apiEndpointConfigured
        }
    }
}
