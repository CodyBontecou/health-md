import SwiftUI

struct MetricSelectionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var selectionState: MetricSelectionState
    @ObservedObject var healthKitManager: HealthKitManager

    @State private var expandedCategories: Set<HealthMetricCategory> = []
    @State private var searchText = ""
    @State private var showPendingApprovalAlert = false
    @State private var showMedicationAuthorizationAlert = false
    @State private var showMedicationAuthorizationErrorAlert = false
    @State private var medicationAuthorizationError = ""
    @State private var isRequestingMedicationAuthorization = false
    @State private var pendingMedicationAction: MedicationSelectionAction?

    private enum MedicationSelectionAction {
        case category
        case metric(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary header
            summaryHeader

            // Search bar
            searchBar

            // Category list
            List {
                ForEach(filteredCategories, id: \.self) { category in
                    categorySection(for: category)
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Health Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Permission pending", isPresented: $showPendingApprovalAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This metric requires additional Apple permission before Health.md can export it.")
        }
        .alert("Choose medications to export", isPresented: $showMedicationAuthorizationAlert) {
            Button("Choose Medications") {
                let action = pendingMedicationAction
                Task { await requestMedicationAuthorizationAndApply(action) }
            }
            Button("Cancel", role: .cancel) {
                pendingMedicationAction = nil
            }
        } message: {
            Text("Apple treats medications differently from other Health data. You'll choose the individual medications Health.md may read, and exports will include only the medications you select.")
        }
        .alert("Medication access unavailable", isPresented: $showMedicationAuthorizationErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(medicationAuthorizationError)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Select All Standard Metrics") {
                        selectionState.selectAll()
                    }
                    Button("Deselect All") {
                        selectionState.deselectAll()
                    }
                    if healthKitManager.isMedicationAuthorizationSupported {
                        Divider()
                        Button(healthKitManager.isMedicationAuthorizationRequested ? "Change Medication Access" : "Choose Medications…") {
                            Task { await requestMedicationAuthorizationAndApply(nil) }
                        }
                    }
                    Divider()
                    Button("Expand All") {
                        expandedCategories = Set(HealthMetricCategory.allCases)
                    }
                    Button("Collapse All") {
                        expandedCategories.removeAll()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Metric actions")
                .accessibilityHint("Opens actions for selecting or expanding metric groups")
            }
        }
    }

    private var standardMetricIDs: [String] {
        HealthMetrics.all
            .filter { !$0.isPendingAppleApproval && !$0.category.requiresSeparateAuthorization }
            .map(\.id)
    }

    private var allStandardMetricsEnabled: Bool {
        standardMetricIDs.allSatisfy { selectionState.isMetricEnabled($0) }
    }

    private var summaryHeader: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics")
                        .font(.headline)
                    Text("\(enabledCategoryCount) of \(availableCategoryCount) categories")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Enabled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView(value: Double(selectionState.totalEnabledCount), total: Double(selectionState.totalMetricCount))
                        .frame(width: 100)
                        .tint(.green)
                }
            }

            // Enable All / Disable All toggle. Medications remain opt-in because
            // they require Apple's separate per-object selector.
            Toggle(isOn: Binding(
                get: { allStandardMetricsEnabled },
                set: { newValue in
                    if newValue {
                        selectionState.selectAll()
                    } else {
                        selectionState.deselectAll()
                    }
                }
            )) {
                Text(allStandardMetricsEnabled ? "All Standard Metrics Enabled" : "Enable Standard Metrics")
                    .font(.subheadline)
            }
            .tint(.green)
            .accessibilityLabel(allStandardMetricsEnabled ? "Disable all standard metrics" : "Enable all standard metrics")
            .accessibilityHint("Double tap to \(allStandardMetricsEnabled ? "disable" : "enable") standard health metrics. Medications require a separate permission step.")
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics enabled across \(enabledCategoryCount) of \(availableCategoryCount) categories")
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
            TextField("Search metrics...", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search metrics")
                .accessibilityHint("Type to filter metrics by name")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Clear search")
                .accessibilityHint("Double tap to clear search text")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var filteredCategories: [HealthMetricCategory] {
        if searchText.isEmpty {
            return HealthMetricCategory.allCases
        }
        return HealthMetricCategory.allCases.filter { category in
            let metrics = HealthMetrics.byCategory[category] ?? []
            return category.rawValue.localizedCaseInsensitiveContains(searchText)
                || metrics.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func filteredMetrics(for category: HealthMetricCategory) -> [HealthMetricDefinition] {
        let metrics = HealthMetrics.byCategory[category] ?? []
        if searchText.isEmpty {
            return metrics
        }
        return metrics.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var enabledCategoryCount: Int {
        HealthMetricCategory.allCases.filter { selectionState.isCategoryFullyEnabled($0) }.count
    }

    private var availableCategoryCount: Int {
        HealthMetricCategory.allCases.filter { !$0.isPendingAppleApproval }.count
    }

    @ViewBuilder
    private func categorySection(for category: HealthMetricCategory) -> some View {
        if category.isPendingAppleApproval {
            pendingCategorySection(for: category)
        } else {
            standardCategorySection(for: category)
        }
    }

    @ViewBuilder
    private func pendingCategorySection(for category: HealthMetricCategory) -> some View {
        Section {
            Button {
                showPendingApprovalAlert = true
            } label: {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(category.rawValue))
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Pending Apple permission")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(category.rawValue), pending Apple permission")
            .accessibilityHint("Double tap to learn more")
            .accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder
    private func standardCategorySection(for category: HealthMetricCategory) -> some View {
        let metrics = filteredMetrics(for: category)
        let isExpanded = expandedCategories.contains(category) || !searchText.isEmpty
        let enabledCount = selectionState.enabledMetricCount(for: category)
        let totalCount = selectionState.totalMetricCount(for: category)

        Section {
            // Category header row
            Button {
                withOptionalMotionAnimation {
                    if expandedCategories.contains(category) {
                        expandedCategories.remove(category)
                    } else {
                        expandedCategories.insert(category)
                    }
                }
            } label: {
                HStack {
                    Image(systemName: category.icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(category.rawValue))
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(categorySubtitle(for: category, enabledCount: enabledCount, totalCount: totalCount))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Category toggle
                    Button {
                        toggleCategory(category)
                    } label: {
                        categoryToggleIcon(for: category)
                    }
                    .buttonStyle(.plain)
                    .disabled(category == .medications && !healthKitManager.isMedicationAuthorizationSupported)
                    .accessibilityLabel("Toggle all \(category.rawValue) metrics")
                    .accessibilityValue(categoryToggleAccessibilityValue(for: category))
                    .accessibilityHint("Double tap to toggle all metrics in this category")

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(category.rawValue), \(enabledCount) of \(totalCount) metrics enabled")
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")
            .accessibilityAddTraits(.isButton)

            if category == .medications {
                medicationAuthorizationRow
            }

            // Expanded metrics
            if isExpanded {
                ForEach(metrics, id: \.id) { metric in
                    metricRow(for: metric)
                }
            }
        }
    }

    private func categorySubtitle(for category: HealthMetricCategory, enabledCount: Int, totalCount: Int) -> String {
        guard category == .medications else {
            return "\(enabledCount)/\(totalCount) enabled"
        }
        if !healthKitManager.isMedicationAuthorizationSupported {
            return "Requires iOS 26 or later"
        }
        if healthKitManager.isMedicationAuthorizationRequested {
            return "\(enabledCount)/\(totalCount) enabled · access selected"
        }
        return "Separate permission required"
    }

    private var medicationAuthorizationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: healthKitManager.isMedicationAuthorizationRequested ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .foregroundColor(healthKitManager.isMedicationAuthorizationRequested ? .green : .orange)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(medicationAuthorizationTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(medicationAuthorizationMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            if healthKitManager.isMedicationAuthorizationSupported {
                Button {
                    Task { await requestMedicationAuthorizationAndApply(nil) }
                } label: {
                    HStack(spacing: 8) {
                        if isRequestingMedicationAuthorization {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(healthKitManager.isMedicationAuthorizationRequested ? "Change Medication Access" : "Choose Medications")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isRequestingMedicationAuthorization)
                .accessibilityHint("Opens Apple's medication selector")
            }
        }
        .padding(.leading, 32)
        .padding(.vertical, 6)
    }

    private var medicationAuthorizationTitle: String {
        if !healthKitManager.isMedicationAuthorizationSupported {
            return "Medication export unavailable"
        }
        if healthKitManager.isMedicationAuthorizationRequested {
            return "Medication access selected"
        }
        return "Choose medications before exporting"
    }

    private var medicationAuthorizationMessage: String {
        if !healthKitManager.isMedicationAuthorizationSupported {
            return "Medication export requires iOS 26 or later. Other Health metrics can still be exported."
        }
        if healthKitManager.isMedicationAuthorizationRequested {
            return "Health.md exports only the medications you selected in Apple's permission sheet. You can reopen the selector anytime."
        }
        return "Medications use Apple's per-medication permission sheet instead of the standard Health access prompt."
    }

    private func categoryToggleAccessibilityValue(for category: HealthMetricCategory) -> String {
        if selectionState.isCategoryFullyEnabled(category) {
            return "All enabled"
        } else if selectionState.isCategoryPartiallyEnabled(category) {
            return "Partially enabled"
        } else {
            return "All disabled"
        }
    }

    private func withOptionalMotionAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeInOut(duration: 0.2), updates)
        }
    }

    @ViewBuilder
    private func categoryToggleIcon(for category: HealthMetricCategory) -> some View {
        if category == .medications && !healthKitManager.isMedicationAuthorizationSupported {
            Image(systemName: "lock.circle")
                .foregroundColor(.secondary)
        } else if selectionState.isCategoryFullyEnabled(category) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .accessibilityHidden(true)
        } else if selectionState.isCategoryPartiallyEnabled(category) {
            Image(systemName: "minus.circle.fill")
                .foregroundColor(.orange)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "circle")
                .foregroundColor(.secondary)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func metricRow(for metric: HealthMetricDefinition) -> some View {
        let isEnabled = selectionState.isMetricEnabled(metric.id)
        HStack {
            Toggle(isOn: Binding(
                get: { selectionState.isMetricEnabled(metric.id) },
                set: { _ in toggleMetric(metric) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(metric.name)
                        .font(.body)
                    if !metric.unit.isEmpty {
                        Text(metric.unit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint(.green)
            .disabled(metric.category == .medications && !healthKitManager.isMedicationAuthorizationSupported)
            .accessibilityLabel(metric.unit.isEmpty ? metric.name : "\(metric.name), \(metric.unit)")
            .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
            .accessibilityHint(metric.category == .medications && !healthKitManager.isMedicationAuthorizationRequested ? "Double tap to choose medications before enabling" : "Double tap to \(isEnabled ? "disable" : "enable")")
        }
        .padding(.leading, 32)
    }

    private func toggleCategory(_ category: HealthMetricCategory) {
        guard category == .medications else {
            selectionState.toggleCategory(category)
            return
        }

        if selectionState.isCategoryFullyEnabled(category) {
            selectionState.toggleCategory(category)
            return
        }

        guard healthKitManager.isMedicationAuthorizationSupported else {
            showMedicationUnsupportedError()
            return
        }

        guard healthKitManager.isMedicationAuthorizationRequested else {
            pendingMedicationAction = .category
            showMedicationAuthorizationAlert = true
            return
        }

        selectionState.toggleCategory(category)
    }

    private func toggleMetric(_ metric: HealthMetricDefinition) {
        guard metric.category == .medications else {
            selectionState.toggleMetric(metric.id)
            return
        }

        if selectionState.isMetricEnabled(metric.id) {
            selectionState.toggleMetric(metric.id)
            return
        }

        guard healthKitManager.isMedicationAuthorizationSupported else {
            showMedicationUnsupportedError()
            return
        }

        guard healthKitManager.isMedicationAuthorizationRequested else {
            pendingMedicationAction = .metric(metric.id)
            showMedicationAuthorizationAlert = true
            return
        }

        selectionState.toggleMetric(metric.id)
    }

    @MainActor
    private func requestMedicationAuthorizationAndApply(_ action: MedicationSelectionAction?) async {
        guard healthKitManager.isMedicationAuthorizationSupported else {
            showMedicationUnsupportedError()
            return
        }

        isRequestingMedicationAuthorization = true
        defer {
            isRequestingMedicationAuthorization = false
            pendingMedicationAction = nil
        }

        do {
            try await healthKitManager.requestMedicationAuthorization(force: true)
            if let action {
                applyMedicationSelection(action)
            }
        } catch {
            medicationAuthorizationError = error.localizedDescription
            showMedicationAuthorizationErrorAlert = true
        }
    }

    private func applyMedicationSelection(_ action: MedicationSelectionAction) {
        switch action {
        case .category:
            if !selectionState.isCategoryFullyEnabled(.medications) {
                selectionState.toggleCategory(.medications)
            }
        case .metric(let metricId):
            if !selectionState.isMetricEnabled(metricId) {
                selectionState.toggleMetric(metricId)
            }
        }
    }

    private func showMedicationUnsupportedError() {
        medicationAuthorizationError = "Medication export requires iOS 26 or later. You can still export all other Health metrics."
        showMedicationAuthorizationErrorAlert = true
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MetricSelectionView(
            selectionState: MetricSelectionState(),
            healthKitManager: HealthKitManager.shared
        )
    }
}
