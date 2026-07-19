import SwiftUI

struct ExportPreviewScope: Equatable {
    static let losslessFormatPriority: [ExportFormat] = [
        .markdown,
        .obsidianBases,
        .json,
        .csv
    ]

    let maximumRenderedDates: Int
    let formats: [ExportFormat]
    let includesSupplementalFiles: Bool

    static func make(
        selectedFormats: Set<ExportFormat>,
        losslessEnabled: Bool,
        defaultMaximumRenderedDates: Int = 5
    ) -> ExportPreviewScope {
        guard losslessEnabled else {
            return ExportPreviewScope(
                maximumRenderedDates: defaultMaximumRenderedDates,
                formats: selectedFormats.sorted { $0.rawValue < $1.rawValue },
                includesSupplementalFiles: true
            )
        }

        let representativeFormat = losslessFormatPriority.first {
            selectedFormats.contains($0)
        }

        return ExportPreviewScope(
            maximumRenderedDates: 1,
            formats: representativeFormat.map { [$0] } ?? [],
            includesSupplementalFiles: false
        )
    }
}

// MARK: - Export Preview
// Shows the user a dry-run of what will be written to their vault for the
// current date range, format selection, and customization settings — actual
// filenames, folder paths, and the rendered file contents per format.
//
// Side effects (individual entry tracking, daily-note injection) are rendered
// as additional preview rows so users can inspect the actual generated content.

struct ExportPreviewView: View {
    let startDate: Date
    let endDate: Date
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var settings: AdvancedExportSettings
    let destinationLabel: String
    let destinationRootName: String?
    let dateRangePreset: ExportDateRangePreset
    let targetType: PricingAnalyticsExportTargetType
    let fetchHealthData: (Date) async -> HealthData?
    let requestHealthAuthorization: (@MainActor () async throws -> HealthKitManager.AuthorizationRequestOutcome)?
    private let analytics = PricingAnalyticsClient.shared

    init(
        startDate: Date,
        endDate: Date,
        vaultManager: VaultManager,
        settings: AdvancedExportSettings,
        destinationLabel: String,
        destinationRootName: String?,
        dateRangePreset: ExportDateRangePreset,
        targetType: PricingAnalyticsExportTargetType,
        fetchHealthData: @escaping (Date) async -> HealthData?,
        requestHealthAuthorization: (@MainActor () async throws -> HealthKitManager.AuthorizationRequestOutcome)? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        _vaultManager = ObservedObject(wrappedValue: vaultManager)
        _settings = ObservedObject(wrappedValue: settings)
        self.destinationLabel = destinationLabel
        self.destinationRootName = destinationRootName
        self.dateRangePreset = dateRangePreset
        self.targetType = targetType
        self.fetchHealthData = fetchHealthData
        self.requestHealthAuthorization = requestHealthAuthorization
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var datePreviews: [DatePreview] = []
    @State private var partialFailures: [ExportPartialFailure] = []
    @State private var isLoading = true
    @State private var totalDateCount = 0
    @State private var renderedDayPreviewCount = 0
    @State private var estimatedExportSize: ExportPreviewSizeEstimate?
    @State private var permissionGuidance: ExportPermissionGuidance?

    /// Cap how many dates we render so opening preview never feels slow.
    /// We also cap how many dates we'll *fetch* — preview is for shape, not census.
    private static let maxRenderedDates = 5
    private static let maxFetchAttempts = 14
    private static let bloodPressureMetricIDs = [
        "blood_pressure_systolic",
        "blood_pressure_diastolic"
    ]

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if datePreviews.isEmpty && partialFailures.isEmpty {
                    emptyStateView
                } else {
                    contentList
                }
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Export Preview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            await buildPreviews()
        }
        .alert(item: $permissionGuidance) { guidance in
            #if os(iOS)
            Alert(
                title: Text("Health Permissions Needed"),
                message: Text(guidance.iOSInstructions),
                primaryButton: .default(Text("Request Access")) {
                    requestAdditionalHealthAccess()
                },
                secondaryButton: .default(Text("Open Health App")) {
                    openHealthApp()
                }
            )
            #else
            Alert(
                title: Text("Health Permissions Needed"),
                message: Text(guidance.macInstructions),
                dismissButton: .default(Text("Done"))
            )
            #endif
        }
    }

    // MARK: - States

    private func requestAdditionalHealthAccess() {
        guard let requestHealthAuthorization else {
            openHealthApp()
            return
        }

        Task { @MainActor in
            do {
                switch try await requestHealthAuthorization() {
                case .requested:
                    await buildPreviews()
                case .unnecessary:
                    openHealthApp()
                case .unavailable:
                    break
                }
            } catch {
                openHealthApp()
            }
        }
    }

    private func openHealthApp() {
        if let healthURL = URL(string: "x-apple-health://") {
            openURL(healthURL)
        }
    }

    private var loadingView: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.accent)
            Text("Building preview…")
                .font(.footnote)
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Color.textMuted)
            Text("No data to preview")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("There is no health data for the selected dates, or no formats are selected.")
                .font(.footnote)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentList: some View {
        List {
            summarySection
            partialFailuresSection
            ForEach(datePreviews) { preview in
                Section {
                    ForEach(preview.files) { file in
                        NavigationLink {
                            FileContentView(file: file)
                        } label: {
                            fileRow(file)
                        }
                        .accessibilityIdentifier("exportPreview.fileRow.\(file.kind.accessibilityIdentifierSuffix)")
                    }
                    if preview.files.isEmpty {
                        Text("No data for this date.")
                            .font(.footnote)
                            .foregroundStyle(Color.textMuted)
                    }
                } header: {
                    Text(preview.dateLabel)
                        .font(Typography.monoCaptionEmphasis())
                        .foregroundStyle(Color.textSecondary)
                } footer: {
                    if !preview.folderPath.isEmpty {
                        Text(preview.folderPath)
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.textMuted)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - Summary header

    @ViewBuilder
    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Date range")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(totalDateCount) day\(totalDateCount == 1 ? "" : "s")")
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.textPrimary)
                }
                HStack {
                    Text("Formats per day")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(settings.dailyNotesOnlyModeEnabled
                         ? "0 (daily notes only)"
                         : (settings.summaryOnlyModeEnabled ? "0 (summary-only)" : "\(settings.exportFormats.count)"))
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.textPrimary)
                }
                if let estimatedExportSize {
                    HStack {
                        Text(targetType == .apiEndpoint ? "Estimated payload" : "Estimated size")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("~\(estimatedExportSize.sizeLabel)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "Estimated export size, approximately \(estimatedExportSize.sizeLabel), based on \(estimatedExportSize.sampledDataDayCount) sampled data day\(estimatedExportSize.sampledDataDayCount == 1 ? "" : "s")"
                    )
                    .accessibilityHint("Actual size can vary across the selected date range")
                }
                if settings.rollupSummariesEnabled {
                    HStack {
                        Text("Roll-up periods")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(settings.enabledRollupPeriods.map { $0.displayName }.joined(separator: ", "))
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                }
                HStack {
                    Text("Destination")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(destinationLabel)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if settings.effectiveGranularDataEnabled {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text("Showing one representative \(previewScope.formats.first?.rawValue ?? "selected format") file from the most recent selected day. The full export will still include every selected date and format.")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 2)
                } else if totalDateCount > renderedDayPreviewCount {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text(settings.summaryOnlyModeEnabled
                             ? "Previewing \(renderedDayPreviewCount) recent source day\(renderedDayPreviewCount == 1 ? "" : "s") with data. The full summary-only export will fetch the complete touched roll-up windows."
                             : "Previewing the \(renderedDayPreviewCount) most recent day\(renderedDayPreviewCount == 1 ? "" : "s") with data. The full export will run on every selected date.")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var bloodPressurePermissionFailures: [ExportPartialFailure] {
        partialFailures.filter(\.isBloodPressureAuthorizationNotDetermined)
    }

    private var additionalPermissionFailures: [ExportPartialFailure] {
        partialFailures.filter {
            !$0.isBloodPressureAuthorizationNotDetermined
                && ExportPermissionGuidance(failure: $0) != nil
        }
    }

    private var nonPermissionFailures: [ExportPartialFailure] {
        partialFailures.filter { ExportPermissionGuidance(failure: $0) == nil }
    }

    @ViewBuilder
    private var partialFailuresSection: some View {
        if !partialFailures.isEmpty {
            Section("Warnings") {
                if !bloodPressurePermissionFailures.isEmpty {
                    bloodPressurePermissionRecoveryCard
                }

                if let guidance = ExportPermissionGuidance(failures: additionalPermissionFailures) {
                    additionalHealthPermissionRecoveryCard(guidance)
                }

                ForEach(Array(nonPermissionFailures.enumerated()), id: \.offset) { _, failure in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        warningGlyph
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)

                        Text(failure.summary)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.s2)
                    }
                }
            }
        }
    }

    private func additionalHealthPermissionRecoveryCard(_ guidance: ExportPermissionGuidance) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label {
                Text("Additional Apple Health access needed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(Color.orange)
            }

            Text("Health.md has not requested \(guidance.healthDataName) on this device yet. Apple Health will not list new data types until Health.md requests them.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)

            Button {
                requestAdditionalHealthAccess()
            } label: {
                Label("Request Additional Access", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityID.ExportPreview.permissionHelpButton)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    private var bloodPressurePermissionRecoveryCard: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label {
                Text("Blood Pressure permission needs attention")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            } icon: {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(Color.orange)
            }

            Text("Health.md can still export the rest of your data, but iOS did not allow access to Blood Pressure, so systolic and diastolic values are skipped.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.s2) {
                Button {
                    permissionGuidance = ExportPermissionGuidance(healthDataName: "Blood Pressure")
                } label: {
                    Label("Show Fix Instructions", systemImage: "questionmark.circle")
                }

                Button(role: .destructive) {
                    disableBloodPressureMetricsAndReload()
                } label: {
                    Label("Disable Blood Pressure in Health.md", systemImage: "slash.circle")
                }

                Button {
                    Task { await buildPreviews() }
                } label: {
                    Label("Retry Preview", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Row

    private var warningGlyph: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.title3)
            .foregroundStyle(Color.orange)
    }

    private func fileRow(_ file: FilePreview) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: file.kind.iconName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentSubtle))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("\(file.kind.displayName) · \(file.sizeLabel)")
                    .font(.caption)
                    .foregroundStyle(Color.textMuted)
                if file.kind.showsFolderPath {
                    Text(file.folderPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func disableBloodPressureMetricsAndReload() {
        for metricID in Self.bloodPressureMetricIDs where settings.metricSelection.isMetricEnabled(metricID) {
            settings.metricSelection.toggleMetric(metricID)
        }

        Task { await buildPreviews() }
    }

    // MARK: - Build previews

    private var previewScope: ExportPreviewScope {
        ExportPreviewScope.make(
            selectedFormats: settings.exportFormats,
            losslessEnabled: settings.effectiveGranularDataEnabled,
            defaultMaximumRenderedDates: Self.maxRenderedDates
        )
    }

    @MainActor
    private func buildPreviews() async {
        isLoading = true
        datePreviews = []
        partialFailures = []
        renderedDayPreviewCount = 0
        estimatedExportSize = nil

        let metadata = analyticsMetadata()
        analytics.trackExportPreviewOpened(metadata: metadata)

        let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)
        totalDateCount = dates.count

        guard settings.hasFileDestinationOutput,
              !(settings.dailyNotesOnlyModeEnabled && targetType == .apiEndpoint) else {
            isLoading = false
            analytics.trackExportPreviewFailed(
                metadata: metadata,
                errorCategory: .configurationUnavailable
            )
            return
        }

        // Walk newest → oldest, fetching at most maxFetchAttempts dates and
        // collecting up to the scope's date limit. Lossless previews intentionally
        // stop after one representative file so inspecting an all-time export does
        // not perform several complete canonical captures.
        let scope = previewScope
        var built: [DatePreview] = []
        var rollupInputs: [HealthData] = []
        var sizeSamples: [ExportPreviewSizeSample] = []
        var warnings: [ExportPartialFailure] = []
        var attempts = 0

        for date in dates.reversed() {
            let renderedCount = settings.summaryOnlyModeEnabled ? rollupInputs.count : built.count
            if renderedCount >= scope.maximumRenderedDates { break }
            if attempts >= Self.maxFetchAttempts { break }
            attempts += 1

            guard let healthData = await fetchHealthData(date) else { continue }
            warnings.append(contentsOf: healthData.partialFailures)
            guard healthData.filtered(by: settings.metricSelection).hasAnyData else { continue }
            rollupInputs.append(healthData)

            if targetType == .apiEndpoint {
                sizeSamples.append(ExportPreviewSizeSample(
                    aggregateByteCount: healthData.export(format: .json, settings: settings).utf8.count
                ))
            } else if settings.summaryOnlyModeEnabled {
                sizeSamples.append(ExportPreviewSizeSample(aggregateByteCount: 0))
            }

            if settings.summaryOnlyModeEnabled { continue }

            let folderPath = settings.dailyNotesOnlyModeEnabled
                ? dailyNoteFolderPath(for: date)
                : previewFolderSummaryPath(for: date)
            var files = (settings.dailyNotesOnlyModeEnabled ? [] : scope.formats)
                .map { format -> FilePreview in
                    let filename = settings.filename(for: date, format: format)
                    let content = healthData.export(format: format, settings: settings)
                    return FilePreview(
                        id: "\(date.timeIntervalSince1970)-\(format.rawValue)",
                        filename: filename,
                        folderPath: previewFolderPath(for: date, format: format),
                        kind: .exportFormat(format),
                        content: content
                    )
                }

            if let collisionWarning = dailyNoteCollisionWarning(for: healthData.date) {
                warnings.append(collisionWarning)
            }

            if scope.includesSupplementalFiles {
                if let dailyNotePreview = dailyNoteInjectionPreview(for: healthData) {
                    if let file = dailyNotePreview.file {
                        files.append(file)
                    }
                    if let warning = dailyNotePreview.warning {
                        warnings.append(warning)
                    }
                }

                files.append(contentsOf: individualEntryPreviews(
                    for: healthData,
                    baseFolderPath: previewFolderPath(
                        for: date,
                        format: settings.organizeFormatsIntoFolders ? .markdown : nil
                    )
                ))
            }

            if targetType != .apiEndpoint {
                sizeSamples.append(ExportPreviewSizeSample(
                    aggregateByteCount: files
                        .filter(\.kind.isDailyAggregateFormat)
                        .reduce(0) { $0 + $1.byteCount },
                    supplementalByteCount: files
                        .filter { !$0.kind.isDailyAggregateFormat }
                        .reduce(0) { $0 + $1.byteCount }
                ))
            }

            built.append(DatePreview(
                id: date,
                date: date,
                dateLabel: Self.dateLabelFormatter.string(from: date),
                folderPath: folderPath,
                files: files
            ))
        }

        renderedDayPreviewCount = settings.summaryOnlyModeEnabled ? rollupInputs.count : built.count
        let rollupSection = targetType == .apiEndpoint
            ? nil
            : rollupSummaryPreviewSection(for: rollupInputs)
        if scope.includesSupplementalFiles, let rollupSection {
            built.insert(rollupSection, at: 0)
        }

        let sampledRollupFiles = rollupSection?.files ?? []
        let renderedAggregateFormatCount: Int
        let selectedAggregateFormatCount: Int
        if targetType == .apiEndpoint {
            renderedAggregateFormatCount = 1
            selectedAggregateFormatCount = 1
        } else if settings.summaryOnlyModeEnabled || settings.dailyNotesOnlyModeEnabled {
            renderedAggregateFormatCount = 0
            selectedAggregateFormatCount = 0
        } else {
            renderedAggregateFormatCount = scope.formats.count
            selectedAggregateFormatCount = settings.exportFormats.count
        }
        estimatedExportSize = ExportPreviewSizeEstimator.estimate(
            totalDateCount: dates.count,
            attemptedDateCount: attempts,
            samples: sizeSamples,
            renderedAggregateFormatCount: renderedAggregateFormatCount,
            selectedAggregateFormatCount: selectedAggregateFormatCount,
            sampledRollupByteCount: sampledRollupFiles.reduce(0) { $0 + $1.byteCount },
            sampledRollupFileCount: sampledRollupFiles.count,
            projectedRollupFileCount: projectedRollupFileCount(for: dates),
            fixedByteCount: fixedExportByteCount
        )

        datePreviews = built
        partialFailures = warnings
        isLoading = false

        if built.isEmpty {
            analytics.trackExportPreviewFailed(
                metadata: metadata,
                errorCategory: .noData
            )
        } else {
            analytics.trackExportPreviewGenerated(metadata: metadata)
        }
    }

    private var fixedExportByteCount: Int {
        guard targetType != .apiEndpoint, !settings.dailyNotesOnlyModeEnabled else { return 0 }

        let entries = HealthMetricDataDictionary.entries(using: settings.formatCustomization)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return ((try? encoder.encode(entries).count) ?? 0) + 1
    }

    private func projectedRollupFileCount(for dates: [Date]) -> Int {
        guard targetType != .apiEndpoint,
              !settings.dailyNotesOnlyModeEnabled,
              !settings.enabledRollupPeriods.isEmpty,
              !settings.exportFormats.isEmpty else { return 0 }

        var windows = Set<HealthRollupPeriodWindow>()
        for period in settings.enabledRollupPeriods {
            for date in dates {
                windows.insert(HealthRollupPeriodWindow.window(
                    containing: date,
                    period: period,
                    calendar: .current
                ))
            }
        }
        return windows.count * settings.exportFormats.count
    }

    private func rollupSummaryPreviewSection(for healthData: [HealthData]) -> DatePreview? {
        guard HealthRollupExporter.isEnabled(settings: settings) else { return nil }

        let summaries = HealthRollupExporter.makeSummaries(
            from: healthData,
            settings: settings
        )
        guard !summaries.isEmpty else { return nil }

        let files = HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: vaultManager.healthSubfolder,
            settings: settings
        ).map { target in
            FilePreview(
                id: "rollup-\(target.summary.period.rawValue)-\(target.summary.periodID)-\(target.format.rawValue)",
                filename: target.filename,
                folderPath: previewRollupFolderPath(for: target.summary.period, format: target.format),
                kind: .rollupSummary(target.summary.period, target.format),
                content: target.content
            )
        }

        return DatePreview(
            id: Date.distantFuture,
            date: Date.distantFuture,
            dateLabel: "Roll-up summaries",
            folderPath: previewRollupFolderPath(for: nil),
            files: files
        )
    }

    private func analyticsMetadata() -> PricingAnalyticsExportMetadata {
        PricingAnalyticsExportMetadata(
            targetType: targetType,
            formatCount: settings.exportFormats.count,
            metricCount: settings.metricSelection.totalEnabledCount,
            dateRangePreset: dateRangePreset,
            startDate: startDate,
            endDate: endDate
        )
    }

    private func individualEntryPreviews(
        for healthData: HealthData,
        baseFolderPath: String
    ) -> [FilePreview] {
        guard settings.writesIndividualEntryFiles else { return [] }

        let exporter = IndividualEntryExporter()
        let samples = exporter.extractIndividualSamples(
            from: healthData,
            settings: settings.individualTracking
        )

        return samples.compactMap { sample in
            guard settings.individualTracking.shouldTrackIndividually(sample.metricId) else {
                return nil
            }

            let metric = HealthMetrics.all.first(where: { $0.id == sample.metricId }) ?? HealthMetricDefinition(
                id: sample.metricId,
                name: sample.metricName,
                category: sample.category,
                unit: sample.unit,
                healthKitIdentifier: nil,
                metricType: .quantity,
                aggregation: .mostRecent
            )
            let entryFolderPath = settings.individualTracking.folderPath(for: metric)
            let filename = exporter.filename(for: sample, settings: settings.individualTracking)
            let content = exporter.previewEntryContent(
                for: sample,
                formatSettings: settings.formatCustomization
            )

            return FilePreview(
                id: "\(sample.timestamp.timeIntervalSince1970)-individual-\(sample.metricId)-\(filename)",
                filename: filename,
                folderPath: baseFolderPath + entryFolderPath + "/",
                kind: .individualEntry,
                content: content
            )
        }
    }

    private enum DailyNotePreviewBaseResolution {
        case resolved(DailyNoteInjector.InjectionPreviewBase)
        case missing
        case unreadable(Error)
    }

    private func dailyNoteInjectionPreview(for healthData: HealthData) -> (file: FilePreview?, warning: ExportPartialFailure?)? {
        let dailyNoteSettings = settings.dailyNoteInjection
        guard dailyNoteSettings.enabled else { return nil }

        let previewBase: DailyNoteInjector.InjectionPreviewBase
        switch dailyNotePreviewBase(for: healthData.date) {
        case .resolved(let base):
            previewBase = base
        case .missing:
            return (
                nil,
                warning(
                    for: healthData.date,
                    message: "Daily note not found and Create note if missing is off: \(dailyNoteSettings.previewPath(for: healthData.date))"
                )
            )
        case .unreadable(let error):
            return (
                nil,
                warning(
                    for: healthData.date,
                    message: "Could not read the existing daily note for preview: \(error.localizedDescription)"
                )
            )
        }

        let result = DailyNoteInjector.preview(
            healthData: healthData,
            base: previewBase,
            settings: dailyNoteSettings,
            customization: settings.formatCustomization,
            metricSelection: settings.metricSelection
        )

        switch result {
        case .preview(let preview):
            return (
                FilePreview(
                    id: "\(healthData.date.timeIntervalSince1970)-daily-note-injection",
                    filename: preview.filename,
                    folderPath: dailyNoteFolderPath(for: healthData.date),
                    kind: .dailyNoteInjection,
                    content: preview.content
                ),
                nil
            )
        case .skipped(let reason):
            return (nil, warning(for: healthData.date, message: reason))
        }
    }

    private func dailyNotePreviewBase(for date: Date) -> DailyNotePreviewBaseResolution {
        let dailyNoteSettings = settings.dailyNoteInjection

        guard targetType == .localFile, let localURL = localDailyNoteURL(for: date) else {
            return .resolved(.emptyDocument)
        }

        guard vaultManager.startVaultAccess() else {
            return .unreadable(ExportError.accessDenied)
        }
        defer { vaultManager.stopVaultAccess() }

        if FileManager.default.fileExists(atPath: localURL.path) {
            do {
                return .resolved(.existingContent(try String(contentsOf: localURL, encoding: .utf8)))
            } catch {
                return .unreadable(error)
            }
        }

        return dailyNoteSettings.createIfMissing ? .resolved(.emptyDocument) : .missing
    }

    private func localDailyNoteURL(for date: Date) -> URL? {
        guard let vaultURL = vaultManager.vaultURL else { return nil }

        return ExportPathPlanner.dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings.dailyNoteInjection,
            date: date
        )
    }

    private func dailyNoteFolderPath(for date: Date) -> String {
        let relativePath = ExportPathPlanner.dailyNoteRelativePath(
            settings: settings.dailyNoteInjection,
            date: date
        )
        let folderComponents = relativePath.split(separator: "/").dropLast().map(String.init)
        var components: [String] = [destinationRootName ?? vaultManager.vaultName]
        components.append(contentsOf: folderComponents)
        return components.joined(separator: "/") + "/"
    }

    private func dailyNoteCollisionWarning(for date: Date) -> ExportPartialFailure? {
        guard !settings.dailyNotesOnlyModeEnabled else { return nil }
        guard let collision = ExportPathPlanner.dailyNoteExportCollision(
            healthSubfolder: vaultManager.healthSubfolder,
            settings: settings,
            date: date
        ) else {
            return nil
        }
        return warning(for: date, message: collision.message)
    }

    private func warning(for date: Date, message: String) -> ExportPartialFailure {
        ExportPartialFailure(
            date: date,
            dataType: "Daily Note",
            dateRangeDescription: Self.dateLabelFormatter.string(from: date),
            errorDescription: message
        )
    }

    private func previewRollupFolderPath(for period: HealthRollupPeriod?, format: ExportFormat? = nil) -> String {
        var components: [String] = [destinationRootName ?? vaultManager.vaultName]
        let relativeFolderPath: String
        if let period {
            relativeFolderPath = HealthRollupExporter.relativeFolderPath(
                healthSubfolder: vaultManager.healthSubfolder,
                period: period,
                format: format,
                settings: settings
            )
        } else {
            relativeFolderPath = [vaultManager.healthSubfolder, "Rollups"]
                .flatMap { $0.split(separator: "/").map(String.init) }
                .joined(separator: "/")
        }
        if !relativeFolderPath.isEmpty {
            components.append(relativeFolderPath)
        }
        return components.joined(separator: "/") + "/"
    }

    private func previewFolderPath(for date: Date, format: ExportFormat? = nil) -> String {
        let relativeFolderPath = ExportPathPlanner.aggregateFolderRelativePath(
            healthSubfolder: vaultManager.healthSubfolder,
            settings: settings,
            date: date,
            format: format
        )
        var components: [String] = [destinationRootName ?? vaultManager.vaultName]
        if !relativeFolderPath.isEmpty {
            components.append(relativeFolderPath)
        }
        return components.joined(separator: "/") + "/"
    }

    private func previewFolderSummaryPath(for date: Date) -> String {
        guard settings.organizeFormatsIntoFolders else {
            return previewFolderPath(for: date)
        }

        var components: [String] = [destinationRootName ?? vaultManager.vaultName]
        if !vaultManager.healthSubfolder.isEmpty {
            components.append(vaultManager.healthSubfolder)
        }
        components.append("{format}")
        if let dateFolder = settings.formatFolderPath(for: date) {
            components.append(dateFolder)
        }
        return components.joined(separator: "/") + "/"
    }

    private static let dateLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d, yyyy"
        return f
    }()
}

// MARK: - File Content View

private struct FileContentView: View {
    let file: FilePreview

    private var displayContent: ExportPreviewDisplayContent {
        ExportPreviewDisplayContent.make(from: file.content)
    }

    var body: some View {
        let content = displayContent

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if content.isTruncated {
                    Label {
                        Text("Showing a lightweight preview of this \(content.originalSizeLabel) file. The full export will still include all data.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "scissors")
                    }
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                }

                Text(content.text)
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.disabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
                    .accessibilityIdentifier(AccessibilityID.ExportPreview.fileContent)
            }
        }
        .background(Color.bgPrimary)
        .navigationTitle(file.filename)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

struct ExportPreviewDisplayContent: Equatable {
    static let defaultMaximumRenderedBytes = 64 * 1024
    static let defaultHeadBytes = 48 * 1024
    static let defaultTailBytes = 16 * 1024

    let text: String
    let originalByteCount: Int
    let omittedByteCount: Int

    var isTruncated: Bool { omittedByteCount > 0 }
    var originalSizeLabel: String { Self.sizeLabel(for: originalByteCount) }
    var omittedSizeLabel: String { Self.sizeLabel(for: omittedByteCount) }

    static func make(
        from content: String,
        maximumRenderedBytes: Int = defaultMaximumRenderedBytes,
        headBytes: Int = defaultHeadBytes,
        tailBytes: Int = defaultTailBytes
    ) -> ExportPreviewDisplayContent {
        guard !content.isEmpty else {
            return ExportPreviewDisplayContent(
                text: "(empty file)",
                originalByteCount: 0,
                omittedByteCount: 0
            )
        }

        let originalByteCount = content.utf8.count
        guard originalByteCount > maximumRenderedBytes else {
            return ExportPreviewDisplayContent(
                text: content,
                originalByteCount: originalByteCount,
                omittedByteCount: 0
            )
        }

        let safeMaximumRenderedBytes = max(1, maximumRenderedBytes)
        let safeHeadBytes = min(max(0, headBytes), safeMaximumRenderedBytes)
        let safeTailBytes = min(max(0, tailBytes), max(0, safeMaximumRenderedBytes - safeHeadBytes))

        let head = prefix(of: content, maxUTF8Bytes: safeHeadBytes)
        let tail = suffix(of: content, maxUTF8Bytes: safeTailBytes)
        let renderedContentBytes = head.utf8.count + tail.utf8.count
        let omittedByteCount = max(0, originalByteCount - renderedContentBytes)
        let marker = "\n\n… Preview truncated: \(sizeLabel(for: omittedByteCount)) omitted from the middle of this \(sizeLabel(for: originalByteCount)) file. …\n\n"

        return ExportPreviewDisplayContent(
            text: head + marker + tail,
            originalByteCount: originalByteCount,
            omittedByteCount: omittedByteCount
        )
    }

    static func sizeLabel(for bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }

    private static func prefix(of content: String, maxUTF8Bytes: Int) -> String {
        guard maxUTF8Bytes > 0 else { return "" }
        guard content.utf8.count > maxUTF8Bytes else { return content }

        var boundary = content.utf8.index(content.utf8.startIndex, offsetBy: maxUTF8Bytes)
        while boundary > content.utf8.startIndex {
            if let stringIndex = String.Index(boundary, within: content) {
                return String(content[..<stringIndex])
            }
            boundary = content.utf8.index(before: boundary)
        }
        return ""
    }

    private static func suffix(of content: String, maxUTF8Bytes: Int) -> String {
        guard maxUTF8Bytes > 0 else { return "" }
        guard content.utf8.count > maxUTF8Bytes else { return content }

        var boundary = content.utf8.index(content.utf8.endIndex, offsetBy: -maxUTF8Bytes)
        while boundary < content.utf8.endIndex {
            if let stringIndex = String.Index(boundary, within: content) {
                return String(content[stringIndex...])
            }
            boundary = content.utf8.index(after: boundary)
        }
        return ""
    }
}

// MARK: - Partial failure helpers

private extension ExportPartialFailure {
    var isBloodPressureAuthorizationNotDetermined: Bool {
        let normalizedDataType = dataType.lowercased()
        let isBloodPressureType = normalizedDataType == "blood pressure systolic"
            || normalizedDataType == "blood pressure diastolic"
            || normalizedDataType.contains("blood pressure")

        return isBloodPressureType && ExportPermissionGuidance(failure: self) != nil
    }
}

// MARK: - Models

private struct DatePreview: Identifiable {
    let id: Date
    let date: Date
    let dateLabel: String
    let folderPath: String
    let files: [FilePreview]
}

private struct FilePreview: Identifiable {
    let id: String
    let filename: String
    let folderPath: String
    let kind: PreviewFileKind
    let content: String

    var byteCount: Int { content.utf8.count }

    var sizeLabel: String {
        let bytes = byteCount
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

private enum PreviewFileKind: Equatable {
    case exportFormat(ExportFormat)
    case rollupSummary(HealthRollupPeriod, ExportFormat)
    case dailyNoteInjection
    case individualEntry

    var iconName: String {
        switch self {
        case .exportFormat(let format): return format.iconName
        case .rollupSummary(_, let format): return format.iconName
        case .dailyNoteInjection: return "note.text"
        case .individualEntry: return "doc.badge.clock"
        }
    }

    var displayName: String {
        switch self {
        case .exportFormat(let format): return format.rawValue
        case .rollupSummary(let period, let format): return "\(period.displayName) Roll-up · \(format.rawValue)"
        case .dailyNoteInjection: return "Daily Note Injection"
        case .individualEntry: return "Individual Entry"
        }
    }

    var isDailyAggregateFormat: Bool {
        if case .exportFormat = self { return true }
        return false
    }

    var accessibilityIdentifierSuffix: String {
        switch self {
        case .exportFormat(let format): return format.rawValue
        case .rollupSummary(let period, let format): return "rollupSummary.\(period.displayName).\(format.rawValue)"
        case .dailyNoteInjection: return "dailyNoteInjection"
        case .individualEntry: return "individualEntry"
        }
    }

    var showsFolderPath: Bool {
        switch self {
        case .dailyNoteInjection, .individualEntry, .rollupSummary:
            return true
        case .exportFormat:
            return true
        }
    }
}

private extension ExportFormat {
    var iconName: String {
        switch self {
        case .markdown: return "doc.text"
        case .obsidianBases: return "tablecells"
        case .json: return "curlybraces"
        case .csv: return "list.bullet.rectangle"
        }
    }
}
