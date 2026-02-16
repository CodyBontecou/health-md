#if os(macOS)
import SwiftUI

// MARK: - History View — Branded

struct MacHistoryView: View {
    @ObservedObject private var historyManager = ExportHistoryManager.shared
    @State private var selectedEntry: ExportHistoryEntry?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let rangeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        Group {
            if historyManager.history.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.textMuted)
                    Text("No Export History")
                        .font(BrandTypography.subheading())
                        .foregroundStyle(Color.textPrimary)
                    Text("Export history will appear here after your first export.")
                        .font(BrandTypography.body())
                        .foregroundStyle(Color.textMuted)
                }
            } else {
                GeometryReader { proxy in
                    if proxy.size.width < 980 {
                        VStack(spacing: 0) {
                            historyList
                                .frame(minHeight: 220, idealHeight: 280, maxHeight: 320)

                            Divider()
                                .opacity(0.3)

                            detailPanel
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        HSplitView {
                            historyList
                                .frame(minWidth: 320, idealWidth: 380, maxWidth: .infinity, maxHeight: .infinity)

                            detailPanel
                                .frame(minWidth: 300, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !historyManager.history.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear History", role: .destructive) {
                        selectedEntry = nil
                        historyManager.clearHistory()
                    }
                    .tint(Color.error)
                }
            }
        }
        .onAppear {
            selectDefaultEntryIfNeeded()
        }
        .onChange(of: historyManager.history.count, initial: false) { _, _ in
            selectDefaultEntryIfNeeded()
        }
    }

    // MARK: - History List

    private var historyList: some View {
        List(historyManager.history, selection: $selectedEntry) { entry in
            HStack(spacing: 10) {
                statusIcon(for: entry)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.summaryDescription)
                        .font(BrandTypography.bodyMedium())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(Self.dateFormatter.string(from: entry.timestamp))
                            .font(BrandTypography.caption())
                            .foregroundStyle(Color.textMuted)

                        sourceBadge(for: entry)
                    }
                }

                Spacer()

                Text("\(entry.successCount)/\(entry.totalCount)")
                    .font(BrandTypography.value())
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.vertical, 2)
            .tag(entry)
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status header
                    HStack(spacing: 8) {
                        statusIcon(for: entry)
                        Text(entry.isFullSuccess ? "Success" : entry.success ? "Partial" : "Failed")
                            .font(BrandTypography.heading())
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandGlassCard()

                    // Details card
                    VStack(alignment: .leading, spacing: 12) {
                        BrandLabel("Details")

                        detailDataRow(label: "Timestamp", value: Self.dateFormatter.string(from: entry.timestamp))
                        detailDataRow(label: "Source", value: entry.source.rawValue)
                        detailDataRow(label: "Date Range", value: dateRangeString(entry))
                        detailDataRow(label: "Files Exported", value: "\(entry.successCount) of \(entry.totalCount)")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .brandGlassCard()

                    if let reason = entry.failureReason {
                        VStack(alignment: .leading, spacing: 8) {
                            BrandLabel("Failure Reason")
                            Text(reason.detailedDescription)
                                .font(BrandTypography.body())
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .brandGlassCard(tintOpacity: 0.02)
                    }

                    if !entry.failedDateDetails.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            BrandLabel("Failed Dates")
                            ForEach(entry.failedDateDetails, id: \.dateString) { detail in
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color.error)
                                        .font(.caption)
                                    Text(detail.dateString)
                                        .font(BrandTypography.value())
                                        .foregroundStyle(Color.textPrimary)
                                    Text("— \(detail.reason.shortDescription)")
                                        .font(BrandTypography.caption())
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .brandGlassCard(tintOpacity: 0.02)
                    }

                    Spacer()
                }
                .padding(16)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.textMuted)
                Text("Select an export to see details")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(for entry: ExportHistoryEntry) -> some View {
        Image(systemName: entry.isFullSuccess
              ? "checkmark.circle.fill"
              : entry.success ? "exclamationmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(entry.isFullSuccess ? Color.success : entry.success ? Color.warning : Color.error)
    }

    @ViewBuilder
    private func sourceBadge(for entry: ExportHistoryEntry) -> some View {
        Text(entry.source.rawValue)
            .font(BrandTypography.caption())
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .brandGlassPill()
    }

    @ViewBuilder
    private func detailDataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(BrandTypography.body())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(value)
                .font(BrandTypography.value())
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .layoutPriority(1)
        }
    }

    private func selectDefaultEntryIfNeeded() {
        guard !historyManager.history.isEmpty else {
            selectedEntry = nil
            return
        }

        if let selectedEntry,
           historyManager.history.contains(where: { $0.id == selectedEntry.id }) {
            return
        }

        self.selectedEntry = historyManager.history.first
    }

    private func dateRangeString(_ entry: ExportHistoryEntry) -> String {
        let start = Self.rangeDateFormatter.string(from: entry.dateRangeStart)
        let end = Self.rangeDateFormatter.string(from: entry.dateRangeEnd)
        return start == end ? start : "\(start) → \(end)"
    }
}

// Make ExportHistoryEntry selectable
extension ExportHistoryEntry: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ExportHistoryEntry, rhs: ExportHistoryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

#endif
