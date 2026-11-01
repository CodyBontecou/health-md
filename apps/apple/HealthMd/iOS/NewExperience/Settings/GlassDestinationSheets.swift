#if os(iOS)
import SwiftUI

/// Shared layout for APIDestG and GatewayDestG. Edits apply as you type, through the
/// same protected bindings as the existing settings sheets.
private struct GlassDestinationForm<Fields: View>: View {
    let title: LocalizedStringKey
    let sectionTitle: LocalizedStringKey
    let explanation: LocalizedStringKey
    let trustNote: LocalizedStringKey
    let isConfigured: Bool
    let readyText: LocalizedStringKey
    @ViewBuilder let fields: Fields

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    Text(sectionTitle).glassFont(.caption).foregroundStyle(palette.muted)
                    VStack(spacing: 12) { fields }
                        .textFieldStyle(.plain)
                        .glassFont(.body)
                        .foregroundStyle(palette.text)
                        .padding(GlassMetrics.panelPadding)
                        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
                    Text(explanation).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                    HStack(spacing: 8) {
                        Image(systemName: isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isConfigured ? palette.ok : palette.coral)
                            .accessibilityHidden(true)
                        Text(isConfigured ? readyText : "Enter a valid HTTP or HTTPS URL")
                            .glassFont(.body)
                            .foregroundStyle(palette.text)
                    }
                    Text(trustNote).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                }
                .padding(GlassMetrics.screenMargin)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
        .overlay(alignment: .top) {
            ConfigurationProtectionToast(configurationProtection: configurationProtection)
        }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil { dismiss() }
        }
    }
}

struct GlassAPIDestinationSheet: View {
    @ObservedObject var settings: APIExportSettings
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        GlassDestinationForm(
            title: "API Export",
            sectionTitle: "Endpoint",
            explanation: "Health.md will POST a JSON envelope containing one public Health.md JSON record per day. Re-exporting a date sends a newly fetched complete snapshot so your endpoint can replace or upsert the previous version. If you enter a token, it is stored in Keychain and sent as an Authorization header.",
            trustNote: "Only send Apple Health data to endpoints you control or trust. API exports use your selected metrics and Data Detail setting.",
            isConfigured: settings.isConfigured,
            readyText: "Ready to export to API"
        ) {
            TextField("https://api.example.com/healthmd", text: configurationProtection.protecting($settings.endpointURLString))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("API endpoint URL")
            SecureField("Optional bearer token", text: configurationProtection.protecting($settings.bearerToken))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("API bearer token")
        }
    }
}

struct GlassGatewayDestinationSheet: View {
    @ObservedObject var settings: AgentDataGatewaySettings
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        GlassDestinationForm(
            title: "Agent Data Gateway",
            sectionTitle: "Gateway",
            explanation: "Health.md uploads each exported artifact file unchanged to your gateway's /v1/ingest endpoint using the Agent Data protocol. Re-uploading identical artifacts is idempotent. Gateways use HTTP or HTTPS and need no token in this version.",
            trustNote: "Only send Apple Health data to gateways you control or trust. Gateway uploads use your selected metrics and Data Detail setting, and always include the JSON daily export.",
            isConfigured: settings.isConfigured,
            readyText: "Ready to export to the gateway"
        ) {
            TextField("https://gateway.example.com", text: configurationProtection.protecting($settings.endpointURLString))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Agent Data gateway endpoint URL")
        }
    }
}
#endif
