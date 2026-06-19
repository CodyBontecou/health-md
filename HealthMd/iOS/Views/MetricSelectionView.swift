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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                summaryHeader
                searchBar
                categoryListHeader

                if filteredCategories.isEmpty {
                    emptySearchState
                } else {
                    LazyVStack(spacing: Spacing.s3) {
                        ForEach(filteredCategories, id: \.self) { category in
                            categorySection(for: category)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s4)
            .padding(.bottom, 132)
        }
        .background(Color.bgSecondary.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
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

    private var selectionProgress: Double {
        guard selectionState.totalMetricCount > 0 else { return 0 }
        return Double(selectionState.totalEnabledCount) / Double(selectionState.totalMetricCount)
    }

    private var selectionPercent: Int {
        Int((selectionProgress * 100).rounded())
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(alignment: .top, spacing: Spacing.s4) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("\(selectionState.totalEnabledCount)")
                        .font(Typography.displayMedium())
                        .foregroundStyle(Color.textPrimary)
                        .contentTransition(.numericText())

                    Text("of \(selectionState.totalMetricCount) metrics enabled")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: Spacing.s4)

                Text("\(selectionPercent)%")
                    .font(Typography.monoCaptionEmphasis())
                    .foregroundStyle(selectionPercent == 100 ? Color.success : Color.accent)
                    .geistPill(tint: selectionPercent == 100 ? Color.success : Color.accent)
                    .accessibilityLabel("\(selectionPercent) percent enabled")
            }

            ProgressView(value: selectionProgress)
                .progressViewStyle(.linear)
                .tint(selectionPercent == 100 ? Color.success : Color.accent)
                .accessibilityHidden(true)

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
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(allStandardMetricsEnabled ? "Standard metrics enabled" : "Enable standard metrics")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                    Text("Medications use a separate Apple permission step.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            }
            .tint(Color.success)
            .padding(Spacing.s3)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .accessibilityLabel(allStandardMetricsEnabled ? "Disable all standard metrics" : "Enable all standard metrics")
            .accessibilityHint("Double tap to \(allStandardMetricsEnabled ? "disable" : "enable") standard health metrics. Medications require a separate permission step.")
        }
        .geistCard(cornerRadius: GeistRadius.lg, padding: Spacing.s4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(selectionState.totalEnabledCount) of \(selectionState.totalMetricCount) metrics enabled across \(enabledCategoryCount) of \(availableCategoryCount) categories")
    }

    private var searchBar: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)

            TextField("Search metrics", text: $searchText)
                .textFieldStyle(.plain)
                .font(Typography.body())
                .submitLabel(.search)
                .accessibilityLabel("Search metrics")
                .accessibilityHint("Type to filter metrics by name or category")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityHint("Double tap to clear search text")
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    private var categoryListHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(searchText.isEmpty ? "Metric Categories" : "Search Results")
                .font(Typography.labelUppercase())
                .foregroundStyle(Color.textMuted)
                .tracking(1.2)

            Spacer()

            Text(searchText.isEmpty
                 ? "\(enabledCategoryCount)/\(availableCategoryCount) categories"
                 : "\(filteredCategories.count) groups")
                .font(Typography.caption())
                .foregroundStyle(Color.textMuted)
        }
        .padding(.top, Spacing.s1)
        .accessibilityElement(children: .combine)
    }

    private var emptySearchState: some View {
        VStack(spacing: Spacing.s3) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
            Text("No matching metrics")
                .font(Typography.headline())
                .foregroundStyle(Color.textPrimary)
            Text("Try a category like Sleep or a metric like Steps.")
                .font(Typography.caption())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.s8)
        .geistCard(cornerRadius: GeistRadius.lg, padding: 0)
        .accessibilityElement(children: .combine)
    }

    private var filteredCategories: [HealthMetricCategory] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty {
            return HealthMetricCategory.allCases
        }
        return HealthMetricCategory.allCases.filter { category in
            let metrics = HealthMetrics.byCategory[category] ?? []
            return category.rawValue.localizedCaseInsensitiveContains(trimmedSearch)
                || category.displayName.localizedCaseInsensitiveContains(trimmedSearch)
                || metrics.contains { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
        }
    }

    private func filteredMetrics(for category: HealthMetricCategory) -> [HealthMetricDefinition] {
        let metrics = HealthMetrics.byCategory[category] ?? []
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSearch.isEmpty || category.rawValue.localizedCaseInsensitiveContains(trimmedSearch) || category.displayName.localizedCaseInsensitiveContains(trimmedSearch) {
            return metrics
        }
        return metrics.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
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

    private func pendingCategorySection(for category: HealthMetricCategory) -> some View {
        Button {
            showPendingApprovalAlert = true
        } label: {
            HStack(spacing: Spacing.s3) {
                categoryIconBlock(for: category, tint: Color.textMuted)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(category.displayName)
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)
                    Text("Pending Apple permission")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.s4)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(category.rawValue), pending Apple permission")
        .accessibilityHint("Double tap to learn more")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func standardCategorySection(for category: HealthMetricCategory) -> some View {
        let metrics = filteredMetrics(for: category)
        let isExpanded = expandedCategories.contains(category) || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let enabledCount = selectionState.enabledMetricCount(for: category)
        let totalCount = selectionState.totalMetricCount(for: category)

        VStack(spacing: 0) {
            Button {
                toggleExpanded(category)
            } label: {
                HStack(spacing: Spacing.s3) {
                    categoryIconBlock(for: category, tint: categoryTint(for: category))

                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text(category.displayName)
                            .font(Typography.headline())
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text(categorySubtitle(for: category, enabledCount: enabledCount, totalCount: totalCount))
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.s2)

                    categoryStatusPill(for: category)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .accessibilityHidden(true)
                }
                .padding(Spacing.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(category.rawValue), \(enabledCount) of \(totalCount) metrics enabled")
            .accessibilityHint("Double tap anywhere on the category to \(isExpanded ? "collapse" : "expand")")
            .accessibilityAddTraits(.isButton)

            if category == .medications {
                rowDivider
                medicationAuthorizationRow
                    .padding(Spacing.s4)
            }

            if isExpanded {
                if !metrics.isEmpty {
                    rowDivider
                    VStack(spacing: 0) {
                        ForEach(metrics, id: \.id) { metric in
                            metricRow(for: metric)
                            if metric.id != metrics.last?.id {
                                rowDivider.padding(.leading, 64)
                            }
                        }
                    }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                } else if !searchText.isEmpty {
                    rowDivider
                    Text("No metrics in this category match your search.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.s4)
                }
            }
        }
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
    }

    private func toggleExpanded(_ category: HealthMetricCategory) {
        withOptionalMotionAnimation {
            if expandedCategories.contains(category) {
                expandedCategories.remove(category)
            } else {
                expandedCategories.insert(category)
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
    }

    private func categoryIconBlock(for category: HealthMetricCategory, tint: Color) -> some View {
        Image(systemName: category.icon)
            .font(.system(size: 15, weight: .semibold, design: .default))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.11))
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private func categoryToggleButton(for category: HealthMetricCategory) -> some View {
        let isUnavailable = category == .medications && !healthKitManager.isMedicationAuthorizationSupported

        return Button {
            toggleCategory(category)
        } label: {
            categoryStatusPill(for: category)
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .opacity(isUnavailable ? 0.55 : 1)
        .accessibilityLabel("Toggle all \(category.rawValue) metrics")
        .accessibilityValue(categoryToggleAccessibilityValue(for: category))
        .accessibilityHint("Double tap to toggle all metrics in this category")
    }

    private func categoryStatusPill(for category: HealthMetricCategory) -> some View {
        let tint = categoryStatusTint(for: category)
        let label = categoryStatusLabel(for: category)
        let icon = categoryStatusIcon(for: category)

        return HStack(spacing: Spacing.s1) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, 7)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
    }

    private func categoryStatusLabel(for category: HealthMetricCategory) -> String {
        if category == .medications && !healthKitManager.isMedicationAuthorizationSupported {
            return "Locked"
        }
        if selectionState.isCategoryFullyEnabled(category) {
            return "Enabled"
        }
        if selectionState.isCategoryPartiallyEnabled(category) {
            return "Partial"
        }
        if category == .medications && !healthKitManager.isMedicationAuthorizationRequested {
            return "Choose"
        }
        return "Off"
    }

    private func categoryStatusIcon(for category: HealthMetricCategory) -> String {
        if category == .medications && !healthKitManager.isMedicationAuthorizationSupported {
            return "lock.fill"
        }
        if selectionState.isCategoryFullyEnabled(category) {
            return "checkmark"
        }
        if selectionState.isCategoryPartiallyEnabled(category) {
            return "minus"
        }
        if category == .medications && !healthKitManager.isMedicationAuthorizationRequested {
            return "shield"
        }
        return "circle"
    }

    private func categoryStatusTint(for category: HealthMetricCategory) -> Color {
        if category == .medications && !healthKitManager.isMedicationAuthorizationSupported {
            return Color.textMuted
        }
        if selectionState.isCategoryFullyEnabled(category) {
            return Color.success
        }
        if selectionState.isCategoryPartiallyEnabled(category) {
            return Color.warning
        }
        if category == .medications && !healthKitManager.isMedicationAuthorizationRequested {
            return Color.accent
        }
        return Color.textMuted
    }

    private func categoryTint(for category: HealthMetricCategory) -> Color {
        if category == .medications && !healthKitManager.isMedicationAuthorizationSupported {
            return Color.textMuted
        }
        if selectionState.isCategoryFullyEnabled(category) {
            return Color.accent
        }
        if selectionState.isCategoryPartiallyEnabled(category) {
            return Color.warning
        }
        if category == .medications && !healthKitManager.isMedicationAuthorizationRequested {
            return Color.accent
        }
        return Color.textMuted
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
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: healthKitManager.isMedicationAuthorizationRequested ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(healthKitManager.isMedicationAuthorizationRequested ? Color.success : Color.warning)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(medicationAuthorizationTitle)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                    Text(medicationAuthorizationMessage)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.s2)
            }

            if healthKitManager.isMedicationAuthorizationSupported {
                Button {
                    Task { await requestMedicationAuthorizationAndApply(nil) }
                } label: {
                    HStack(spacing: Spacing.s2) {
                        if isRequestingMedicationAuthorization {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(healthKitManager.isMedicationAuthorizationRequested ? "Change access" : "Choose medications")
                            .font(Typography.label())
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                    .background(Color.accentSubtle, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.accent.opacity(0.22), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isRequestingMedicationAuthorization)
                .accessibilityHint("Opens Apple's medication selector")
            }
        }
        .padding(Spacing.s4)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
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
            withAnimation(AnimationTimings.standard, updates)
        }
    }

    @ViewBuilder
    private func metricRow(for metric: HealthMetricDefinition) -> some View {
        let isEnabled = selectionState.isMetricEnabled(metric.id)
        let isMedicationUnavailable = metric.category == .medications && !healthKitManager.isMedicationAuthorizationSupported

        HStack(spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(metric.name)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(isMedicationUnavailable ? Color.textMuted : Color.textPrimary)
                    .lineLimit(2)

                if !metric.unit.isEmpty {
                    Text(metric.unit)
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textMuted)
                }
            }

            Spacer(minLength: Spacing.s4)

            Toggle("", isOn: Binding(
                get: { selectionState.isMetricEnabled(metric.id) },
                set: { _ in toggleMetric(metric) }
            ))
            .labelsHidden()
            .tint(Color.success)
            .controlSize(.small)
            .disabled(isMedicationUnavailable)
            .accessibilityLabel(metric.unit.isEmpty ? metric.name : "\(metric.name), \(metric.unit)")
            .accessibilityValue(isEnabled ? "Enabled" : "Disabled")
            .accessibilityHint(metric.category == .medications && !healthKitManager.isMedicationAuthorizationRequested ? "Double tap to choose medications before enabling" : "Double tap to \(isEnabled ? "disable" : "enable")")
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .padding(.leading, 48)
        .contentShape(Rectangle())
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
