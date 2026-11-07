#if os(iOS)
import SwiftUI

extension ExportProfileCoordinator {
    /// Replaces a profile's settings through the same path as the profile editor. Name,
    /// destination and bindings come from the stored profile, so an earlier page's save
    /// is never undone by a stale copy.
    func saveSettings(_ settings: ExportSettingsSnapshot, for profile: ExportProfile) {
        let current = profileStore.profile(id: profile.id) ?? profile
        _ = updateProfile(
            id: current.id,
            name: current.name,
            target: current.target,
            folderVaultID: current.folderVaultID,
            apiEndpointID: current.apiEndpointID,
            agentDataGatewayID: destinationStore.agentDataGatewayBinding(profileID: current.id),
            settings: settings
        )
    }

    /// Changes one part of the stored profile's settings and saves the result.
    func saveSettings(for profile: ExportProfile, _ change: (inout ExportSettingsSnapshot) -> Void) {
        var settings = (profileStore.profile(id: profile.id) ?? profile).settings
        change(&settings)
        saveSettings(settings, for: profile)
    }
}

extension ExportSettingsSnapshot {
    /// Yesterday's output paths, from the exporter's own formatter on a throwaway object.
    var glassPreviewPaths: [String] {
        guard let defaults = UserDefaults(suiteName: "com.healthmd.glass.output-preview") else { return [] }
        let settings = AdvancedExportSettings(snapshot: self, userDefaults: defaults)
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return ExportProfileCardSummary.sortedFormats(exportFormats).map { format in
            let components = [
                healthSubfolder,
                settings.formatFolderPath(for: date, format: format),
                settings.filename(for: date, format: format)
            ]
            return components.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "/")
        }
    }
}

/// The settings pages of one automation, pushed from its detail or composer.
enum GlassProfilePageKind: String, Identifiable, Hashable {
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

/// A pushed settings page: inline title and the stack's Back. Pages save as they change
/// (`glassAutosave`), so there is no Cancel or Save.
struct GlassSettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    @Environment(\.glassPalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) { content }
                .padding(GlassMetrics.screenMargin)
        }
        .scrollDismissesKeyboard(.interactively)
        .tint(palette.accent)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Hosts a pushed page where the caller can only present a sheet: its own stack, an
/// optional Done, and the lock's toast above the sheet.
struct GlassPageSheet<Content: View>: View {
    var showsDone = true
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        NavigationStack {
            content.toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Done")) { dismiss() }
                            .accessibilityIdentifier("glass.page.done")
                    }
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

extension View {
    /// Saves a page's edits as they happen: shortly after the last change, and at once
    /// when the page goes away. A change made while settings are locked is undone and the
    /// lock's toast explains why. An invalid value is never saved; leaving with one asks
    /// before discarding it, so Back never drops a change without saying so.
    func glassAutosave<Value: Equatable>(
        _ value: Value,
        isValid: Bool = true,
        invalidReason: String = "",
        revert: @escaping (Value) -> Void,
        save: @escaping (Value) -> Void
    ) -> some View {
        modifier(GlassAutosaveModifier(
            value: value,
            isValid: isValid,
            invalidReason: invalidReason,
            revert: revert,
            save: save
        ))
    }
}

private struct GlassAutosaveModifier<Value: Equatable>: ViewModifier {
    let value: Value
    let isValid: Bool
    let invalidReason: String
    let revert: (Value) -> Void
    let save: (Value) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    /// The value last written. Nil until the page first appears.
    @State private var saved: Value?
    @State private var pending: Task<Void, Never>?
    @State private var showDiscard = false

    private var holdsInvalidChange: Bool {
        guard let saved else { return false }
        return !isValid && value != saved
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Returning from a pushed sub-page may bring edits made there.
                if saved == nil { saved = value } else { changed(value) }
            }
            .onChange(of: value) { _, newValue in changed(newValue) }
            .onDisappear(perform: flush)
            .navigationBarBackButtonHidden(holdsInvalidChange)
            .toolbar {
                if holdsInvalidChange {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showDiscard = true
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(palette.text)
                        }
                        .accessibilityLabel(String(localized: "Back"))
                        .accessibilityIdentifier("glass.page.back")
                        // On the back button, so the confirmation points at what was tapped.
                        .confirmationDialog(
                            String(localized: "Discard this change?"),
                            isPresented: $showDiscard,
                            titleVisibility: .visible
                        ) {
                            Button(String(localized: "Discard Change"), role: .destructive) {
                                if let saved { revert(saved) }
                                dismiss()
                            }
                            Button(String(localized: "Keep Editing"), role: .cancel) {}
                        } message: {
                            Text(invalidReason)
                        }
                    }
                }
            }
    }

    private func changed(_ newValue: Value) {
        pending?.cancel()
        pending = nil
        guard let saved, newValue != saved else { return }
        guard !configurationProtection.isEnabled else {
            configurationProtection.presentBlockedChangeToast()
            revert(saved)
            return
        }
        guard isValid else { return }
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            commit(newValue)
        }
    }

    private func commit(_ newValue: Value) {
        pending = nil
        guard configurationProtection.performConfigurationChange({ save(newValue) }) else {
            if let saved { revert(saved) }
            return
        }
        saved = newValue
    }

    private func flush() {
        guard let task = pending else { return }
        task.cancel()
        commit(value)
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
    /// Shown when the field is empty, for templates whose empty value has a meaning.
    var placeholder: String?
    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).glassFont(.caption).foregroundStyle(palette.muted)
            TextField(placeholder ?? title, text: $text)
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
                styled(path).glassFont(.monoBody)
            }
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Folders in the secondary colour and the file's name in the accent, as on OutputG.
    private func styled(_ path: String) -> Text {
        let slash = path.lastIndex(of: "/")
        let folder = slash.map { String(path[...$0]) } ?? ""
        let file = slash.map { String(path[path.index(after: $0)...]) } ?? path
        let dot = file.lastIndex(of: ".")
        let stem = dot.map { String(file[..<$0]) } ?? file
        let ext = dot.map { String(file[$0...]) } ?? ""
        return Text(verbatim: folder).foregroundColor(palette.sec)
            + Text(verbatim: stem).foregroundColor(palette.accent)
            + Text(verbatim: ext).foregroundColor(palette.sec)
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
