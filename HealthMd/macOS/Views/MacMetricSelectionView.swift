#if os(macOS)
import SwiftUI

// MARK: - Metric Selection (macOS) — Branded

struct MacMetricSelectionView: View {
    @ObservedObject var selectionState: MetricSelectionState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var expandedCategories: Set<HealthMetricCategory> = []
    @State private var showPendingApprovalAlert = false

    private var allEnabled: Bool {
        selectionState.totalEnabledCount == selectionState.totalMetricCount
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        BrandLabel("Health Metrics")
                        Text("\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics enabled · \(enabledCategoryCount) of \(availableCategoryCount) categories")
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    ProgressView(value: Double(selectionState.totalEnabledCount), total: Double(selectionState.totalMetricCount))
                        .frame(width: 100)
                        .tint(Color.accent)
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
                        .font(BrandTypography.body())
                }
                .toggleStyle(.switch)
                .tint(Color.accent)
            }
            .padding()

            Divider()
                .opacity(0.3)

            // Category list
            List {
                ForEach(filteredCategories, id: \.self) { category in
                    categorySection(for: category)
                }
            }
            .searchable(text: $searchText, prompt: "Search metrics…")

            Divider()
                .opacity(0.3)

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
                    .tint(Color.accent)
            }
            .padding()
        }
        .alert("Medication tracking pending", isPresented: $showPendingApprovalAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Medication tracking requires special permission from Apple. We've applied and are waiting for approval. We'll enable this metric automatically once it's granted.")
        }
    }

    // MARK: - Computed

    private var enabledCategoryCount: Int {
        HealthMetricCategory.allCases.filter { selectionState.isCategoryFullyEnabled($0) }.count
    }

    private var availableCategoryCount: Int {
        HealthMetricCategory.allCases.filter { !$0.isPendingAppleApproval }.count
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
        if category.isPendingAppleApproval {
            pendingCategoryRow(for: category)
        } else {
            standardCategorySection(for: category)
        }
    }

    @ViewBuilder
    private func pendingCategoryRow(for category: HealthMetricCategory) -> some View {
        Button {
            showPendingApprovalAlert = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .foregroundStyle(Color.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.rawValue)
                        .font(BrandTypography.bodyMedium())
                        .foregroundStyle(Color.textPrimary)
                    Text("Pending Apple permission")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }

                Spacer()

                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func standardCategorySection(for category: HealthMetricCategory) -> some View {
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
                    .foregroundStyle(Color.accent)
                    .frame(width: 20)

                Text(category.rawValue)
                    .font(BrandTypography.bodyMedium())

                Spacer()

                Text("\(selectionState.enabledMetricCount(for: category))/\(selectionState.totalMetricCount(for: category))")
                    .font(BrandTypography.value())
                    .foregroundStyle(Color.textMuted)

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
                    .foregroundStyle(Color.success)
            } else if selectionState.isCategoryPartiallyEnabled(category) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Color.warning)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(Color.textMuted)
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
                    .font(BrandTypography.body())
                if !metric.unit.isEmpty {
                    Text("(\(metric.unit))")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .toggleStyle(.checkbox)
        .tint(Color.accent)
        .padding(.leading, 8)
    }
}

#endif
