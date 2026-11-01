#if os(iOS)
import SwiftUI

extension ExportProfileCoordinator {
    /// Replaces a profile's settings through the same path as the profile editor.
    func saveSettings(_ settings: ExportSettingsSnapshot, for profile: ExportProfile) {
        _ = updateProfile(
            id: profile.id,
            name: profile.name,
            target: profile.target,
            folderVaultID: profile.folderVaultID,
            apiEndpointID: profile.apiEndpointID,
            agentDataGatewayID: destinationStore.agentDataGatewayBinding(profileID: profile.id),
            settings: settings
        )
    }
}

/// The sheet-sized settings pages of one automation.
enum GlassProfilePageKind: String, Identifiable {
    case metrics, formats, output, dailyNotes, entries, formatCustom
    var id: String { rawValue }
}

struct GlassProfilePage: View {
    let kind: GlassProfilePageKind
    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    var body: some View {
        Group {
            switch kind {
            case .metrics: GlassMetricsScreen(coordinator: coordinator, profile: profile)
            case .formats: GlassFormatsScreen(coordinator: coordinator, profile: profile)
            case .output: GlassOutputScreen(coordinator: coordinator, profile: profile)
            case .dailyNotes: GlassDailyNoteScreen(coordinator: coordinator, profile: profile)
            case .entries: GlassEntriesScreen(coordinator: coordinator, profile: profile)
            case .formatCustom: GlassFormatCustomScreen(coordinator: coordinator, profile: profile)
            }
        }
        .glassTheme()
    }
}

/// Cancel and Save chrome for a page that edits a draft. Saving goes through the
/// configuration lock, and the lock's toast stays visible above the sheet.
struct GlassSettingsSheet<Content: View>: View {
    let title: String
    var canSave = true
    let onSave: () -> Void
    @ViewBuilder let content: Content

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) { content }
                    .padding(GlassMetrics.screenMargin)
            }
            .tint(palette.accent)
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        configurationProtection.performConfigurationChange {
                            onSave()
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
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

struct GlassSectionLabel: View {
    let title: String
    @Environment(\.glassPalette) private var palette

    var body: some View {
        Text(title).glassFont(.caption).foregroundStyle(palette.muted)
    }
}

struct GlassToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    @Environment(\.glassPalette) private var palette

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).glassFont(.body).foregroundStyle(palette.text)
                if let subtitle {
                    Text(subtitle).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                }
            }
        }
        .toggleStyle(GlassToggleStyle())
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 8)
    }
}

/// A labelled template field. Tokens insert a placeholder at the end of the text.
struct GlassTemplateField: View {
    let title: String
    @Binding var text: String
    var tokens: [String] = []
    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).glassFont(.caption).foregroundStyle(palette.muted)
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .glassFont(.monoBody)
                .foregroundStyle(palette.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .frame(minHeight: GlassMetrics.touchTarget)
            if !tokens.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tokens, id: \.self) { token in
                            GlassChip(title: token) { text += token }
                        }
                    }
                }
            }
        }
        .padding(GlassMetrics.panelPadding)
    }
}

/// Mono "Writes to" path preview.
struct GlassPathPreview: View {
    let paths: [String]
    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Writes to")).glassFont(.caption).foregroundStyle(palette.muted)
            ForEach(paths, id: \.self) { path in
                Text(verbatim: path).glassFont(.monoBody).foregroundStyle(palette.sec)
            }
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A row that picks from a menu, for choices too long for a segmented control.
struct GlassMenuRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    @Environment(\.glassPalette) private var palette

    var body: some View {
        HStack {
            Text(title).glassFont(.body).foregroundStyle(palette.text)
            Spacer(minLength: 8)
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(palette.accent)
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .frame(minHeight: GlassMetrics.rowMinHeight)
    }
}
#endif
