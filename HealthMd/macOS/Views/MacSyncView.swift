#if os(macOS)
import SwiftUI
import MultipeerConnectivity

// MARK: - Sync View (macOS) — Glass Card Layout

struct MacSyncView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var healthDataStore: HealthDataStore

    @State private var isSyncing = false
    @State private var syncDays = 7
    @State private var showDeleteConfirmation = false
    @State private var showAllTimeConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: - Connection Status
                VStack(alignment: .leading, spacing: 14) {
                    BrandLabel("iPhone Connection")

                    HStack(spacing: 12) {
                        Circle()
                            .fill(connectionDotColor)
                            .frame(width: 10, height: 10)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(connectionTitle)
                                .font(BrandTypography.bodyMedium())
                                .foregroundStyle(Color.textPrimary)
                            Text(connectionSubtitle)
                                .font(BrandTypography.detail())
                                .foregroundStyle(Color.textMuted)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Connection status")
                        .accessibilityValue("\(connectionTitle). \(connectionSubtitle)")

                        Spacer()
                        connectionActionButton
                    }

                    Text("Make sure Health.md is open on your iPhone with sync enabled.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .brandGlassCard()

                // MARK: - Discovered Devices
                if !syncService.discoveredPeers.isEmpty && syncService.connectionState != .connected {
                    VStack(alignment: .leading, spacing: 14) {
                        BrandLabel("Nearby Devices")

                        ForEach(syncService.discoveredPeers, id: \.displayName) { peer in
                            HStack(spacing: 10) {
                                Image(systemName: "iphone")
                                    .foregroundStyle(Color.accent)
                                    .font(.system(size: 14))
                                    .accessibilityHidden(true)
                                Text(peer.displayName)
                                    .font(BrandTypography.bodyMedium())
                                    .foregroundStyle(Color.textPrimary)
                                Spacer()
                                Button("Connect") {
                                    syncService.connectToPeer(peer)
                                }
                                .buttonStyle(.bordered)
                                .tint(Color.accent)
                                .controlSize(.small)
                                .accessibilityLabel("Connect to \(peer.displayName)")
                                .accessibilityHint("Double tap to connect to this iPhone")
                            }
                            .padding(.vertical, 4)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("iPhone: \(peer.displayName)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .brandGlassCard()
                }

                // MARK: - Sync Actions
                if syncService.connectionState == .connected {
                    VStack(alignment: .leading, spacing: 14) {
                        BrandLabel("Sync Data")

                        HStack {
                            Text("Date Range")
                                .font(BrandTypography.body())
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Picker("Date range", selection: $syncDays) {
                                Text("Yesterday").tag(1)
                                Text("Last 7 Days").tag(7)
                                Text("Last 30 Days").tag(30)
                                Text("Last 90 Days").tag(90)
                                Text("Last Year").tag(365)
                                Divider()
                                Text("All Time").tag(0)
                            }
                            .pickerStyle(.menu)
                            .tint(Color.accent)
                            .frame(width: 180)
                            .accessibilityLabel("Sync date range")
                            .accessibilityValue(syncDays == 0 ? "All time" : syncDays == 1 ? "Yesterday" : "Last \(syncDays) days")
                        }

                        Button {
                            if syncDays == 0 {
                                showAllTimeConfirmation = true
                            } else {
                                requestSync()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                if isSyncing || healthDataStore.isSyncingAllData {
                                    ProgressView()
                                        .controlSize(.small)
                                        .accessibilityHidden(true)
                                    Text("Syncing…")
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .accessibilityHidden(true)
                                    Text("Sync Now")
                                }
                            }
                            .font(BrandTypography.bodyMedium())
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isSyncing ? Color.textMuted : Color.textPrimary)
                        .brandGlassButton()
                        .disabled(isSyncing || healthDataStore.isSyncingAllData)
                        .accessibilityLabel(isSyncing || healthDataStore.isSyncingAllData ? "Syncing" : "Sync now")
                        .accessibilityHint("Syncs health data from your iPhone for the selected date range")

                        if syncDays == 0 {
                            Text("All Time will sync every day of health data. This may take several minutes.")
                                .font(BrandTypography.caption())
                                .foregroundStyle(Color.textMuted)
                        }

                        // Progress indicator for all-time sync
                        if let progress = healthDataStore.syncProgress {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(progress.message ?? "Syncing…")
                                        .font(BrandTypography.detail())
                                        .foregroundStyle(Color.textSecondary)
                                    Spacer()
                                    if progress.totalDays > 0 {
                                        Text("\(Int(progress.fractionComplete * 100))%")
                                            .font(BrandTypography.value())
                                            .foregroundStyle(Color.accent)
                                    }
                                }

                                if progress.totalDays > 0 && !progress.isComplete {
                                    ProgressView(value: progress.fractionComplete)
                                        .tint(Color.accent)
                                }

                                if progress.isComplete {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.success)
                                        Text("Sync complete!")
                                            .foregroundStyle(Color.success)
                                    }
                                    .font(BrandTypography.detail())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .brandGlassCard()
                }

                // MARK: - Local Data
                VStack(alignment: .leading, spacing: 14) {
                    BrandLabel("Local Data")

                    BrandDataRow(label: "Stored Records", value: "\(healthDataStore.recordCount)")

                    if let lastSync = healthDataStore.lastSyncDate {
                        HStack {
                            Text("Last Sync")
                                .font(BrandTypography.body())
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(lastSync, style: .relative)
                                .font(BrandTypography.value())
                                .foregroundStyle(Color.textPrimary)
                        }
                    }

                    if let device = healthDataStore.lastSyncDevice {
                        BrandDataRow(label: "Source Device", value: device)
                    }

                    if let range = healthDataStore.dateRange() {
                        HStack {
                            Text("Date Range")
                                .font(BrandTypography.body())
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text("\(range.earliest, format: .dateTime.month().day()) – \(range.latest, format: .dateTime.month().day())")
                                .font(BrandTypography.value())
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .brandGlassCard()

                // MARK: - Recent Syncs
                MacSyncEventsSection()

                // MARK: - Danger Zone
                if healthDataStore.recordCount > 0 {
                    VStack(alignment: .leading, spacing: 14) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                    .accessibilityHidden(true)
                                Text("Delete All Synced Data")
                            }
                            .font(BrandTypography.bodyMedium())
                        }
                        .tint(Color.error)
                        .accessibilityLabel("Delete all synced data")
                        .accessibilityHint("Removes all health data cached on this Mac")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .brandGlassCard(tintOpacity: 0.02)
                }

                // MARK: - Error
                if let error = syncService.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color.warning)
                        Text(error)
                            .font(BrandTypography.body())
                            .foregroundStyle(Color.warning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .brandGlassCard(tintOpacity: 0.02)
                }
            }
            .padding(24)
        }
        .navigationTitle("Sync")
        .onAppear {
            syncService.startBrowsing()
        }
        .alert("Delete All Synced Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                healthDataStore.deleteAll()
            }
        } message: {
            Text("This will remove all health data cached on this Mac. You can re-sync from your iPhone at any time.")
        }
        .alert("Sync All Health Data?", isPresented: $showAllTimeConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sync All Data") {
                requestAllTimeSync()
            }
        } message: {
            Text("This will sync your entire health data history from your iPhone. Depending on how much data you have, this could take several minutes.\n\nMake sure Health.md stays open on your iPhone during the sync.")
        }
    }

    // MARK: - Computed Properties

    private var connectionDotColor: Color {
        switch syncService.connectionState {
        case .connected: return Color.success
        case .connecting: return Color.warning
        case .disconnected: return Color.textMuted
        }
    }

    private var connectionTitle: String {
        switch syncService.connectionState {
        case .connected:
            return "Connected to \(syncService.connectedPeerName ?? "iPhone")"
        case .connecting:
            return "Connecting…"
        case .disconnected:
            return "Not Connected"
        }
    }

    private var connectionSubtitle: String {
        switch syncService.connectionState {
        case .connected: return "Ready to sync health data"
        case .connecting: return "Establishing connection…"
        case .disconnected: return "Searching for nearby iPhones…"
        }
    }

    @ViewBuilder
    private var connectionActionButton: some View {
        switch syncService.connectionState {
        case .connected:
            Button("Disconnect") {
                syncService.disconnect()
            }
            .buttonStyle(.bordered)
            .tint(Color.accent)
            .controlSize(.small)
            .accessibilityLabel("Disconnect")
            .accessibilityHint("Disconnects from the connected iPhone")
        case .connecting:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Connecting")
        case .disconnected:
            Button("Refresh") {
                syncService.stopBrowsing()
                syncService.startBrowsing()
            }
            .buttonStyle(.bordered)
            .tint(Color.accent)
            .controlSize(.small)
            .accessibilityLabel("Refresh")
            .accessibilityHint("Searches for nearby iPhones")
        }
    }

    // MARK: - Actions

    private func requestSync() {
        if syncDays == 0 {
            requestAllTimeSync()
            return
        }

        isSyncing = true
        let endDate = Calendar.current.startOfDay(for: Date())
        let startDate = Calendar.current.date(byAdding: .day, value: -(syncDays), to: endDate) ?? endDate

        var dates: [Date] = []
        var current = startDate
        while current <= endDate {
            dates.append(current)
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? endDate.addingTimeInterval(1)
        }

        // Capture pre-sync state so we can detect when data arrives, even from
        // older iPhone builds that don't send an explicit completion signal.
        let initialLastSync = healthDataStore.lastSyncDate
        let initialRecordCount = healthDataStore.recordCount

        syncService.send(.requestData(dates: dates))

        Task {
            // Stop syncing as soon as we see either:
            // - an explicit completion signal (new iPhone build), or
            // - the data landing in the local store (any iPhone build).
            // 30s safety net for the empty-data + old-iPhone case.
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(500))
                let progressComplete = healthDataStore.syncProgress?.isComplete == true
                let dataArrived = healthDataStore.lastSyncDate != initialLastSync
                    || healthDataStore.recordCount != initialRecordCount
                if progressComplete || dataArrived {
                    // Brief settle for any trailing payload before clearing the spinner
                    try? await Task.sleep(for: .milliseconds(400))
                    break
                }
            }
            isSyncing = false
        }
    }

    private func requestAllTimeSync() {
        isSyncing = true
        syncService.send(.requestAllData)

        Task {
            for _ in 0..<1800 {
                try? await Task.sleep(for: .seconds(1))
                if !healthDataStore.isSyncingAllData && healthDataStore.syncProgress?.isComplete == true {
                    break
                }
            }
            isSyncing = false
        }
    }
}

#endif
