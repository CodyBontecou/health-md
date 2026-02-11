#if os(macOS)
import SwiftUI

// MARK: - Menu Bar View

struct MacMenuBarView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var schedulingManager: SchedulingManager
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var advancedSettings: AdvancedExportSettings
    @State private var isExportingYesterday = false
    @State private var exportResultMessage: String?

    private var canExport: Bool {
        healthKitManager.isAuthorized && vaultManager.hasVaultAccess && !isExportingYesterday
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.pink)
                    .font(.title3)
                Text("Health.md")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider()

            // Status section
            VStack(alignment: .leading, spacing: 6) {
                statusRow(
                    label: "Health",
                    connected: healthKitManager.isAuthorized,
                    detail: healthKitManager.isAuthorized ? "Connected" : "Not connected"
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
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text("Last export:")
                                .foregroundStyle(.secondary)
                            Text(lastExport, style: .relative)
                        }
                        .font(.caption)
                    }

                    if let next = schedulingManager.getNextExportDescription() {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text("Next:")
                                .foregroundStyle(.secondary)
                            Text(next)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            // Actions
            VStack(spacing: 2) {
                // Quick export yesterday
                Button {
                    exportYesterday()
                } label: {
                    HStack {
                        if isExportingYesterday {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up.doc")
                        }
                        Text(isExportingYesterday ? "Exporting…" : "Export Yesterday")
                        Spacer()
                        if let message = exportResultMessage {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canExport)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                // Open main window
                Button {
                    activateMainWindow()
                } label: {
                    HStack {
                        Image(systemName: "macwindow")
                        Text("Open Health.md")
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                // Preferences
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    // Use the correct selector for the current macOS version
                    if #available(macOS 14.0, *) {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    } else {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                    }
                } label: {
                    HStack {
                        Image(systemName: "gearshape")
                        Text("Settings…")
                        Spacer()
                        Text("⌘,")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .padding(.vertical, 4)

            Divider()

            // Quit
            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Text("Quit Health.md")
                    Spacer()
                    Text("⌘Q")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
        }
        .frame(width: 260)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusRow(label: String, connected: Bool, detail: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(connected ? .green : .secondary)
                .frame(width: 6, height: 6)
            Text(label + ":")
                .foregroundStyle(.secondary)
            Text(detail)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)

        // Find the main content window (not Settings/Preferences panels or menu bar extras)
        let mainWindow = NSApp.windows.first(where: {
            $0.canBecomeMain
                && $0.level == .normal
                && !$0.className.contains("Settings")
                && !$0.className.contains("Preferences")
        })

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // All windows are closed — create a new one by toggling a dummy menu action
            // This is the standard SwiftUI way to open the default WindowGroup
            NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        }
    }

    private func exportYesterday() {
        guard canExport else { return }
        isExportingYesterday = true
        exportResultMessage = nil

        Task {
            defer { isExportingYesterday = false }

            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
            let dates = [Calendar.current.startOfDay(for: yesterday)]

            let result = await ExportOrchestrator.exportDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vaultManager,
                settings: advancedSettings
            )

            ExportOrchestrator.recordResult(
                result,
                source: .manual,
                dateRangeStart: dates.first!,
                dateRangeEnd: dates.last!
            )

            if result.isFullSuccess {
                exportResultMessage = "✓"
            } else if result.isPartialSuccess {
                exportResultMessage = "⚠"
            } else {
                exportResultMessage = "✗"
            }

            // Clear result message after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                exportResultMessage = nil
            }
        }
    }
}

#endif
