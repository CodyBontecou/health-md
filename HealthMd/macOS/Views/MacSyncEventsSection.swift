#if os(macOS)
import SwiftUI

// MARK: - Recent Syncs Section

/// Renders the persistent iPhone→Mac sync history as a section inside MacSyncView.
struct MacSyncEventsSection: View {
    @ObservedObject private var historyManager = SyncEventHistoryManager.shared
    @State private var showAll = false
    @State private var showClearConfirmation = false

    private static let inlineLimit = 5

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                BrandLabel("Recent Syncs")
                Spacer()
                if !historyManager.history.isEmpty {
                    Button("Clear") {
                        showClearConfirmation = true
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .tint(Color.error)
                    .accessibilityLabel("Clear sync history")
                    .accessibilityHint("Removes all recorded sync events")
                }
            }

            if historyManager.history.isEmpty {
                emptyState
            } else {
                eventsList
                if historyManager.history.count > Self.inlineLimit {
                    Button(showAll
                           ? String(localized: "Show fewer", comment: "Collapse expanded sync history")
                           : String(localized: "Show all (\(historyManager.history.count))",
                                    comment: "Expand sync history button")) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showAll.toggle()
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .tint(Color.accent)
                    .padding(.top, 4)
                    .accessibilityHint(showAll ? "Collapses the list to the most recent syncs" : "Expands the list to show all stored sync events")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brandGlassCard()
        .alert("Clear Sync History?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                historyManager.clearHistory()
                showAll = false
            }
        } message: {
            Text("This removes all recorded iPhone→Mac sync events from this Mac. Your synced health data is not affected.")
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
            Text("No sync history yet. Run a sync to see it here.")
                .font(BrandTypography.body())
                .foregroundStyle(Color.textMuted)
        }
    }

    private var eventsList: some View {
        let entries = showAll
            ? historyManager.history
            : Array(historyManager.history.prefix(Self.inlineLimit))

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(entries.indices, id: \.self) { index in
                if index > 0 {
                    Divider().opacity(0.25)
                }
                row(for: entries[index])
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func row(for entry: SyncEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(for: entry)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.summaryDescription)
                        .font(BrandTypography.bodyMedium())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if entry.kind == .dataReceived && entry.payloadByteEstimate > 0 {
                        Text(byteString(entry.payloadByteEstimate))
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.textMuted)
                    }
                }

                HStack(spacing: 8) {
                    Text(Self.timestampFormatter.string(from: entry.timestamp))
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                    Text("·")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                    Text(entry.peerName)
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }

                if let rangeText = dateRangeString(entry) {
                    Text(rangeText)
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: entry))
    }

    @ViewBuilder
    private func statusIcon(for entry: SyncEvent) -> some View {
        switch entry.kind {
        case .dataReceived:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
        case .progressComplete:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.error)
        }
    }

    // MARK: - Helpers

    private func dateRangeString(_ entry: SyncEvent) -> String? {
        guard let start = entry.dateRangeStart, let end = entry.dateRangeEnd else {
            return nil
        }
        let s = Self.rangeFormatter.string(from: start)
        let e = Self.rangeFormatter.string(from: end)
        return s == e ? s : "\(s) → \(e)"
    }

    private func byteString(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func accessibilityLabel(for entry: SyncEvent) -> String {
        let status = entry.isSuccess ? "Success" : "Failed"
        let date = Self.timestampFormatter.string(from: entry.timestamp)
        return "\(status). \(entry.summaryDescription). From \(entry.peerName). \(date)."
    }
}

#endif
