import SwiftUI

// MARK: - Sync Settings View (iOS)

struct SyncSettingsView: View {
    @EnvironmentObject var syncService: SyncService
    @AppStorage("syncEnabled") private var syncEnabled = false
    @AppStorage("autoSyncAfterExport") private var autoSyncAfterExport = true

    private let discordURL = URL(string: "https://discord.gg/RaQYS4t6gn")!

    var body: some View {
        List {
            // MARK: Sync Toggle
            Section {
                Toggle("Sync to Mac", isOn: $syncEnabled)
                    .onChange(of: syncEnabled) { _, newValue in
                        if newValue {
                            if !TestMode.isUITesting {
                                syncService.startAdvertising()
                            }
                            UIAccessibility.post(notification: .announcement, argument: "Mac sync enabled")
                        } else {
                            if !TestMode.isUITesting {
                                syncService.stopAdvertising()
                                syncService.disconnect()
                            }
                            UIAccessibility.post(notification: .announcement, argument: "Mac sync disabled")
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.Sync.syncToggle)
                    .accessibilityLabel("Mac sync")
                    .accessibilityValue(syncEnabled ? "Enabled" : "Disabled")
                    .accessibilityHint("Double tap to \(syncEnabled ? "disable" : "enable") syncing health data to your Mac")
            } footer: {
                Text("When enabled, your Mac can discover this iPhone and request health data over your local network.")
            }

            if !syncEnabled {
                Section {
                    Link(destination: discordURL) {
                        HStack(spacing: 14) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.accent)
                                .frame(width: 34, height: 34)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("JOIN THE")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .tracking(1.1)

                                Text("Discord Community")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }

                            Spacer()

                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accent)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.accent.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Join the Health.md Discord community")
                    .accessibilityHint("Double tap to open Discord invite in browser")
                    .accessibilityAddTraits(.isLink)
                }
            }

            // MARK: Connection Status
            if syncEnabled {
                Section("Connection") {
                    HStack {
                        connectionStatusIcon
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(connectionTitle)
                            Text(connectionSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.Sync.connectionStatus)
                    .accessibilityLabel("Connection status")
                    .accessibilityValue("\(connectionTitle). \(connectionSubtitle)")

                    if syncService.connectionState == .connected {
                        Toggle("Auto-sync after export", isOn: $autoSyncAfterExport)
                            .accessibilityLabel("Auto-sync after export")
                            .accessibilityValue(autoSyncAfterExport ? "Enabled" : "Disabled")
                            .accessibilityHint("When enabled, automatically sends data to Mac after each export")
                    }
                }
            }

            // MARK: Manual Sync
            if syncService.connectionState == .connected {
                Section {
                    Button {
                        sendAllRecentData()
                    } label: {
                        Label("Sync Last 7 Days Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier(AccessibilityID.Sync.manualSyncButton)
                    .accessibilityLabel("Sync last 7 days now")
                    .accessibilityHint("Double tap to send the last 7 days of health data to your connected Mac")
                } footer: {
                    Text("Sends the last 7 days of health data to your connected Mac.")
                }
            }

            // MARK: Error
            if let error = syncService.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .accessibilityLabel("Error")
                        .accessibilityValue(error)
                }
            }
        }
        .navigationTitle("Mac Sync")
        .onAppear {
            if syncEnabled && !TestMode.isUITesting {
                syncService.startAdvertising()
            }
        }
        .onChange(of: syncService.connectionState) { oldValue, newValue in
            // Announce connection state changes to VoiceOver users
            if oldValue != newValue {
                let announcement: String
                switch newValue {
                case .connected:
                    announcement = "Connected to Mac"
                case .connecting:
                    announcement = "Connecting to Mac"
                case .disconnected:
                    announcement = "Disconnected from Mac"
                }
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var connectionStatusIcon: some View {
        switch syncService.connectionState {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .disconnected:
            Image(systemName: "circle.dotted")
                .foregroundStyle(.secondary)
        }
    }

    private var connectionTitle: String {
        switch syncService.connectionState {
        case .connected:
            return "Connected to \(syncService.connectedPeerName ?? "Mac")"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "Waiting for Mac"
        }
    }

    private var connectionSubtitle: String {
        switch syncService.connectionState {
        case .connected: return "Ready to sync"
        case .connecting: return "Establishing connection…"
        case .disconnected: return "Open Health.md on your Mac to connect"
        }
    }

    private func sendAllRecentData() {
        // This triggers the iOS-side handler to fetch from HealthKit and send
        // The actual data fetching is handled by the sync message handler in HealthMdApp
        let endDate = Calendar.current.startOfDay(for: Date())
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate

        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? endDate.addingTimeInterval(1)
        }

        // Send a self-request to trigger the fetch-and-send pipeline
        syncService.onMessageReceived?(.requestData(dates: dates))
    }
}
