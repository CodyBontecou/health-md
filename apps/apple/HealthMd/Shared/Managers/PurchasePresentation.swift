// Presentation-only purchase context. No analytics collection or persistence.
import Foundation

nonisolated enum PaywallContext: String, CaseIterable, Sendable {
    case export
    case onboarding
    case settings
    case schedule
    case shortcut
    case macTarget = "mac_target"
    case exportQuota = "export_quota"
    case restore
    case upgradePrompt = "upgrade_prompt"
}

nonisolated enum PurchaseSetupStep: String, CaseIterable, Sendable, Hashable {
    case welcome
    case healthAccess = "health_access"
    case sampleExport = "sample_export"
    case obsidianPlugin = "obsidian_plugin"
    case folderSetup = "folder_setup"
    case macHowItWorks = "mac_how_it_works"
    case macIPhoneApp = "mac_iphone_app"
    case macConnect = "mac_connect"
    case unlock
    case ready
}

nonisolated struct PurchasePresentationSource: Equatable, Sendable {
    let paywallContext: PaywallContext
    let onboardingStep: PurchaseSetupStep?

    static let onboardingUnlock = PurchasePresentationSource(
        paywallContext: .onboarding,
        onboardingStep: .unlock
    )

    static func paywall(_ context: PaywallContext) -> PurchasePresentationSource {
        PurchasePresentationSource(paywallContext: context, onboardingStep: nil)
    }
}

nonisolated enum ExportPreviewTargetType: String, CaseIterable, Sendable {
    case localFile = "local_file"
    case connectedMac = "connected_mac"
    case apiEndpoint = "api_endpoint"
    case agentDataGateway = "agent_data_gateway"
    case previewOnly = "preview_only"
}
