import SwiftUI

struct ExportFormatHelpSheet: View {
    let showJSONTip: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    header

                    VStack(spacing: Spacing.s3) {
                        formatRow(
                            icon: "curlybraces.square.fill",
                            title: "JSON",
                            subtitle: "Complete structured data",
                            detail: "Best for backups, automation, and future re-imports. Preserves workouts, route points, timestamped samples, medications, and metadata."
                        )

                        formatRow(
                            icon: "doc.text.fill",
                            title: "Markdown & Obsidian Bases",
                            subtitle: "Readable notes and flat properties",
                            detail: "Best for daily notes, Obsidian browsing, and Bases tables. Nested health data is summarized or flattened for easier querying."
                        )

                        formatRow(
                            icon: "tablecells.fill",
                            title: "CSV",
                            subtitle: "Spreadsheet-friendly rows",
                            detail: "Best for spreadsheets and data analysis tools. Nested data is expanded into rows instead of preserved as objects."
                        )
                    }

                    if showJSONTip {
                        HStack(alignment: .top, spacing: Spacing.s2) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundStyle(Color.accent)
                            Text(ExportRolloutCopy.jsonFormatTip)
                                .font(Typography.caption())
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(Spacing.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentSubtle)
                        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
                    }
                }
                .padding(Spacing.s6)
            }
            .background(Color.bgPrimary)
            .navigationTitle("Export Formats")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: "info.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 44, height: 44)
                .background(Color.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Choose the format for your workflow")
                    .font(Typography.heading20())
                    .foregroundStyle(Color.textPrimary)
                Text("All formats use the same schema version, but they optimize for different ways of reading and reusing your health data.")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func formatRow(icon: String, title: String, subtitle: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(Color.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(Typography.label())
                    .foregroundStyle(Color.textSecondary)
                Text(detail)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
    }
}
