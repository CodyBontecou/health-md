#if os(macOS)
import SwiftUI

// MARK: - History (MacHistoryG)

/// "History" header, glass rows of when/status, and a detail panel with why it failed, what to
/// do, the failed dates on one mono line, and a "Technical details · Open GitHub issue" link.
struct MacHistoryView: View {
    @ObservedObject private var historyManager = ExportHistoryManager.shared
    @StateObject private var feedbackReporter = FeedbackReporter()
    @State private var selectedEntry: ExportHistoryEntry?
    @State private var showsTechnicalDetails = false

    private static let rangeDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("History")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.glassAdaptive(\.text))
                .accessibilityAddTraits(.isHeader)

            if historyManager.history.isEmpty {
                emptyState
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        historyList
                            .frame(minWidth: 320, maxWidth: .infinity)
                        detailPanel
                            .frame(minWidth: 320, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        historyList
                            .frame(maxHeight: 280)
                        detailPanel
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.glassAdaptive(\.bg).ignoresSafeArea())
        .foregroundStyle(Color.glassAdaptive(\.text))
        .tint(Color.glassAdaptive(\.accent))
        .navigationTitle("History")
        .toolbar {
            if !historyManager.history.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear History", role: .destructive) {
                        selectedEntry = nil
                        historyManager.clearHistory()
                    }
                    .tint(Color.error)
                    .accessibilityLabel("Clear history")
                    .accessibilityHint("Removes all export history entries")
                }
            }
        }
        .feedbackFailureSheet($feedbackReporter.failure)
        .onAppear {
            selectDefaultEntryIfNeeded()
        }
        .onChange(of: historyManager.history.count, initial: false) { _, _ in
            selectDefaultEntryIfNeeded()
        }
        .onChange(of: selectedEntry?.id) { _, _ in
            showsTechnicalDetails = false
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Export History")
                .font(.system(size: 16, weight: .bold))
            Text("Export history will appear here after your first export.")
                .font(.system(size: 13))
                .foregroundStyle(Color.glassAdaptive(\.muted))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 16)
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(historyManager.history.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { MacGlassDivider() }
                    historyRow(entry)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func historyRow(_ entry: ExportHistoryEntry) -> some View {
        let isSelected = selectedEntry?.id == entry.id
        return Button {
            selectedEntry = entry
        } label: {
            HStack(spacing: 12) {
                Text(ExportHistorySummaryFormat.historyWhen(entry.timestamp))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.glassAdaptive(\.text))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.historyStatusLine)
                    .font(.system(size: 13))
                    .foregroundStyle(statusColor(for: entry))
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(historyEntryAccessibilityLabel(for: entry))
        .accessibilityHint("Select to view details")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func historyEntryAccessibilityLabel(for entry: ExportHistoryEntry) -> String {
        let date = ExportHistorySummaryFormat.historyWhen(entry.timestamp)
        let base = "\(date): \(entry.historyStatusLine). \(entry.summaryDescription). \(entry.resultCountAccessibilityDescription)"
        guard let message = entry.failureListMessage else { return base }
        return "\(base). \(message)"
    }

    private func statusColor(for entry: ExportHistoryEntry) -> Color {
        entry.isFullSuccess ? Color.glassAdaptive(\.ok) : Color.glassAdaptive(\.coral)
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let entry = selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.historyDetailTitle())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.glassAdaptive(\.text))
                        .accessibilityAddTraits(.isHeader)

                    if let reason = entry.failureReasonForDisplay {
                        detailBlock(String(localized: "Why it failed"), reason.detailedDescription)
                        detailBlock(String(localized: "What to do"), reason.recoverySuggestion)
                    } else {
                        detailBlock(String(localized: "Date Range"), dateRangeString(entry), monospaced: true)
                    }

                    if let failedDates = entry.failedDatesLine {
                        detailBlock(String(localized: "Failed dates"), failedDates, monospaced: true)
                    }

                    linksLine(for: entry)

                    if showsTechnicalDetails {
                        technicalDetails(for: entry)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func detailBlock(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.glassAdaptive(\.muted))
                .accessibilityAddTraits(.isHeader)
            Text(value)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .lineSpacing(monospaced ? 0 : 3)
                .foregroundStyle(Color.glassAdaptive(\.text))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    /// "Technical details · Open GitHub issue"; the issue link only follows an unsuccessful export.
    private func linksLine(for entry: ExportHistoryEntry) -> some View {
        HStack(spacing: 0) {
            Button(String(localized: "Technical details")) {
                showsTechnicalDetails.toggle()
            }
            .accessibilityAddTraits(showsTechnicalDetails ? .isSelected : [])
            if !entry.isFullSuccess {
                Text(verbatim: " · ")
                    .accessibilityHidden(true)
                Button(String(localized: "Open GitHub issue")) {
                    feedbackReporter.open(.github)
                }
            }
        }
        .buttonStyle(MacGlassRowButtonStyle())
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.glassAdaptive(\.accent))
    }

    private func technicalDetails(for entry: ExportHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MacGlassDivider()
            technicalRow(String(localized: "Timestamp"), entry.timestamp.formatted(date: .abbreviated, time: .shortened))
            technicalRow(String(localized: "Source"), entry.source.localizedDisplayName)
            if let targetLabel = entry.targetLabel {
                technicalRow(String(localized: "Target"), targetLabel)
            }
            technicalRow(String(localized: "Date Range"), dateRangeString(entry))
            technicalRow(entry.resultCountLabel, entry.resultCountDescription)

            ForEach(entry.failedDateDetails, id: \.dateString) { detail in
                technicalRow(detail.dateString, detail.reason.shortDescription)
            }

            ForEach(Array(entry.partialFailures.enumerated()), id: \.offset) { _, failure in
                Text(failure.localizedSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.glassAdaptive(\.muted))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !entry.failureDiagnosticDetails.isEmpty {
                ForEach(entry.failureDiagnosticDetails, id: \.self) { details in
                    Text(details)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color.glassAdaptive(\.sec))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("If the suggested fix does not work, include this message in your bug report after removing any private folder or server information.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.glassAdaptive(\.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func technicalRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.glassAdaptive(\.muted))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Color.glassAdaptive(\.text))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

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
