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
    let fetchHealthData: (Date) async -> HealthData?

    @Environment(\.dismiss) private var dismiss

    @State private var datePreviews: [DatePreview] = []
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
                .font(.system(size: 40))
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
            sideEffectsSection
            ForEach(datePreviews) { preview in
                Section {
                    ForEach(preview.files) { file in
                        NavigationLink {
                            FileContentView(file: file)
                        } label: {
                            fileRow(file)
                        }
                    }
                    if preview.files.isEmpty {
                        Text("No data for this date.")
                            .font(.footnote)
                            .foregroundStyle(Color.textMuted)
                    }
                } header: {
                    Text(preview.dateLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                } footer: {
                    if !preview.folderPath.isEmpty {
                        Text(preview.folderPath)
                            .font(.system(size: 11, design: .monospaced))
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
                if totalDateCount > datePreviews.count {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
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
    private var sideEffectsSection: some View {
        let injection = settings.dailyNoteInjection.enabled && settings.exportFormats.contains(.markdown)
        let individual = settings.individualTracking.globalEnabled && settings.exportFormats.contains(.markdown)
        if injection || individual {
            Section("Also writes") {
                if injection {
                    Label {
                        Text("Daily-note injection updates one note per day")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "note.text.badge.plus").foregroundStyle(Color.accent)
                    }
                }
                if individual {
                    Label {
                        Text("Individual entry files for tracked metrics")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "doc.on.doc").foregroundStyle(Color.accent)
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func fileRow(_ file: FilePreview) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: file.format.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentSubtle))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(file.format.rawValue) · \(file.sizeLabel)")
                    .font(.caption)
                    .foregroundStyle(Color.textMuted)
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
        var attempts = 0

        for date in dates.reversed() {
            if built.count >= Self.maxRenderedDates { break }
            if attempts >= Self.maxFetchAttempts { break }
            attempts += 1

            guard let healthData = await fetchHealthData(date), healthData.hasAnyData else { continue }

            let folderPath = previewFolderPath(for: date)
            let files = settings.exportFormats
                .sorted(by: { $0.rawValue < $1.rawValue })
                .map { format -> FilePreview in
                    let filename = settings.filename(for: date, format: format)
                    let content = healthData.export(format: format, settings: settings)
                    return FilePreview(
                        id: "\(date.timeIntervalSince1970)-\(format.rawValue)",
                        filename: filename,
                        folderPath: folderPath,
                        format: format,
                        content: content
                    )
                }

            built.append(DatePreview(
                id: date,
                date: date,
                dateLabel: Self.dateLabelFormatter.string(from: date),
                folderPath: folderPath,
                files: files
            ))
        }

        datePreviews = built
        isLoading = false
    }

    private func previewFolderPath(for date: Date) -> String {
        var components: [String] = [vaultManager.vaultName]
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
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.md)
            }
        }
        .background(Color.bgPrimary)
        .navigationTitle(file.filename)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = file.content
                    #elseif os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(file.content, forType: .string)
                    #endif
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .accessibilityLabel("Copy file contents")
            }
        }
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
    let format: ExportFormat
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
