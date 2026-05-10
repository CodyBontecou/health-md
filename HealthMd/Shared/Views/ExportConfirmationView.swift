import SwiftUI

struct ExportConfirmationView: View {
    let startDate: Date
    let endDate: Date
    let vaultName: String
    let healthSubfolder: String
    @ObservedObject var settings: AdvancedExportSettings
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var purchaseManager = PurchaseManager.shared

    private var dates: [Date] {
        ExportOrchestrator.dateRange(from: startDate, to: endDate)
    }

    private var dayCount: Int {
        dates.count
    }

    private var formatCount: Int {
        settings.exportFormats.count
    }

    private var totalPrimaryFiles: Int {
        dayCount * formatCount
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Review before exporting", systemImage: "exclamationmark.shield")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)

                        Text("No files will be written and no free export will be used until you confirm this screen.")
                            .font(.footnote)
                            .foregroundStyle(Color.textMuted)
                    }
                    .padding(.vertical, 4)
                }

                Section("Export Summary") {
                    confirmationRow("Date range", value: dateRangeSummary)
                    confirmationRow("Days", value: "\(dayCount)")
                    confirmationRow("Formats", value: formatsSummary)
                    confirmationRow("Primary files", value: "\(totalPrimaryFiles)")
                    confirmationRow("Write mode", value: settings.writeMode.rawValue)
                }

                Section("Destination") {
                    confirmationRow("Vault", value: vaultName)
                    confirmationRow("Subfolder", value: healthSubfolder.isEmpty ? "Health" : healthSubfolder)
                    confirmationRow("Folder layout", value: settings.folderStructure.isEmpty ? "Flat" : settings.folderStructure)
                    confirmationRow("Example file", value: examplePath)
                }

                if settings.dailyNoteInjection.enabled && settings.exportFormats.contains(.markdown) {
                    Section("Also Writes") {
                        Label("Daily-note injection may update one note for each exported day.", systemImage: "note.text.badge.plus")
                            .font(.footnote)
                    }
                }

                if settings.individualTracking.globalEnabled && settings.exportFormats.contains(.markdown) {
                    Section("Individual Entries") {
                        Label("Tracked individual entries can create additional markdown files beyond the primary file count.", systemImage: "doc.on.doc")
                            .font(.footnote)
                    }
                }

                if !purchaseManager.isUnlocked {
                    Section("Free Export Use") {
                        confirmationRow("Remaining now", value: "\(purchaseManager.freeExportsRemaining)")
                        confirmationRow("Remaining after confirm", value: "\(max(0, purchaseManager.freeExportsRemaining - 1))")
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            #else
            .listStyle(.inset)
            #endif
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Confirm Export")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                    .accessibilityIdentifier(AccessibilityID.ExportConfirmation.cancelButton)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmButtonTitle) {
                        dismiss()
                        onConfirm()
                    }
                    .fontWeight(.semibold)
                    .disabled(settings.exportFormats.isEmpty || dayCount == 0)
                    .accessibilityIdentifier(AccessibilityID.ExportConfirmation.confirmButton)
                    .accessibilityHint("Starts the export and uses one free export if you have not unlocked Health.md")
                }
            }
        }
    }

    private func confirmationRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(Color.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.textPrimary)
                .font(.footnote.monospaced())
        }
    }

    private var confirmButtonTitle: String {
        !purchaseManager.isUnlocked ? "Confirm & Use Export" : "Confirm Export"
    }

    private var formatsSummary: String {
        settings.exportFormats
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map(\.rawValue)
            .joined(separator: ", ")
    }

    private var dateRangeSummary: String {
        guard let first = dates.first, let last = dates.last else { return "No dates" }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return Self.dateFormatter.string(from: first)
        }
        return "\(Self.dateFormatter.string(from: first)) to \(Self.dateFormatter.string(from: last))"
    }

    private var examplePath: String {
        guard let firstDate = dates.first else { return "" }
        var components: [String] = [vaultName]
        if !healthSubfolder.isEmpty {
            components.append(healthSubfolder)
        }
        if let folderPath = settings.formatFolderPath(for: firstDate), !folderPath.isEmpty {
            components.append(folderPath)
        }
        components.append(settings.filename(for: firstDate, format: settings.primaryFormat))
        return components.joined(separator: "/")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
