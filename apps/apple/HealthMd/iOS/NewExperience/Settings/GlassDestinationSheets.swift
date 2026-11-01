#if os(iOS)
import SwiftUI

/// Shared layout for APIDestG and GatewayDestG. Edits apply as you type, through the
/// same protected bindings as the existing settings sheets, so the header keeps Done
/// rather than the mock's Save.
private struct GlassDestinationForm<Fields: View>: View {
    let title: String
    let sectionTitle: String
    /// What Health.md sends. Part of the public contract, so keep it accurate.
    let contractNote: String
    let trustNote: String
    let isConfigured: Bool
    let readyText: String
    let endpointDescription: String
    let removeTitle: String
    let canRemove: Bool
    let onRemove: () -> Void
    @ViewBuilder let fields: Fields

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    VStack(alignment: .leading, spacing: 6) {
                        GlassSectionLabel(title: sectionTitle).padding(.horizontal, 20)
                        GlassPanel { fields }
                        Text(contractNote)
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(palette.muted)
                            .padding(.horizontal, 20)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        GlassSectionLabel(title: String(localized: "Status")).padding(.horizontal, 20)
                        GlassPanel { statusRow }
                    }

                    trustNoteView

                    if canRemove {
                        GlassPanel {
                            Button(role: .destructive) { confirmingRemoval = true } label: {
                                Text(removeTitle)
                                    .glassFont(.body)
                                    .foregroundStyle(palette.coral)
                                    .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight, alignment: .leading)
                                    .padding(.horizontal, GlassMetrics.panelPadding)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .tint(palette.accent)
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
            .confirmationDialog(removeTitle, isPresented: $confirmingRemoval, titleVisibility: .visible) {
                Button(removeTitle, role: .destructive) {
                    configurationProtection.performConfigurationChange(onRemove)
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

    private var statusRow: some View {
        GlassRow(
            title: isConfigured ? readyText : String(localized: "Enter a valid HTTP or HTTPS URL"),
            subtitle: isConfigured ? endpointDescription : nil
        ) {
            Text(isConfigured ? String(localized: "Ready") : String(localized: "Not set"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isConfigured ? palette.ok : palette.coral)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(palette.surface2))
        }
        .accessibilityElement(children: .combine)
    }

    private var trustNoteView: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle")
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(trustNote)
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.sec)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
        .overlay(
            RoundedRectangle(cornerRadius: GlassMetrics.panelSmallRadius, style: .continuous)
                .strokeBorder(palette.accent.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// A labelled field row inside a destination panel: caption above, input below,
/// optional helper text underneath.
private struct GlassDestinationFieldRow<Field: View>: View {
    let label: String
    var helper: String?
    var showsDivider = false
    @ViewBuilder let field: Field

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).glassFont(.caption).foregroundStyle(palette.muted)
                .accessibilityHidden(true)
            field
                .textFieldStyle(.plain)
                .foregroundStyle(palette.text)
                .frame(minHeight: 28)
            if let helper {
                Text(helper).font(.system(size: 12)).foregroundStyle(palette.muted)
            }
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle().fill(palette.line).frame(height: 1)
                    .padding(.horizontal, GlassMetrics.panelPadding)
            }
        }
    }
}

struct GlassAPIDestinationSheet: View {
    @ObservedObject var settings: APIExportSettings
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        GlassDestinationForm(
            title: String(localized: "API Endpoint"),
            sectionTitle: String(localized: "Endpoint"),
            contractNote: String(localized: "Health.md POSTs a JSON envelope with one public Health.md JSON record per day. Re-exporting a date sends a newly fetched complete snapshot, so your endpoint can replace or upsert it."),
            trustNote: String(localized: "Only send Apple Health data to endpoints you control or trust. API exports use your selected metrics and Data Detail setting."),
            isConfigured: settings.isConfigured,
            readyText: String(localized: "Ready to export to API"),
            endpointDescription: settings.redactedEndpointDescription,
            removeTitle: String(localized: "Remove Endpoint"),
            canRemove: !settings.endpointURLString.isEmpty || !settings.bearerToken.isEmpty,
            onRemove: {
                settings.endpointURLString = ""
                settings.bearerToken = ""
            }
        ) {
            GlassDestinationFieldRow(label: String(localized: "Endpoint URL")) {
                TextField("https://api.example.com/healthmd", text: configurationProtection.protecting($settings.endpointURLString))
                    .glassFont(.monoBody)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("API endpoint URL")
            }
            GlassDestinationFieldRow(
                label: String(localized: "Token"),
                helper: String(localized: "Optional. Stored in Keychain and sent as an Authorization header."),
                showsDivider: true
            ) {
                SecureField("Optional bearer token", text: configurationProtection.protecting($settings.bearerToken))
                    .glassFont(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("API bearer token")
            }
        }
    }
}

struct GlassGatewayDestinationSheet: View {
    @ObservedObject var settings: AgentDataGatewaySettings
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        GlassDestinationForm(
            title: String(localized: "Agent Data Gateway"),
            sectionTitle: String(localized: "Gateway"),
            contractNote: String(localized: "Uploads each exported artifact file unchanged to /v1/ingest using the Agent Data protocol, always including the JSON daily export. Re-uploading identical artifacts is idempotent. No token is needed in this version."),
            trustNote: String(localized: "Only send Apple Health data to gateways you control or trust. Gateway uploads use your selected metrics and Data Detail setting."),
            isConfigured: settings.isConfigured,
            readyText: String(localized: "Ready to export to the gateway"),
            endpointDescription: settings.redactedEndpointDescription,
            removeTitle: String(localized: "Remove Gateway"),
            canRemove: !settings.endpointURLString.isEmpty,
            onRemove: { settings.endpointURLString = "" }
        ) {
            GlassDestinationFieldRow(label: String(localized: "Gateway URL")) {
                TextField("https://gateway.example.com", text: configurationProtection.protecting($settings.endpointURLString))
                    .glassFont(.monoBody)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Agent Data gateway endpoint URL")
            }
        }
    }
}
#endif
