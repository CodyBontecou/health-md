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
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    HealthMdPageHeader(
                        title: "History",
                        subtitle: "Export history will appear here after your first export"
                    )

                    VStack(spacing: Spacing.s3) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(Typography.heading24())
                            .foregroundStyle(Color.textMuted)
                            .accessibilityHidden(true)
                        Text("No Export History")
                            .font(Typography.headline())
                            .foregroundStyle(Color.textPrimary)
                        Text("Run an export to see status, dates, and file counts here.")
                            .font(Typography.body())
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Spacing.s8)
                    .iPadLiquidGlass()
                }
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s8)
                .iPadContentColumn()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    HealthMdPageHeader(
                        title: "History",
                        subtitle: "Review past Health.md exports and inspect their results"
                    )

                    HStack(spacing: 0) {
                        historyList
                            .frame(minWidth: 350, maxWidth: .infinity, maxHeight: .infinity)

                        Divider()
                            .background(Color.borderSubtle)

                        detailPanel
                            .frame(minWidth: 250, idealWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .iPadLiquidGlass()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .iPadPageBackground()
        .navigationTitle("History")
        .iPadHiddenSystemNavigationTitle()
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
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(Self.dateFormatter.string(from: entry.timestamp))
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)

                        sourceBadge(for: entry)
                    }
                }

                Spacer()

                Text("\(entry.successCount)/\(entry.totalCount)")
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.vertical, 2)
            .tag(entry)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(historyEntryAccessibilityLabel(for: entry))
            .accessibilityHint("Select to view details")
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
                            .font(Typography.heading20())
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(Spacing.s4)
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
                    .padding(Spacing.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .iPadLiquidGlass()

                    if let reason = entry.failureReason {
                        VStack(alignment: .leading, spacing: 8) {
                            iPadBrandLabel("Failure Reason")
                            Text(reason.detailedDescription)
                                .font(Typography.body())
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(Spacing.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .iPadLiquidGlass()
                    }

                    if !entry.partialFailures.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            iPadBrandLabel("Partial Export Warnings")
                            ForEach(Array(entry.partialFailures.enumerated()), id: \.offset) { _, failure in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(Color.warning)
                                        .font(Typography.caption())
                                    Text(failure.summary)
                                        .font(Typography.caption())
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                        }
                        .padding(Spacing.s4)
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
                                        .font(Typography.caption())
                                        .accessibilityHidden(true)
                                    Text(detail.dateString)
                                        .font(Typography.bodyEmphasis())
                                        .foregroundStyle(Color.textPrimary)
                                    Text("— \(detail.reason.shortDescription)")
                                        .font(Typography.caption())
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                        }
                        .padding(Spacing.s4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .iPadLiquidGlass()
                    }

                    Spacer()
                }
                .padding(Spacing.s4)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(Typography.heading24())
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
                Text("Select an export to see details")
                    .font(Typography.body())
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
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func sourceBadge(for entry: ExportHistoryEntry) -> some View {
        Text(entry.source.rawValue)
            .font(Typography.caption())
            .foregroundStyle(Color.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.bgSecondary)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
    }

    private func dateRangeString(_ entry: ExportHistoryEntry) -> String {
        let start = Self.rangeDateFormatter.string(from: entry.dateRangeStart)
        let end = Self.rangeDateFormatter.string(from: entry.dateRangeEnd)
        return start == end ? start : "\(start) → \(end)"
    }

    private func historyEntryAccessibilityLabel(for entry: ExportHistoryEntry) -> String {
        let status = entry.isFullSuccess ? "Success" : entry.success ? "Partial success" : "Failed"
        return "\(status). \(entry.summaryDescription). \(entry.successCount) of \(entry.totalCount) files. \(Self.dateFormatter.string(from: entry.timestamp)). Source: \(entry.source.rawValue)."
    }
}
