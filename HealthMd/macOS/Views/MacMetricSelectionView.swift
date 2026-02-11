#if os(macOS)
import SwiftUI

// MARK: - Metric Selection (macOS)

struct MacMetricSelectionView: View {
    @ObservedObject var selectionState: MetricSelectionState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var expandedCategories: Set<HealthMetricCategory> = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health Metrics")
                        .font(.headline)
                    Text("\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics enabled · \(enabledCategoryCount) of \(HealthMetricCategory.allCases.count) categories")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView(value: Double(selectionState.totalEnabledCount), total: Double(selectionState.totalMetricCount))
                    .frame(width: 100)
                    .tint(Color.accentColor)
            }
            .padding()

            Divider()

            // Category list
            List {
                ForEach(filteredCategories, id: \.self) { category in
                    categorySection(for: category)
                }
            }
            .searchable(text: $searchText, prompt: "Search metrics…")

            Divider()

            // Footer with actions
            HStack {
                Menu("Actions") {
                    Button("Select All") { selectionState.selectAll() }
                    Button("Deselect All") { selectionState.deselectAll() }
                    Divider()
                    Button("Expand All") { expandedCategories = Set(HealthMetricCategory.allCases) }
                    Button("Collapse All") { expandedCategories.removeAll() }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    // MARK: - Computed

    private var enabledCategoryCount: Int {
        HealthMetricCategory.allCases.filter { selectionState.isCategoryFullyEnabled($0) }.count
    }

    private var filteredCategories: [HealthMetricCategory] {
        if searchText.isEmpty { return HealthMetricCategory.allCases }
        return HealthMetricCategory.allCases.filter { category in
            let metrics = HealthMetrics.byCategory[category] ?? []
            return metrics.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
                || category.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func filteredMetrics(for category: HealthMetricCategory) -> [HealthMetricDefinition] {
        let metrics = HealthMetrics.byCategory[category] ?? []
        if searchText.isEmpty { return metrics }
        return metrics.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: - Sections

    @ViewBuilder
    private func categorySection(for category: HealthMetricCategory) -> some View {
        let metrics = filteredMetrics(for: category)
        let isExpanded = expandedCategories.contains(category) || !searchText.isEmpty

        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { newVal in
                if newVal { expandedCategories.insert(category) }
                else { expandedCategories.remove(category) }
            }
        )) {
            ForEach(metrics, id: \.id) { metric in
                metricRow(for: metric)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)

                Text(category.rawValue)
                    .fontWeight(.medium)

                Spacer()

                Text("\(selectionState.enabledMetricCount(for: category))/\(selectionState.totalMetricCount(for: category))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                categoryToggle(for: category)
            }
        }
    }

    @ViewBuilder
    private func categoryToggle(for category: HealthMetricCategory) -> some View {
        Button {
            selectionState.toggleCategory(category)
        } label: {
            if selectionState.isCategoryFullyEnabled(category) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if selectionState.isCategoryPartiallyEnabled(category) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func metricRow(for metric: HealthMetricDefinition) -> some View {
        Toggle(isOn: Binding(
            get: { selectionState.isMetricEnabled(metric.id) },
            set: { _ in selectionState.toggleMetric(metric.id) }
        )) {
            HStack {
                Text(metric.name)
                if !metric.unit.isEmpty {
                    Text("(\(metric.unit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.leading, 8)
    }
}

#endif
