import SwiftUI

struct ExportModal: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var subfolder: String
    let vaultName: String
    let onExport: () -> Void
    let onSubfolderChange: () -> Void
    @ObservedObject var exportSettings: AdvancedExportSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showFilenameEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Subfolder input with Liquid Glass styling
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("SUBFOLDER")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.accent)

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
                            .padding(.vertical, Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        }

                        // Date range pickers with Liquid Glass styling
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            // Start Date
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("START DATE")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.textMuted)
                                    .tracking(2)

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
                                .padding(Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                            }

                            // End Date
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("END DATE")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.textMuted)
                                    .tracking(2)

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
                                .padding(Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                            }
                        }

                        // Export path preview with Liquid Glass styling (tappable)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("EXPORT TO")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Button {
                                showFilenameEditor = true
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    ZStack {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(Color.accent)
                                            .blur(radius: 4)
                                            .opacity(0.5)

                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(Color.accent)
                                    }

                                    Text(exportPath)
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Spacer()

                                    Image(systemName: "pencil.circle.fill")
                                        .font(.system(size: 18, weight: .medium))
                                        .foregroundStyle(Color.textMuted)
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            Text("Tap to customize filename format")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textMuted)
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
        .sheet(isPresented: $showFilenameEditor) {
            FilenameFormatEditor(filenameFormat: $exportSettings.filenameFormat)
        }
    }

    private var exportPath: String {
        let subfolder = subfolder.isEmpty ? "" : subfolder + "/"
        let fileExtension = exportSettings.exportFormat.fileExtension

        let dayCount = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0

        if dayCount == 0 {
            let filename = exportSettings.formatFilename(for: startDate)
            return "\(vaultName)/\(subfolder)\(filename).\(fileExtension)"
        } else {
            let startFilename = exportSettings.formatFilename(for: startDate)
            let endFilename = exportSettings.formatFilename(for: endDate)
            return "\(vaultName)/\(subfolder)\(startFilename).\(fileExtension) to \(endFilename).\(fileExtension) (\(dayCount + 1) files)"
        }
    }
}

// MARK: - Filename Format Editor

struct FilenameFormatEditor: View {
    @Binding var filenameFormat: String
    @Environment(\.dismiss) private var dismiss
    @State private var tempFormat: String = ""

    private let placeholders: [(name: String, placeholder: String, description: String)] = [
        ("Date", "{date}", "yyyy-MM-dd"),
        ("Year", "{year}", "yyyy"),
        ("Month", "{month}", "MM"),
        ("Day", "{day}", "dd"),
        ("Month Name", "{monthName}", "January, February..."),
        ("Weekday", "{weekday}", "Monday, Tuesday...")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Format input
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("FILENAME FORMAT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.accent)

                                TextField("{date}", text: $tempFormat)
                                    .font(Typography.bodyMono())
                                    .foregroundStyle(Color.textPrimary)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        }

                        // Preview
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("PREVIEW")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Text(previewFilename)
                                .font(Typography.bodyMono())
                                .foregroundStyle(Color.accent)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1)
                                )
                        }

                        // Available placeholders
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("AVAILABLE PLACEHOLDERS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            VStack(spacing: Spacing.xs) {
                                ForEach(placeholders, id: \.placeholder) { item in
                                    Button {
                                        tempFormat += item.placeholder
                                    } label: {
                                        HStack {
                                            Text(item.placeholder)
                                                .font(Typography.bodyMono())
                                                .foregroundStyle(Color.accent)

                                            Spacer()

                                            Text(item.description)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(Color.textMuted)
                                        }
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.sm)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(Color.white.opacity(0.05))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                            )
                        }

                        // Reset button
                        Button {
                            tempFormat = AdvancedExportSettings.defaultFilenameFormat
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Default")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle("Filename Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        filenameFormat = tempFormat.isEmpty ? AdvancedExportSettings.defaultFilenameFormat : tempFormat
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tempFormat = filenameFormat
            }
        }
        .preferredColorScheme(.dark)
    }

    private var previewFilename: String {
        let format = tempFormat.isEmpty ? AdvancedExportSettings.defaultFilenameFormat : tempFormat
        let dateFormatter = DateFormatter()
        var result = format
        let date = Date()

        // {date} -> yyyy-MM-dd
        dateFormatter.dateFormat = "yyyy-MM-dd"
        result = result.replacingOccurrences(of: "{date}", with: dateFormatter.string(from: date))

        // {year} -> yyyy
        dateFormatter.dateFormat = "yyyy"
        result = result.replacingOccurrences(of: "{year}", with: dateFormatter.string(from: date))

        // {month} -> MM
        dateFormatter.dateFormat = "MM"
        result = result.replacingOccurrences(of: "{month}", with: dateFormatter.string(from: date))

        // {day} -> dd
        dateFormatter.dateFormat = "dd"
        result = result.replacingOccurrences(of: "{day}", with: dateFormatter.string(from: date))

        // {weekday} -> Monday, Tuesday, etc.
        dateFormatter.dateFormat = "EEEE"
        result = result.replacingOccurrences(of: "{weekday}", with: dateFormatter.string(from: date))

        // {monthName} -> January, February, etc.
        dateFormatter.dateFormat = "MMMM"
        result = result.replacingOccurrences(of: "{monthName}", with: dateFormatter.string(from: date))

        return result + ".md"
    }
}
