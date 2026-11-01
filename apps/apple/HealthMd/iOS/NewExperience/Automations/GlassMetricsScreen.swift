#if os(iOS)
import SwiftUI

/// MetricsG. Edits one profile's selection and saves through the same coordinator path as
/// the profile editor. Medications and Vision keep their permission flows in the
/// existing screen, which opens from "More options".
struct GlassMetricsScreen: View {
    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @StateObject private var state: MetricSelectionState
    @State private var expanded: Set<HealthMetricCategory> = []

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        let state = MetricSelectionState()
        profile.settings.metricSelection.apply(to: state)
        _state = StateObject(wrappedValue: state)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    Text(verbatim: "\(state.totalEnabledCount)")
                        .glassFont(.heroNumber)
                        .foregroundStyle(palette.text)
                    HStack(spacing: 8) {
                        GlassChip(title: String(localized: "Select All")) {
                            standardMetrics.forEach { state.setMetric($0.id, enabled: true) }
                        }
                        GlassChip(title: String(localized: "Deselect All")) { state.deselectAll() }
                    }
                    GlassPanel {
                        ForEach(standardCategories, id: \.self) { category in
                            categoryRow(category)
                        }
                    }
                    NavigationLink {
                        MetricSelectionView(selectionState: state, healthKitManager: HealthKitManager.shared)
                    } label: {
                        GlassPanel {
                            GlassRow(title: String(localized: "More options")) {
                                Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(GlassMetrics.screenMargin)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "Metrics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save"), action: save)
                }
            }
        }
        .accessibilityIdentifier("glass.metrics")
    }

    /// Same filter as the existing screen. Permission-gated metrics are never bulk-enabled.
    private var standardMetrics: [HealthMetricDefinition] {
        HealthMetrics.availableInCurrentBuild.filter {
            !$0.isPendingAppleApproval && !$0.category.requiresSeparateAuthorization
        }
    }

    private var standardCategories: [HealthMetricCategory] {
        HealthMetricCategory.allCases.filter { !$0.requiresSeparateAuthorization }
    }

    @ViewBuilder private func categoryRow(_ category: HealthMetricCategory) -> some View {
        let isExpanded = expanded.contains(category)
        Button {
            if isExpanded { expanded.remove(category) } else { expanded.insert(category) }
        } label: {
            GlassRow(title: category.displayName) {
                Text(verbatim: "\(state.enabledMetricCount(for: category))/\(state.totalMetricCount(for: category))")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(palette.muted)
            }
        }
        .buttonStyle(.plain)
        if isExpanded {
            ForEach(standardMetrics.filter { $0.category == category }, id: \.id) { metric in
                Toggle(isOn: Binding(
                    get: { state.isMetricEnabled(metric.id) },
                    set: { state.setMetric(metric.id, enabled: $0) }
                )) {
                    Text(metric.localizedDisplayName).glassFont(.body).foregroundStyle(palette.sec)
                }
                .toggleStyle(GlassToggleStyle())
                .padding(.horizontal, GlassMetrics.panelPadding)
            }
        }
    }

    private func save() {
        configurationProtection.performConfigurationChange {
            var settings = profile.settings
            settings.metricSelection = MetricSelectionSnapshot.from(state)
            _ = coordinator.updateProfile(
                id: profile.id,
                name: profile.name,
                target: profile.target,
                folderVaultID: profile.folderVaultID,
                apiEndpointID: profile.apiEndpointID,
                agentDataGatewayID: coordinator.destinationStore.agentDataGatewayBinding(profileID: profile.id),
                settings: settings
            )
            dismiss()
        }
    }
}
#endif
