#if os(macOS)
import SwiftUI

// MARK: - Menu Bar View — Branded Popup

struct MacMenuBarView: View {
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var advancedSettings: AdvancedExportSettings
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var healthDataStore: HealthDataStore
    @State private var isExportingYesterday = false
    @State private var exportResultMessage: String?

    // Use semantic system colors in the menu bar popup so text contrast adapts
    // correctly to macOS material/vibrancy in both light and dark appearances.
    private var primaryTextColor: Color { .primary }
    private var secondaryTextColor: Color { .secondary }
    private var mutedTextColor: Color { .secondary.opacity(0.75) }

    private var canExport: Bool {
        healthDataStore.recordCount > 0 && vaultManager.hasVaultAccess && !isExportingYesterday
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Brand header
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(Color.accent)
                    .font(.title3)
                Text("health.md")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(primaryTextColor)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()
                .opacity(0.3)

            // Status section
            VStack(alignment: .leading, spacing: 6) {
                statusRow(
                    label: "iPhone",
                    connected: syncService.connectionState == .connected,
                    detail: syncService.connectionState == .connected
                        ? syncService.connectedPeerName ?? "Connected"
                        : "Not connected"
                )

                statusRow(
                    label: "Data",
                    connected: healthDataStore.recordCount > 0,
                    detail: healthDataStore.recordCount > 0
                        ? "\(healthDataStore.recordCount) days synced"
                        : "No synced data"
                )

                statusRow(
                    label: "Folder",
                    connected: vaultManager.hasVaultAccess,
                    detail: vaultManager.hasVaultAccess ? vaultManager.vaultName : "Not selected"
                )

                if schedulingManager.schedule.isEnabled {
                    if let lastExport = schedulingManager.schedule.lastExportDate {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(mutedTextColor)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Text("Last export:")
                                .foregroundStyle(mutedTextColor)
                            Text(lastExport, style: .relative)
                                .foregroundStyle(secondaryTextColor)
                        }
                        .font(BrandTypography.caption())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Last export")
                    }

                    if let next = schedulingManager.getNextExportDescription() {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(mutedTextColor)
                                .frame(width: 14)
                                .accessibilityHidden(true)
                            Text("Next:")
                                .foregroundStyle(mutedTextColor)
                            Text(next)
                                .foregroundStyle(secondaryTextColor)
                        }
                        .font(BrandTypography.caption())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Next scheduled export")
                        .accessibilityValue(next)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()
                .opacity(0.3)

            // Actions
            VStack(spacing: 2) {
                menuAction(
                    icon: isExportingYesterday ? nil : "arrow.up.doc",
                    label: isExportingYesterday ? "Exporting…" : "Export Yesterday",
                    trailing: exportResultMessage,
                    isLoading: isExportingYesterday,
                    disabled: !canExport
                ) {
                    exportYesterday()
                }

                menuAction(
                    icon: "macwindow",
                    label: "Open Health.md",
                    shortcut: "⌘0"
                ) {
                    WindowManager.shared.openMainWindow?()
                }

                menuAction(
                    icon: "gearshape",
                    label: "Settings…",
                    shortcut: "⌘,"
                ) {
                    NSApp.activate(ignoringOtherApps: true)
                    if #available(macOS 14.0, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                }
            }
            .padding(.vertical, 4)

            Divider()
                .opacity(0.3)

            // Quit
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Text("Quit Health.md")
                        .font(BrandTypography.body())
                    Spacer()
                    Text("⌘Q")
                        .font(BrandTypography.caption())
                        .foregroundStyle(mutedTextColor)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(secondaryTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
            .accessibilityLabel("Quit Health.md")
            .accessibilityHint("Keyboard shortcut: Command Q")
        }
        .frame(width: 280)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Health.md menu")
    }

    // MARK: - Components

    @ViewBuilder
    private func statusRow(label: String, connected: Bool, detail: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connected ? Color.success : mutedTextColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(label + ":")
                .foregroundStyle(mutedTextColor)
            Text(detail)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(BrandTypography.caption())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) status")
        .accessibilityValue("\(connected ? "Connected" : "Not connected"): \(detail)")
    }

    @ViewBuilder
    private func menuAction(
        icon: String? = nil,
        label: String,
        trailing: String? = nil,
        shortcut: String? = nil,
        isLoading: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else if let icon {
                    Image(systemName: icon)
                        .foregroundStyle(Color.accent)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .font(BrandTypography.body())
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(BrandTypography.caption())
                        .foregroundStyle(mutedTextColor)
                }
                if let shortcut {
                    Text(shortcut)
                        .font(BrandTypography.caption())
                        .foregroundStyle(mutedTextColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? mutedTextColor : secondaryTextColor)
        .disabled(disabled)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityLabel(label)
        .accessibilityValue(trailing ?? "")
        .accessibilityHint(shortcut != nil ? "Keyboard shortcut: \(shortcut!)" : "")
        .accessibilityAddTraits(disabled ? .isStaticText : .isButton)
    }

    // MARK: - Helpers

    private func exportYesterday() {
        guard canExport else { return }
        isExportingYesterday = true
        exportResultMessage = nil

        Task {
            defer { isExportingYesterday = false }

            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let date = Calendar.current.startOfDay(for: yesterday)

            guard let healthData = healthDataStore.fetchHealthData(for: date) else {
                exportResultMessage = "✗ No data"
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    exportResultMessage = nil
                }
                return
            }

            do {
                try await vaultManager.exportHealthData(healthData, settings: advancedSettings)

                let result = ExportOrchestrator.ExportResult(
                    successCount: 1,
                    totalCount: 1,
                    failedDateDetails: []
                )

                ExportOrchestrator.recordResult(
                    result,
                    source: .manual,
                    dateRangeStart: date,
                    dateRangeEnd: date
                )

                exportResultMessage = "✓"
            } catch {
                exportResultMessage = "✗"
            }

            Task {
                try? await Task.sleep(for: .seconds(5))
                exportResultMessage = nil
            }
        }
    }
}

#endif
