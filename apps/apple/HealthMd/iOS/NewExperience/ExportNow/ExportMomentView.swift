#if os(iOS)
import SwiftUI

/// MomentGlass: progress over the shell while an interactive export runs.
struct ExportMomentView: View {
    let progress: Double
    let message: String
    let onCancel: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Exporting…")).glassFont(.navTitle).foregroundStyle(palette.text)
                Spacer()
                Text(verbatim: progress.formatted(.percent.precision(.fractionLength(0))))
                    .glassFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(palette.muted)
            }
            ProgressView(value: min(max(progress, 0), 1)).tint(palette.accent)
            HStack {
                Text(message).glassFont(.rowSubtitle).foregroundStyle(palette.sec).lineLimit(2)
                Spacer()
                Button(String(localized: "Cancel"), action: onCancel)
                    .buttonStyle(.plain)
                    .glassFont(.caption)
                    .foregroundStyle(palette.accent)
                    .frame(minHeight: GlassMetrics.touchTarget)
            }
        }
        .padding(GlassMetrics.panelPadding)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius, style: .strong)
        .padding(.horizontal, GlassMetrics.screenMargin)
        .accessibilityElement(children: .contain)
    }
}

/// ExportResultG, shown when a run did not fully succeed.
struct ExportResultScreen: View {
    let entry: ExportHistoryEntry
    let onRetry: (Date, Date) -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    Text(entry.summaryDescription).glassFont(.screenTitle).foregroundStyle(palette.text)
                    if !entry.failedDateDetails.isEmpty {
                        GlassPanel {
                            ForEach(entry.failedDateDetails, id: \.date) { detail in
                                GlassRow(
                                    title: detail.date.formatted(.dateTime.month(.abbreviated).day()),
                                    subtitle: detail.reason.shortDescription
                                ) {
                                    StatusBadge(title: String(localized: "Failed"), status: .missing)
                                }
                            }
                        }
                        Text("Completed dates stay completed. Retry writes only the failed dates.")
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(palette.muted)
                    }
                    if let suggestion = entry.failureRecoverySuggestion {
                        GlassBanner(title: suggestion, systemImage: "lightbulb", tone: .info)
                    }
                    if let first = entry.failedDateDetails.map(\.date).min(),
                       let last = entry.failedDateDetails.map(\.date).max() {
                        Button(String(localized: "Retry")) {
                            dismiss()
                            onRetry(first, last)
                        }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    }
                }
                .padding(GlassMetrics.screenMargin)
            }
            .background(palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }
}
#endif
