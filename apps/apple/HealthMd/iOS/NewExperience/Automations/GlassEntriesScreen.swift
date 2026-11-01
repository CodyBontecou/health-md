#if os(iOS)
import SwiftUI

/// EntriesG: one file per health event, for metrics enabled in this profile.
struct GlassEntriesScreen: View {
    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @State private var draft: ExportSettingsSnapshot

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        _draft = State(initialValue: profile.settings)
    }

    private var metrics: [HealthMetricDefinition] {
        let enabled = draft.metricSelection.enabledMetricIDs
        return HealthMetrics.availableInCurrentBuild.filter { enabled.contains($0.id) }
    }

    var body: some View {
        GlassSettingsSheet(
            title: String(localized: "Individual entries"),
            onSave: { coordinator.saveSettings(draft, for: profile) }
        ) {
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "One file per health event"),
                    subtitle: String(localized: "Workouts, symptoms, blood pressure, glucose, mood…"),
                    isOn: $draft.individualTracking.globalEnabled
                )
            }
            if draft.individualTracking.globalEnabled {
                GlassSectionLabel(title: String(localized: "Output"))
                GlassPanel {
                    GlassTemplateField(title: String(localized: "Folder"), text: $draft.individualTracking.entriesFolder)
                    GlassTemplateField(
                        title: String(localized: "Filename"),
                        text: $draft.individualTracking.filenameTemplate,
                        tokens: ["{date}", "{time}", "{metric}", "{category}"]
                    )
                    GlassToggleRow(
                        title: String(localized: "Group by category"),
                        isOn: $draft.individualTracking.useCategoryFolders
                    )
                }

                GlassSectionLabel(title: String(localized: "Track"))
                HStack(spacing: 8) {
                    GlassChip(title: String(localized: "Track all")) { setAll(true) }
                    GlassChip(title: String(localized: "Disable all")) { setAll(false) }
                }
                GlassPanel {
                    LazyVStack(spacing: 0) {
                        ForEach(metrics, id: \.id) { metric in
                            GlassToggleRow(title: metric.localizedDisplayName, isOn: binding(metric.id))
                        }
                    }
                }
                Text("Only metrics enabled in this profile appear.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
            }
        }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { draft.individualTracking.metricConfigs[id]?.trackIndividually ?? false },
            set: { draft.individualTracking.metricConfigs[id, default: MetricTrackingConfig()].trackIndividually = $0 }
        )
    }

    /// Track all covers this profile's metrics. Disable all clears every saved rule,
    /// as the existing screen does.
    private func setAll(_ isOn: Bool) {
        if isOn {
            metrics.forEach { binding($0.id).wrappedValue = true }
        } else {
            for id in draft.individualTracking.metricConfigs.keys {
                draft.individualTracking.metricConfigs[id]?.trackIndividually = false
            }
        }
    }
}
#endif
