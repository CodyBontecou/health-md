#if os(iOS)
import SwiftUI

/// Pushed pages of FormatCustomG's Frontmatter section. They edit the format page's private
/// copy of the configuration, so nothing is written until that page saves.
private struct GlassFieldPage<Content: View>: View {
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

/// One group of health metric fields: search at the top, a toggle per field, and tap a
/// field's key to rename it.
struct GlassFrontmatterGroupScreen: View {
    @ObservedObject var config: FrontmatterConfiguration
    let group: FrontmatterFieldGroup

    @Environment(\.glassPalette) private var palette
    @State private var query = ""
    @State private var renameKey: String?
    @State private var renameText = ""

    private var fields: [CustomFrontmatterField] {
        config.fields.filter { FrontmatterFieldGroup.group(for: $0.originalKey) == group }
    }

    private var visibleFields: [CustomFrontmatterField] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return fields }
        return fields.filter {
            $0.originalKey.localizedCaseInsensitiveContains(normalizedQuery)
                || $0.customKey.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    var body: some View {
        GlassFieldPage(title: group.title) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.muted).accessibilityHidden(true)
                TextField(String(localized: "Search Fields"), text: $query)
                    .textFieldStyle(.plain)
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .frame(minHeight: GlassMetrics.touchTarget)
            .glassSurface(cornerRadius: GlassMetrics.touchTarget / 2)

            GlassPanel {
                ForEach(visibleFields) { field in
                    fieldRow(field)
                }
            }
            Text("Tap a field to rename its key.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 20)
        }
        .alert(
            String(localized: "Rename Field"),
            isPresented: Binding(get: { renameKey != nil }, set: { if !$0 { renameKey = nil } })
        ) {
            TextField(renameKey ?? "", text: $renameText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Save Name")) { applyRename(renameText) }
            Button(String(localized: "Reset Name")) { applyRename(nil) }
        } message: {
            if let renameKey { Text("Enter a custom name for \(renameKey).") }
        }
    }

    private func fieldRow(_ field: CustomFrontmatterField) -> some View {
        HStack(spacing: 12) {
            Button {
                renameText = field.customKey
                renameKey = field.originalKey
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: field.outputKey)
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(palette.text)
                    if field.outputKey != field.originalKey {
                        Text(verbatim: field.originalKey).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: field.outputKey))
            .accessibilityHint(Text("Rename \(field.originalKey)"))

            Toggle(isOn: binding(field)) { EmptyView() }
                .toggleStyle(GlassToggleStyle(labelsHidden: true))
                .accessibilityLabel(Text(verbatim: field.outputKey))
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .frame(minHeight: GlassMetrics.rowMinHeight)
    }

    private func binding(_ field: CustomFrontmatterField) -> Binding<Bool> {
        Binding(
            get: { config.fields.first { $0.originalKey == field.originalKey }?.isEnabled ?? false },
            set: { isOn in
                guard let index = config.fields.firstIndex(where: { $0.originalKey == field.originalKey }) else { return }
                config.fields[index].isEnabled = isOn
            }
        )
    }

    private func applyRename(_ newKey: String?) {
        guard let key = renameKey, let index = config.fields.firstIndex(where: { $0.originalKey == key }) else { return }
        let trimmed = newKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        config.fields[index].customKey = trimmed.isEmpty ? key : trimmed
    }
}

/// Core metadata: key style plus the date and type fields.
struct GlassFrontmatterCoreScreen: View {
    @ObservedObject var config: FrontmatterConfiguration

    var body: some View {
        GlassFieldPage(title: String(localized: "Core metadata")) {
            GlassPanel {
                GlassMenuRow(
                    title: String(localized: "Key Style"),
                    selection: Binding(get: { config.keyStyle }, set: { config.applyKeyStyle($0) }),
                    options: FrontmatterKeyStyle.allCases,
                    label: \.displayName
                )
            }
            GlassPanel {
                GlassToggleRow(title: String(localized: "Include Date Field"), isOn: $config.includeDate)
                if config.includeDate {
                    GlassTemplateField(title: String(localized: "Date Field Name"), text: $config.customDateKey)
                }
            }
            GlassPanel {
                GlassToggleRow(title: String(localized: "Include Type Field"), isOn: $config.includeType)
                if config.includeType {
                    GlassTemplateField(title: String(localized: "Type Field Name"), text: $config.customTypeKey)
                    GlassTemplateField(title: String(localized: "Type Field Value"), text: $config.customTypeValue)
                }
            }
        }
    }
}

/// Custom (fixed value) or placeholder (empty) fields, with delete and add.
struct GlassUserFieldsScreen: View {
    enum Kind { case custom, placeholder }

    @ObservedObject var config: FrontmatterConfiguration
    let kind: Kind

    @Environment(\.glassPalette) private var palette
    @State private var showAdd = false

    var body: some View {
        GlassFieldPage(title: kind == .custom ? String(localized: "Custom fields") : String(localized: "Placeholder fields")) {
            Text(kind == .custom
                 ? String(localized: "Same value in every export, e.g. type: health")
                 : String(localized: "Left empty to fill in later, e.g. mood"))
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 20)
            GlassPanel {
                ForEach(keys, id: \.self) { key in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: key).font(.system(size: 15, design: .monospaced)).foregroundStyle(palette.text)
                            Text(verbatim: value(for: key)).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 8)
                        Button(role: .destructive) { delete(key) } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(palette.coral)
                                .frame(minWidth: GlassMetrics.touchTarget, minHeight: GlassMetrics.touchTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(kind == .custom
                            ? String(localized: "Delete custom field \(key)")
                            : String(localized: "Delete placeholder field \(key)"))
                    }
                    .padding(.horizontal, GlassMetrics.panelPadding)
                    .frame(minHeight: GlassMetrics.rowWithSubtitleMinHeight)
                }
                GlassAddFieldButton { showAdd = true }
            }
        }
        .glassAddFieldAlerts(config: config, kind: showAdd ? kind : nil, onDismiss: { showAdd = false })
    }

    private var keys: [String] {
        kind == .custom ? config.customFields.keys.sorted() : config.placeholderFields.sorted()
    }

    private func value(for key: String) -> String {
        kind == .custom
            ? FrontmatterFieldPresentation.customValue(config.customFields[key] ?? "")
            : String(localized: "Empty on export")
    }

    private func delete(_ key: String) {
        if kind == .custom {
            config.customFields.removeValue(forKey: key)
        } else {
            config.placeholderFields.removeAll { $0 == key }
        }
    }
}

/// "+ Add field" row from FormatCustomG.
struct GlassAddFieldButton: View {
    let action: () -> Void
    @Environment(\.glassPalette) private var palette

    var body: some View {
        Button(action: action) {
            Label(String(localized: "Add field"), systemImage: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight, alignment: .leading)
                .padding(.horizontal, GlassMetrics.panelPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The existing editor's add-field dialogs, as glass alerts.
private struct GlassAddFieldAlerts: ViewModifier {
    @ObservedObject var config: FrontmatterConfiguration
    let kind: GlassUserFieldsScreen.Kind?
    let onDismiss: () -> Void

    @State private var key = ""
    @State private var value = ""

    func body(content: Content) -> some View {
        content
            .alert(String(localized: "Add Custom Field"), isPresented: presented(.custom)) {
                TextField(String(localized: "Field name (e.g., tags)"), text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(String(localized: "Value (e.g., health, daily)"), text: $value)
                Button(String(localized: "Cancel"), role: .cancel) { clear() }
                Button(String(localized: "Add Field")) {
                    let name = trimmedKey
                    if !name.isEmpty { config.customFields[name] = value }
                    clear()
                }
                .disabled(trimmedKey.isEmpty)
            } message: {
                Text("Add a custom field that will be included in every export.")
            }
            .alert(String(localized: "Add Placeholder Field"), isPresented: presented(.placeholder)) {
                TextField(String(localized: "Field name (e.g., omron_systolic)"), text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(String(localized: "Cancel"), role: .cancel) { clear() }
                Button(String(localized: "Add Placeholder")) {
                    let name = trimmedKey
                    if !name.isEmpty && !config.placeholderFields.contains(name) {
                        config.placeholderFields.append(name)
                    }
                    clear()
                }
                .disabled(trimmedKey.isEmpty)
            } message: {
                Text("Add a field that will export with an empty value for manual entry.")
            }
    }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func presented(_ target: GlassUserFieldsScreen.Kind) -> Binding<Bool> {
        Binding(get: { kind == target }, set: { if !$0 { onDismiss() } })
    }

    private func clear() {
        key = ""
        value = ""
        onDismiss()
    }
}

extension View {
    func glassAddFieldAlerts(
        config: FrontmatterConfiguration,
        kind: GlassUserFieldsScreen.Kind?,
        onDismiss: @escaping () -> Void
    ) -> some View {
        modifier(GlassAddFieldAlerts(config: config, kind: kind, onDismiss: onDismiss))
    }
}
#endif
