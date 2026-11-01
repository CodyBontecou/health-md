#if os(iOS)
import SwiftUI

/// DailyNoteG.
struct GlassDailyNoteScreen: View {
    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @State private var draft: ExportSettingsSnapshot

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        _draft = State(initialValue: profile.settings)
    }

    var body: some View {
        GlassSettingsSheet(
            title: String(localized: "Daily notes"),
            canSave: draft.hasFileDestinationOutput,
            onSave: { coordinator.saveSettings(draft, for: profile) }
        ) {
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Merge into daily notes"),
                    subtitle: String(localized: "Selected metrics go into each note’s frontmatter"),
                    isOn: $draft.dailyNoteInjection.enabled
                )
            }
            if draft.dailyNoteInjection.enabled {
                GlassSectionLabel(title: String(localized: "Location"))
                GlassPanel {
                    GlassTemplateField(title: String(localized: "Folder"), text: $draft.dailyNoteInjection.folderPath)
                    GlassTemplateField(
                        title: String(localized: "Filename"),
                        text: $draft.dailyNoteInjection.filenamePattern,
                        tokens: ["{date}", "{year}", "{month}", "{day}", "{weekday}"]
                    )
                    GlassPathPreview(paths: [notePath])
                }
                GlassSectionLabel(title: String(localized: "Content"))
                GlassPanel {
                    GlassToggleRow(
                        title: String(localized: "Add metric sections to body"),
                        subtitle: String(localized: "App-managed sections are replaced each export"),
                        isOn: $draft.dailyNoteInjection.injectMarkdownSections
                    )
                    GlassToggleRow(
                        title: String(localized: "Create note if missing"),
                        subtitle: String(localized: "Leave off if a plugin or template creates notes"),
                        isOn: $draft.dailyNoteInjection.createIfMissing
                    )
                    GlassToggleRow(
                        title: String(localized: "Daily Notes only"),
                        isOn: $draft.dailyNoteInjection.dailyNotesOnly
                    )
                }
            }
            if !draft.hasFileDestinationOutput {
                GlassBanner(
                    title: String(localized: "Select at least one export format, or enable Daily Notes Only."),
                    systemImage: "exclamationmark.triangle",
                    tone: .warning
                )
            }
        }
    }

    private var notePath: String {
        let settings = DailyNoteInjectionSettings()
        draft.dailyNoteInjection.apply(to: settings)
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        let folder = draft.dailyNoteInjection.folderPath
        let file = settings.formatFilename(for: date) + ".md"
        return folder.isEmpty ? file : "\(folder)/\(file)"
    }
}
#endif
