import SwiftUI
import ExportKit

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
    private let analytics = PricingAnalyticsClient.shared

    @Environment(\.dismiss) private var dismiss

    @State private var datePreviews: [DatePreview] = []
    @State private var previewWarnings: [ExportWarning] = []
    @State private var isLoading = true
    @State private var totalDateCount = 0

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
        if !previewWarnings.isEmpty {
            Section("Warnings") {
                ForEach(Array(previewWarnings.enumerated()), id: \.offset) { _, warning in
                    Label {
                        Text(warning.message)
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

    // MARK: - Build previews

    private func buildPreviews() async {
        let metadata = analyticsMetadata()
        analytics.trackExportPreviewOpened(metadata: metadata)

        let dates = ExportOrchestrator.dateRange(from: startDate, to: endDate)
        totalDateCount = dates.count

        guard !settings.exportFormats.isEmpty else {
            isLoading = false
            analytics.trackExportPreviewFailed(
                metadata: metadata,
                errorCategory: .configurationUnavailable
            )
            return
        }

        do {
            let preview = try await HealthExportPreviewBuilder.buildPreview(
                dates: dates,
                vaultManager: vaultManager,
                settings: settings,
                destinationRootName: destinationRootName,
                targetType: targetType,
                fetchHealthData: fetchHealthData
            )
            let rootName = destinationRootName ?? vaultManager.vaultName
            datePreviews = preview.records.map { DatePreview(record: $0, rootName: rootName) }
            previewWarnings = preview.warnings
            isLoading = false

            if preview.records.isEmpty {
                analytics.trackExportPreviewFailed(
                    metadata: metadata,
                    errorCategory: .noData
                )
            } else {
                analytics.trackExportPreviewGenerated(metadata: metadata)
            }
        } catch {
            datePreviews = []
            previewWarnings = [ExportWarning(
                id: "healthmd.preview.error",
                message: "Could not build export preview: \(error.localizedDescription)"
            )]
            isLoading = false
            analytics.trackExportPreviewFailed(
                metadata: metadata,
                errorCategory: .configurationUnavailable
            )
        }
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

    fileprivate static let dateLabelFormatter: DateFormatter = {
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

// MARK: - Models

private struct DatePreview: Identifiable {
    let id: Date
    let date: Date
    let dateLabel: String
    let folderPath: String
    let files: [FilePreview]

    init(record: ExportPreviewRecord, rootName: String) {
        let date = record.reference.date ?? Date(timeIntervalSince1970: 0)
        let aggregateFolderPath = record.files.firstAggregateFolderPath ?? record.files.first?.relativeFolderPath ?? ""

        self.id = date
        self.date = date
        self.dateLabel = ExportPreviewView.dateLabelFormatter.string(from: date)
        self.folderPath = Self.displayFolderPath(relativeFolderPath: aggregateFolderPath, rootName: rootName)
        self.files = record.files.map { FilePreview(plannedFile: $0, rootName: rootName) }
    }

    private static func displayFolderPath(relativeFolderPath: String, rootName: String) -> String {
        var components: [String] = [rootName]
        components.append(contentsOf: relativeFolderPath.previewPathComponents)
        return components.joined(separator: "/") + "/"
    }
}

private struct FilePreview: Identifiable {
    let id: String
    let filename: String
    let folderPath: String
    let kind: PreviewFileKind
    let content: String
    let sizeLabel: String

    init(plannedFile: PlannedExportFile, rootName: String) {
        self.id = plannedFile.id
        self.filename = plannedFile.filename
        self.folderPath = Self.displayFolderPath(
            relativeFolderPath: plannedFile.relativeFolderPath,
            rootName: rootName
        )
        self.kind = PreviewFileKind(plannedFile: plannedFile)
        self.content = plannedFile.content
        self.sizeLabel = plannedFile.sizeLabel
    }

    private static func displayFolderPath(relativeFolderPath: String, rootName: String) -> String {
        var components: [String] = [rootName]
        components.append(contentsOf: relativeFolderPath.previewPathComponents)
        return components.joined(separator: "/") + "/"
    }
}

private enum PreviewFileKind: Equatable {
    case exportFormat(ExportFormat)
    case dailyNoteInjection
    case individualEntry
    case plannedFile(String)

    init(plannedFile: PlannedExportFile) {
        switch plannedFile.role {
        case .aggregate(let formatID):
            if let format = ExportFormat(exportKitFormatID: formatID) {
                self = .exportFormat(format)
            } else {
                self = .plannedFile(plannedFile.displayName ?? "Export File")
            }
        case .mutation(let pluginID) where pluginID == HealthExportPreviewBuilder.dailyNoteInjectionPluginID:
            self = .dailyNoteInjection
        case .supplemental(let pluginID) where pluginID == HealthExportPreviewBuilder.individualEntryPluginID:
            self = .individualEntry
        case .mutation, .supplemental:
            self = .plannedFile(plannedFile.displayName ?? "Supplemental File")
        }
    }

    var iconName: String {
        switch self {
        case .exportFormat(let format): return format.iconName
        case .dailyNoteInjection: return "note.text"
        case .individualEntry: return "doc.badge.clock"
        case .plannedFile: return "doc.text"
        }
    }

    var displayName: String {
        switch self {
        case .exportFormat(let format): return format.rawValue
        case .dailyNoteInjection: return "Daily Note Injection"
        case .individualEntry: return "Individual Entry"
        case .plannedFile(let displayName): return displayName
        }
    }

    var accessibilityIdentifierSuffix: String {
        switch self {
        case .exportFormat(let format): return format.rawValue
        case .dailyNoteInjection: return "dailyNoteInjection"
        case .individualEntry: return "individualEntry"
        case .plannedFile(let displayName): return displayName.previewAccessibilitySuffix
        }
    }

    var showsFolderPath: Bool {
        switch self {
        case .dailyNoteInjection, .individualEntry, .plannedFile:
            return true
        case .exportFormat:
            return false
        }
    }
}

private extension Array where Element == PlannedExportFile {
    var firstAggregateFolderPath: String? {
        first { file in
            if case .aggregate = file.role { return true }
            return false
        }?.relativeFolderPath
    }
}

private extension String {
    var previewPathComponents: [String] {
        split(separator: "/").map(String.init).filter { !$0.isEmpty }
    }

    var previewAccessibilitySuffix: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let suffix = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return suffix.isEmpty ? "plannedFile" : suffix
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
