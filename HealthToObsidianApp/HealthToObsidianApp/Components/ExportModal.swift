import SwiftUI

struct ExportModal: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var subfolder: String
    let vaultName: String
    let onExport: () -> Void
    let onSubfolderChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Subfolder input
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("SUBFOLDER")
                                .font(Typography.label())
                                .foregroundStyle(Color.textMuted)
                                .tracking(1)

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.textMuted)

                                TextField("Health", text: $subfolder)
                                    .font(Typography.bodyMono())
                                    .foregroundStyle(Color.textPrimary)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .onChange(of: subfolder) { _, _ in
                                        onSubfolderChange()
                                    }
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm + 4)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.bgSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.borderDefault, lineWidth: 1)
                            )
                        }

                        // Date range pickers
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            // Start Date
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("START DATE")
                                    .font(Typography.label())
                                    .foregroundStyle(Color.textMuted)
                                    .tracking(1)

                                DatePicker(
                                    selection: $startDate,
                                    in: ...endDate,
                                    displayedComponents: .date
                                ) {
                                    EmptyView()
                                }
                                .datePickerStyle(.graphical)
                                .tint(.accent)
                                .colorScheme(.dark)
                                .padding(Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.bgSecondary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.borderDefault, lineWidth: 1)
                                )
                            }

                            // End Date
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("END DATE")
                                    .font(Typography.label())
                                    .foregroundStyle(Color.textMuted)
                                    .tracking(1)

                                DatePicker(
                                    selection: $endDate,
                                    in: startDate...Date(),
                                    displayedComponents: .date
                                ) {
                                    EmptyView()
                                }
                                .datePickerStyle(.graphical)
                                .tint(.accent)
                                .colorScheme(.dark)
                                .padding(Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.bgSecondary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.borderDefault, lineWidth: 1)
                                )
                            }
                        }

                        // Export path preview
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("EXPORT TO")
                                .font(Typography.label())
                                .foregroundStyle(Color.textMuted)
                                .tracking(1)

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.accent)

                                Text(exportPath)
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(2)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentSubtle)
                            )
                        }

                        Spacer()
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle("Export Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        dismiss()
                        onExport()
                    }
                    .foregroundStyle(Color.accent)
                    .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var exportPath: String {
        let subfolder = subfolder.isEmpty ? "" : subfolder + "/"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let dayCount = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0

        if dayCount == 0 {
            return "\(vaultName)/\(subfolder)\(dateFormatter.string(from: startDate)).md"
        } else {
            return "\(vaultName)/\(subfolder)\(dateFormatter.string(from: startDate)).md to \(dateFormatter.string(from: endDate)).md (\(dayCount + 1) files)"
        }
    }
}
