#if os(iOS)
import SwiftUI

/// MetricsG. A pushed page that saves one profile's selection as it changes, through the
/// same coordinator path as the profile editor; Done returns. Medications and vision prescriptions use Apple's per-object
/// selectors, requested from their own rows under Extra permissions.
struct GlassMetricsScreen: View {
    private enum PermissionKind { case medications, vision }

    let coordinator: ExportProfileCoordinator
    let profile: ExportProfile

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var state: MetricSelectionState
    @State private var expanded: Set<HealthMetricCategory> = []
    @State private var query = ""
    @State private var showMedicationExplanation = false
    @State private var permissionError: (title: String, message: String)?
    @State private var requestingPermission: PermissionKind?

    init(coordinator: ExportProfileCoordinator, profile: ExportProfile) {
        self.coordinator = coordinator
        self.profile = profile
        let state = MetricSelectionState()
        profile.settings.metricSelection.apply(to: state)
        _state = StateObject(wrappedValue: state)
    }

    var body: some View {
        page
            .glassAutosave(
                MetricSelectionSnapshot.from(state),
                revert: { $0.apply(to: state) },
                save: { value in coordinator.saveSettings(for: profile) { $0.metricSelection = value } }
            )
            .accessibilityIdentifier("glass.metrics")
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                summary
                searchField
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        GlassChip(title: String(localized: "Recommended")) {
                            state.deselectAll()
                            standardMetrics
                                .filter { Self.recommendedCategories.contains($0.category) }
                                .forEach { state.setMetric($0.id, enabled: true) }
                        }
                        GlassChip(title: String(localized: "Select all")) {
                            standardMetrics.forEach { state.setMetric($0.id, enabled: true) }
                        }
                        GlassChip(title: String(localized: "Select none")) { state.deselectAll() }
                    }
                }
                GlassPanel {
                    if query.isEmpty {
                        ForEach(standardCategories, id: \.self) { category in
                            categoryRow(category)
                        }
                    } else {
                        ForEach(searchResults, id: \.id) { metricToggle($0) }
                    }
                }
                GlassSectionLabel(title: String(localized: "Extra permissions"))
                GlassPanel {
                    permissionRow(.medications)
                    permissionRow(.vision)
                    ForEach(otherSeparateCategories, id: \.self) { categoryRow($0) }
                }
            }
            .padding(GlassMetrics.screenMargin)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Metrics"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Done")) { dismiss() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("glass.metrics.done")
            }
        }
        .alert(
            String(localized: "Choose medications to export"),
            isPresented: $showMedicationExplanation
        ) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Choose Medications")) {
                Task { await request(.medications) }
            }
        } message: {
            Text("Apple treats medications differently from other Health data. You'll choose the individual medications Health.md may read, and exports will include only the medications you select.")
        }
        .alert(
            permissionError?.title ?? "",
            isPresented: Binding(
                get: { permissionError != nil },
                set: { if !$0 { permissionError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(permissionError?.message ?? "")
        }
    }

    // MARK: - Summary and search

    private var summary: some View {
        let total = state.totalMetricCount
        let enabled = state.totalEnabledCount
        return HStack(spacing: 12) {
            Text(verbatim: "\(enabled)")
                .font(.system(size: 40, weight: .bold))
                .tracking(-1.5)
                .foregroundStyle(palette.text)
            VStack(alignment: .leading, spacing: 6) {
                Text("of \(total) metrics in this profile")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.sec)
                GeometryReader { proxy in
                    Capsule().fill(palette.track)
                        .overlay(alignment: .leading) {
                            Capsule().fill(palette.accent)
                                .frame(width: proxy.size.width * Self.fraction(enabled, of: total))
                        }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }

    private static func fraction(_ enabled: Int, of total: Int) -> CGFloat {
        guard total > 0 else { return 0 }
        return min(1, CGFloat(enabled) / CGFloat(total))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.muted)
                .accessibilityHidden(true)
            TextField(String(localized: "Search, e.g. Sleep or Steps"), text: $query)
                .textFieldStyle(.plain)
                .glassFont(.body)
                .foregroundStyle(palette.text)
                .autocorrectionDisabled()
                .accessibilityLabel(String(localized: "Search metrics"))
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .frame(minHeight: GlassMetrics.touchTarget)
        .glassSurface(cornerRadius: GlassMetrics.touchTarget / 2)
    }

    // MARK: - Categories

    /// The core archive. Never includes categories that need a separate Apple permission,
    /// because `standardMetrics` already excludes them.
    private static let recommendedCategories: Set<HealthMetricCategory> = [
        .sleep, .activity, .heart, .vitals, .bodyMeasurements, .workouts
    ]

    /// Same filter as the existing screen. Permission-gated metrics are never bulk-enabled.
    private var standardMetrics: [HealthMetricDefinition] {
        HealthMetrics.availableInCurrentBuild.filter {
            !$0.isPendingAppleApproval && !$0.category.requiresSeparateAuthorization
        }
    }

    private var standardCategories: [HealthMetricCategory] {
        HealthMetricCategory.availableCases.filter { !$0.requiresSeparateAuthorization }
    }

    /// Separate-permission categories without their own Apple selector row (clinical
    /// documents, when this build includes them) keep a plain category row.
    private var otherSeparateCategories: [HealthMetricCategory] {
        HealthMetricCategory.availableCases.filter {
            $0.requiresSeparateAuthorization && $0 != .medications && $0 != .vision
        }
    }

    private func metrics(in category: HealthMetricCategory) -> [HealthMetricDefinition] {
        HealthMetrics.availableInCurrentBuild.filter { $0.category == category && !$0.isPendingAppleApproval }
    }

    private func countText(_ category: HealthMetricCategory) -> String {
        String(localized: "\(state.enabledMetricCount(for: category)) of \(state.totalMetricCount(for: category))")
    }

    @ViewBuilder private func categoryRow(_ category: HealthMetricCategory) -> some View {
        let isExpanded = expanded.contains(category)
        HStack(spacing: 0) {
            // Separate-permission categories keep their Apple selector flow; only
            // standard categories get the bulk toggle.
            if !category.requiresSeparateAuthorization {
                categoryToggle(category)
                    .padding(.leading, GlassMetrics.panelPadding - 10)
            }
            Button {
                toggleExpanded(category)
            } label: {
                GlassRow(title: category.displayName) {
                    Text(verbatim: countText(category))
                        .font(.system(size: 15))
                        .foregroundStyle(palette.muted)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isExpanded ? .isSelected : [])
        }
        if isExpanded {
            ForEach(metrics(in: category), id: \.id) { metricToggle($0) }
        }
    }

    /// Checkbox that turns every metric in a category on or off, separate from the
    /// row's expand action so the two never share a hit target.
    private func categoryToggle(_ category: HealthMetricCategory) -> some View {
        let isFull = state.isCategoryFullyEnabled(category)
        let isPartial = state.isCategoryPartiallyEnabled(category)
        return Button {
            state.toggleCategory(category)
        } label: {
            Image(systemName: isFull ? "checkmark.square.fill" : (isPartial ? "minus.square.fill" : "square"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isFull || isPartial ? palette.text : palette.muted)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("glass.metrics.categoryToggle.\(category.rawValue)")
        .accessibilityLabel("Toggle all \(category.displayName) metrics")
        .accessibilityValue(isFull
            ? String(localized: "All enabled")
            : (isPartial ? String(localized: "Partially enabled") : String(localized: "All disabled")))
        .accessibilityHint("Double tap to toggle all metrics in this category")
    }

    private func toggleExpanded(_ category: HealthMetricCategory) {
        if expanded.contains(category) { expanded.remove(category) } else { expanded.insert(category) }
    }

    private var searchResults: [HealthMetricDefinition] {
        standardMetrics.filter { $0.localizedDisplayName.localizedCaseInsensitiveContains(query) }
    }

    private func metricToggle(_ metric: HealthMetricDefinition) -> some View {
        Toggle(isOn: Binding(
            get: { state.isMetricEnabled(metric.id) },
            set: { state.setMetric(metric.id, enabled: $0) }
        )) {
            Text(metric.localizedDisplayName).glassFont(.body).foregroundStyle(palette.sec)
        }
        .toggleStyle(GlassToggleStyle())
        .disabled(!metric.availability.isAvailableOnCurrentPlatform)
        .padding(.horizontal, GlassMetrics.panelPadding)
    }

    // MARK: - Extra permissions

    private func permissionCategory(_ kind: PermissionKind) -> HealthMetricCategory {
        kind == .medications ? .medications : .vision
    }

    private func isSupported(_ kind: PermissionKind) -> Bool {
        kind == .medications
            ? healthKitManager.isMedicationAuthorizationSupported
            : healthKitManager.isVisionAuthorizationSupported
    }

    private func isRequested(_ kind: PermissionKind) -> Bool {
        kind == .medications
            ? healthKitManager.isMedicationAuthorizationRequested
            : healthKitManager.isVisionAuthorizationRequested
    }

    @ViewBuilder private func permissionRow(_ kind: PermissionKind) -> some View {
        let category = permissionCategory(kind)
        let isExpanded = expanded.contains(category) && isRequested(kind)
        let title = kind == .medications
            ? category.displayName
            : String(localized: "Vision prescriptions")
        let subtitle = kind == .medications
            ? String(localized: "Separate Apple permission — you pick each medication")
            : String(localized: "Needs its own Apple permission")
        let action = isRequested(kind)
            ? String(localized: "Change access")
            : (kind == .medications ? String(localized: "Choose") : String(localized: "Allow"))

        HStack(spacing: 12) {
            Button {
                if isRequested(kind) { toggleExpanded(category) } else { startRequest(kind) }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).glassFont(.body).foregroundStyle(palette.text)
                        Text(subtitle).glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                    }
                    Spacer(minLength: 8)
                    if isRequested(kind) {
                        Text(verbatim: countText(category))
                            .font(.system(size: 15))
                            .foregroundStyle(palette.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                startRequest(kind)
            } label: {
                Group {
                    if requestingPermission == kind {
                        ProgressView().controlSize(.mini)
                    } else {
                        Text(action)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(palette.surface2))
                .frame(minHeight: GlassMetrics.touchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(requestingPermission != nil)
            .accessibilityLabel(Text(verbatim: "\(action), \(title)"))

            if isRequested(kind) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .frame(minHeight: GlassMetrics.rowWithSubtitleMinHeight)
        .opacity(isSupported(kind) ? 1 : 0.55)
        if isExpanded {
            ForEach(metrics(in: category), id: \.id) { metricToggle($0) }
        }
    }

    private func startRequest(_ kind: PermissionKind) {
        guard isSupported(kind) else {
            permissionError = kind == .medications
                ? (String(localized: "Medication access unavailable"),
                   String(localized: "Medication export requires iOS 26 or later. Other Health metrics can still be exported."))
                : (String(localized: "Vision prescription access unavailable"),
                   String(localized: "Vision prescription access requires a supported iOS runtime."))
            return
        }
        if kind == .medications && !healthKitManager.isMedicationAuthorizationRequested {
            showMedicationExplanation = true
        } else {
            Task { await request(kind) }
        }
    }

    /// Opens Apple's selector, then turns the category on when nothing in it was selected,
    /// matching the existing screen's category action.
    @MainActor
    private func request(_ kind: PermissionKind) async {
        requestingPermission = kind
        defer { requestingPermission = nil }
        do {
            if kind == .medications {
                try await healthKitManager.requestMedicationAuthorization(force: true)
            } else {
                try await healthKitManager.requestVisionPrescriptionAuthorization(force: true)
            }
            let category = permissionCategory(kind)
            if state.enabledMetricCount(for: category) == 0 {
                state.toggleCategory(category)
            }
            expanded.insert(category)
        } catch {
            if kind == .medications {
                permissionError = (String(localized: "Medication access unavailable"), error.localizedDescription)
            } else {
                let nsError = error as NSError
                permissionError = (
                    String(localized: "Vision prescription access unavailable"),
                    String(localized: "Apple's vision prescription selector did not complete (\(nsError.domain), code \(nsError.code)).")
                )
            }
        }
    }
}
#endif
