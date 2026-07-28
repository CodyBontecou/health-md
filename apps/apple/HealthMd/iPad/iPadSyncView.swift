import SwiftUI
import UIKit

// MARK: - iPad Sync View (matching macOS MacSyncView card layout)
// On iPad, "sync" means enabling this device as a data source for a Mac.

struct iPadSyncView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var healthKitManager: HealthKitManager
    @AppStorage("syncEnabled") private var syncEnabled = false
    @AppStorage("autoSyncAfterExport") private var autoSyncAfterExport = true

    private let macAppURL = URL(string: "https://apps.apple.com/us/app/health-md/id6757763969")!

    @State private var showHealthPermissionsGuide = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                HealthMdPageHeader(
                    title: "Sync",
                    subtitle: "Share Apple Health data with Health.md on your Mac"
                )

                // MARK: - Apple Health Status
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Apple Health")

                    HStack(spacing: 12) {
                        Circle()
                            .fill(healthKitManager.isAuthorized ? Color.success : Color.textMuted)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(healthKitManager.isAuthorized ? "Connected" : "Not Connected")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text(healthKitManager.isAuthorized
                                 ? "Health data is accessible"
                                 : "Grant access to export health data")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }

                        Spacer()

                        Button(healthKitManager.isAuthorized ? "Permissions" : "Connect") {
                            Task {
                                let outcome = try? await healthKitManager.requestAuthorization()
                                if outcome == .unnecessary {
                                    showHealthPermissionsGuide = true
                                }
                            }
                        }
                        .font(Typography.bodyEmphasis())
                        .buttonStyle(.bordered)
                        .tint(Color.accent)
                        .controlSize(.small)
                    }

                    Text("Health.md reads your Apple Health data locally on this device.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - Mac Sync Toggle
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Mac Sync")

                    HStack(spacing: 12) {
                        Circle()
                            .fill(syncEnabled ? (syncService.connectionState == .connected ? Color.success : Color.warning) : Color.textMuted)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(syncEnabled ? "Enabled" : "Disabled")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text(syncEnabled
                                 ? "This iPad is discoverable by Health.md on Mac"
                                 : "Enable to let your Mac sync health data from this iPad")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }

                        Spacer()

                        Toggle("", isOn: $syncEnabled)
                            .labelsHidden()
                            .tint(Color.accent)
                            .onChange(of: syncEnabled) { _, newValue in
                                if newValue {
                                    syncService.startAdvertising()
                                } else {
                                    syncService.stopAdvertising()
                                    syncService.disconnect()
                                }
                            }
                    }

                    Text("When enabled, your Mac can discover this iPad and request health data over your local network.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: - macOS Promo Banner
                if !syncEnabled {
                    Link(destination: macAppURL) {
                        VStack(alignment: .leading, spacing: 12) {
                            iPadBrandLabel("Download for")

                            HStack(spacing: 12) {
                                Image(systemName: "desktopcomputer")
                                    .foregroundStyle(Color.accent)
                                    .font(Typography.headline())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("macOS on App Store")
                                        .font(Typography.headline())
                                        .foregroundStyle(Color.textPrimary)
                                    Text("Use Health.md on your desktop")
                                        .font(Typography.caption())
                                        .foregroundStyle(Color.textMuted)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(Typography.label())
                                    .foregroundStyle(Color.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Spacing.s6)
                        .background(Color.bgPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                                .strokeBorder(Color.accent.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - Connection Status
                if syncEnabled {
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        iPadBrandLabel("Connection")

                        HStack(spacing: 12) {
                            connectionStatusIcon

                            VStack(alignment: .leading, spacing: 2) {
                                Text(connectionTitle)
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(Color.textPrimary)
                                Text(connectionSubtitle)
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textMuted)
                            }

                            Spacer()

                            if syncService.connectionState == .connected {
                                Button("Disconnect") {
                                    syncService.disconnect()
                                }
                                .font(Typography.bodyEmphasis())
                                .buttonStyle(.bordered)
                                .tint(Color.accent)
                                .controlSize(.small)
                            }
                        }

                        if syncService.connectionState == .connected {
                            Divider()
                                .background(Color.borderSubtle)

                            Toggle(isOn: $autoSyncAfterExport) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-sync after export")
                                        .font(Typography.bodyEmphasis())
                                        .foregroundStyle(Color.textPrimary)
                                    Text("Automatically send data to Mac when you export")
                                        .font(Typography.caption())
                                        .foregroundStyle(Color.textMuted)
                                }
                            }
                            .tint(Color.accent)
                        }

                        if syncService.isSyncing {
                            Divider()
                                .background(Color.borderSubtle)

                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Syncing health data to Mac…")
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()
                }

                // MARK: - Manual Sync
                if syncService.connectionState == .connected {
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        iPadBrandLabel("Manual Sync")

                        Button {
                            sendRecentData()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Sync Last 7 Days Now")
                            }
                            .font(Typography.bodyEmphasis())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.accent)

                        Text("Sends the last 7 days of health data to your connected Mac.")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()
                }

                // MARK: - Error
                if let error = syncService.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.warning)
                        Text(error)
                            .font(Typography.body())
                            .foregroundStyle(Color.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.s4)
                    .iPadLiquidGlass()
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.top, Spacing.s6)
            .padding(.bottom, Spacing.s8)
            .iPadContentColumn()
        }
        .scrollIndicators(.hidden)
        .iPadPageBackground()
        .navigationTitle("Sync")
        .iPadHiddenSystemNavigationTitle()
        .onAppear {
            if syncEnabled {
                syncService.startAdvertising()
            }
        }
        .alert("Adjust Health Permissions", isPresented: $showHealthPermissionsGuide) {
            Button("Open Health App") {
                if let healthURL = URL(string: "x-apple-health://") {
                    UIApplication.shared.open(healthURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To change which health data Health.md can access:\n\n1. Tap \"Open Health App\"\n2. Tap your profile icon (top right)\n3. Tap \"Apps\"\n4. Select \"Health.md\"\n5. Toggle permissions on or off")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var connectionStatusIcon: some View {
        switch syncService.connectionState {
        case .connected:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
        case .connecting:
            ProgressView()
                .controlSize(.small)
        case .disconnected:
            Image(systemName: "circle.dotted")
                .foregroundStyle(Color.textMuted)
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
        case .connected: return "Ready to sync health data"
        case .connecting: return "Establishing connection…"
        case .disconnected: return "Open Health.md on your Mac to connect"
        }
    }

    private func sendRecentData() {
        let endDate = Calendar.current.startOfDay(for: Date())
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: endDate) ?? endDate

        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? endDate.addingTimeInterval(1)
        }

        syncService.onMessageReceived?(.requestData(dates: dates))
    }
}

// MARK: - iPad Brand Label (matching macOS BrandLabel)

struct iPadBrandLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Typography.label())
            .foregroundStyle(Color.textSecondary)
            .tracking(-0.1)
    }
}

// MARK: - iPad Brand Data Row (matching macOS BrandDataRow)

struct iPadBrandDataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Typography.body())
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.textPrimary)
        }
    }
}
