import SwiftUI

// Make ExportHistoryEntry selectable on iOS
extension ExportHistoryEntry: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: ExportHistoryEntry, rhs: ExportHistoryEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - iPad History View (matching macOS MacHistoryView)

struct iPadHistoryView: View {
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
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                    Text("Export history will appear here after your first export.")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.textMuted)
                }
            } else {
                HStack(spacing: 0) {
                    historyList
                        .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)

                    Divider()
                        .opacity(0.3)

                    detailPanel
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !historyManager.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear History", role: .destructive) {
                        selectedEntry = nil
                        historyManager.clearHistory()
                    }
                    .tint(Color.error)
                }
            }
        }
    }

    // MARK: - History List

    private var historyList: some View {
        List(historyManager.history, selection: $selectedEntry) { entry in
            HStack(spacing: 10) {
                statusIcon(for: entry)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.summaryDescription)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(Self.dateFormatter.string(from: entry.timestamp))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.textMuted)

                        sourceBadge(for: entry)
                    }
                }

                Spacer()

                Text("\(entry.successCount)/\(entry.totalCount)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
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
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .iPadLiquidGlass()

                    // Details card
                    VStack(alignment: .leading, spacing: 12) {
                        iPadBrandLabel("Details")

                        iPadBrandDataRow(label: "Timestamp", value: Self.dateFormatter.string(from: entry.timestamp))
                        iPadBrandDataRow(label: "Source", value: entry.source.rawValue)
                        iPadBrandDataRow(label: "Date Range", value: dateRangeString(entry))
                        iPadBrandDataRow(label: "Files Exported", value: "\(entry.successCount) of \(entry.totalCount)")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .iPadLiquidGlass()

                    if let reason = entry.failureReason {
                        VStack(alignment: .leading, spacing: 8) {
                            iPadBrandLabel("Failure Reason")
                            Text(reason.detailedDescription)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .iPadLiquidGlass()
                    }

                    if !entry.failedDateDetails.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            iPadBrandLabel("Failed Dates")
                            ForEach(entry.failedDateDetails, id: \.dateString) { detail in
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color.error)
                                        .font(.caption)
                                    Text(detail.dateString)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.textPrimary)
                                    Text("— \(detail.reason.shortDescription)")
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .iPadLiquidGlass()
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
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
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
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
    }

    private func dateRangeString(_ entry: ExportHistoryEntry) -> String {
        let start = Self.rangeDateFormatter.string(from: entry.dateRangeStart)
        let end = Self.rangeDateFormatter.string(from: entry.dateRangeEnd)
        return start == end ? start : "\(start) → \(end)"
    }
}
