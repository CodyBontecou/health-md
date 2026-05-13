#if os(macOS)
import SwiftUI
import MultipeerConnectivity

// MARK: - Mac Destination View

/// Single-screen Mac destination UI. iPhone owns export configuration; macOS
/// only connects, exposes destination readiness, writes received jobs, and shows
/// activity.
struct MacSyncView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var healthDataStore: HealthDataStore

    @State private var showClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                connectionCard

                if !syncService.discoveredPeers.isEmpty && syncService.connectionState != .connected {
                    nearbyDevicesCard
                }

                destinationFolderCard
                readinessCard
                macExportStatusCard
                MacSyncEventsSection()
                legacyCacheCard
                errorCard
            }
            .padding(24)
            .frame(maxWidth: 860, alignment: .topLeading)
        }
        .navigationTitle("Mac Destination")
        .onAppear {
            syncService.startBrowsing()
        }
        .alert("Delete Legacy Synced Data?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                healthDataStore.deleteAll()
            }
        } message: {
            Text("This removes the old iPhone→Mac cache from this Mac. It does not affect Health data on iPhone or files already exported to your destination folder.")
        }
    }

    // MARK: - Cards

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "macbook.and.iphone")
                    .font(.title2)
                    .foregroundStyle(Color.accent)
                    .accessibilityHidden(true)
                BrandLabel("Mac Destination")
            }

            Text("Configure your export on iPhone, then choose this Mac as the export target. Health.md for Mac saves received exports to the folder below.")
                .font(BrandTypography.body())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                setupStep(1, "Open Health.md on iPhone")
                setupStep(2, "Enable Mac Destination")
                setupStep(3, "Choose a destination folder on this Mac")
                setupStep(4, "Select Connected Mac on iPhone and tap Export")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brandGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mac Destination. Configure exports on iPhone, then choose this Mac as the export target.")
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textPrimary)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accent.opacity(0.2)))
            Text(text)
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var connectionCard: some View {
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

                Spacer()
                connectionActionButton
            }

            Text("Keep Health.md open on iPhone while exporting to this Mac.")
                .font(BrandTypography.caption())
                .foregroundStyle(Color.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brandGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Connection status")
        .accessibilityValue("\(connectionTitle). \(connectionSubtitle)")
    }

    private var nearbyDevicesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            BrandLabel("Nearby iPhones")

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
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brandGlassCard()
    }

    private var destinationFolderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                BrandLabel("Destination Folder")
                Spacer()
                Button(vaultManager.vaultURL == nil ? "Choose…" : "Change…") {
                    MacFolderPicker.show { url in
                        vaultManager.setVaultFolder(url)
                    }
                }
                .buttonStyle(.bordered)
                .tint(Color.accent)
                .controlSize(.small)
                .accessibilityLabel(vaultManager.vaultURL == nil ? "Choose destination folder" : "Change destination folder")
            }

            HStack(spacing: 10) {
                Image(systemName: vaultManager.vaultURL == nil ? "folder" : "folder.fill")
                    .font(.title3)
                    .foregroundStyle(vaultManager.vaultURL == nil ? Color.textMuted : folderAccessHealthy ? Color.success : Color.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(folderTitle)
                        .font(BrandTypography.bodyMedium())
                        .foregroundStyle(Color.textPrimary)
                    Text(folderSubtitle)
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                Spacer()

                if vaultManager.vaultURL != nil {
                    Button("Clear", role: .destructive) {
                        vaultManager.clearVaultFolder()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .tint(Color.error)
                    .accessibilityLabel("Clear destination folder")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brandGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Destination folder")
        .accessibilityValue(folderAccessibilityValue)
    }

    private var readinessCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: readinessIcon)
                .font(.title3)
                .foregroundStyle(readinessColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(readinessTitle)
                    .font(BrandTypography.bodyMedium())
                    .foregroundStyle(Color.textPrimary)
                Text(readinessMessage)
                    .font(BrandTypography.detail())
                    .foregroundStyle(Color.textMuted)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brandGlassCard(tintOpacity: isReadyForExports ? 0.04 : 0.02)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mac export readiness")
        .accessibilityValue("\(readinessTitle). \(readinessMessage)")
    }

    @ViewBuilder
    private var macExportStatusCard: some View {
        if let progress = syncService.activeMacExportProgress,
           ![MacExportPhase.completed, .failed, .cancelled].contains(progress.phase) {
            VStack(alignment: .leading, spacing: 10) {
                BrandLabel("Active Export")
                HStack {
                    Text(progress.message)
                        .font(BrandTypography.body())
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    if progress.totalDays > 0 {
                        Text("\(progress.processedDays)/\(progress.totalDays)")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }
                }
                if progress.totalDays > 0 {
                    ProgressView(value: progress.fractionComplete)
                        .tint(Color.accent)
                        .accessibilityLabel("Mac export progress")
                        .accessibilityValue("\(Int(progress.fractionComplete * 100)) percent")
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .brandGlassCard()
        } else if let result = syncService.lastMacExportResult {
            lastResultCard(result)
        } else if let failure = syncService.lastMacExportFailure {
            lastFailureCard(failure)
        }
    }

    private func lastResultCard(_ result: MacExportResultPayload) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: resultIcon(for: result.status))
                .font(.title3)
                .foregroundStyle(resultColor(for: result.status))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                BrandLabel("Last Export")
                Text(resultSummary(for: result))
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                if let path = result.destinationPathForDisplay {
                    Text(path)
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brandGlassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last Mac export")
        .accessibilityValue(resultSummary(for: result))
    }

    private func lastFailureCard(_ failure: MacExportFailure) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.error)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                BrandLabel("Last Export")
                Text(failure.message)
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .brandGlassCard(tintOpacity: 0.02)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last Mac export failed")
        .accessibilityValue(failure.message)
    }

    @ViewBuilder
    private var legacyCacheCard: some View {
        if healthDataStore.recordCount > 0 {
            VStack(alignment: .leading, spacing: 10) {
                BrandLabel("Legacy Synced Cache")
                Text("This Mac still has \(healthDataStore.recordCount) cached day(s) from the old manual sync flow. New exports are built on iPhone and sent directly to this Mac.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Delete Legacy Cache", role: .destructive) {
                    showClearConfirmation = true
                }
                .tint(Color.error)
                .accessibilityHint("Removes cached Health data from the old Mac sync flow")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .brandGlassCard(tintOpacity: 0.02)
        }
    }

    @ViewBuilder
    private var errorCard: some View {
        if let error = syncService.lastError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.warning)
                    .accessibilityHidden(true)
                Text(error)
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.warning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .brandGlassCard(tintOpacity: 0.02)
        }
    }

    // MARK: - Computed State

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
        case .connected:
            return iPhoneSupportsMacExports
                ? "Ready for iPhone-controlled exports"
                : "Connected to an older iPhone build"
        case .connecting: return "Establishing connection…"
        case .disconnected: return "Searching for nearby iPhones…"
        }
    }

    private var folderAccessHealthy: Bool {
        vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
    }

    private var folderTitle: String {
        guard vaultManager.vaultURL != nil else { return "No folder selected" }
        return folderAccessHealthy ? vaultManager.vaultName : "Folder access needs attention"
    }

    private var folderSubtitle: String {
        guard let url = vaultManager.vaultURL else {
            return "Choose where this Mac should save exports received from iPhone."
        }
        if folderAccessHealthy {
            return url.path(percentEncoded: false)
        }
        return "Re-select \(url.lastPathComponent) so Health.md can write received exports."
    }

    private var folderAccessibilityValue: String {
        if vaultManager.vaultURL == nil { return "No folder selected" }
        return folderAccessHealthy ? "Selected and accessible: \(vaultManager.vaultName)" : "Selected but access denied"
    }

    private var isReadyForExports: Bool {
        syncService.connectionState == .connected
            && iPhoneSupportsMacExports
            && folderAccessHealthy
            && syncService.activeMacExportProgress?.phase != .writing
            && syncService.activeMacExportProgress?.phase != .exporting
    }

    private var readinessTitle: String {
        if syncService.isSyncing { return "Receiving export from iPhone" }
        return isReadyForExports ? "Ready to receive exports from iPhone" : "Not ready yet"
    }

    private var readinessMessage: String {
        if syncService.isSyncing {
            return syncService.activeMacExportProgress?.message ?? "Writing received files to your destination folder."
        }
        if syncService.connectionState != .connected { return "Connect your iPhone to make this Mac available as an export target." }
        if !iPhoneSupportsMacExports { return compatibilityMessage }
        if vaultManager.vaultURL == nil { return "Choose a destination folder on this Mac." }
        if !folderAccessHealthy { return "Folder access is denied. Re-select the destination folder to restore access." }
        return "Open Health.md on iPhone, choose Connected Mac as the target, and tap Export."
    }

    private var readinessIcon: String {
        if syncService.isSyncing { return "arrow.down.doc.fill" }
        return isReadyForExports ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var readinessColor: Color {
        if syncService.isSyncing { return Color.accent }
        return isReadyForExports ? Color.success : Color.warning
    }

    private var iPhoneSupportsMacExports: Bool {
        guard syncService.connectionState == .connected else { return false }
        guard let capabilities = syncService.remoteCapabilities else { return false }
        return capabilities.platform == .iOS && capabilities.isCompatibleWithMacExportJobs
    }

    private var compatibilityMessage: String {
        "This iPhone can still use the legacy sync path, but it must be updated to send iPhone-configured exports to this Mac."
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
            .accessibilityLabel("Disconnect iPhone")
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
            .accessibilityLabel("Refresh nearby iPhones")
        }
    }

    private func resultSummary(for result: MacExportResultPayload) -> String {
        switch result.status {
        case .success:
            return "Exported \(result.totalFilesWritten) file(s) from iPhone."
        case .partialSuccess:
            return "Exported \(result.totalFilesWritten) file(s); \(result.failedDateDetails.count) date(s) need attention."
        case .failure:
            return result.failedDateDetails.first?.reason.shortDescription ?? "Mac export failed."
        case .cancelled:
            return result.successCount > 0
                ? "Export stopped after \(result.totalFilesWritten) file(s)."
                : "Mac export cancelled."
        }
    }

    private func resultIcon(for status: MacExportResultStatus) -> String {
        switch status {
        case .success: return "checkmark.circle.fill"
        case .partialSuccess: return "exclamationmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    private func resultColor(for status: MacExportResultStatus) -> Color {
        switch status {
        case .success: return Color.success
        case .partialSuccess, .cancelled: return Color.warning
        case .failure: return Color.error
        }
    }
}

#endif
