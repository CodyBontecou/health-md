#if os(iOS)
import SwiftUI

/// FormatCustomG. Edits a copy of the profile's customization and saves it as it changes.
/// Frontmatter fields are edited on native glass pages; custom templates reuse the existing
/// editor on that copy. Reset is in the header, as on the board.
struct GlassFormatCustomScreen: View {
    private enum Section: Hashable { case frontmatter, body, units }

    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var customization: FormatCustomization
    @State private var section = Section.frontmatter
    @State private var addFieldKind: GlassUserFieldsScreen.Kind?
    @State private var showAddFieldChoice = false
    @State private var showResetConfirmation = false

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        let customization = FormatCustomization()
        profile.settings.formatCustomization.apply(to: customization)
        customization.frontmatterConfig.migrateMissingDefaultFields()
        _customization = StateObject(wrappedValue: customization)
    }

    var body: some View {
        // FormatCustomG stacks all three sections on one page; the Section control
        // above them scrolls to the one chosen.
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) { frontmatter }
                        .id(Section.frontmatter)
                    VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                        GlassSectionLabel(title: String(localized: "Markdown body"))
                        markdownBody
                    }
                    .id(Section.body)
                    VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                        GlassSectionLabel(title: String(localized: "Dates & units"))
                        datesAndUnits
                    }
                    .id(Section.units)
                }
                .padding(GlassMetrics.screenMargin)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                GlassSegmentedControl(
                    segments: [
                        .init(value: .frontmatter, title: String(localized: "Frontmatter")),
                        .init(value: .body, title: String(localized: "Markdown body")),
                        .init(value: .units, title: String(localized: "Dates & units"))
                    ],
                    selection: Binding(
                        get: { section },
                        set: { value in
                            section = value
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                proxy.scrollTo(value, anchor: .top)
                            }
                        }
                    )
                )
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.vertical, 8)
                .background(palette.bg)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .tint(palette.accent)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Customize format"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(String(localized: "Reset")) { showResetConfirmation = true }
                    .accessibilityIdentifier("glass.formatCustom.reset")
            }
        }
        .confirmationDialog(
            String(localized: "Reset format customization?"),
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Reset"), role: .destructive, action: reset)
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("Field names, the Markdown body, and date and unit choices return to their defaults for this automation.")
        }
        .glassAutosave(
            FormatCustomizationSnapshot.from(customization),
            revert: { $0.apply(to: customization) },
            save: { value in coordinator.saveSettings(for: profile) { $0.formatCustomization = value } }
        )
    }

    private var config: FrontmatterConfiguration { customization.frontmatterConfig }

    @ViewBuilder private var datesAndUnits: some View {
        GlassPanel {
            GlassMenuRow(
                title: String(localized: "Date format"),
                selection: $customization.dateFormat,
                options: DateFormatPreference.allCases,
                label: \.displayName
            )
            GlassMenuRow(
                title: String(localized: "Time format"),
                selection: $customization.timeFormat,
                options: TimeFormatPreference.allCases,
                label: \.displayName
            )
        }
        GlassSectionLabel(title: String(localized: "Units"))
        GlassSegmentedControl(
            segments: UnitPreference.allCases.map { .init(value: $0, title: $0.displayName) },
            selection: $customization.unitPreference
        )
    }

    @ViewBuilder private var frontmatter: some View {
        let groups = FrontmatterFieldGroup.grouped(config.fields)
        let coreEnabled = (config.includeDate ? 1 : 0) + (config.includeType ? 1 : 0)
        let enabled = coreEnabled + config.fields.filter(\.isEnabled).count
        GlassSectionLabel(title: String(localized: "Fields · \(enabled) of \(config.fields.count + 2)"))
        GlassPanel {
            fieldLink(String(localized: "Core metadata"), value: String(localized: "\(coreEnabled) of \(2)")) {
                GlassFrontmatterCoreScreen(config: config)
            }
            ForEach(groups, id: \.group) { entry in
                let count = entry.fields.filter(\.isEnabled).count
                fieldLink(entry.group.title, value: String(localized: "\(count) of \(entry.fields.count)")) {
                    GlassFrontmatterGroupScreen(config: config, group: entry.group)
                }
            }
        }
        Text("Tap a field to rename its key. Search is at the top of each category.")
            .glassFont(.rowSubtitle)
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 20)

        GlassSectionLabel(title: String(localized: "Your fields"))
        GlassPanel {
            fieldLink(
                String(localized: "Custom fields"),
                subtitle: String(localized: "Same value in every export, e.g. type: health"),
                value: "\(config.customFields.count)"
            ) {
                GlassUserFieldsScreen(config: config, kind: .custom)
            }
            fieldLink(
                String(localized: "Placeholder fields"),
                subtitle: String(localized: "Left empty to fill in later, e.g. mood"),
                value: "\(config.placeholderFields.count)"
            ) {
                GlassUserFieldsScreen(config: config, kind: .placeholder)
            }
            GlassAddFieldButton { showAddFieldChoice = true }
        }
        .confirmationDialog(String(localized: "Add field"), isPresented: $showAddFieldChoice) {
            Button(String(localized: "Add Custom Field")) { addFieldKind = .custom }
            Button(String(localized: "Add Placeholder Field")) { addFieldKind = .placeholder }
        }
        .glassAddFieldAlerts(config: config, kind: addFieldKind, onDismiss: { addFieldKind = nil })
    }

    private func fieldLink<Destination: View>(
        _ title: String,
        subtitle: String? = nil,
        value: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            GlassRow(title: title, subtitle: subtitle) {
                Text(verbatim: value).font(.system(size: 15)).foregroundStyle(palette.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var markdownBody: some View {
        GlassPanel {
            labelledControl(String(localized: "Template")) {
                GlassSegmentedControl(
                    segments: MarkdownTemplateStyle.allCases.map { .init(value: $0, title: $0.displayName) },
                    selection: $customization.markdownTemplate.style
                )
            }
            labelledControl(String(localized: "Bullets")) {
                GlassSegmentedControl(
                    segments: MarkdownTemplateConfig.BulletStyle.allCases.map { .init(value: $0, title: $0.rawValue) },
                    selection: $customization.markdownTemplate.bulletStyle
                )
            }
            labelledControl(String(localized: "Heading level")) {
                GlassSegmentedControl(
                    segments: [1, 2, 3].map { .init(value: $0, title: "H\($0)") },
                    selection: $customization.markdownTemplate.sectionHeaderLevel
                )
            }
            GlassToggleRow(
                title: String(localized: "Summary line"),
                subtitle: String(localized: "Short overview under the title"),
                isOn: $customization.markdownTemplate.includeSummary
            )
            GlassToggleRow(
                title: String(localized: "Category emoji"),
                isOn: $customization.markdownTemplate.useEmoji
            )
        }
        // Custom template text, workout tables and the live preview stay in the existing editor.
        GlassPanel {
            NavigationLink {
                MarkdownTemplateView(config: $customization.markdownTemplate)
            } label: {
                GlassRow(title: String(localized: "Edit template")) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func labelledControl<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).glassFont(.body).foregroundStyle(palette.text)
            control()
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 12)
    }

    private func reset() {
        FormatCustomizationSnapshot.from(FormatCustomization()).apply(to: customization)
    }
}
#endif
