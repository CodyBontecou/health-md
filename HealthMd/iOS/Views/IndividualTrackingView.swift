//
//  IndividualTrackingView.swift
//  Health.md
//
//  Settings UI for configuring individual timestamped entry exports.
//

import SwiftUI

struct IndividualTrackingView: View {
    @ObservedObject var settings: IndividualTrackingSettings
    @ObservedObject var metricSelection: MetricSelectionState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var expandedCategories: Set<HealthMetricCategory> = []

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                enableCard

                if settings.globalEnabled {
                    if settings.totalEnabledCount == 0 {
                        noMetricsCallout
                    }
                    quickActionsCard
                    metricSelectionCard
                    outputSettingsCard
                    previewCard
                } else {
                    disabledStateCard
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle("Individual Tracking")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "doc.on.doc")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.accent.opacity(0.12)))
                .overlay(Circle().strokeBorder(Color.accent.opacity(0.22), lineWidth: 1))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Text("Individual Entries")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textMuted)

                    IndividualTrackingStatePill(
                        title: headerStateTitle,
                        color: headerStateColor
                    )
                }

                Text("Create One File Per Health Event")
                    .font(Typography.bodyLarge().weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Track workouts, symptoms, blood pressure, glucose, mood, and other events as timestamped Markdown entries.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Individual Entry Tracking, \(headerStateTitle)")
    }

    private var headerStateTitle: String {
        guard settings.globalEnabled else { return "Disabled" }
        guard settings.totalEnabledCount > 0 else { return "Needs Metrics" }
        return "\(settings.totalEnabledCount) Tracked"
    }

    private var headerStateColor: Color {
        guard settings.globalEnabled else { return Color.textMuted }
        guard settings.totalEnabledCount > 0 else { return Color.warning }
        return Color.accent
    }

    // MARK: - Enablement

    private var enableCard: some View {
        card {
            Toggle(isOn: $settings.globalEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Individual Entry Tracking")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Creates separate timestamped Markdown files for selected health events in addition to your normal daily export.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.accent)
            .accessibilityLabel("Enable individual entry tracking")
            .accessibilityValue(settings.globalEnabled ? "Enabled" : "Disabled")
            .accessibilityHint("Double tap to \(settings.globalEnabled ? "disable" : "enable") individual entry tracking")
        }
    }

    private var disabledStateCard: some View {
        calloutCard(
            icon: "pause.circle",
            title: "Individual Entries Disabled",
            message: "Turn this on to create one timestamped Markdown file per selected event when you run an export.",
            color: Color.textMuted
        )
    }

    private var noMetricsCallout: some View {
        calloutCard(
            icon: "exclamationmark.circle.fill",
            title: "Choose Metrics To Track",
            message: "Individual tracking is enabled, but no metrics are selected below. Pick at least one metric to create entry files.",
            color: Color.warning
        )
    }

    // MARK: - Quick Actions

    private var quickActionsCard: some View {
        sectionGroup(title: "Quick Actions") {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Toggle(isOn: Binding(
                    get: { tracksAllEnabledMetrics },
                    set: { setTracksAllEnabledMetrics($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tracksAllEnabledMetrics ? "All Enabled Metrics Tracked" : "Track All Enabled Metrics")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(quickActionToggleSubtitle)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Color.accent)
                .disabled(individualTrackableMetrics.isEmpty)
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .accessibilityLabel("Track all enabled metrics")
                .accessibilityValue(tracksAllEnabledMetrics ? "All tracked" : "Not all tracked")
                .accessibilityHint(individualTrackableMetrics.isEmpty ? "Enable metrics in Health Metrics first." : "Double tap to \(tracksAllEnabledMetrics ? "disable all individual tracking" : "track all enabled metrics individually").")

                quickActionButton(
                    title: "Disable All",
                    icon: "xmark.circle",
                    color: Color.error,
                    accessibilityHint: "Disables individual tracking for every metric."
                ) {
                    settings.disableAll()
                }
                .disabled(settings.totalEnabledCount == 0)
                .opacity(settings.totalEnabledCount == 0 ? 0.55 : 1)
            }
        }
    }

    private func quickActionButton(
        title: String,
        icon: String,
        color: Color,
        accessibilityHint: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Metric Selection

    private var metricSelectionCard: some View {
        let categories = categoriesWithEnabledMetrics

        return sectionGroup(
            title: "Per-Metric Tracking",
            badge: settings.totalEnabledCount == 0 ? "No Metrics" : "\(settings.totalEnabledCount) Tracked"
        ) {
            if categories.isEmpty {
                emptyMetricsState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(categories.enumerated()), id: \.element) { index, category in
                        CategoryTrackingRow(
                            category: category,
                            settings: settings,
                            metricSelection: metricSelection,
                            isExpanded: expandedCategories.contains(category),
                            onToggleExpand: { toggleCategory(category) }
                        )

                        if index < categories.count - 1 {
                            rowDivider
                        }
                    }
                }
            }
        }
    }

    private var emptyMetricsState: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.textMuted.opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("No Export Metrics Enabled")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Only metrics enabled in Export Settings → Health Metrics appear here.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Output Settings

    private var outputSettingsCard: some View {
        sectionGroup(title: "Output Settings") {
            VStack(spacing: 0) {
                textFieldRow(
                    title: "Entries Folder",
                    placeholder: "entries",
                    text: $settings.entriesFolder,
                    helper: "Folder for timestamped entry files.",
                    accessibilityLabel: "Entries folder",
                    accessibilityHint: "Enter the folder path for individual entry files."
                )

                rowDivider

                toggleRow(
                    title: "Organize By Category",
                    subtitle: "Creates category subfolders inside the entries folder.",
                    isOn: $settings.useCategoryFolders,
                    accessibilityLabel: "Organize individual entries by category"
                )

                rowDivider

                textFieldRow(
                    title: "Filename Template",
                    placeholder: "{date}_{time}_{metric}",
                    text: $settings.filenameTemplate,
                    helper: "Supports {date}, {time}, {metric}, and {category}.",
                    accessibilityLabel: "Filename template",
                    accessibilityHint: "Enter the filename template for individual entry files."
                )

                rowDivider

                previewRow(
                    icon: "folder",
                    title: "Folder Preview",
                    value: folderStructurePreview
                )

                rowDivider

                previewRow(
                    icon: "doc.text",
                    title: "Filename Example",
                    value: filenamePreview
                )
            }
        }
    }

    private var previewCard: some View {
        sectionGroup(title: "Entry Preview") {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "curlybraces")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)
                    Text("Example Frontmatter")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }

                Text(entryPreview)
                    .font(.caption.monospaced())
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.bgSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.borderSubtle, lineWidth: 1)
                    )
                    .accessibilityLabel("Example individual entry frontmatter")
                    .accessibilityValue(entryPreview)
            }
        }
    }

    // MARK: - Row Helpers

    @ViewBuilder
    private func textFieldRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        helper: String,
        accessibilityLabel: String,
        accessibilityHint: String
    ) -> some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                fieldLabel(title: title, helper: helper)
                fieldTextField(placeholder: placeholder, text: text, accessibilityLabel: accessibilityLabel, accessibilityHint: accessibilityHint)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
                fieldLabel(title: title, helper: helper)
                Spacer(minLength: Spacing.md)
                fieldTextField(placeholder: placeholder, text: text, accessibilityLabel: accessibilityLabel, accessibilityHint: accessibilityHint)
                    .frame(maxWidth: 220)
            }
        }
    }

    private func fieldLabel(title: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text(helper)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldTextField(
        placeholder: String,
        text: Binding<String>,
        accessibilityLabel: String,
        accessibilityHint: String
    ) -> some View {
        TextField(placeholder, text: text)
            .font(.footnote.monospaced())
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(usesAccessibilityLayout ? .leading : .trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(accessibilityHint)
    }

    private func toggleRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        accessibilityLabel: String
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Color.accent)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn.wrappedValue ? "Enabled" : "Disabled")
    }

    private func previewRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accent.opacity(0.12)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(value)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    // MARK: - Card Helpers

    private func sectionGroup<Content: View>(
        title: String,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                sectionLabel(title)
                Spacer()
                if let badge {
                    IndividualTrackingStatePill(
                        title: badge,
                        color: badge == "No Metrics" ? Color.warning : Color.accent
                    )
                }
            }

            card(content: content)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.textMuted)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    private func calloutCard(icon: String, title: String, message: String, color: Color) -> some View {
        card {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(color.opacity(0.12)))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
            .padding(.vertical, Spacing.md)
    }

    // MARK: - Computed Properties

    /// Categories that have at least one enabled metric in export settings
    private var categoriesWithEnabledMetrics: [HealthMetricCategory] {
        HealthMetricCategory.allCases.filter { category in
            metricSelection.enabledMetricCount(for: category) > 0
        }
    }

    /// Metrics eligible for individual tracking based on the Health Metrics selection.
    private var individualTrackableMetrics: [HealthMetricDefinition] {
        HealthMetrics.all.filter { metricSelection.isMetricEnabled($0.id) }
    }

    private var enabledTrackableMetricCount: Int {
        individualTrackableMetrics.filter { settings.shouldTrackIndividually($0.id) }.count
    }

    private var tracksAllEnabledMetrics: Bool {
        guard !individualTrackableMetrics.isEmpty else { return false }
        return enabledTrackableMetricCount == individualTrackableMetrics.count
    }

    private var quickActionToggleSubtitle: String {
        let total = individualTrackableMetrics.count
        guard total > 0 else {
            return "Enable metrics in Health Metrics before choosing individual entries."
        }

        let noun = total == 1 ? "metric" : "metrics"
        if tracksAllEnabledMetrics {
            return "Switch off to disable individual tracking for all enabled Health Metrics."
        }
        if enabledTrackableMetricCount == 0 {
            return "Tracks all \(total) \(noun) currently enabled in Health Metrics."
        }
        return "\(enabledTrackableMetricCount) of \(total) enabled \(noun) are currently tracked."
    }

    private func setTracksAllEnabledMetrics(_ shouldTrack: Bool) {
        settings.disableAll()

        guard shouldTrack else { return }
        for metric in individualTrackableMetrics {
            settings.setTrackIndividually(metric.id, enabled: true)
        }
    }

    private func toggleCategory(_ category: HealthMetricCategory) {
        if expandedCategories.contains(category) {
            expandedCategories.remove(category)
        } else {
            expandedCategories.insert(category)
        }
    }

    private var folderStructurePreview: String {
        if settings.useCategoryFolders {
            let enabledCategories = HealthMetricCategory.allCases.filter { category in
                settings.enabledCount(for: category) > 0
            }

            if enabledCategories.isEmpty {
                return "\(settings.entriesFolder)/\n  No metrics selected"
            }

            var preview = "\(settings.entriesFolder)/"
            for category in enabledCategories {
                let folderName = category.rawValue
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                preview += "\n  \(folderName)/"
            }
            return preview
        } else {
            return "\(settings.entriesFolder)/"
        }
    }

    private var filenamePreview: String {
        let sampleMetric: HealthMetricDefinition

        if let enabledMetricId = settings.metricConfigs.first(where: { $0.value.trackIndividually })?.key,
           let metric = HealthMetrics.all.first(where: { $0.id == enabledMetricId }) {
            sampleMetric = metric
        } else {
            sampleMetric = HealthMetricDefinition(
                id: "daily_mood",
                name: "Daily Mood",
                category: .mindfulness,
                unit: "",
                healthKitIdentifier: nil,
                metricType: .category,
                aggregation: .mostRecent
            )
        }
        return settings.filename(for: sampleMetric, date: Date(), time: Date())
    }

    private var entryPreview: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())

        dateFormatter.dateFormat = "HH:mm"
        let timeStr = dateFormatter.string(from: Date())

        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let datetimeStr = dateFormatter.string(from: Date())

        return """
        ---
        date: \(dateStr)
        time: "\(timeStr)"
        datetime: \(datetimeStr)
        type: mindfulness
        metric: daily_mood
        valence: 0.7
        feeling: pleasant
        labels:
          - happy
          - calm
        ---
        """
    }
}

// MARK: - Category Row Component

struct CategoryTrackingRow: View {
    let category: HealthMetricCategory
    @ObservedObject var settings: IndividualTrackingSettings
    @ObservedObject var metricSelection: MetricSelectionState
    let isExpanded: Bool
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: category.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.accent.opacity(0.12)))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(category.rawValue))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)

                        Text("\(enabledCount) of \(enabledMetricsInCategory.count) tracked")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: Spacing.sm)

                    IndividualTrackingStatePill(title: categoryStateTitle, color: categoryStateColor)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, Spacing.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(category.rawValue), \(enabledCount) of \(enabledMetricsInCategory.count) individual metrics tracked")
            .accessibilityValue(categoryStateTitle)
            .accessibilityHint("Double tap to \(isExpanded ? "collapse" : "expand")")

            if isExpanded {
                metricsList
                    .padding(.top, Spacing.sm)
                    .padding(.leading, 44)
            }
        }
    }

    private var metricsList: some View {
        let metrics = enabledMetricsInCategory

        return VStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                MetricTrackingRow(metric: metric, settings: settings)

                if index < metrics.count - 1 {
                    rowDivider
                        .padding(.vertical, 0)
                }
            }
        }
    }

    private var enabledCount: Int {
        settings.enabledCount(for: category)
    }

    private var categoryStateTitle: String {
        if settings.isCategoryFullyEnabled(category) {
            return "All Tracked"
        } else if settings.isCategoryPartiallyEnabled(category) {
            return "Partial"
        } else {
            return "Not Tracked"
        }
    }

    private var categoryStateColor: Color {
        if settings.isCategoryFullyEnabled(category) {
            return Color.accent
        } else if settings.isCategoryPartiallyEnabled(category) {
            return Color.warning
        } else {
            return Color.textMuted
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
    }

    /// Metrics in this category that are enabled in export settings
    private var enabledMetricsInCategory: [HealthMetricDefinition] {
        let categoryMetrics = HealthMetrics.byCategory[category] ?? []
        return categoryMetrics.filter { metricSelection.isMetricEnabled($0.id) }
    }
}

// MARK: - Individual Metric Row

struct MetricTrackingRow: View {
    let metric: HealthMetricDefinition
    @ObservedObject var settings: IndividualTrackingSettings

    var body: some View {
        Toggle(isOn: Binding(
            get: { settings.shouldTrackIndividually(metric.id) },
            set: { settings.setTrackIndividually(metric.id, enabled: $0) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.xs) {
                    Text(metric.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    if IndividualTrackingSettings.isSuggested(metric.id) {
                        IndividualTrackingStatePill(title: "Suggested", color: Color.accent)
                    }
                }

                Text(aggregationDescription(metric.aggregation))
                    .font(.caption)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .tint(Color.accent)
        .padding(.vertical, 8)
        .accessibilityLabel(metric.name)
        .accessibilityValue(settings.shouldTrackIndividually(metric.id) ? "Tracked" : "Not tracked")
        .accessibilityHint("Double tap to \(settings.shouldTrackIndividually(metric.id) ? "stop tracking" : "track") individual entry files for \(metric.name)")
    }

    private func aggregationDescription(_ aggregation: HealthMetricDefinition.AggregationType) -> String {
        switch aggregation {
        case .cumulative: return "Daily: sum"
        case .discreteAvg: return "Daily: average"
        case .discreteMin: return "Daily: minimum"
        case .discreteMax: return "Daily: maximum"
        case .mostRecent: return "Daily: latest"
        case .duration: return "Daily: total time"
        case .count: return "Daily: count"
        }
    }
}

private struct IndividualTrackingStatePill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        IndividualTrackingView(
            settings: IndividualTrackingSettings(),
            metricSelection: MetricSelectionState()
        )
    }
}
