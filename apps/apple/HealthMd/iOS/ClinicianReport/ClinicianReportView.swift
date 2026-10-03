import SwiftUI
import UIKit

struct ClinicianReportView: View {
    private enum ScrollTarget: Hashable { case top }

    private enum NoticeTone {
        case accent
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .accent: Color.accent
            case .success: Color.success
            case .warning: Color.warning
            case .error: Color.error
            }
        }
    }

    @StateObject private var viewModel: ClinicianReportViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var showShare = false
    @State private var showExportSuccess = false
    @State private var exportSuccessPresentationID = UUID()

    private var copy: ClinicianReportCopy { ClinicianReportCopy(locale: locale) }
    private var usesAccessibilityLayout: Bool { dynamicTypeSize.isAccessibilitySize }

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
                    .padding(.horizontal, Spacing.s4)
                    .padding(.top, Spacing.s4)
                    .padding(.bottom, Spacing.s6)
                }
                .scrollIndicators(.hidden)
                .background(Color.bgSecondary.ignoresSafeArea())
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
                        .padding(.horizontal, Spacing.s4)
                        .padding(.top, Spacing.s2)
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
                    .frame(minHeight: 44)
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
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s2)
        }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil {
                dismiss()
            }
        }
    }

    private var configurationContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            Text(copy.string(.intro))
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            section(title: copy.string(.period)) { periodControls }
            section(title: copy.string(.metrics)) { metricControls }
            section(title: copy.string(.detail)) { detailControls }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(copy.string(.display_name))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                TextField(copy.string(.display_name), text: Binding(
                    get: { viewModel.configuration.displayName },
                    set: viewModel.setDisplayName
                ))
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)
                .controlSize(.large)
                .frame(minHeight: 48)
                .accessibilityIdentifier(AccessibilityID.ClinicianReport.displayName)
                Text(copy.string(.display_name_hint))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

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

    private var periodControls: some View {
        VStack(spacing: Spacing.sm) {
            LazyVGrid(
                columns: usesAccessibilityLayout
                    ? [GridItem(.flexible())]
                    : [GridItem(.flexible()), GridItem(.flexible())],
                spacing: Spacing.sm
            ) {
                ForEach(ReportDateRangePreset.allCases) { preset in
                    let selected = viewModel.selectedPreset == preset
                    Button {
                        viewModel.selectPreset(preset)
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            Text(preset.title(using: copy))
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(selected ? Color.accent : Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            selected ? Color.selectedBackground : Color.controlBackground,
                            in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                                .strokeBorder(
                                    selected ? Color.accent.opacity(0.45) : Color.borderSubtle,
                                    lineWidth: 1
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
                .frame(minHeight: 44)
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
                .frame(minHeight: 44)
                .accessibilityIdentifier(AccessibilityID.ClinicianReport.customEndDate)
            }
        }
    }

    private var metricControls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(copy.format(
                .selected_count,
                "\(viewModel.configuration.selectedMetrics.count)",
                "\(ReportMetric.allCases.count)"
            ))
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.textSecondary)
            .monospacedDigit()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s2) { metricSelectionButtons(expands: false) }
                VStack(spacing: Spacing.s2) { metricSelectionButtons(expands: true) }
            }

            Divider()

            VStack(spacing: 0) {
                ForEach(ReportMetric.allCases) { metric in
                    Toggle(metric.displayName(using: copy), isOn: Binding(
                        get: { viewModel.configuration.selectedMetrics.contains(metric) },
                        set: { _ in viewModel.toggleMetric(metric) }
                    ))
                    .tint(Color.accent)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier(AccessibilityID.ClinicianReport.metric(metric))
                    if metric != ReportMetric.allCases.last { Divider() }
                }
            }
        }
    }

    @ViewBuilder
    private func metricSelectionButtons(expands: Bool) -> some View {
        metricSelectionButton(
            copy.string(.recommended),
            identifier: AccessibilityID.ClinicianReport.recommended,
            isActive: viewModel.configuration.selectedMetrics == ReportMetric.recommended,
            expands: expands,
            action: viewModel.selectRecommendedMetrics
        )
        metricSelectionButton(
            copy.string(.select_all),
            identifier: AccessibilityID.ClinicianReport.selectAll,
            isActive: viewModel.configuration.selectedMetrics.count == ReportMetric.allCases.count,
            expands: expands,
            action: viewModel.selectAllMetrics
        )
        metricSelectionButton(
            copy.string(.clear),
            identifier: AccessibilityID.ClinicianReport.clear,
            isActive: viewModel.configuration.selectedMetrics.isEmpty,
            expands: expands,
            action: viewModel.clearMetrics
        )
    }

    private func metricSelectionButton(
        _ title: String,
        identifier: String,
        isActive: Bool,
        expands: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isActive ? Color.accent : Color.textPrimary)
                .padding(.horizontal, Spacing.s3)
                .frame(maxWidth: expands ? .infinity : nil, minHeight: 44)
                .background(
                    isActive ? Color.selectedBackground : Color.controlBackground,
                    in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.accent.opacity(0.45) : Color.borderSubtle,
                            lineWidth: 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(copy.string(isActive ? .selected : .not_selected))
    }

    private var detailControls: some View {
        VStack(spacing: 0) {
            detailOption(
                .summary,
                title: copy.string(.summary_only),
                description: copy.string(.summary_description)
            )
            Divider()
            detailOption(
                .summaryAndReadings,
                title: copy.string(.summary_readings),
                description: copy.string(.readings_description)
            )
            .padding(.top, Spacing.s2)
        }
        .accessibilityIdentifier(AccessibilityID.ClinicianReport.detail)
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
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accent : Color.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(copy.string(selected ? .selected : .not_selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textSecondary)
            content()
                .padding(Spacing.s4)
                .background(
                    RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                        .fill(Color.bgPrimary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.025), radius: 2, x: 0, y: 1)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: Spacing.sm) {
            Divider()

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
                Button(action: { viewModel.generateReport(locale: locale) }) {
                    Text(copy.string(.preview))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: GeistRadius.sm))
                .tint(Color.accent)
                .disabled(!viewModel.canGenerateReport)
                .accessibilityIdentifier(AccessibilityID.ClinicianReport.preview)
            }
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .background(Color.bgPrimary)
    }

    @ViewBuilder
    private func reviewActions(_ report: ClinicianReportData) -> some View {
        if !report.hasReportableData {
            editButton(prominent: true, fillsAvailableHeight: false)
        } else if usesAccessibilityLayout {
            VStack(spacing: Spacing.sm) {
                primaryReviewButton(fillsAvailableHeight: false)
                editButton(prominent: false, fillsAvailableHeight: false)
            }
        } else {
            HStack(spacing: Spacing.sm) {
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
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48,
                        maxHeight: fillsAvailableHeight ? .infinity : nil
                    )
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: GeistRadius.sm))
            .tint(Color.accent)
            .accessibilityIdentifier(AccessibilityID.ClinicianReport.edit)
        } else {
            Button(action: viewModel.editConfiguration) {
                Label(copy.string(.edit), systemImage: "slider.horizontal.3")
                    .foregroundStyle(Color.textPrimary)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48,
                        maxHeight: fillsAvailableHeight ? .infinity : nil
                    )
                    .background(
                        Color.controlBackground,
                        in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                            .strokeBorder(Color.borderDefault, lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
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
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48,
                        maxHeight: fillsAvailableHeight ? .infinity : nil
                    )
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: GeistRadius.sm))
            .tint(Color.accent)
            .accessibilityIdentifier(AccessibilityID.ClinicianReport.share)
        } else {
            Button(action: viewModel.generatePDF) {
                Label(copy.string(.generate_pdf), systemImage: "doc.richtext")
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 48,
                        maxHeight: fillsAvailableHeight ? .infinity : nil
                    )
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: GeistRadius.sm))
            .tint(Color.accent)
            .disabled(!viewModel.canGeneratePDF)
            .accessibilityIdentifier(AccessibilityID.ClinicianReport.generate)
        }
    }

    private var exportSuccessToast: some View {
        Label {
            Text(copy.string(.saved))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            Color.bgPrimary,
            in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.success.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 3)
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
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer(minLength: Spacing.sm)
                Text(clampedProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
            ProgressView(value: clampedProgress)
                .progressViewStyle(.linear)
                .tint(Color.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(Text(clampedProgress, format: .percent.precision(.fractionLength(0))))
    }

    private func reportPreview(_ report: ClinicianReportData) -> some View {
        let availabilityTone: NoticeTone = if !report.hasReportableData {
            .warning
        } else if report.unavailableSections.isEmpty {
            .success
        } else {
            .accent
        }
        let availabilityIcon = if !report.hasReportableData {
            "exclamationmark.triangle.fill"
        } else if report.unavailableSections.isEmpty {
            "checkmark.circle.fill"
        } else {
            "info.circle.fill"
        }

        return VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(copy.string(.preview_heading))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                Text(report.title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(report.dateRangeLabel)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                if let name = report.displayName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            noticeCard(
                report.hasReportableData ? report.availabilityOverview : report.noReportableDataMessage,
                systemImage: availabilityIcon,
                tone: availabilityTone
            )

            if !report.warnings.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Label(report.availabilityNoteTitle, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    ForEach(report.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.warning.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(Color.warning.opacity(0.22), lineWidth: 1)
                )
            }

            if report.hasReportableData {
                ForEach(report.availableSections) { reportSectionPreview($0) }
            }

            if let unavailable = report.unavailableMeasurementsSummary {
                Label(unavailable, systemImage: "minus.circle")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            errorCard

            Divider()
                .overlay(Color.borderSubtle)
                .padding(.top, Spacing.s2)

            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(report.aboutTitle)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text(report.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(report.attribution)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let practiceLine = report.practiceLine,
                   let practiceURL = ClinicianReportCopy.practiceURL.flatMap({ URL(string: "https://\($0)") }) {
                    Link(destination: practiceURL) {
                        Text(practiceLine)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier(AccessibilityID.ClinicianReport.previewContent)
    }

    private func reportSectionPreview(_ reportSection: MetricReportSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(reportSection.localizedTitle)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text(reportSection.availabilitySummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(Array(reportSection.facts.enumerated()), id: \.offset) { index, fact in
                if index > 0 {
                    Divider()
                        .overlay(Color.borderSubtle)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(fact.label)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                        Spacer(minLength: Spacing.sm)
                        Text(fact.value)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.label)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                        Text(fact.value)
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }

            if let detail = reportSection.detailReadingsDescription {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .fill(Color.bgPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.025), radius: 2, x: 0, y: 1)
    }

    private func noticeCard(
        _ message: String,
        systemImage: String,
        tone: NoticeTone = .accent
    ) -> some View {
        Label {
            Text(message)
                .font(.footnote)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(
            tone.color.opacity(0.08),
            in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(tone.color.opacity(0.22), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var errorCard: some View {
        if let error = viewModel.errorMessage {
            noticeCard(error, systemImage: "exclamationmark.circle.fill", tone: .error)
        }
    }
}
