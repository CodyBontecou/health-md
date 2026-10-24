import Combine
import Foundation

/// User-configurable Agent Data gateway destination for direct iOS uploads.
/// Mirrors `APIExportSettings` storage and validation patterns; gateways
/// carry no credential in ingestion protocol v1, so the persisted state is
/// exactly one endpoint URL string.
@MainActor
final class AgentDataGatewaySettings: ObservableObject {
    // Keep deallocation on the releasing thread, matching the
    // `AdvancedExportSettings`/`APIExportSettings` convention.
    nonisolated deinit {}
    static let endpointURLStorageKey = "agentDataGateway.endpointURL"

    @Published var endpointURLString: String {
        didSet { userDefaults.set(endpointURLString, forKey: Self.endpointURLStorageKey) }
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.endpointURLString = userDefaults.string(forKey: Self.endpointURLStorageKey) ?? ""
    }

    /// Replaces the persisted endpoint verifiably, mirroring
    /// `APIExportSettings.replaceEndpointURLVerifiably`.
    func replaceEndpointURLVerifiably(_ value: String) throws {
        endpointURLString = value
        guard (userDefaults.string(forKey: Self.endpointURLStorageKey) ?? "") == value else {
            throw APIExportSettingsPersistenceError.verificationFailed
        }
    }

    var isConfigured: Bool {
        destinationSnapshot != nil
    }

    var destinationSnapshot: AgentDataGatewayDestinationSnapshot? {
        AgentDataGatewayDestinationSnapshot(endpointURLString: endpointURLString)
    }

    var displayName: String {
        AgentDataGatewayEndpoint.displayName(endpointURLString)
    }

    var redactedEndpointDescription: String {
        AgentDataGatewayEndpoint.redactedDescription(endpointURLString)
    }
}
