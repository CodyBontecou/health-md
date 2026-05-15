import SwiftUI

// MARK: - Export Preview
// Shows the user a dry-run of what will be written to their vault for the
// current date range, format selection, and customization settings — actual
// filenames, folder paths, and the rendered file contents per format.
//
// Side effects (individual entry tracking, daily-note injection) are hinted
// at the top of the screen but not rendered in full to keep the preview fast.

struct ExportPreviewView: View {
    let startDate: Date
    let endDate: Date
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var settings: AdvancedExportSettings
    let destinationLabel: String
    let destinationRootName: String?
    let fetchHealthData: (Date) async -> HealthData?

    @Environment(\.dismiss) private var dismiss

    @State private var datePreviews: [DatePreview] = []
    @State private var partialFailures: [ExportPartialFailure] = []
    @State private var isLoading = true
    @State private var totalDateCount = 0

    /// Cap how many dates we render so opening preview never feels slow.
    /// We also cap how many dates we'll *fetch* — preview is for shape, not census.
    private static let maxRenderedDates = 5
    private static let maxFetchAttempts = 14

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if datePreviews.isEmpty {
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
    }

    // MARK: - States

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
                    Text("\(settings.exportFormats.count)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.textPrimary)
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
                if totalDateCount > datePreviews.count {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text("Previewing the \(datePreviews.count) most recent day\(datePreviews.count == 1 ? "" : "s") with data. The full export will run on every selected date.")
                            .font(.caption)
                    }
                    .foregroundStyle(Color.textMuted)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var partialFailuresSection: some View {
        if !partialFailures.isEmpty {
            Section("Warnings") {
                ForEach(Array(partialFailures.enumerated()), id: \.offset) { _, failure in
                    Label {
                        Text(failure.summary)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                    }
                }
            }
        }
    }

    // MARK: - Row

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
                if file.kind == .individualEntry {
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

    // MARK: - Build previews

    private func buildPreviews() async {
        let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)
        totalDateCount = dates.count

        guard !settings.exportFormats.isEmpty else {
            isLoading = false
            return
        }

        // Walk newest → oldest, fetching at most maxFetchAttempts dates and
        // collecting up to maxRenderedDates previews. Newest-first matches
        // what users want to see and avoids paying for empty leading days.
        var built: [DatePreview] = []
        var warnings: [ExportPartialFailure] = []
        var attempts = 0

        for date in dates.reversed() {
            if built.count >= Self.maxRenderedDates { break }
            if attempts >= Self.maxFetchAttempts { break }
            attempts += 1

            guard let healthData = await fetchHealthData(date) else { continue }
            warnings.append(contentsOf: healthData.partialFailures)
            guard healthData.hasAnyData else { continue }

            let folderPath = previewFolderPath(for: date)
            var files = settings.exportFormats
                .sorted(by: { $0.rawValue < $1.rawValue })
                .map { format -> FilePreview in
                    let filename = settings.filename(for: date, format: format)
                    let content = healthData.export(format: format, settings: settings)
                    return FilePreview(
                        id: "\(date.timeIntervalSince1970)-\(format.rawValue)",
                        filename: filename,
                        folderPath: folderPath,
                        kind: .exportFormat(format),
                        content: content
                    )
                }

            files.append(contentsOf: individualEntryPreviews(
                for: healthData,
                baseFolderPath: folderPath
            ))

            built.append(DatePreview(
                id: date,
                date: date,
                dateLabel: Self.dateLabelFormatter.string(from: date),
                folderPath: folderPath,
                files: files
            ))
        }

        datePreviews = built
        partialFailures = warnings
        isLoading = false
    }

    private func individualEntryPreviews(
        for healthData: HealthData,
        baseFolderPath: String
    ) -> [FilePreview] {
        guard settings.individualTracking.globalEnabled else { return [] }

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
            let filename = settings.individualTracking.filename(for: metric, date: sample.timestamp, time: sample.timestamp)
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

    private func previewFolderPath(for date: Date) -> String {
        var components: [String] = [destinationRootName ?? vaultManager.vaultName]
        if !vaultManager.healthSubfolder.isEmpty {
            components.append(vaultManager.healthSubfolder)
        }
        if let folderPath = settings.formatFolderPath(for: date), !folderPath.isEmpty {
            components.append(folderPath)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(file.content.isEmpty ? "(empty file)" : file.content)
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
    case individualEntry

    var iconName: String {
        switch self {
        case .exportFormat(let format): return format.iconName
        case .individualEntry: return "doc.badge.clock"
        }
    }

    var displayName: String {
        switch self {
        case .exportFormat(let format): return format.rawValue
        case .individualEntry: return "Individual Entry"
        }
    }

    var accessibilityIdentifierSuffix: String {
        switch self {
        case .exportFormat(let format): return format.rawValue
        case .individualEntry: return "individualEntry"
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
