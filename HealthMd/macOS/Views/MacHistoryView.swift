#if os(macOS)
import SwiftUI

// MARK: - History View

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
                ContentUnavailableView(
                    "No Export History",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Export history will appear here after your first export.")
                )
            } else {
                HSplitView {
                    historyList
                        .frame(minWidth: 350)

                    detailPanel
                        .frame(minWidth: 250, idealWidth: 300)
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
                }
            }
        }
    }

    // MARK: - History List

    private var historyList: some View {
        List(historyManager.history, selection: $selectedEntry) { entry in
            HStack(spacing: 10) {
                // Status icon
                statusIcon(for: entry)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.summaryDescription)
                        .font(.body)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(Self.dateFormatter.string(from: entry.timestamp))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        sourceBadge(for: entry)
                    }
                }

                Spacer()

                // File count
                Text("\(entry.successCount)/\(entry.totalCount)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 16) {
                    // Status header
                    HStack {
                        statusIcon(for: entry)
                        Text(entry.isFullSuccess ? "Success" : entry.success ? "Partial" : "Failed")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    Divider()

                    // Details
                    detailRow("Timestamp", value: Self.dateFormatter.string(from: entry.timestamp))
                    detailRow("Source", value: entry.source.rawValue)
                    detailRow("Date Range", value: dateRangeString(entry))
                    detailRow("Files Exported", value: "\(entry.successCount) of \(entry.totalCount)")

                    if let reason = entry.failureReason {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Failure Reason")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(reason.detailedDescription)
                                .font(.callout)
                        }
                    }

                    if !entry.failedDateDetails.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Failed Dates")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(entry.failedDateDetails, id: \.dateString) { detail in
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                    Text(detail.dateString)
                                        .font(.callout)
                                        .monospacedDigit()
                                    Text("— \(detail.reason.shortDescription)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
        } else {
            VStack {
                Spacer()
                Text("Select an export to see details")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(for entry: ExportHistoryEntry) -> some View {
        Image(systemName: entry.isFullSuccess
              ? "checkmark.circle.fill"
              : entry.success ? "exclamationmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(entry.isFullSuccess ? .green : entry.success ? .orange : .red)
    }

    @ViewBuilder
    private func sourceBadge(for entry: ExportHistoryEntry) -> some View {
        Text(entry.source.rawValue)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }

    @ViewBuilder
    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
        }
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
