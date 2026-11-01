import SwiftUI
import UIKit

/// ClinicianReportG. Configures, previews, and shares the on-device clinician PDF.
struct ClinicianReportView: View {
    private enum ScrollTarget: Hashable { case top }

    private enum NoticeTone {
        case info
        case success
        case warning
        case error

        var bannerTone: GlassBanner.Tone {
            switch self {
            case .info: .info
            case .success: .success
            case .warning, .error: .warning
            }
        }
    }

    @StateObject private var viewModel: ClinicianReportViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var showShare = false
    @State private var showExportSuccess = false
    @State private var exportSuccessPresentationID = UUID()

    private var copy: ClinicianReportCopy { ClinicianReportCopy(locale: locale) }
    private var usesAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }
    /// Resolved here because the sheet sits outside the shell's `glassTheme()`.
    private var palette: GlassPalette {
        GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
    }

    init(healthKitManager: HealthKitManager, unitPreference: UnitPreference) {
        _viewModel = StateObject(wrappedValue: ClinicianReportViewModel(
            dataSource: AppleClinicianReportDataSource(healthKitManager: healthKitManager),
            unitPreference: unitPreference
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    Color.clear
                        .frame(height: 0)
                        .id(ScrollTarget.top)

                    Group {
                        if let report = viewModel.report, !viewModel.isRendering {
                            reportPreview(report)
                        } else {
                            configurationContent
                                .configurationChangesProtected()
                                .disabled(!viewModel.isConfigurationEditable)
                        }
                    }
                    .padding(.horizontal, GlassMetrics.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, GlassMetrics.screenMargin)
                }
                .scrollIndicators(.hidden)
                .tint(palette.accent)
                .background(palette.bg.ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actionBar
                }
                .onChange(of: viewModel.report != nil && !viewModel.isRendering) { _, _ in
                    Task { @MainActor in
                        await Task.yield()
                        proxy.scrollTo(ScrollTarget.top, anchor: .top)
                    }
                }
            }
            .overlay(alignment: .top) {
                if showExportSuccess {
                    exportSuccessToast
                        .padding(.horizontal, GlassMetrics.screenMargin)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .navigationTitle(copy.string(.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.string(.close)) {
                        viewModel.cancel()
                        dismiss()
                    }
                    .frame(minHeight: GlassMetrics.touchTarget)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isBusy)
        .sheet(isPresented: $showShare) {
            if let artifact = viewModel.artifact {
                ClinicianReportShareSheet(artifact: artifact) { completed in
                    showShare = false
                    if completed {
                        presentExportSuccess()
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            ConfigurationProtectionToast(configurationProtection: configurationProtection)
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 8)
        }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil {
                dismiss()
            }
        }
        .glassSheet(palette: palette)
        .glassTheme()
    }

    // MARK: - Configuration

    private var configurationContent: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            Text(copy.string(.intro))
                .glassFont(.caption)
                .fontWeight(.regular)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            // ClinicianReportG leads with the name on the report.
            displayNameField
            periodSection
            metricSection
            detailSection

            if viewModel.configuration.selectedMetrics.isEmpty {
                noticeCard(
                    copy.string(.select_metric),
                    systemImage: "exclamationmark.circle.fill",
                    tone: .warning
                )
            }

            errorCard
        }
    }

    private var displayNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.string(.display_name))
                        .glassFont(.rowSubtitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.muted)
                    TextField(copy.string(.optional), text: Binding(
                        get: { viewModel.configuration.displayName },
                        set: viewModel.setDisplayName
                    ))
                    .accessibilityLabel(copy.string(.display_name))
                    .textFieldStyle(.plain)
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                    .textContentType(.name)
                    .frame(minHeight: GlassMetrics.touchTarget)
                    .accessibilityIdentifier(AccessibilityID.ClinicianReport.displayName)
                }
                .padding(.horizontal, GlassMetrics.panelPadding)
                .padding(.vertical, 10)
            }
            footnote(copy.string(.display_name_hint))
        }
    }

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.string(.period))
                        .glassFont(.body)
                        .foregroundStyle(palette.text)
                    periodPicker
                }
                .padding(.horizontal, GlassMetrics.panelPadding)
                .padding(.vertical, 12)

                if viewModel.selectedPreset == .custom {
                    rowDivider
                    datePickerRow(
                        copy.string(.start_date),
                        selection: Binding(
                            get: { viewModel.configuration.dateRange.startDate },
                            set: { viewModel.setCustomRange(start: $0, end: viewModel.configuration.dateRange.endDate) }
                        ),
                        in: ...viewModel.configuration.dateRange.endDate,
                        identifier: AccessibilityID.ClinicianReport.customStartDate
                    )
                    rowDivider
                    datePickerRow(
                        copy.string(.end_date),
                        selection: Binding(
                            get: { viewModel.configuration.dateRange.endDate },
                            set: { viewModel.setCustomRange(start: viewModel.configuration.dateRange.startDate, end: $0) }
                        ),
                        in: viewModel.configuration.dateRange.startDate...Date(),
                        identifier: AccessibilityID.ClinicianReport.customEndDate
                    )
                }
            }
            footnote(resolvedRangeLabel)
                .monospacedDigit()
        }
    }

    /// Four segments at standard sizes; chips that can wrap at accessibility sizes.
    @ViewBuilder
    private var periodPicker: some View {
        if usesAccessibilityLayout {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ReportDateRangePreset.allCases) { preset in
                    let selected = viewModel.selectedPreset == preset
                    GlassChip(title: preset.title(using: copy), isSelected: selected) {
                        viewModel.selectPreset(preset)
                    }
                    .accessibilityIdentifier(AccessibilityID.ClinicianReport.preset(preset))
                    .accessibilityValue(copy.string(selected ? .selected : .not_selected))
                }
            }
        } else {
            GlassSegmentedControl(
                segments: ReportDateRangePreset.allCases.map {
                    GlassSegmentedControl<ReportDateRangePreset>.Segment(value: $0, title: $0.title(using: copy))
                },
                selection: Binding(
                    get: { viewModel.selectedPreset },
                    set: viewModel.selectPreset
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(copy.string(.period))
        }
    }

    private func datePickerRow(
        _ title: String,
        selection: Binding<Date>,
        in range: PartialRangeThrough<Date>,
        identifier: String
    ) -> some View {
        DatePicker(title, selection: selection, in: range, displayedComponents: .date)
            .glassFont(.body)
            .foregroundStyle(palette.text)
            .padding(.horizontal, GlassMetrics.panelPadding)
            .frame(minHeight: GlassMetrics.rowMinHeight)
            .accessibilityIdentifier(identifier)
    }

    private func datePickerRow(
        _ title: String,
        selection: Binding<Date>,
        in range: ClosedRange<Date>,
        identifier: String
    ) -> some View {
        DatePicker(title, selection: selection, in: range, displayedComponents: .date)
            .glassFont(.body)
            .foregroundStyle(palette.text)
            .padding(.horizontal, GlassMetrics.panelPadding)
            .frame(minHeight: GlassMetrics.rowMinHeight)
            .accessibilityIdentifier(identifier)
    }

    private var resolvedRangeLabel: String {
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
        let range = viewModel.configuration.dateRange
        return "\(range.startDate.formatted(style)) – \(range.endDate.formatted(style))"
    }

    private var metricSection: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { metricSelectionChips }
                VStack(alignment: .leading, spacing: 8) { metricSelectionChips }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    GlassSectionLabel(title: copy.string(.include))
                    Spacer(minLength: 8)
                    Text(copy.format(
                        .selected_count,
                        "\(viewModel.configuration.selectedMetrics.count)",
                        "\(ReportMetric.allCases.count)"
                    ))
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .monospacedDigit()
                }
                .padding(.horizontal, 20)

                GlassPanel {
                    ForEach(ReportMetric.allCases) { metric in
                        if metric != ReportMetric.allCases.first { rowDivider }
                        GlassToggleRow(
                            title: metric.displayName(using: copy),
                            isOn: Binding(
                                get: { viewModel.configuration.selectedMetrics.contains(metric) },
                                set: { _ in viewModel.toggleMetric(metric) }
                            )
                        )
                        .accessibilityIdentifier(AccessibilityID.ClinicianReport.metric(metric))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var metricSelectionChips: some View {
        metricSelectionChip(
            copy.string(.recommended),
            identifier: AccessibilityID.ClinicianReport.recommended,
            isActive: viewModel.configuration.selectedMetrics == ReportMetric.recommended,
            action: viewModel.selectRecommendedMetrics
        )
        metricSelectionChip(
            copy.string(.select_all),
            identifier: AccessibilityID.ClinicianReport.selectAll,
            isActive: viewModel.configuration.selectedMetrics.count == ReportMetric.allCases.count,
            action: viewModel.selectAllMetrics
        )
        metricSelectionChip(
            copy.string(.clear),
            identifier: AccessibilityID.ClinicianReport.clear,
            isActive: viewModel.configuration.selectedMetrics.isEmpty,
            action: viewModel.clearMetrics
        )
    }

    private func metricSelectionChip(
        _ title: String,
        identifier: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassChip(title: title, isSelected: isActive, action: action)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(copy.string(isActive ? .selected : .not_selected))
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassSectionLabel(title: copy.string(.detail))
                .padding(.horizontal, 20)
            GlassPanel {
                detailOption(
                    .summary,
                    title: copy.string(.summary_only),
                    description: copy.string(.summary_description)
                )
                rowDivider
                detailOption(
                    .summaryAndReadings,
                    title: copy.string(.summary_readings),
                    description: copy.string(.readings_description)
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.ClinicianReport.detail)
        }
    }

    private func detailOption(
        _ level: ReportDetailLevel,
        title: String,
        description: String
    ) -> some View {
        let selected = viewModel.configuration.detailLevel == level
        return Button {
            viewModel.setDetailLevel(level)
        } label: {
            GlassRow(title: title, subtitle: description) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? palette.accent : palette.muted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(copy.string(selected ? .selected : .not_selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rowDivider: some View {
        Divider()
            .overlay(palette.line)
            .padding(.horizontal, GlassMetrics.panelPadding)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .glassFont(.caption)
            .fontWeight(.regular)
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        VStack(spacing: 8) {
            if viewModel.isLoading {
                progressStatus(
                    title: copy.string(.preparing),
                    progress: viewModel.preparationProgress
                )
            } else if viewModel.isRendering {
                progressStatus(
                    title: copy.string(.generating),
                    progress: viewModel.renderingProgress
                )
            } else if let report = viewModel.report {
                reviewActions(report)
            } else {
                // Preparing the preview also renders the PDF, so one action covers both
                // of ClinicianReportG's Preview and Create PDF buttons.
                Button(action: { viewModel.generateReport(locale: locale) }) {
                    Text(copy.string(.preview))
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(!viewModel.canGenerateReport)
                .accessibilityIdentifier(AccessibilityID.ClinicianReport.preview)
            }
        }
        .padding(.horizontal, GlassMetrics.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            Color.clear
                .glassSurface(in: Rectangle(), style: .strong)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func reviewActions(_ report: ClinicianReportData) -> some View {
        if !report.hasReportableData {
            editButton(prominent: true, fillsAvailableHeight: false)
        } else if usesAccessibilityLayout {
            VStack(spacing: 8) {
                primaryReviewButton(fillsAvailableHeight: false)
                editButton(prominent: false, fillsAvailableHeight: false)
            }
        } else {
            HStack(spacing: 8) {
                editButton(prominent: false, fillsAvailableHeight: true)
                primaryReviewButton(fillsAvailableHeight: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func editButton(prominent: Bool, fillsAvailableHeight: Bool) -> some View {
        if prominent {
            Button(action: viewModel.editConfiguration) {
                Label(copy.string(.edit), systemImage: "slider.horizontal.3")
                    .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            .accessibilityIdentifier(AccessibilityID.ClinicianReport.edit)
        } else {
            Button(action: viewModel.editConfiguration) {
                Label(copy.string(.edit), systemImage: "slider.horizontal.3")
                    .glassFont(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 12)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: GlassMetrics.primaryButtonHeight,
                        maxHeight: fillsAvailableHeight ? .infinity : nil
                    )
                    .background(Capsule().fill(palette.surface2))
                    .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.ClinicianReport.edit)
        }
    }

    @ViewBuilder
    private func primaryReviewButton(fillsAvailableHeight: Bool) -> some View {
        if viewModel.artifact != nil {
            Button {
                showExportSuccess = false
                exportSuccessPresentationID = UUID()
                showShare = true
            } label: {
                Label(copy.string(.share_or_save_pdf), systemImage: "square.and.arrow.up")
                    .padding(.horizontal, 12)
                    .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            .accessibilityIdentifier(AccessibilityID.ClinicianReport.share)
        } else {
            Button(action: viewModel.generatePDF) {
                Label(copy.string(.generate_pdf), systemImage: "doc.richtext")
                    .padding(.horizontal, 12)
                    .frame(maxHeight: fillsAvailableHeight ? .infinity : nil)
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            .disabled(!viewModel.canGeneratePDF)
            .accessibilityIdentifier(AccessibilityID.ClinicianReport.generate)
        }
    }

    private var exportSuccessToast: some View {
        Label {
            Text(copy.string(.saved))
                .glassFont(.body)
                .fontWeight(.medium)
                .foregroundStyle(palette.text)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(palette.ok)
        }
        .padding(.horizontal, GlassMetrics.panelPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget, alignment: .leading)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius, style: .strong)
        .accessibilityIdentifier(AccessibilityID.ClinicianReport.exportSuccess)
    }

    private func presentExportSuccess() {
        let presentationID = UUID()
        exportSuccessPresentationID = presentationID
        let message = copy.string(.saved)

        withAnimation(AnimationTimings.fast) {
            showExportSuccess = true
        }
        UIAccessibility.post(notification: .announcement, argument: message)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard exportSuccessPresentationID == presentationID else { return }
            withAnimation(AnimationTimings.fast) {
                showExportSuccess = false
            }
        }
    }

    private func progressStatus(title: String, progress: Double) -> some View {
        let clampedProgress = min(max(progress, 0), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .glassFont(.caption)
                    .foregroundStyle(palette.text)
                Spacer(minLength: 8)
                Text(clampedProgress, format: .percent.precision(.fractionLength(0)))
                    .glassFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.text)
            }
            ProgressView(value: clampedProgress)
                .progressViewStyle(.linear)
                .tint(palette.accent)
        }
        .frame(minHeight: GlassMetrics.primaryButtonHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(clampedProgress, format: .percent.precision(.fractionLength(0))))
    }

    // MARK: - Preview

    private func reportPreview(_ report: ClinicianReportData) -> some View {
        let availabilityTone: NoticeTone = if !report.hasReportableData {
            .warning
        } else if report.unavailableSections.isEmpty {
            .success
        } else {
            .info
        }
        let availabilityIcon = if !report.hasReportableData {
            "exclamationmark.triangle.fill"
        } else if report.unavailableSections.isEmpty {
            "checkmark.circle.fill"
        } else {
            "info.circle.fill"
        }

        return VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 4) {
                GlassSectionLabel(title: copy.string(.preview_heading))
                Text(report.title)
                    .glassFont(.sentence)
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(report.dateRangeLabel)
                    .glassFont(.caption)
                    .fontWeight(.regular)
                    .monospacedDigit()
                    .foregroundStyle(palette.sec)
                if let name = report.displayName {
                    Text(name)
                        .glassFont(.body)
                        .foregroundStyle(palette.text)
                }
            }
            .padding(.horizontal, 4)

            noticeCard(
                report.hasReportableData ? report.availabilityOverview : report.noReportableDataMessage,
                systemImage: availabilityIcon,
                tone: availabilityTone
            )

            if !report.warnings.isEmpty {
                GlassBanner(
                    title: report.availabilityNoteTitle,
                    message: report.warnings.joined(separator: "\n"),
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning
                )
            }

            if report.hasReportableData {
                ForEach(report.availableSections) { reportSectionPreview($0) }
            }

            if let unavailable = report.unavailableMeasurementsSummary {
                Label(unavailable, systemImage: "minus.circle")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }

            errorCard

            GlassPanel {
                VStack(alignment: .leading, spacing: 8) {
                    Text(report.aboutTitle)
                        .glassFont(.navTitle)
                        .foregroundStyle(palette.text)
                    Text(report.disclaimer)
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.sec)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(report.attribution)
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.sec)
                        .fixedSize(horizontal: false, vertical: true)
                    if let practiceLine = report.practiceLine,
                       let practiceURL = ClinicianReportCopy.practiceURL.flatMap({ URL(string: "https://\($0)") }) {
                        Link(destination: practiceURL) {
                            Text(practiceLine)
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.accent)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(GlassMetrics.panelPadding)
            }
        }
        .accessibilityIdentifier(AccessibilityID.ClinicianReport.previewContent)
    }

    private func reportSectionPreview(_ reportSection: MetricReportSummary) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 2) {
                Text(reportSection.localizedTitle)
                    .glassFont(.navTitle)
                    .foregroundStyle(palette.text)
                Text(reportSection.availabilitySummary)
                    .glassFont(.rowSubtitle)
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
            }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .padding(.top, GlassMetrics.panelPadding)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(reportSection.facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { rowDivider }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(fact.label)
                            .glassFont(.caption)
                            .foregroundStyle(palette.sec)
                        Spacer(minLength: 8)
                        Text(fact.value)
                            .glassFont(.caption)
                            .fontWeight(.regular)
                            .monospacedDigit()
                            .foregroundStyle(palette.text)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label)
                            .glassFont(.caption)
                            .foregroundStyle(palette.sec)
                        Text(fact.value)
                            .glassFont(.caption)
                            .fontWeight(.regular)
                            .monospacedDigit()
                            .foregroundStyle(palette.text)
                    }
                }
                .padding(.horizontal, GlassMetrics.panelPadding)
                .frame(minHeight: GlassMetrics.touchTarget)
            }

            if let detail = reportSection.detailReadingsDescription {
                Text(detail)
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, GlassMetrics.panelPadding)
                    .padding(.top, 4)
            }

            Color.clear.frame(height: 8)
        }
    }

    private func noticeCard(
        _ message: String,
        systemImage: String,
        tone: NoticeTone = .info
    ) -> some View {
        GlassBanner(title: message, systemImage: systemImage, tone: tone.bannerTone)
    }

    @ViewBuilder
    private var errorCard: some View {
        if let error = viewModel.errorMessage {
            noticeCard(error, systemImage: "exclamationmark.circle.fill", tone: .error)
        }
    }
}
