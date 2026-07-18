import SwiftUI

struct ExportModal: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var dateRangePreset: ExportDateRangePreset
    @Binding var subfolder: String
    let vaultName: String
    let onExport: () -> Void
    let onSubfolderChange: () -> Void
    @ObservedObject var exportSettings: AdvancedExportSettings
    let resolveAllTimeRange: (() async -> ExportDateRange?)?
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
                        // Subfolder input (tappable)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("SUBFOLDER")
                                .font(Typography.headline())
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Button {
                                showSubfolderEditor = true
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "folder")
                                        .font(Typography.bodyEmphasis())
                                        .foregroundStyle(Color.accent)
                                        .accessibilityHidden(true)

                                    Text(subfolder.isEmpty ? "Health" : subfolder)
                                        .font(Typography.bodyMono())
                                        .foregroundStyle(Color.textPrimary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(Typography.headline())
                                        .foregroundStyle(Color.textMuted)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.bgPrimary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Subfolder: \(subfolder.isEmpty ? "Health" : subfolder)")
                            .accessibilityHint("Double tap to change subfolder name")

                            Text("Base folder for your health data exports")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textMuted)
                        }

                        // Folder organization
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("FOLDER ORGANIZATION")
                                .font(Typography.headline())
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Button {
                                showFolderStructureEditor = true
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "folder.badge.gearshape")
                                        .font(Typography.bodyEmphasis())
                                        .foregroundStyle(Color.accent)
                                        .accessibilityHidden(true)

                                    Text(LocalizedStringKey(folderStructureDisplayText))
                                        .font(Typography.bodyMono())
                                        .foregroundStyle(Color.textPrimary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(Typography.headline())
                                        .foregroundStyle(Color.textMuted)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.bgPrimary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Folder organization: \(folderStructureDisplayText)")
                            .accessibilityHint("Double tap to change folder structure")

                            Text("Organize exports by date and optional file type folders")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textMuted)
                        }

                        // Date range controls
                        VStack(alignment: .leading, spacing: Spacing.md) {
                            Text("DATE RANGE")
                                .font(Typography.headline())
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: Spacing.sm
                            ) {
                                ForEach(ExportDateRangePreset.allCases) { preset in
                                    dateRangePresetButton(preset)
                                }
                            }

                            if dateRangePreset == .custom {
                                // Start Date
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    Text("START DATE")
                                        .font(Typography.headline())
                                        .foregroundStyle(Color.textMuted)
                                        .tracking(2)

                                    DatePicker(
                                        selection: $startDate,
                                        in: ...endDate,
                                        displayedComponents: .date
                                    ) {
                                        Text("Start Date")
                                    }
                                    .datePickerStyle(.graphical)
                                    .tint(.accent)
                                    .padding(Spacing.md)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.bgPrimary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(Color.borderSubtle, lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                    .accessibilityIdentifier(AccessibilityID.ExportModal.startDatePicker)
                                    .accessibilityHint("Select the start date for your export range")
                                }

                                // End Date
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    Text("END DATE")
                                        .font(Typography.headline())
                                        .foregroundStyle(Color.textMuted)
                                        .tracking(2)

                                    DatePicker(
                                        selection: $endDate,
                                        in: startDate...Date(),
                                        displayedComponents: .date
                                    ) {
                                        Text("End Date")
                                    }
                                    .datePickerStyle(.graphical)
                                    .tint(.accent)
                                    .padding(Spacing.md)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(Color.bgPrimary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .strokeBorder(Color.borderSubtle, lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                    .accessibilityIdentifier(AccessibilityID.ExportModal.endDatePicker)
                                    .accessibilityHint("Select the end date for your export range")
                                }
                            }
                        }

                        // Export path preview (tappable)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("EXPORT TO")
                                .font(Typography.headline())
                                .foregroundStyle(Color.textMuted)
                                .tracking(2)

                            Button {
                                showFilenameEditor = true
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(Typography.bodyEmphasis())
                                        .foregroundStyle(Color.accent)
                                        .accessibilityHidden(true)

                                    Text(exportPath)
                                        .font(Typography.monoEmphasis())
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)

                                    Spacer()

                                    Image(systemName: "pencil.circle.fill")
                                        .font(Typography.headline())
                                        .foregroundStyle(Color.textMuted)
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.bgPrimary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Export destination: \(exportPath)")
                            .accessibilityHint("Double tap to customize filename format")

                            Text("Tap to customize filename format")
                                .font(Typography.bodyEmphasis())
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
                    .accessibilityIdentifier(AccessibilityID.ExportModal.exportButton)
                }
            }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(
                for: MarketingCapture.dismissSheetNotification
            )) { _ in
                dismiss()
            }
            #endif
        }
        .sheet(isPresented: $showFilenameEditor) {
            FilenameFormatEditor(filenameFormat: $exportSettings.filenameFormat)
        }
        .sheet(isPresented: $showFolderStructureEditor) {
            FolderStructureEditor(
                folderStructure: $exportSettings.folderStructure,
                organizeFormatsIntoFolders: $exportSettings.organizeFormatsIntoFolders
            )
        }
        .sheet(isPresented: $showSubfolderEditor) {
            SubfolderEditor(subfolder: $subfolder, onSave: onSubfolderChange)
        }
    }

    private func dateRangePresetButton(_ preset: ExportDateRangePreset) -> some View {
        let isSelected = dateRangePreset == preset
        return Button {
            selectDateRangePreset(preset)
        } label: {
            HStack(spacing: Spacing.xs) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.headline())
                }
                Text(preset.title)
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.accent : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accent.opacity(0.18) : Color.bgSecondary)
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? Color.accent.opacity(0.45) : Color.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier(for: preset))
        .accessibilityLabel(preset.title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(preset.accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectDateRangePreset(_ preset: ExportDateRangePreset) {
        dateRangePreset = preset

        switch preset {
        case .custom:
            return
        case .allTime:
            Task {
                let range = await resolveAllTimeRange?()
                await MainActor.run {
                    guard dateRangePreset == .allTime else { return }
                    applyDateRange(range ?? fallbackTodayRange())
                }
            }
        case .today, .yesterday:
            if let range = preset.resolvedRange(
                currentStartDate: startDate,
                currentEndDate: endDate
            ) {
                applyDateRange(range)
            }
        }
    }

    private func fallbackTodayRange() -> ExportDateRange {
        ExportDateRangePreset.today.resolvedRange(
            currentStartDate: startDate,
            currentEndDate: endDate
        ) ?? ExportDateRange(startDate: Date(), endDate: Date())
    }

    private func applyDateRange(_ range: ExportDateRange) {
        startDate = range.startDate
        endDate = range.endDate
    }

    private func accessibilityIdentifier(for preset: ExportDateRangePreset) -> String {
        switch preset {
        case .today:
            return AccessibilityID.ExportModal.datePresetTodayButton
        case .yesterday:
            return AccessibilityID.ExportModal.datePresetYesterdayButton
        case .allTime:
            return AccessibilityID.ExportModal.datePresetAllTimeButton
        case .custom:
            return AccessibilityID.ExportModal.datePresetCustomButton
        }
    }

    private var folderStructureDisplayText: String {
        let dateFolders = exportSettings.folderStructure.isEmpty ? "Flat (no date subfolders)" : exportSettings.folderStructure
        if exportSettings.organizeFormatsIntoFolders {
            return "File type folders / \(dateFolders)"
        }
        return exportSettings.folderStructure.isEmpty ? "Flat (no subfolders)" : exportSettings.folderStructure
    }

    private var exportPath: String {
        let dateRange = effectiveDateRange
        let startDate = dateRange.startDate
        let endDate = dateRange.endDate

        if exportSettings.dailyNotesOnlyModeEnabled {
            if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return "\(vaultName)/\(exportSettings.dailyNoteInjection.previewPath(for: startDate))"
            }
            return "\(vaultName)/\(exportSettings.dailyNoteInjection.folderPath)/… (daily notes only)"
        }

        let subfolderPath = subfolder.isEmpty ? "" : subfolder + "/"
        let fileExtension = exportSettings.primaryFormat.fileExtension
        let formatCount = exportSettings.exportFormats.count

        let dayCount = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        let totalFiles = (dayCount + 1) * max(formatCount, 1)

        if dayCount == 0 {
            let primaryFormat = exportSettings.primaryFormat
            let folderPath = exportSettings.formatFolderPath(for: startDate, format: primaryFormat).map { $0 + "/" } ?? ""
            let filename = exportSettings.formatFilename(for: startDate)
            let primaryFilename = exportSettings.filename(for: startDate, format: primaryFormat)
            if formatCount > 1 {
                if exportSettings.organizeFormatsIntoFolders {
                    let groupedFolderPreview = exportSettings.folderStructure.isEmpty ? "{format}/" : "{format}/…/"
                    return "\(vaultName)/\(subfolderPath)\(groupedFolderPreview)\(filename).{\(formatExtensionsList)} (\(formatCount) files)"
                }
                return "\(vaultName)/\(subfolderPath)\(folderPath)\(filename).{\(formatExtensionsList)} (\(formatCount) files)"
            }
            return "\(vaultName)/\(subfolderPath)\(folderPath)\(primaryFilename)"
        } else {
            // For date ranges, show a simplified preview
            let startFilename = exportSettings.formatFilename(for: startDate)
            let endFilename = exportSettings.formatFilename(for: endDate)

            // If folder structure includes date placeholders, indicate multiple folders
            if exportSettings.organizeFormatsIntoFolders || !exportSettings.folderStructure.isEmpty {
                let folderDescription = exportSettings.organizeFormatsIntoFolders ? "format/date folders" : "date folders"
                return "\(vaultName)/\(subfolderPath).../{files} (\(totalFiles) files in \(folderDescription))"
            } else {
                return "\(vaultName)/\(subfolderPath)\(startFilename).\(fileExtension) to \(endFilename).\(fileExtension) (\(totalFiles) files)"
            }
        }
    }

    private var formatExtensionsList: String {
        exportSettings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map { $0.fileExtension }
            .joined(separator: ",")
    }

    private var effectiveDateRange: (startDate: Date, endDate: Date) {
        (startDate, endDate)
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
        ("Month Name", "{monthName}", "January, February…"),
        ("Weekday", "{weekday}", "Monday, Tuesday…"),
        ("Quarter", "{quarter}", "Q1, Q2, Q3, Q4")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        OutputEditorHeader(
                            icon: "doc.text",
                            title: "Filename Format",
                            subtitle: "Choose the naming template Health.md applies to every exported file."
                        )

                        OutputEditorCard {
                            OutputEditorSectionHeader(
                                "Format",
                                caption: "Use placeholders to build a readable, predictable file name."
                            )

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "curlybraces")
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(Color.accent)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)

                                TextField("{date}", text: $tempFormat)
                                    .font(Typography.bodyMono())
                                    .foregroundStyle(Color.textPrimary)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Filename Format")
                                    .accessibilityHint("Use placeholders like date, year, or month")
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm + 2)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.bgSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.md)

                            OutputEditorDivider()

                            OutputEditorSectionHeader(
                                "Preview",
                                caption: "This preview uses today’s date and the primary Markdown format."
                            )

                            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                                Text(previewFilename)
                                    .font(Typography.monoEmphasis())
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)

                                Spacer(minLength: Spacing.sm)

                                OutputEditorStatusPill(
                                    text: "Markdown",
                                    icon: "doc.text",
                                    tint: Color.accent
                                )
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accent.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.accent.opacity(0.24), lineWidth: 1)
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.md)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Preview filename")
                            .accessibilityValue(previewFilename)

                            OutputEditorDivider()

                            OutputEditorSectionHeader(
                                "Available Placeholders",
                                caption: "Tap a token to append it to the format."
                            )

                            VStack(spacing: 0) {
                                ForEach(placeholders.indices, id: \.self) { index in
                                    let item = placeholders[index]
                                    OutputTokenRow(
                                        name: item.name,
                                        placeholder: item.placeholder,
                                        description: item.description
                                    ) {
                                        tempFormat += item.placeholder
                                    }

                                    if index < placeholders.count - 1 {
                                        OutputEditorDivider()
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.bottom, Spacing.sm)

                            OutputEditorDivider()

                            Button {
                                tempFormat = AdvancedExportSettings.defaultFilenameFormat
                            } label: {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .accessibilityHidden(true)
                                    Text("Reset to Default")
                                    Spacer()
                                    Text(AdvancedExportSettings.defaultFilenameFormat)
                                        .font(Typography.monoCaption())
                                        .foregroundStyle(Color.textMuted)
                                }
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textSecondary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Reset Filename Format to Default")
                            .accessibilityHint("Restores the default date-based filename")
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                }
                .scrollIndicators(.hidden)
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

        // {quarter} -> Q1, Q2, Q3, Q4
        let month = Calendar.current.component(.month, from: date)
        let quarter = "Q\((month - 1) / 3 + 1)"
        result = result.replacingOccurrences(of: "{quarter}", with: quarter)

        return result + ".md"
    }
}

// MARK: - Folder Structure Editor

struct FolderStructureEditor: View {
    @Binding var folderStructure: String
    @Binding var organizeFormatsIntoFolders: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var tempStructure: String = ""
    @State private var tempOrganizeFormatsIntoFolders = false

    private let presets: [(name: String, value: String, description: String)] = [
        ("Flat", "", "All files in one folder"),
        ("By Year", "{year}", "Health/2025/…"),
        ("By Year & Month", "{year}/{month}", "Health/2025/02/…"),
        ("By Year & Month Name", "{year}/{monthName}", "Health/2025/February/…"),
        ("By Year & Quarter", "{year}/{quarter}", "Health/2025/Q1/…")
    ]

    private let placeholders: [(name: String, placeholder: String, description: String)] = [
        ("Year", "{year}", "2025"),
        ("Month", "{month}", "02"),
        ("Month Name", "{monthName}", "February"),
        ("Day", "{day}", "04"),
        ("Weekday", "{weekday}", "Tuesday"),
        ("Quarter", "{quarter}", "Q1, Q2, Q3, Q4")
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        OutputEditorHeader(
                            icon: "folder.badge.gearshape",
                            title: "Folder Organization",
                            subtitle: "Control the folders Health.md creates before writing each export file."
                        )

                        OutputEditorCard {
                            OutputEditorSectionHeader(
                                "Presets",
                                caption: "Start with a flat layout or date-based folders."
                            )

                            VStack(spacing: 0) {
                                ForEach(presets.indices, id: \.self) { index in
                                    let preset = presets[index]
                                    OutputPresetRow(
                                        title: preset.name,
                                        subtitle: preset.description,
                                        isSelected: tempStructure == preset.value
                                    ) {
                                        tempStructure = preset.value
                                    }

                                    if index < presets.count - 1 {
                                        OutputEditorDivider()
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.bottom, Spacing.sm)

                            OutputEditorDivider()

                            OutputEditorSectionHeader(
                                "Custom Format",
                                caption: "Leave empty for a flat structure, or compose date folders with placeholders."
                            )

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder")
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(Color.accent)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)

                                TextField("e.g. {year}/{month}", text: $tempStructure)
                                    .font(Typography.bodyMono())
                                    .foregroundStyle(Color.textPrimary)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Custom Folder Structure")
                                    .accessibilityHint("Use placeholders to organize exports into dated folders")
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm + 2)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.bgSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.md)

                            OutputEditorDivider()

                            Toggle(isOn: $tempOrganizeFormatsIntoFolders) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: Spacing.xs) {
                                        Text("File Type Folders")
                                            .font(Typography.bodyEmphasis())
                                            .foregroundStyle(Color.textPrimary)

                                        OutputEditorStatusPill(
                                            text: tempOrganizeFormatsIntoFolders ? "Enabled" : "Disabled",
                                            icon: tempOrganizeFormatsIntoFolders ? "checkmark" : nil,
                                            tint: tempOrganizeFormatsIntoFolders ? Color.accent : Color.textMuted
                                        )
                                    }

                                    Text(ExportRolloutCopy.formatFoldersHelp)
                                        .font(Typography.caption())
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                            .tint(Color.accent)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.md)

                            OutputEditorDivider()

                            OutputEditorSectionHeader(
                                "Preview",
                                caption: "Path preview uses the Markdown format and a sample date."
                            )

                            Text(previewPath)
                                .font(Typography.monoEmphasis())
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.accent.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.accent.opacity(0.24), lineWidth: 1)
                                )
                                .padding(.horizontal, Spacing.md)
                                .padding(.bottom, Spacing.md)
                                .accessibilityLabel("Preview folder path")
                                .accessibilityValue(previewPath)

                            OutputEditorDivider()

                            OutputEditorSectionHeader(
                                "Available Placeholders",
                                caption: "Tap a token to append it as the next folder segment."
                            )

                            VStack(spacing: 0) {
                                ForEach(placeholders.indices, id: \.self) { index in
                                    let item = placeholders[index]
                                    OutputTokenRow(
                                        name: item.name,
                                        placeholder: item.placeholder,
                                        description: item.description
                                    ) {
                                        if !tempStructure.isEmpty && !tempStructure.hasSuffix("/") {
                                            tempStructure += "/"
                                        }
                                        tempStructure += item.placeholder
                                    }

                                    if index < placeholders.count - 1 {
                                        OutputEditorDivider()
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.bottom, Spacing.sm)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                }
                .scrollIndicators(.hidden)
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
                        organizeFormatsIntoFolders = tempOrganizeFormatsIntoFolders
                        dismiss()
                    }
                    .foregroundStyle(Color.accent)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tempStructure = folderStructure
                tempOrganizeFormatsIntoFolders = organizeFormatsIntoFolders
            }
        }
    }

    private var previewPath: String {
        let dateFormatter = DateFormatter()
        let date = Date()

        let formatFolder = tempOrganizeFormatsIntoFolders ? "Markdown/" : ""

        if tempStructure.isEmpty {
            return "Health/\(formatFolder)2025-02-04.md"
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

        // {quarter} -> Q1, Q2, Q3, Q4
        let month = Calendar.current.component(.month, from: date)
        let quarter = "Q\((month - 1) / 3 + 1)"
        result = result.replacingOccurrences(of: "{quarter}", with: quarter)

        dateFormatter.dateFormat = "yyyy-MM-dd"
        return "Health/\(formatFolder)\(result)/\(dateFormatter.string(from: date)).md"
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
                        OutputEditorHeader(
                            icon: "folder",
                            title: "Export Folder",
                            subtitle: "Set the Obsidian or Files subfolder Health.md writes into."
                        )

                        OutputEditorCard {
                            OutputEditorSectionHeader(
                                "Presets",
                                caption: "Choose a common destination folder, or enter your own below."
                            )

                            VStack(spacing: 0) {
                                ForEach(presets.indices, id: \.self) { index in
                                    let preset = presets[index]
                                    OutputPresetRow(
                                        title: preset.name,
                                        subtitle: preset.description,
                                        isSelected: tempSubfolder == preset.value
                                    ) {
                                        tempSubfolder = preset.value
                                    }

                                    if index < presets.count - 1 {
                                        OutputEditorDivider()
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.bottom, Spacing.sm)

                            OutputEditorDivider()

                            OutputEditorSectionHeader(
                                "Custom Folder Name",
                                caption: "Leave empty to export directly into the selected root folder."
                            )

                            HStack(spacing: Spacing.sm) {
                                Image(systemName: "folder")
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(Color.accent)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)

                                TextField("Health", text: $tempSubfolder)
                                    .font(Typography.bodyMono())
                                    .foregroundStyle(Color.textPrimary)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel("Custom Export Folder Name")
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm + 2)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.bgSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.md)

                            OutputEditorDivider()

                            OutputEditorSectionHeader(
                                "Preview",
                                caption: "This is where today’s Markdown export would be written."
                            )

                            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                                Text(previewPath)
                                    .font(Typography.monoEmphasis())
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: Spacing.sm)

                                OutputEditorStatusPill(
                                    text: tempSubfolder.isEmpty ? "Root Folder" : "Subfolder",
                                    icon: tempSubfolder.isEmpty ? "tray" : "folder",
                                    tint: tempSubfolder.isEmpty ? Color.textMuted : Color.accent
                                )
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.accent.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.accent.opacity(0.24), lineWidth: 1)
                            )
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.md)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Preview export folder path")
                            .accessibilityValue(previewPath)

                            OutputEditorDivider()

                            HStack(alignment: .top, spacing: Spacing.sm) {
                                Image(systemName: "info.circle")
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(Color.accent)
                                    .frame(width: 24)
                                    .accessibilityHidden(true)

                                Text("This folder will be created inside your selected export location. Empty names export directly to the root folder.")
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.md)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xxl)
                }
                .scrollIndicators(.hidden)
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

// MARK: - Output Editor Helpers

private struct OutputEditorHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.bgTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.displayMedium())
                    .foregroundStyle(Color.textPrimary)

                Text(subtitle)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OutputEditorCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }
}

private struct OutputEditorSectionHeader: View {
    let title: String
    let caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OutputEditorDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.borderSubtle)
    }
}

private struct OutputEditorStatusPill: View {
    let text: String
    var icon: String? = nil
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.24), lineWidth: 1))
    }
}

private struct OutputPresetRow: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)

                    Text(subtitle)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.sm)

                if isSelected {
                    OutputEditorStatusPill(
                        text: "Selected",
                        icon: "checkmark",
                        tint: Color.accent
                    )
                } else {
                    Image(systemName: "circle")
                        .font(.footnote)
                        .foregroundStyle(Color.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accent.opacity(0.10) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OutputTokenRow: View {
    let name: String
    let placeholder: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)

                    Text(description)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }

                Spacer(minLength: Spacing.sm)

                Text(placeholder)
                    .font(Typography.monoCaptionEmphasis())
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accent.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Color.accent.opacity(0.22), lineWidth: 1))

                Image(systemName: "plus.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Insert \(name) placeholder")
        .accessibilityValue(placeholder)
    }
}
