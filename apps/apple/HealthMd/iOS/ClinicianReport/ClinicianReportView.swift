import SwiftUI

struct ClinicianReportView: View {
    @StateObject private var viewModel: ClinicianReportViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var showShare = false

    private var copy: ClinicianReportCopy { ClinicianReportCopy(locale: locale) }

    init(healthKitManager: HealthKitManager, unitPreference: UnitPreference) {
        _viewModel = StateObject(wrappedValue: ClinicianReportViewModel(
            dataSource: AppleClinicianReportDataSource(healthKitManager: healthKitManager),
            unitPreference: unitPreference
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(copy.string(.intro))
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)

                    section(title: copy.string(.period)) { periodControls }
                    section(title: copy.string(.metrics)) { metricControls }
                    section(title: copy.string(.detail)) { detailControls }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        TextField(copy.string(.display_name), text: Binding(
                            get: { viewModel.configuration.displayName },
                            set: viewModel.setDisplayName
                        ))
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.name)
                        .accessibilityIdentifier(AccessibilityID.ClinicianReport.displayName)
                        Text(copy.string(.display_name_hint))
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.textPrimary)
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: { viewModel.preview(locale: locale) }) {
                        Label(copy.string(.preview), systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accent)
                    .disabled(!viewModel.canPreview)
                    .accessibilityIdentifier(AccessibilityID.ClinicianReport.preview)

                    if viewModel.configuration.selectedMetrics.isEmpty {
                        Text(copy.string(.select_metric))
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }

                    if viewModel.isLoading {
                        ProgressView(copy.string(.preparing))
                            .frame(maxWidth: .infinity)
                    }

                    if let report = viewModel.report {
                        reportPreview(report)
                        Button(action: viewModel.generatePDF) {
                            Label(copy.string(.generate_pdf), systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accent)
                        .disabled(viewModel.isRendering)
                        .accessibilityIdentifier(AccessibilityID.ClinicianReport.generate)
                    }

                    if viewModel.isRendering {
                        ProgressView(copy.string(.generating))
                            .frame(maxWidth: .infinity)
                    }

                    if viewModel.artifact != nil {
                        Button {
                            showShare = true
                        } label: {
                            Label(copy.string(.share_or_save_pdf), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .accessibilityIdentifier(AccessibilityID.ClinicianReport.share)
                    }
                }
                .padding(Spacing.md)
            }
            .background(Color.bgPrimary)
            .navigationTitle(copy.string(.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.string(.close)) {
                        viewModel.cancel()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isLoading || viewModel.isRendering)
        .sheet(isPresented: $showShare) {
            if let artifact = viewModel.artifact {
                ClinicianReportShareSheet(artifact: artifact) {
                    showShare = false
                }
            }
        }
    }

    private var periodControls: some View {
        VStack(spacing: Spacing.sm) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                ForEach(ReportDateRangePreset.allCases) { preset in
                    let selected = viewModel.selectedPreset == preset
                    Button {
                        viewModel.selectPreset(preset)
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            if selected { Image(systemName: "checkmark.circle.fill") }
                            Text(preset.title(using: copy)).font(.footnote.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? Color.accent : Color.textSecondary)
                    .accessibilityIdentifier(AccessibilityID.ClinicianReport.preset(preset))
                    .accessibilityValue(copy.string(selected ? .selected : .not_selected))
                }
            }
            if viewModel.selectedPreset == .custom {
                Divider()
                DatePicker(
                    copy.string(.start_date),
                    selection: Binding(
                        get: { viewModel.configuration.dateRange.startDate },
                        set: { viewModel.setCustomRange(start: $0, end: viewModel.configuration.dateRange.endDate) }
                    ),
                    in: ...viewModel.configuration.dateRange.endDate,
                    displayedComponents: .date
                )
                .accessibilityIdentifier(AccessibilityID.ClinicianReport.customStartDate)
                Divider()
                DatePicker(
                    copy.string(.end_date),
                    selection: Binding(
                        get: { viewModel.configuration.dateRange.endDate },
                        set: { viewModel.setCustomRange(start: viewModel.configuration.dateRange.startDate, end: $0) }
                    ),
                    in: viewModel.configuration.dateRange.startDate...Date(),
                    displayedComponents: .date
                )
                .accessibilityIdentifier(AccessibilityID.ClinicianReport.customEndDate)
            }
        }
    }

    private var metricControls: some View {
        VStack(spacing: 0) {
            ForEach(ReportMetric.allCases) { metric in
                Toggle(metric.displayName(using: copy), isOn: Binding(
                    get: { viewModel.configuration.selectedMetrics.contains(metric) },
                    set: { _ in viewModel.toggleMetric(metric) }
                ))
                .tint(Color.accent)
                .padding(.vertical, Spacing.xs)
                .accessibilityIdentifier(AccessibilityID.ClinicianReport.metric(metric))
                if metric != ReportMetric.allCases.last { Divider() }
            }
        }
    }

    private var detailControls: some View {
        Picker(copy.string(.detail), selection: Binding(
            get: { viewModel.configuration.detailLevel },
            set: viewModel.setDetailLevel
        )) {
            Text(copy.string(.summary_only)).tag(ReportDetailLevel.summary)
            Text(copy.string(.summary_readings)).tag(ReportDetailLevel.summaryAndReadings)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(AccessibilityID.ClinicianReport.detail)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            content()
                .padding(Spacing.sm)
                .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderSubtle, lineWidth: 1))
        }
    }

    private func reportPreview(_ report: ClinicianReportData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(copy.string(.preview_heading))
                .font(.title3.weight(.semibold))
            Text(report.title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(report.dateRangeLabel)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
            if let name = report.displayName {
                Text(name).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
            ForEach(report.warnings, id: \.self) { warning in
                Text(warning).font(.footnote).foregroundStyle(Color.textSecondary)
            }
            ForEach(report.sections) { section in
                Divider().padding(.vertical, Spacing.xs)
                Text(section.localizedTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if let noData = section.noDataMessage {
                    Text(noData).font(.footnote).foregroundStyle(Color.textSecondary)
                }
                ForEach(Array(section.facts.enumerated()), id: \.offset) { _, fact in
                    HStack(alignment: .firstTextBaseline) {
                        Text(fact.label).font(.footnote.weight(.semibold))
                        Spacer(minLength: Spacing.sm)
                        Text(fact.value).font(.footnote.monospacedDigit()).multilineTextAlignment(.trailing)
                    }
                }
                if let coverage = section.coverageDisclosure {
                    Text(coverage).font(.caption).foregroundStyle(Color.textSecondary)
                }
                if let sources = section.sourcesDisclosure {
                    Text(sources)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                if let detail = section.detailReadingsDescription {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Divider()
            Text(report.disclaimer).font(.caption).foregroundStyle(Color.textSecondary)
        }
        .padding(Spacing.md)
        .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderSubtle, lineWidth: 1))
        .accessibilityIdentifier(AccessibilityID.ClinicianReport.previewContent)
    }
}
