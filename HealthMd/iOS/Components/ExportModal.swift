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
    @State private var showFolderStructureEditor = false
    @State private var showSubfolderEditor = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Subfolder input with Liquid Glass styling (tappable)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("SUBFOLDER")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Button {
                                showSubfolderEditor = true
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.accent)

                                    Text(subfolder.isEmpty ? "Health" : subfolder)
                                        .font(Typography.bodyMono())
                                        .foregroundStyle(Color.textPrimary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.textMuted)
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
                            .buttonStyle(.plain)

                            Text("Base folder for your health data exports")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textMuted)
                        }

                        // Folder organization with Liquid Glass styling
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("FOLDER ORGANIZATION")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Button {
                                showFolderStructureEditor = true
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "folder.badge.gearshape")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(Color.accent)

                                    Text(folderStructureDisplayText)
                                        .font(Typography.bodyMono())
                                        .foregroundStyle(Color.textPrimary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.textMuted)
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
                            .buttonStyle(.plain)

                            Text("Organize exports into subfolders by date")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textMuted)
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
                        
                        // Individual Tracking Section
                        if exportSettings.individualTracking.globalEnabled {
                            IndividualTrackingExportPreview(settings: exportSettings.individualTracking)
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
        .sheet(isPresented: $showFolderStructureEditor) {
            FolderStructureEditor(folderStructure: $exportSettings.folderStructure)
        }
        .sheet(isPresented: $showSubfolderEditor) {
            SubfolderEditor(subfolder: $subfolder, onSave: onSubfolderChange)
        }
    }

    private var folderStructureDisplayText: String {
        if exportSettings.folderStructure.isEmpty {
            return "Flat (no subfolders)"
        } else {
            return exportSettings.folderStructure
        }
    }

    private var exportPath: String {
        let subfolderPath = subfolder.isEmpty ? "" : subfolder + "/"
        let fileExtension = exportSettings.exportFormat.fileExtension

        let dayCount = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0

        if dayCount == 0 {
            let folderPath = exportSettings.formatFolderPath(for: startDate).map { $0 + "/" } ?? ""
            let filename = exportSettings.formatFilename(for: startDate)
            return "\(vaultName)/\(subfolderPath)\(folderPath)\(filename).\(fileExtension)"
        } else {
            // For date ranges, show a simplified preview
            let startFolderPath = exportSettings.formatFolderPath(for: startDate).map { $0 + "/" } ?? ""
            let startFilename = exportSettings.formatFilename(for: startDate)
            let endFilename = exportSettings.formatFilename(for: endDate)

            // If folder structure includes date placeholders, indicate multiple folders
            if !exportSettings.folderStructure.isEmpty {
                return "\(vaultName)/\(subfolderPath).../{files} (\(dayCount + 1) files in date folders)"
            } else {
                return "\(vaultName)/\(subfolderPath)\(startFilename).\(fileExtension) to \(endFilename).\(fileExtension) (\(dayCount + 1) files)"
            }
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

// MARK: - Folder Structure Editor

struct FolderStructureEditor: View {
    @Binding var folderStructure: String
    @Environment(\.dismiss) private var dismiss
    @State private var tempStructure: String = ""

    private let presets: [(name: String, value: String, description: String)] = [
        ("Flat", "", "All files in one folder"),
        ("By Year", "{year}", "Health/2025/..."),
        ("By Year & Month", "{year}/{month}", "Health/2025/02/..."),
        ("By Year & Month Name", "{year}/{monthName}", "Health/2025/February/...")
    ]

    private let placeholders: [(name: String, placeholder: String, description: String)] = [
        ("Year", "{year}", "2025"),
        ("Month", "{month}", "02"),
        ("Month Name", "{monthName}", "February"),
        ("Day", "{day}", "04"),
        ("Weekday", "{weekday}", "Tuesday")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Quick presets
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("PRESETS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            VStack(spacing: Spacing.xs) {
                                ForEach(presets, id: \.value) { preset in
                                    Button {
                                        tempStructure = preset.value
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(preset.name)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundStyle(Color.textPrimary)

                                                Text(preset.description)
                                                    .font(.system(size: 12, weight: .regular))
                                                    .foregroundStyle(Color.textMuted)
                                            }

                                            Spacer()

                                            if tempStructure == preset.value {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 18, weight: .medium))
                                                    .foregroundStyle(Color.accent)
                                            }
                                        }
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.sm)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(tempStructure == preset.value ? Color.accent.opacity(0.15) : Color.white.opacity(0.05))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(tempStructure == preset.value ? Color.accent.opacity(0.5) : Color.clear, lineWidth: 1)
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

                        // Custom format input
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("CUSTOM FORMAT")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.accent)

                                TextField("e.g. {year}/{month}", text: $tempStructure)
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

                            Text("Leave empty for flat structure, or use placeholders below")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textMuted)
                        }

                        // Preview
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("PREVIEW")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Text(previewPath)
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
                                        if !tempStructure.isEmpty && !tempStructure.hasSuffix("/") {
                                            tempStructure += "/"
                                        }
                                        tempStructure += item.placeholder
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

                        Spacer()
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle("Folder Organization")
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
                        folderStructure = tempStructure
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tempStructure = folderStructure
            }
        }
        .preferredColorScheme(.dark)
    }

    private var previewPath: String {
        let dateFormatter = DateFormatter()
        let date = Date()

        if tempStructure.isEmpty {
            return "Health/2025-02-04.md"
        }

        var result = tempStructure

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

        dateFormatter.dateFormat = "yyyy-MM-dd"
        return "Health/\(result)/\(dateFormatter.string(from: date)).md"
    }
}

// MARK: - Subfolder Editor

struct SubfolderEditor: View {
    @Binding var subfolder: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tempSubfolder: String = ""

    private let presets: [(name: String, value: String, description: String)] = [
        ("Health", "Health", "Default health data folder"),
        ("Daily Notes", "Daily Notes", "Common Obsidian folder"),
        ("Journal", "Journal", "Personal journal folder"),
        ("Life", "Life", "General life tracking folder"),
        ("Quantified Self", "Quantified Self", "For data enthusiasts")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        // Quick presets
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("PRESETS")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            VStack(spacing: Spacing.xs) {
                                ForEach(presets, id: \.value) { preset in
                                    Button {
                                        tempSubfolder = preset.value
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(preset.name)
                                                    .font(.system(size: 15, weight: .medium))
                                                    .foregroundStyle(Color.textPrimary)

                                                Text(preset.description)
                                                    .font(.system(size: 12, weight: .regular))
                                                    .foregroundStyle(Color.textMuted)
                                            }

                                            Spacer()

                                            if tempSubfolder == preset.value {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 18, weight: .medium))
                                                    .foregroundStyle(Color.accent)
                                            }
                                        }
                                        .padding(.horizontal, Spacing.md)
                                        .padding(.vertical, Spacing.sm)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(tempSubfolder == preset.value ? Color.accent.opacity(0.15) : Color.white.opacity(0.05))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(tempSubfolder == preset.value ? Color.accent.opacity(0.5) : Color.clear, lineWidth: 1)
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

                        // Custom folder name input
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("CUSTOM FOLDER NAME")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.accent)

                                TextField("Health", text: $tempSubfolder)
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

                            Text("Enter a custom folder name for your exports")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textMuted)
                        }

                        // Preview
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("PREVIEW")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Text(previewPath)
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

                        // Info section
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("INFO")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.accent)

                                Text("This folder will be created inside your selected export location. Leave empty to export directly to the root folder.")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(Color.textSecondary)
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
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }

                        Spacer()
                    }
                    .padding(Spacing.lg)
                }
            }
            .navigationTitle("Export Folder")
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
                        subfolder = tempSubfolder
                        onSave()
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tempSubfolder = subfolder
            }
        }
        .preferredColorScheme(.dark)
    }

    private var previewPath: String {
        let folderName = tempSubfolder.isEmpty ? "(vault root)" : tempSubfolder
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        if tempSubfolder.isEmpty {
            return "MyVault/\(dateString).md"
        } else {
            return "MyVault/\(folderName)/\(dateString).md"
        }
    }
}

// MARK: - Individual Tracking Export Preview

struct IndividualTrackingExportPreview: View {
    @ObservedObject var settings: IndividualTrackingSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("INDIVIDUAL ENTRIES")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textMuted)
                    .tracking(2)
                
                Spacer()
                
                // Badge showing count
                if settings.totalEnabledCount > 0 {
                    Text("\(settings.totalEnabledCount) metric\(settings.totalEnabledCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.accent)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.accent)
                    
                    Text("Will create individual files for:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.textPrimary)
                }
                
                // List enabled categories with counts
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(enabledCategories, id: \.self) { category in
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.accent.opacity(0.8))
                                .frame(width: 16)
                            
                            Text(category.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                            
                            Text("(\(settings.enabledCount(for: category)))")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
                .padding(.leading, 24)
                
                // Folder preview
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textMuted)
                    
                    Text(folderPreview)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.accent.opacity(0.2), lineWidth: 1)
            )
            
            Text("Individual entries are created in addition to daily summaries")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textMuted)
        }
    }
    
    private var enabledCategories: [HealthMetricCategory] {
        HealthMetricCategory.allCases.filter { category in
            settings.enabledCount(for: category) > 0
        }
    }
    
    private var folderPreview: String {
        if settings.useCategoryFolders {
            if enabledCategories.isEmpty {
                return "\(settings.entriesFolder)/{category}/"
            }
            // Show first enabled category as example
            let firstCategory = enabledCategories.first!
            let folderName = firstCategory.rawValue
                .lowercased()
                .replacingOccurrences(of: " ", with: "_")
            return "\(settings.entriesFolder)/\(folderName)/..."
        } else {
            return "\(settings.entriesFolder)/"
        }
    }
}
