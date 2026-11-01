#if os(iOS)
import SwiftUI

/// FormatCustomG. Edits a private copy of the profile's customization. Field-level
/// frontmatter editing and custom templates reuse the existing editors on that copy.
struct GlassFormatCustomScreen: View {
    private enum Section: Hashable { case frontmatter, body, units }

    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @StateObject private var customization: FormatCustomization
    @State private var section = Section.frontmatter

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        let customization = FormatCustomization()
        profile.settings.formatCustomization.apply(to: customization)
        _customization = StateObject(wrappedValue: customization)
    }

    var body: some View {
        GlassSettingsSheet(title: String(localized: "Customize format"), onSave: save) {
            GlassSegmentedControl(
                segments: [
                    .init(value: .frontmatter, title: String(localized: "Frontmatter")),
                    .init(value: .body, title: String(localized: "Markdown body")),
                    .init(value: .units, title: String(localized: "Dates & units"))
                ],
                selection: $section
            )
            switch section {
            case .frontmatter:
                GlassPanel {
                    NavigationLink {
                        FrontmatterCustomizationView(config: customization.frontmatterConfig)
                    } label: {
                        GlassRow(
                            title: String(localized: "Fields"),
                            subtitle: String(localized: "Tap a field to rename its key.")
                        ) {
                            Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            case .body:
                markdownBody
            case .units:
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
            Button(String(localized: "Reset"), role: .destructive, action: reset)
                .glassFont(.caption)
                .frame(minHeight: GlassMetrics.touchTarget)
        }
    }

    @ViewBuilder private var markdownBody: some View {
        GlassSectionLabel(title: String(localized: "Template"))
        GlassSegmentedControl(
            segments: MarkdownTemplateStyle.allCases.map { .init(value: $0, title: $0.displayName) },
            selection: $customization.markdownTemplate.style
        )
        GlassPanel {
            NavigationLink {
                MarkdownTemplateView(config: $customization.markdownTemplate)
            } label: {
                GlassRow(title: String(localized: "Edit template")) {
                    Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                }
            }
            .buttonStyle(.plain)
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
        GlassSectionLabel(title: String(localized: "Bullets"))
        GlassSegmentedControl(
            segments: MarkdownTemplateConfig.BulletStyle.allCases.map { .init(value: $0, title: $0.rawValue) },
            selection: $customization.markdownTemplate.bulletStyle
        )
        GlassSectionLabel(title: String(localized: "Heading level"))
        GlassSegmentedControl(
            segments: [1, 2, 3].map { .init(value: $0, title: "H\($0)") },
            selection: $customization.markdownTemplate.sectionHeaderLevel
        )
    }

    private func reset() {
        FormatCustomizationSnapshot.from(FormatCustomization()).apply(to: customization)
    }

    private func save() {
        var settings = profile.settings
        settings.formatCustomization = .from(customization)
        coordinator.saveSettings(settings, for: profile)
    }
}
#endif
