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
        GlassSettingsPage(title: String(localized: "Daily notes")) {
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Merge into daily notes"),
                    subtitle: String(localized: "Selected metrics go into each note’s frontmatter"),
                    isOn: mergeEnabled
                )
                .accessibilityIdentifier("glass.dailyNotes.merge")
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
                    // Daily note paths always resolve from the destination's root, never the
                    // Health subfolder, so this is a fact rather than a choice.
                    GlassRow(title: String(localized: "Relative to")) {
                        Text("Vault root").font(.system(size: 15)).foregroundStyle(palette.muted)
                    }
                }
                (Text("Writes to") + Text(verbatim: " ")
                    + Text(verbatim: notePath).font(.system(size: 13, design: .monospaced)).foregroundColor(palette.accent))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 20)
                    .accessibilityElement(children: .combine)

                GlassSectionLabel(title: String(localized: "Content"))
                GlassPanel {
                    // Injection writes this profile's selected metrics; there is no separate list.
                    GlassRow(title: String(localized: "Metrics")) {
                        Text("Same as profile").font(.system(size: 15)).foregroundStyle(palette.muted)
                    }
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
        .glassAutosave(
            draft,
            isValid: draft.hasFileDestinationOutput,
            invalidReason: String(localized: "Select at least one export format, or enable Daily Notes Only."),
            revert: { draft = $0 },
            save: { coordinator.saveSettings($0, for: profile) }
        )
    }

    /// Daily notes only now lives on the Formats page; turning merging off here also
    /// clears it so it cannot silently return when merging is turned back on.
    private var mergeEnabled: Binding<Bool> {
        Binding(
            get: { draft.dailyNoteInjection.enabled },
            set: { isOn in
                draft.dailyNoteInjection.enabled = isOn
                if !isOn { draft.dailyNoteInjection.dailyNotesOnly = false }
            }
        )
    }

    /// Yesterday's note, from the exporter's own path planner.
    private var notePath: String {
        let settings = DailyNoteInjectionSettings()
        draft.dailyNoteInjection.apply(to: settings)
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return settings.previewPath(for: date)
    }
}
#endif
