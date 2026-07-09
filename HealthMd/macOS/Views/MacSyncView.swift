#if os(macOS)
import AppKit
import MultipeerConnectivity
import SwiftUI

// MARK: - Mac Destination View

/// Geist-based destination dashboard. iPhone owns export configuration; macOS
/// listens, validates the local destination, writes received jobs, and exposes
/// recent activity.
struct MacSyncView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var healthDataStore: HealthDataStore

    @ObservedObject private var historyManager = SyncEventHistoryManager.shared

    @State private var receivingPaused = false
    @State private var showClearConfirmation = false
    @State private var showActivityClearConfirmation = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s8) {
                    heroSection

                    if !syncService.discoveredPeers.isEmpty && syncService.connectionState != .connected {
                        nearbyDevicesCard
                    }

                    dashboardGrid(width: proxy.size.width)

                    if let error = syncService.lastError {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, horizontalPadding(for: proxy.size.width))
                .padding(.vertical, Spacing.s8)
                .frame(maxWidth: 1_200, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(GeistMacBackdrop())
        }
        .foregroundStyle(Color.textPrimary)
        .tint(Color.accent)
        .onAppear {
            receivingPaused = false
            syncService.startBrowsing()
        }
        .alert("Delete Legacy Synced Data?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Data", role: .destructive) {
                healthDataStore.deleteAll()
            }
        } message: {
            Text("This removes the old iPhone→Mac cache from this Mac. It does not affect Health data on iPhone or files already exported to your destination folder.")
        }
        .alert("Clear Activity Feed?", isPresented: $showActivityClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Activity", role: .destructive) {
                historyManager.clearHistory()
            }
        } message: {
            Text("This removes recorded iPhone→Mac sync and export events from this Mac. Your synced health data and exported files are not affected.")
        }
    }

    // MARK: - Layout

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        if width < 720 { return Spacing.s4 }
        if width < 1_080 { return Spacing.s6 }
        return Spacing.s8
    }

    @ViewBuilder
    private func dashboardGrid(width: CGFloat) -> some View {
        if width >= 1_040 {
            HStack(alignment: .top, spacing: Spacing.s6) {
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    destinationCard
                    systemStatusCard
                    manualIPConnectionCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: Spacing.s6) {
                    setupStepsCard
                    activityCard
                    if healthDataStore.recordCount > 0 {
                        legacyCacheCard
                    }
                }
                .frame(width: 360, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                destinationCard
                systemStatusCard
                manualIPConnectionCard
                setupStepsCard
                activityCard
                if healthDataStore.recordCount > 0 {
                    legacyCacheCard
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        GeistMacCard(padding: Spacing.s8) {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack(alignment: .top, spacing: Spacing.s6) {
                    VStack(alignment: .leading, spacing: Spacing.s4) {
                        HStack(spacing: Spacing.s3) {
                            Image("AppIconImage")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                                )
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 0) {
                                Text("health.md")
                                    .font(Typography.headline())
                                    .foregroundStyle(Color.textPrimary)
                                    .tracking(-0.2)
                                Text("Mac Destination")
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textMuted)
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.s2) {
                            Text(readinessHeroTitle)
                                .font(Typography.displayLarge())
                                .foregroundStyle(Color.textPrimary)
                                .tracking(-0.9)
                                .accessibilityAddTraits(.isHeader)

                            Text("Receive Health.md exports from your iPhone and save Markdown, JSON, or CSV files directly into your vault.")
                                .font(Typography.body())
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 640, alignment: .leading)
                        }
                    }

                    Spacer(minLength: Spacing.s4)

                    VStack(alignment: .trailing, spacing: Spacing.s3) {
                        GeistStatusPill(
                            title: statusPrimaryLine,
                            subtitle: statusSecondaryLine,
                            systemImage: connectionStatusIcon,
                            color: connectionDotColor
                        )

                        pauseReceivingButton
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: Spacing.s3)],
                    alignment: .leading,
                    spacing: Spacing.s3
                ) {
                    GeistMetricTile(
                        icon: "iphone",
                        title: "iPhone",
                        value: syncService.connectionState == .connected ? (syncService.connectedPeerName ?? "Connected") : "Listening",
                        detail: syncService.connectionState == .connected ? "Local network" : "Open Health.md on iPhone",
                        color: syncService.connectionState == .connected ? Color.success : Color.textMuted
                    )

                    GeistMetricTile(
                        icon: "folder",
                        title: "Destination",
                        value: vaultManager.vaultURL == nil ? "Choose Folder" : vaultManager.vaultName,
                        detail: folderAccessHealthy ? "Ready to write" : "Required before exports",
                        color: folderAccessHealthy ? Color.success : Color.warning
                    )

                    GeistMetricTile(
                        icon: "internaldrive",
                        title: "Storage",
                        value: storageSummary.shortFree,
                        detail: storageSummary.usedPercentText + " used",
                        color: Color.textSecondary
                    )
                }
            }
        }
    }

    private var pauseReceivingButton: some View {
        Button {
            toggleReceivingPaused()
        } label: {
            Label(receivingPaused ? "Resume Receiving" : "Pause Receiving",
                  systemImage: receivingPaused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(GeistMacButtonStyle(kind: .primary))
        .disabled(syncService.connectionState == .connecting)
    }

    // MARK: - Cards

    private var nearbyDevicesCard: some View {
        GeistMacCard(padding: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                GeistSectionHeader(
                    title: "Nearby iPhones",
                    subtitle: "Select a discovered device to connect over the local network."
                )

                HStack(spacing: Spacing.s2) {
                    ForEach(syncService.discoveredPeers.prefix(3), id: \.displayName) { peer in
                        Button {
                            syncService.connectToPeer(peer)
                        } label: {
                            Label(peer.displayName, systemImage: "iphone")
                        }
                        .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
                        .accessibilityLabel("Connect to \(peer.displayName)")
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var destinationCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Destination Folder",
                    subtitle: "Where this Mac writes files received from iPhone."
                ) {
                    Button(vaultManager.vaultURL == nil ? "Choose Folder" : "Change Folder") {
                        chooseDestinationFolder()
                    }
                    .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
                    .accessibilityLabel(vaultManager.vaultURL == nil ? "Choose destination folder" : "Change destination folder")
                }

                HStack(alignment: .center, spacing: Spacing.s4) {
                    ZStack {
                        RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                            .fill(folderAccessHealthy ? Color.accentSubtle : Color.bgSecondary)
                            .frame(width: 56, height: 56)
                        Image(systemName: vaultManager.vaultURL == nil ? "folder" : "folder.fill")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(folderAccessHealthy ? Color.accent : Color.textMuted)
                            .accessibilityHidden(true)
                    }

                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text(folderTitle)
                            .font(Typography.headline())
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Text(folderSubtitle)
                            .font(Typography.caption())
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }

                GeistDivider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 142), spacing: Spacing.s3)],
                    alignment: .leading,
                    spacing: Spacing.s3
                ) {
                    GeistInfoChip(
                        icon: "folder",
                        title: vaultManager.vaultURL == nil ? "No Folder" : "Folder Exists",
                        value: vaultManager.vaultURL == nil ? "Required" : (folderExists ? "Ready" : "Missing"),
                        color: folderExists ? Color.textSecondary : Color.warning
                    )

                    GeistInfoChip(
                        icon: "checkmark.square",
                        title: "Writable",
                        value: folderAccessHealthy ? "Verified" : "Needs Access",
                        color: folderAccessHealthy ? Color.success : Color.warning
                    )

                    GeistInfoChip(
                        icon: "internaldrive",
                        title: storageSummary.shortFree,
                        value: storageSummary.usedPercentText + " used",
                        color: Color.textSecondary
                    )

                    GeistInfoChip(
                        icon: "checkmark.seal",
                        title: volumeKind,
                        value: storageSummary.volumeLabel,
                        color: Color.textSecondary
                    )
                }

                StorageUsageBar(summary: storageSummary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Destination folder")
        .accessibilityValue(folderAccessibilityValue)
    }

    private var systemStatusCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "System Status",
                    subtitle: "Connection, permissions, and receiver version."
                ) {
                    Button {
                        syncService.stopBrowsing()
                        syncService.startBrowsing()
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.s3)],
                    alignment: .leading,
                    spacing: Spacing.s3
                ) {
                    SystemStatusBlock(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Receiver",
                        value: "v\(appVersion)",
                        badge: receivingPaused ? "Paused" : "Listening",
                        color: receivingPaused ? Color.warning : Color.success
                    )

                    SystemStatusBlock(
                        icon: "lock.shield",
                        title: "Permissions",
                        value: permissionValue,
                        badge: folderAccessHealthy ? "Granted" : "Needs Access",
                        color: folderAccessHealthy ? Color.success : Color.warning
                    )
                }

                GeistDivider()

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text("Last Check")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)
                        Text(lastCheckText)
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.textPrimary)
                    }

                    Spacer()

                    GeistStatusPill(
                        title: readinessText,
                        subtitle: nil,
                        systemImage: readinessIcon,
                        color: readinessColor,
                        compact: true
                    )
                }
            }
        }
    }

    private var manualIPConnectionCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Manual IP / Tailscale",
                    subtitle: "Use this when your iPhone cannot discover the Mac automatically."
                ) {
                    Button {
                        syncService.refreshManualIPAddresses()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
                }

                Toggle(isOn: Binding(
                    get: { syncService.manualIPServerEnabled },
                    set: { syncService.setManualIPServerEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        Text("Allow Manual IP Connections")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.textPrimary)
                        Text(manualIPServerStatusText)
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .toggleStyle(.switch)

                if syncService.manualIPServerEnabled {
                    GeistDivider()

                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: Spacing.s1) {
                                Text("Pairing Code")
                                    .font(Typography.label())
                                    .foregroundStyle(Color.textMuted)
                                Text(syncService.manualIPPairingCode ?? "Generate a code")
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.textPrimary)
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            Button(syncService.manualIPPairingCode == nil ? "Generate Code" : "New Code") {
                                syncService.generateManualIPPairingCode()
                            }
                            .buttonStyle(GeistMacButtonStyle(kind: .primary, size: .small))
                        }

                        if let expiry = syncService.manualIPPairingCodeExpiresAt {
                            Text("Expires at \(expiry.formatted(date: .omitted, time: .shortened)).")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                    }

                    GeistDivider()

                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        Text("Enter one of these addresses on iPhone. Port: \(SyncService.manualIPPort)")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)

                        if syncService.manualIPAddresses.isEmpty {
                            Text("No non-loopback IPv4 addresses found. Check Tailscale or Wi‑Fi and refresh.")
                                .font(Typography.caption())
                                .foregroundStyle(Color.warning)
                        } else {
                            ForEach(syncService.manualIPAddresses) { address in
                                HStack(spacing: Spacing.s2) {
                                    Image(systemName: address.isLikelyTailscale ? "lock.icloud" : "network")
                                        .foregroundStyle(address.isLikelyTailscale ? Color.success : Color.textMuted)
                                        .frame(width: 18)
                                        .accessibilityHidden(true)

                                    Text(address.displayName)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                        .textSelection(.enabled)

                                    Spacer(minLength: Spacing.s2)

                                    Button("Copy") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(address.address, forType: .string)
                                    }
                                    .buttonStyle(GeistMacButtonStyle(kind: .tertiary, size: .small))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var setupStepsCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Setup Steps",
                    subtitle: "Use your iPhone to configure and send exports."
                )

                VStack(alignment: .leading, spacing: Spacing.s3) {
                    setupStep(1, "Open Health.md on iPhone")
                    setupStep(2, "Enable Mac Destination")
                    setupStep(3, "Choose a destination folder")
                    setupStep(4, "Select this Mac and export")
                }

                GeistDivider()

                Button {
                    FeedbackHelper.openGitHubIssue()
                } label: {
                    Label("Open GitHub Issue", systemImage: "arrow.up.forward")
                }
                .buttonStyle(GeistMacButtonStyle(kind: .tertiary, size: .small))
                .accessibilityLabel("Open GitHub issue")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup steps: open Health.md on iPhone, enable Mac Destination, choose a destination folder, select this Mac and export")
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(spacing: Spacing.s3) {
            Text(String(number))
                .font(Typography.label())
                .foregroundStyle(Color.bgPrimary)
                .frame(width: 24, height: 24)
                .background(Color.accent, in: Circle())

            Text(text)
                .font(Typography.body())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
        }
    }

    private var activityCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Activity Feed",
                    subtitle: "Recent sync and export events on this Mac."
                ) {
                    Button("Clear Activity") {
                        showActivityClearConfirmation = true
                    }
                    .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
                    .disabled(historyManager.history.isEmpty)
                    .accessibilityLabel("Clear activity feed")
                }

                ActivityTimelineView(
                    items: activityItems,
                    byteFormatter: byteString,
                    dateFormatter: Self.sidebarDateFormatter,
                    visibleItemLimit: 5
                )
            }
        }
    }

    private var legacyCacheCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: "Legacy Cache",
                    subtitle: legacyCacheText
                )

                Button("Delete Legacy Cache", role: .destructive) {
                    showClearConfirmation = true
                }
                .buttonStyle(GeistMacButtonStyle(kind: .danger, size: .small))
                .disabled(healthDataStore.recordCount == 0)
            }
        }
    }

    private func errorBanner(_ error: String) -> some View {
        GeistMacCard(padding: Spacing.s4) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Receiver Error")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                    Text(error)
                        .font(Typography.body())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - State

    private var manualIPServerStatusText: String {
        if !syncService.manualIPServerEnabled {
            return "Disabled. Nearby discovery still works over local Wi‑Fi/Bluetooth."
        }
        if syncService.activeTransport == .manualIP && syncService.connectionState == .connected {
            return "Connected to \(syncService.connectedPeerName ?? "iPhone") by manual IP / Tailscale."
        }
        if syncService.manualIPServerListening {
            return "Listening on port \(SyncService.manualIPPort). Generate a pairing code before connecting from iPhone."
        }
        return "Starting listener…"
    }

    private var connectionDotColor: Color {
        if receivingPaused { return Color.warning }
        switch syncService.connectionState {
        case .connected: return Color.success
        case .connecting: return Color.warning
        case .disconnected: return Color.textMuted
        }
    }

    private var connectionStatusIcon: String {
        if receivingPaused { return "pause.fill" }
        switch syncService.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "dot.radiowaves.left.and.right"
        }
    }

    private var readinessHeroTitle: String {
        if receivingPaused { return "Receiving Paused" }
        if syncService.isSyncing { return "Receiving Export" }
        if isReadyForExports { return "Ready to Receive" }
        if syncService.connectionState == .connected && !folderAccessHealthy { return "Choose Destination" }
        if syncService.connectionState == .connecting { return "Connecting to iPhone" }
        return "Listening for iPhone"
    }

    private var readinessText: String {
        if syncService.isSyncing { return "Receiving Export" }
        if receivingPaused { return "Paused" }
        if syncService.connectionState != .connected { return "Connect iPhone" }
        if !iPhoneSupportsMacExports { return "Update iPhone App" }
        if vaultManager.vaultURL == nil { return "Choose Folder" }
        if !folderAccessHealthy { return "Re-select Folder" }
        return "Ready"
    }

    private var readinessColor: Color {
        readinessText == "Ready" ? Color.success : Color.warning
    }

    private var readinessIcon: String {
        readinessText == "Ready" ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var statusPrimaryLine: String {
        switch syncService.connectionState {
        case .connected:
            return "Connected to \(syncService.connectedPeerName ?? "iPhone")"
        case .connecting:
            return "Establishing local connection"
        case .disconnected:
            return receivingPaused ? "Discovery paused" : "Searching nearby devices"
        }
    }

    private var statusSecondaryLine: String {
        if let progress = syncService.activeMacExportProgress,
           ![MacExportPhase.completed, .failed, .cancelled].contains(progress.phase) {
            return progress.message
        }
        if let error = syncService.lastError { return error }
        if syncService.connectionState == .connected {
            let device = syncService.connectedPeerName ?? "iPhone"
            return "\(device) · local network · encrypted handoff"
        }
        return folderAccessHealthy ? "Destination validated · waiting on iPhone" : "Choose a folder to start receiving"
    }

    private var folderAccessHealthy: Bool {
        vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
    }

    private var folderExists: Bool {
        guard let url = vaultManager.vaultURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var folderTitle: String {
        guard vaultManager.vaultURL != nil else { return "No folder selected" }
        return folderAccessHealthy ? vaultManager.vaultName : "Folder access needs attention"
    }

    private var folderSubtitle: String {
        guard let url = vaultManager.vaultURL else {
            return "Choose where this Mac should save exports."
        }
        if folderAccessHealthy {
            return url.path(percentEncoded: false)
        }
        return "Re-select \(url.lastPathComponent) so Health.md can write exports."
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

    private var iPhoneSupportsMacExports: Bool {
        guard syncService.connectionState == .connected else { return false }
        guard let capabilities = syncService.remoteCapabilities else { return false }
        return capabilities.platform == .iOS && capabilities.isCompatibleWithMacExportJobs
    }

    private var permissionValue: String {
        folderAccessHealthy ? "Folder Access" : "Select Folder"
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var lastCheckText: String {
        if syncService.isSyncing { return "In Progress" }
        if syncService.connectionState == .connected { return "Just Now" }
        return receivingPaused ? "Paused" : "Scanning"
    }

    private var legacyCacheText: String {
        if healthDataStore.recordCount > 0 {
            return "\(healthDataStore.recordCount) cached day(s) from the old sync flow. New exports are received directly."
        }
        return "No legacy records cached from the old sync flow."
    }

    private var volumeKind: String {
        guard let url = vaultManager.vaultURL,
              let values = try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]),
              let description = values.volumeLocalizedFormatDescription,
              !description.isEmpty else {
            return "APFS"
        }
        return description
    }

    private var storageSummary: StorageSummary {
        let targetURL = vaultManager.vaultURL ?? FileManager.default.homeDirectoryForCurrentUser
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: targetURL.path),
              let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else {
            return StorageSummary(freeBytes: 0, totalBytes: 0)
        }
        return StorageSummary(freeBytes: free.int64Value, totalBytes: total.int64Value)
    }

    private var activityItems: [ActivityFeedItem] {
        var items: [ActivityFeedItem] = []

        if let progress = syncService.activeMacExportProgress,
           ![MacExportPhase.completed, .failed, .cancelled].contains(progress.phase) {
            items.append(ActivityFeedItem(
                timestamp: Date(),
                icon: "arrow.down.doc.fill",
                title: "Export in Progress",
                headline: progress.message,
                detail: progress.totalDays > 0 ? "\(progress.processedDays)/\(progress.totalDays) records" : "Receiving from iPhone",
                trailing: progress.filesWritten > 0 ? "\(progress.filesWritten) files" : nil,
                color: Color.accent
            ))
        }

        items.append(contentsOf: historyManager.history.prefix(6).map(activityItem(for:)))

        if items.isEmpty {
            if syncService.connectionState == .connected {
                items.append(ActivityFeedItem(
                    timestamp: Date().addingTimeInterval(-60),
                    icon: "link",
                    title: "Connection Established",
                    headline: syncService.connectedPeerName ?? "iPhone",
                    detail: "Wi‑Fi / local network",
                    trailing: nil,
                    color: Color.success
                ))
            }

            items.append(ActivityFeedItem(
                timestamp: Date().addingTimeInterval(-180),
                icon: folderAccessHealthy ? "checkmark" : "folder.badge.questionmark",
                title: folderAccessHealthy ? "Destination Validated" : "Destination Needed",
                headline: folderAccessHealthy ? storageSummary.shortFree + " available" : "Choose a folder",
                detail: folderAccessHealthy ? "Good to go" : "Required before exports",
                trailing: nil,
                color: folderAccessHealthy ? Color.success : Color.warning
            ))

            items.append(ActivityFeedItem(
                timestamp: Date().addingTimeInterval(-420),
                icon: "paperplane.fill",
                title: "App Launched",
                headline: "Mac Destination ready",
                detail: receivingPaused ? "Discovery paused" : "Listening for Health.md",
                trailing: nil,
                color: Color.accent
            ))
        }

        return items
    }

    private func activityItem(for event: SyncEvent) -> ActivityFeedItem {
        let title: String
        let icon: String
        let color: Color

        switch event.kind {
        case .dataReceived:
            title = "Export Received"
            icon = "tray.and.arrow.down.fill"
            color = Color.accent
        case .progressComplete:
            title = "Sync Complete"
            icon = "checkmark.seal.fill"
            color = Color.success
        case .failed:
            title = "Sync Failed"
            icon = "xmark.circle.fill"
            color = Color.error
        case .macExportSucceeded:
            title = "Export Written"
            icon = "checkmark"
            color = Color.success
        case .macExportPartialSuccess:
            title = "Export Partial"
            icon = "exclamationmark"
            color = Color.warning
        case .macExportFailed:
            title = "Export Failed"
            icon = "xmark"
            color = Color.error
        case .macExportCancelled:
            title = "Export Cancelled"
            icon = "stop.fill"
            color = Color.warning
        }

        return ActivityFeedItem(
            timestamp: event.timestamp,
            icon: icon,
            title: title,
            headline: event.summaryDescription,
            detail: eventDetail(for: event),
            trailing: event.payloadByteEstimate > 0 ? byteString(event.payloadByteEstimate) : nil,
            color: color
        )
    }

    private func eventDetail(for event: SyncEvent) -> String {
        let rangeText = dateRangeString(event)
        if let rangeText {
            return "\(rangeText) · \(event.peerName)"
        }
        return event.peerName
    }

    private func dateRangeString(_ entry: SyncEvent) -> String? {
        guard let start = entry.dateRangeStart, let end = entry.dateRangeEnd else {
            return nil
        }
        let s = Self.rangeFormatter.string(from: start)
        let e = Self.rangeFormatter.string(from: end)
        return s == e ? s : "\(s) → \(e)"
    }

    // MARK: - Actions

    private func toggleReceivingPaused() {
        receivingPaused.toggle()
        if receivingPaused {
            syncService.stopBrowsing()
        } else {
            syncService.startBrowsing()
        }
    }

    private func chooseDestinationFolder() {
        MacFolderPicker.show { url in
            vaultManager.setVaultFolder(url)
        }
    }

    private func byteString(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static let rangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let sidebarDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Geist Components

private struct GeistMacBackdrop: View {
    var body: some View {
        Color.bgSecondary
            .ignoresSafeArea()
    }
}

private struct GeistMacCard<Content: View>: View {
    var cornerRadius: CGFloat = GeistRadius.md
    var padding: CGFloat = Spacing.s6
    @ViewBuilder var content: Content

    init(
        cornerRadius: CGFloat = GeistRadius.md,
        padding: CGFloat = Spacing.s6,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.bgPrimary, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
    }
}

private struct GeistSectionHeader<Accessory: View>: View {
    let title: String
    let subtitle: String?
    private let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-0.2)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Spacing.s3)

            accessory
        }
    }
}

private extension GeistSectionHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

private struct GeistDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
    }
}

private enum GeistMacButtonKind {
    case primary
    case secondary
    case tertiary
    case danger
}

private enum GeistMacButtonSize {
    case regular
    case small
}

private struct GeistMacButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let kind: GeistMacButtonKind
    var size: GeistMacButtonSize = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size == .regular ? Typography.bodyEmphasis() : Typography.caption())
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, size == .regular ? Spacing.s4 : Spacing.s3)
            .frame(height: size == .regular ? 40 : 32)
            .background(backgroundColor(configuration: configuration), in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.52)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary: return Color.bgPrimary
        case .secondary, .tertiary: return Color.textPrimary
        case .danger: return Color.bgPrimary
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return Color.accent
        case .secondary: return Color.borderSubtle
        case .tertiary: return Color.clear
        case .danger: return Color.error
        }
    }

    private var borderWidth: CGFloat {
        kind == .tertiary ? 0 : 1
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        switch kind {
        case .primary:
            return Color.accent.opacity(configuration.isPressed ? 0.84 : 1)
        case .secondary:
            return configuration.isPressed ? Color.controlPressed : Color.controlBackground
        case .tertiary:
            return configuration.isPressed ? Color.controlPressed : Color.clear
        case .danger:
            return Color.error.opacity(configuration.isPressed ? 0.84 : 1)
        }
    }
}

private struct GeistStatusPill: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let color: Color
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.s2) {
            Image(systemName: systemImage)
                .font(Typography.label())
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(compact ? Typography.caption() : Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let subtitle, !compact {
                    Text(subtitle)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, compact ? Spacing.s3 : Spacing.s4)
        .padding(.vertical, compact ? Spacing.s2 : Spacing.s3)
        .background(color.opacity(0.10), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private struct GeistMetricTile: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                Text(value)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct GeistInfoChip: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            Image(systemName: icon)
                .font(Typography.caption())
                .foregroundStyle(color)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .font(Typography.label())
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct SystemStatusBlock: View {
    let icon: String
    let title: String
    let value: String
    let badge: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .fill(Color.bgSecondary)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                Text(value)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                Text(badge)
                    .font(Typography.caption())
                    .foregroundStyle(color)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct StorageUsageBar: View {
    let summary: StorageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.geistGray200)
                    Capsule()
                        .fill(Color.accent)
                        .frame(width: max(8, proxy.size.width * summary.usedFraction))
                }
            }
            .frame(height: 6)
            .accessibilityLabel("Storage used")
            .accessibilityValue(summary.usedPercentText)

            HStack {
                Text("\(summary.free) free of \(summary.total)")
                Spacer()
                Text(summary.usedPercentText)
            }
            .font(Typography.caption())
            .foregroundStyle(Color.textMuted)
        }
    }
}

// MARK: - Activity Timeline

private struct ActivityTimelineView: View {
    let items: [ActivityFeedItem]
    let byteFormatter: (Int) -> String
    let dateFormatter: DateFormatter
    let visibleItemLimit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.prefix(visibleItemLimit).enumerated()), id: \.element.id) { index, item in
                ActivityTimelineRow(
                    item: item,
                    isLast: index == min(items.count, visibleItemLimit) - 1,
                    dateFormatter: dateFormatter
                )
            }
        }
    }
}

private struct ActivityTimelineRow: View {
    let item: ActivityFeedItem
    let isLast: Bool
    let dateFormatter: DateFormatter

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(item.color.opacity(0.10))
                        .frame(width: 30, height: 30)
                    Image(systemName: item.icon)
                        .font(Typography.caption())
                        .foregroundStyle(item.color)
                        .accessibilityHidden(true)
                }

                if !isLast {
                    Rectangle()
                        .fill(Color.borderSubtle)
                        .frame(width: 1, height: 52)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    Text(item.title)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: Spacing.s2)

                    Text(item.timestamp, style: .time)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .accessibilityLabel(dateFormatter.string(from: item.timestamp))
                }

                Text(item.headline)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    Text(item.detail)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let trailing = item.trailing {
                        Text(trailing)
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(.bottom, isLast ? 0 : Spacing.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.headline). \(item.detail)")
    }
}

private struct ActivityFeedItem: Identifiable {
    let id = UUID()
    let timestamp: Date
    let icon: String
    let title: String
    let headline: String
    let detail: String
    let trailing: String?
    let color: Color
}

private struct StorageSummary {
    let freeBytes: Int64
    let totalBytes: Int64

    var usedBytes: Int64 { max(totalBytes - freeBytes, 0) }
    var usedFraction: CGFloat {
        guard totalBytes > 0 else { return 0.38 }
        return min(max(CGFloat(usedBytes) / CGFloat(totalBytes), 0), 1)
    }
    var usedPercentText: String { "\(Int((usedFraction * 100).rounded()))%" }
    var free: String { Self.format(bytes: freeBytes) }
    var total: String { Self.format(bytes: totalBytes) }
    var shortFree: String {
        if freeBytes == 0 { return "— free" }
        return "\(free) free"
    }
    var volumeLabel: String { totalBytes > 0 ? "Local SSD" : "Unknown" }

    private static func format(bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#endif
