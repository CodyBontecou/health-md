import SwiftUI

struct MetricSelectionView: View {
    @ObservedObject var selectionState: MetricSelectionState
    @State private var expandedCategories: Set<HealthMetricCategory> = []
    @State private var searchText = ""
    @State private var showPendingApprovalAlert = false

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
        .alert("Medication tracking pending", isPresented: $showPendingApprovalAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Medication tracking requires special permission from Apple. We've applied and are waiting for approval. We'll enable this metric automatically once it's granted.")
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("Select All") {
                        selectionState.selectAll()
                    }
                    Button("Deselect All") {
                        selectionState.deselectAll()
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
                }
            }
        }
    }

    private var allEnabled: Bool {
        selectionState.totalEnabledCount == selectionState.totalMetricCount
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

            // Enable All / Disable All toggle
            Toggle(isOn: Binding(
                get: { allEnabled },
                set: { newValue in
                    if newValue {
                        selectionState.selectAll()
                    } else {
                        selectionState.deselectAll()
                    }
                }
            )) {
                Text(allEnabled ? "All Metrics Enabled" : "Enable All Metrics")
                    .font(.subheadline)
            }
            .tint(.green)
            .accessibilityLabel(allEnabled ? "Disable all metrics" : "Enable all metrics")
            .accessibilityHint("Double tap to \(allEnabled ? "disable" : "enable") all health metrics")
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics enabled across \(enabledCategoryCount) of \(availableCategoryCount) categories")
    }

    private var searchBar: some View {
        HStack {
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
                }
                .accessibilityLabel("Clear search")
                .accessibilityHint("Double tap to clear search text")
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var filteredCategories: [HealthMetricCategory] {
        if searchText.isEmpty {
            return HealthMetricCategory.allCases
        }
        return HealthMetricCategory.allCases.filter { category in
            let metrics = HealthMetrics.byCategory[category] ?? []
            return metrics.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
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
                withAnimation(.easeInOut(duration: 0.2)) {
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
                        Text("\(enabledCount)/\(totalCount) enabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Category toggle
                    Button {
                        selectionState.toggleCategory(category)
                    } label: {
                        categoryToggleIcon(for: category)
                    }
                    .buttonStyle(.plain)
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

            // Expanded metrics
            if isExpanded {
                ForEach(metrics, id: \.id) { metric in
                    metricRow(for: metric)
                }
            }
        }
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

    @ViewBuilder
    private func categoryToggleIcon(for category: HealthMetricCategory) -> some View {
        if selectionState.isCategoryFullyEnabled(category) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else if selectionState.isCategoryPartiallyEnabled(category) {
            Image(systemName: "minus.circle.fill")
                .foregroundColor(.orange)
        } else {
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func metricRow(for metric: HealthMetricDefinition) -> some View {
        let isEnabled = selectionState.isMetricEnabled(metric.id)
        HStack {
            Toggle(isOn: Binding(
                get: { selectionState.isMetricEnabled(metric.id) },
                set: { _ in selectionState.toggleMetric(metric.id) }
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
            .accessibilityLabel(metric.unit.isEmpty ? metric.name : "\(metric.name), \(metric.unit)")
            .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
            .accessibilityHint("Double tap to \(isEnabled ? "disable" : "enable")")
        }
        .padding(.leading, 32)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MetricSelectionView(selectionState: MetricSelectionState())
    }
}
