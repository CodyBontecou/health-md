#if os(macOS)
import AppKit
import MultipeerConnectivity
import SwiftUI

// MARK: - Mac Destination View

/// Teenage Engineering-inspired destination dashboard with Obsidian-tinted dark chrome.
/// iPhone owns export configuration; macOS listens, validates the local destination,
/// writes received jobs, and exposes recent activity.
struct MacSyncView: View {
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var healthDataStore: HealthDataStore

    @ObservedObject private var historyManager = SyncEventHistoryManager.shared


    @State private var receivingPaused = false
    @State private var showClearConfirmation = false
    @State private var showActivityClearConfirmation = false

    private let sidebarWidth: CGFloat = 360
    private let minimumDashboardWidth: CGFloat = 1_360
    private let minimumDashboardHeight: CGFloat = 760
    private let contentCardRowHeight: CGFloat = 250
    private let contentCardDrop: CGFloat = 48

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(for: proxy.size)

            ZStack(alignment: .topLeading) {
                MacDestinationBackdrop()

                HStack(spacing: 0) {
                    mainPanel(metrics: metrics)
                        .frame(width: metrics.mainPanelWidth, height: metrics.dashboardHeight, alignment: .topLeading)

                    Hairline(axis: .vertical)
                        .frame(height: metrics.dashboardHeight)

                    activitySidebar(metrics: metrics)
                        .frame(width: metrics.sidebarWidth, height: metrics.dashboardHeight, alignment: .topLeading)
                }
                .frame(width: metrics.dashboardWidth, height: metrics.dashboardHeight, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .foregroundStyle(Color.textPrimary)
        .onAppear {
            receivingPaused = false
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
        .alert("Clear Activity Feed?", isPresented: $showActivityClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                historyManager.clearHistory()
            }
        } message: {
            Text("This removes recorded iPhone→Mac sync and export events from this Mac. Your synced health data and exported files are not affected.")
        }
    }

    // MARK: - Shell

    private func layoutMetrics(for size: CGSize) -> MacDestinationDashboardMetrics {
        MacDestinationDashboardMetrics(
            size: size,
            preferredDashboardWidth: minimumDashboardWidth,
            preferredDashboardHeight: minimumDashboardHeight,
            maximumSidebarWidth: sidebarWidth,
            defaultContentCardRowHeight: contentCardRowHeight,
            defaultContentCardDrop: contentCardDrop
        )
    }

    private func mainPanel(metrics: MacDestinationDashboardMetrics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            heroSection(metrics: metrics)

            HStack(alignment: .top, spacing: 12) {
                destinationCard
                systemStatusCard
            }
            .frame(height: metrics.contentCardRowHeight)
            .padding(.top, metrics.contentCardDrop)

            if let error = syncService.lastError {
                errorBanner(error)
            }
        }
        .padding(metrics.mainPanelPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func activitySidebar(metrics: MacDestinationDashboardMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.sidebarSpacing) {
            HStack(alignment: .firstTextBaseline) {
                DestinationLabel("Activity Feed")
                Spacer()
                Button("Clear All") {
                    showActivityClearConfirmation = true
                }
                .buttonStyle(MicroButtonStyle())
                .disabled(historyManager.history.isEmpty)
                .accessibilityLabel("Clear activity feed")
            }

            TimelineView(
                items: activityItems,
                byteFormatter: byteString,
                dateFormatter: Self.sidebarDateFormatter,
                visibleItemLimit: metrics.activityItemLimit,
                connectorHeight: metrics.activityConnectorHeight,
                compact: metrics.compactTimelineRows
            )
            .frame(height: metrics.activityTimelineHeight, alignment: .top)
            .clipped()

            if healthDataStore.recordCount > 0 {
                legacyCacheCard
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.sidebarHorizontalPadding)
        .padding(.top, metrics.sidebarTopPadding)
        .padding(.bottom, metrics.sidebarBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.08))
        .clipped()
    }

    // MARK: - Main Content

    private func heroSection(metrics: MacDestinationDashboardMetrics) -> some View {
        ZStack(alignment: .topLeading) {
            RadarView(isActive: isReadyForExports || syncService.isSyncing)
                .frame(width: metrics.radarSize, height: metrics.radarSize)
                .offset(x: -16, y: metrics.radarYOffset)
                .opacity(metrics.radarOpacity)
                .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: metrics.heroColumnSpacing) {
                VStack(alignment: .leading, spacing: 0) {
                    DestinationLabel("Mac Receiver")
                        .padding(.bottom, 10)

                    Text("Health.md")
                        .font(Typography.monoEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .tracking(1.2)
                        .minimumScaleFactor(0.86)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)

                    Text("Receive Health.md exports from your iPhone\nand save them as Markdown in your vault.")
                        .font(Typography.mono())
                        .foregroundStyle(Color.textSecondary)
                        .lineSpacing(4)
                        .padding(.top, 12)

                    Spacer(minLength: metrics.titleToStatusSpacer)

                    HStack(alignment: .bottom, spacing: metrics.statusGroupSpacing) {
                        Color.clear
                            .frame(width: metrics.radarSpacerWidth, height: metrics.radarSpacerHeight)

                        VStack(alignment: .leading, spacing: 10) {
                            DestinationLabel("Status")

                            Text(readinessHeroTitle)
                                .font(Typography.mono())
                                .foregroundStyle(Color.textPrimary)
                                .tracking(0.7)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            HStack(spacing: 8) {
                                Circle()
                                    .fill(connectionDotColor)
                                    .frame(width: 8, height: 8)
                                    .shadow(color: connectionDotColor.opacity(0.55), radius: 6)
                                    .accessibilityHidden(true)

                                Text(statusPrimaryLine)
                                    .font(Typography.mono())
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                            }

                            Text(statusSecondaryLine)
                                .font(Typography.monoCaption())
                                .foregroundStyle(Color.textMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            receivingControls(compact: metrics.compactControls)
                                .padding(.top, 6)

                            if !syncService.discoveredPeers.isEmpty && syncService.connectionState != .connected {
                                nearbyDevicesStrip
                                    .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: metrics.heroTextColumnMinHeight, alignment: .topLeading)

                setupStepsCard
                    .frame(width: metrics.setupCardWidth)
                    .padding(.bottom, metrics.setupCardBottomPadding)
            }
        }
        .frame(height: metrics.heroHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func receivingControls(compact: Bool) -> some View {
        pauseReceivingButton
    }

    private var pauseReceivingButton: some View {
        Button {
            toggleReceivingPaused()
        } label: {
            Label(receivingPaused ? "Resume Receiving" : "Pause Receiving",
                  systemImage: receivingPaused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(DestinationButtonStyle(kind: .primary))
        .disabled(syncService.connectionState == .connecting)
    }

    private var setupStepsCard: some View {
        DestinationPanel(cornerRadius: 10, padding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                DestinationLabel("Setup Steps")

                VStack(alignment: .leading, spacing: 18) {
                    setupStep(1, "Open Health.md on iPhone")
                    setupStep(2, "Enable Mac Destination")
                    setupStep(3, "Choose a destination folder")
                    setupStep(4, "Select this Mac and tap Export")
                }

                Hairline(axis: .horizontal)
                    .padding(.top, 2)

                Button {
                    FeedbackHelper.openGitHubIssue()
                } label: {
                    HStack(spacing: 6) {
                        Text("Need help?")
                        Image(systemName: "arrow.up.forward")
                            .font(Typography.bodyEmphasis())
                            .accessibilityHidden(true)
                    }
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Need help? Open GitHub issue")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Setup steps: open Health.md on iPhone, enable Mac Destination, choose a destination folder, select this Mac and tap Export")
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", number))
                .font(Typography.monoEmphasis())
                .foregroundStyle(Color.textPrimary.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accent.opacity(0.34)))
                .overlay(Circle().strokeBorder(Color.accent.opacity(0.32), lineWidth: 1))

            Text(text)
                .font(Typography.monoCaption())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
    }

    private var nearbyDevicesStrip: some View {
        HStack(spacing: 8) {
            ForEach(syncService.discoveredPeers.prefix(2), id: \.displayName) { peer in
                Button {
                    syncService.connectToPeer(peer)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                        Text(peer.displayName)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(MicroButtonStyle())
                .accessibilityLabel("Connect to \(peer.displayName)")
            }
        }
    }

    private var destinationCard: some View {
        DestinationPanel(cornerRadius: 10, padding: 18, fillsAvailableHeight: true) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    DestinationLabel("Destination")
                    Spacer()
                    Circle()
                        .fill(folderAccessHealthy ? Color.success : Color.warning)
                        .frame(width: 8, height: 8)
                        .shadow(color: (folderAccessHealthy ? Color.success : Color.warning).opacity(0.55), radius: 5)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 18) {
                    Image(systemName: vaultManager.vaultURL == nil ? "folder" : "folder.fill")
                        .font(Typography.body())
                        .foregroundStyle(folderAccessHealthy ? Color.textPrimary.opacity(0.86) : Color.textMuted)
                        .frame(width: 58, height: 50)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(folderTitle)
                            .font(Typography.mono())
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Text(folderSubtitle)
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 8)

                    Button(vaultManager.vaultURL == nil ? "Choose…" : "Change…") {
                        chooseDestinationFolder()
                    }
                    .buttonStyle(MicroButtonStyle())
                    .accessibilityLabel(vaultManager.vaultURL == nil ? "Choose destination folder" : "Change destination folder")
                }

                Hairline(axis: .horizontal)

                HStack(spacing: 12) {
                    DestinationStatusChip(
                        icon: "folder",
                        title: vaultManager.vaultURL == nil ? "No folder" : "Folder exists",
                        subtitle: vaultManager.vaultURL == nil ? "Required" : (folderExists ? "Ready" : "Missing"),
                        color: folderExists ? Color.textMuted : Color.warning
                    )

                    DestinationStatusChip(
                        icon: "checkmark.square",
                        title: "Writable",
                        subtitle: folderAccessHealthy ? "Verified" : "Needs access",
                        color: folderAccessHealthy ? Color.textMuted : Color.warning
                    )

                    DestinationStatusChip(
                        icon: "internaldrive",
                        title: storageSummary.shortFree,
                        subtitle: storageSummary.usedPercentText + " used",
                        color: Color.textMuted
                    )

                    DestinationStatusChip(
                        icon: "checkmark.seal",
                        title: volumeKind,
                        subtitle: storageSummary.volumeLabel,
                        color: Color.textMuted
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Destination folder")
        .accessibilityValue(folderAccessibilityValue)
    }


    private var systemStatusCard: some View {
        DestinationPanel(cornerRadius: 10, padding: 18, fillsAvailableHeight: true) {
            VStack(alignment: .leading, spacing: 18) {
                DestinationLabel("System Status")

                HStack(alignment: .top, spacing: 28) {
                    systemStatusBlock(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Receiver",
                        value: "v\(appVersion)",
                        badge: "Up to date",
                        color: Color.success
                    )

                    systemStatusBlock(
                        icon: "stopwatch",
                        title: "Permissions",
                        value: permissionValue,
                        badge: folderAccessHealthy ? "Granted" : "Needs access",
                        color: folderAccessHealthy ? Color.success : Color.warning
                    )
                }

                Hairline(axis: .horizontal)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last check")
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.textMuted)
                        Text(lastCheckText)
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer()

                    Button {
                        syncService.stopBrowsing()
                        syncService.startBrowsing()
                    } label: {
                        Label("Check Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(MicroButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func systemStatusBlock(
        icon: String,
        title: String,
        value: String,
        badge: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .strokeBorder(Color.borderDefault.opacity(0.65), lineWidth: 1)
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textMuted)
                Text(value)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)
                Text(badge)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBanner(_ error: String) -> some View {
        DestinationPanel(cornerRadius: 10, padding: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.warning)
                    .accessibilityHidden(true)
                Text(error)
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.warning)
                    .lineLimit(2)
                Spacer()
            }
        }
    }

    // MARK: - Sidebar Cards

    private var storageCard: some View {
        DestinationPanel(cornerRadius: 9, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "internaldrive")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityHidden(true)
                    DestinationLabel("Storage")
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Color.accent)
                            .shadow(color: Color.accent.opacity(0.35), radius: 7)
                            .frame(width: max(7, proxy.size.width * storageSummary.usedFraction))
                    }
                }
                .frame(height: 6)
                .accessibilityLabel("Storage used")
                .accessibilityValue(storageSummary.usedPercentText)

                HStack {
                    Text("\(storageSummary.free) free of \(storageSummary.total)")
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textMuted)
                    Spacer()
                    Text(storageSummary.usedPercentText)
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
    }

    private var legacyCacheCard: some View {
        DestinationPanel(cornerRadius: 9, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)
                    DestinationLabel("Legacy Synced Cache")
                }

                Text(legacyCacheText)
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Delete Legacy Cache", role: .destructive) {
                    showClearConfirmation = true
                }
                .buttonStyle(DestinationButtonStyle(kind: .danger))
                .disabled(healthDataStore.recordCount == 0)
            }
        }
    }

    // MARK: - State

    private var connectionDotColor: Color {
        if receivingPaused { return Color.warning }
        switch syncService.connectionState {
        case .connected: return Color.success
        case .connecting: return Color.warning
        case .disconnected: return Color.textMuted
        }
    }

    private var readinessHeroTitle: String {
        if receivingPaused { return "Receiving Paused" }
        if syncService.isSyncing { return "Receiving Export" }
        if isReadyForExports { return "Ready to Receive" }
        if syncService.connectionState == .connected && !folderAccessHealthy { return "Choose Destination" }
        if syncService.connectionState == .connecting { return "Connecting" }
        return "Listening for iPhone"
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
        return folderAccessHealthy ? "Destination validated · waiting on iPhone" : "Choose a folder to unlock receiving"
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
        if syncService.isSyncing { return "In progress" }
        if syncService.connectionState == .connected { return "Just now" }
        return receivingPaused ? "Paused" : "Scanning"
    }

    private var footerStatusColor: Color {
        if syncService.lastError != nil { return Color.warning }
        return isReadyForExports || folderAccessHealthy ? Color.success : Color.textMuted
    }

    private var footerStatusText: String {
        if let error = syncService.lastError { return error }
        if isReadyForExports { return "All systems nominal" }
        if folderAccessHealthy { return "Destination ready · awaiting iPhone" }
        return "Destination folder required"
    }

    private var transferSource: String {
        if syncService.connectionState == .connected {
            return syncService.connectedPeerName ?? "Health.md on iPhone"
        }
        return "Health.md on iPhone"
    }

    private var transferRecordEstimate: String {
        if let progress = syncService.activeMacExportProgress, progress.totalDays > 0 {
            return "~\(progress.totalDays) record\(progress.totalDays == 1 ? "" : "s")"
        }
        if let result = syncService.lastMacExportResult, result.totalCount > 0 {
            return "last \(result.totalCount) record\(result.totalCount == 1 ? "" : "s")"
        }
        if healthDataStore.recordCount > 0 {
            return "\(healthDataStore.recordCount) cached"
        }
        return "~1 new record"
    }

    private var transferSizeEstimate: String {
        if let latest = historyManager.history.first, latest.payloadByteEstimate > 0 {
            return byteString(latest.payloadByteEstimate)
        }
        if let progress = syncService.activeMacExportProgress, progress.totalDays > 0 {
            return progress.totalDays == 1 ? "~1 KB" : "~\(max(progress.totalDays, 1)) KB"
        }
        return "~1 KB"
    }

    private var transferFileEstimate: String {
        if let progress = syncService.activeMacExportProgress, progress.filesWritten > 0 {
            return "\(progress.filesWritten) written"
        }
        if let result = syncService.lastMacExportResult {
            return "\(result.totalFilesWritten) file\(result.totalFilesWritten == 1 ? "" : "s")"
        }
        return "1 .json file"
    }

    private var legacyCacheText: String {
        if healthDataStore.recordCount > 0 {
            return "\(healthDataStore.recordCount) cached day(s) from old sync flow.\nExports are now received directly."
        }
        return "No legacy records cached from the old sync flow.\nExports are received directly."
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
                title: "EXPORT IN PROGRESS",
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
                    title: "CONNECTION ESTABLISHED",
                    headline: syncService.connectedPeerName ?? "iPhone",
                    detail: "Wi‑Fi / local network",
                    trailing: nil,
                    color: Color.success
                ))
            }

            items.append(ActivityFeedItem(
                timestamp: Date().addingTimeInterval(-180),
                icon: folderAccessHealthy ? "checkmark" : "folder.badge.questionmark",
                title: folderAccessHealthy ? "DESTINATION VALIDATED" : "DESTINATION NEEDED",
                headline: folderAccessHealthy ? storageSummary.shortFree + " available" : "Choose a folder",
                detail: folderAccessHealthy ? "Good to go" : "Required before exports",
                trailing: nil,
                color: folderAccessHealthy ? Color.success : Color.warning
            ))

            items.append(ActivityFeedItem(
                timestamp: Date().addingTimeInterval(-420),
                icon: "paperplane.fill",
                title: "APP LAUNCHED",
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
            title = "EXPORT RECEIVED"
            icon = "tray.and.arrow.down.fill"
            color = Color.accent
        case .progressComplete:
            title = "SYNC COMPLETE"
            icon = "checkmark.seal.fill"
            color = Color.success
        case .failed:
            title = "SYNC FAILED"
            icon = "xmark.circle.fill"
            color = Color.error
        case .macExportSucceeded:
            title = "EXPORT WRITTEN"
            icon = "checkmark"
            color = Color.success
        case .macExportPartialSuccess:
            title = "EXPORT PARTIAL"
            icon = "exclamationmark"
            color = Color.warning
        case .macExportFailed:
            title = "EXPORT FAILED"
            icon = "xmark"
            color = Color.error
        case .macExportCancelled:
            title = "EXPORT CANCELLED"
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

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
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

// MARK: - Responsive Layout Metrics

private struct MacDestinationDashboardMetrics {
    let size: CGSize
    let preferredDashboardWidth: CGFloat
    let preferredDashboardHeight: CGFloat
    let maximumSidebarWidth: CGFloat
    let defaultContentCardRowHeight: CGFloat
    let defaultContentCardDrop: CGFloat

    private var width: CGFloat { max(size.width, 1) }
    private var height: CGFloat { max(size.height, 1) }

    var dashboardWidth: CGFloat { width }
    var dashboardHeight: CGFloat { height }

    var isCompactWidth: Bool { width < preferredDashboardWidth * 0.92 }
    var isCompactHeight: Bool { height < preferredDashboardHeight }
    var isTightHeight: Bool { height < 720 }

    var sidebarWidth: CGFloat {
        if width < 1_160 {
            return min(max(width * 0.27, 286), 304)
        }
        if width < 1_280 {
            return min(max(width * 0.28, 310), 336)
        }
        return maximumSidebarWidth
    }

    var mainPanelWidth: CGFloat {
        max(width - sidebarWidth - 1, 0)
    }

    var mainPanelPadding: CGFloat { isCompactWidth || isCompactHeight ? 20 : 24 }

    var heroHeight: CGFloat { isCompactHeight ? 318 : 330 }
    var heroTextColumnMinHeight: CGFloat { isCompactHeight ? 286 : 300 }
    var heroColumnSpacing: CGFloat { isCompactWidth ? 16 : 24 }
    var heroTitleSize: CGFloat { isCompactWidth ? 31 : 34 }
    var statusTitleSize: CGFloat { isCompactWidth ? 23 : 26 }
    var titleToStatusSpacer: CGFloat { isCompactHeight ? 14 : 22 }
    var setupCardWidth: CGFloat { isCompactWidth ? 280 : 304 }
    var setupCardBottomPadding: CGFloat { isCompactHeight ? 32 : 56 }
    var compactControls: Bool { isCompactWidth }

    var radarSize: CGFloat { isCompactWidth ? 220 : 250 }
    var radarYOffset: CGFloat { isCompactHeight ? 134 : 145 }
    var radarOpacity: Double { isCompactWidth ? 0.72 : 0.92 }
    var radarSpacerWidth: CGFloat { isCompactWidth ? 174 : 240 }
    var radarSpacerHeight: CGFloat { isCompactHeight ? 118 : 132 }
    var statusGroupSpacing: CGFloat { isCompactWidth ? 20 : 32 }

    var contentCardDrop: CGFloat { isCompactHeight ? 28 : defaultContentCardDrop }
    var contentCardRowHeight: CGFloat {
        if isCompactHeight {
            let available = height - (mainPanelPadding * 2) - heroHeight - 16 - contentCardDrop
            return max(220, available)
        }
        return defaultContentCardRowHeight
    }

    var sidebarHorizontalPadding: CGFloat { isCompactWidth ? 16 : 20 }
    var sidebarTopPadding: CGFloat { isTightHeight ? 22 : 30 }
    var sidebarBottomPadding: CGFloat { isTightHeight ? 14 : 18 }
    var sidebarSpacing: CGFloat { isTightHeight ? 12 : 16 }

    var activityItemLimit: Int { isTightHeight ? 3 : 4 }
    var compactTimelineRows: Bool { isCompactHeight || sidebarWidth < 340 }
    var activityConnectorHeight: CGFloat {
        if isTightHeight { return 44 }
        if isCompactHeight { return 56 }
        return 64
    }
    var activityTimelineHeight: CGFloat {
        let rowHeight = compactTimelineRows ? activityConnectorHeight + 38 : activityConnectorHeight + 46
        return CGFloat(activityItemLimit) * rowHeight
    }
}

// MARK: - Components

private struct DestinationLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(Typography.monoEmphasis())
            .foregroundStyle(Color.accentHover)
            .tracking(2.4)
    }
}

private struct DestinationPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let fillsAvailableHeight: Bool
    @ViewBuilder var content: Content

    init(
        cornerRadius: CGFloat = 10,
        padding: CGFloat = 18,
        fillsAvailableHeight: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.fillsAvailableHeight = fillsAvailableHeight
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(
                maxWidth: .infinity,
                maxHeight: fillsAvailableHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.bgSecondary.opacity(0.84))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.055), Color.clear, Color.accent.opacity(0.035)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.borderSubtle.opacity(0.86), Color.accent.opacity(0.14)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private struct Hairline: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis

    var body: some View {
        Rectangle()
            .fill(Color.borderSubtle.opacity(0.9))
            .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
            .overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.035))
                    .offset(x: axis == .vertical ? 1 : 0, y: axis == .horizontal ? 1 : 0)
            )
    }
}

private struct DestinationStatusChip: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.025))
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Typography.mono())
                    .foregroundStyle(Color.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DestinationSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                configuration.isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(configuration.isOn ? Color.accent : Color.white.opacity(0.07))
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(Color.textPrimary)
                        .frame(width: 14, height: 14)
                        .padding(3)
                        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private enum DestinationButtonKind {
    case primary
    case secondary
    case ghost
    case danger
}

private struct DestinationButtonStyle: ButtonStyle {
    let kind: DestinationButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.monoEmphasis())
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, kind == .ghost ? 12 : 16)
            .padding(.vertical, kind == .ghost ? 8 : 10)
            .background {
                background(configuration: configuration)
                    .clipShape(RoundedRectangle(cornerRadius: kind == .ghost ? 6 : 7, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: kind == .ghost ? 6 : 7, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.74 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary: return Color.textPrimary
        case .secondary, .ghost: return Color.textSecondary
        case .danger: return Color.error
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return Color.accent.opacity(0.42)
        case .secondary, .ghost: return Color.borderDefault.opacity(0.75)
        case .danger: return Color.error.opacity(0.16)
        }
    }

    @ViewBuilder
    private func background(configuration: Configuration) -> some View {
        switch kind {
        case .primary:
            LinearGradient(
                colors: [Color.accent.opacity(0.88), Color.accent.opacity(0.58)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .secondary:
            Color.white.opacity(configuration.isPressed ? 0.075 : 0.045)
        case .ghost:
            Color.clear
        case .danger:
            Color.error.opacity(configuration.isPressed ? 0.22 : 0.14)
        }
    }
}

private struct MicroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.monoEmphasis())
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.borderSubtle.opacity(0.75), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct RadarView: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .stroke(
                        index == 2 ? Color.accent.opacity(0.48) : Color.accent.opacity(0.11),
                        style: StrokeStyle(
                            lineWidth: index == 2 ? 1 : 0.8,
                            dash: index >= 4 ? [1.5, 7] : []
                        )
                    )
                    .frame(width: CGFloat(68 + index * 38), height: CGFloat(68 + index * 38))
            }

            Rectangle()
                .fill(Color.accent.opacity(0.34))
                .frame(width: 1, height: 222)
            Rectangle()
                .fill(Color.accent.opacity(0.34))
                .frame(width: 222, height: 1)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.success.opacity(isActive ? 0.95 : 0.35), Color.accent.opacity(0.18), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 30
                    )
                )
                .frame(width: 58, height: 58)

            Circle()
                .fill(isActive ? Color.success : Color.textMuted)
                .frame(width: 15, height: 15)
                .shadow(color: (isActive ? Color.success : Color.textMuted).opacity(0.55), radius: 8)
        }
        .rotationEffect(.degrees(-0.2))
    }
}

private struct WireframeTransferGlyph: View {
    var body: some View {
        ZStack {
            WireGrid()
                .stroke(Color.accent.opacity(0.15), lineWidth: 0.8)
                .frame(width: 150, height: 120)
                .offset(y: 18)

            IsometricCube()
                .fill(
                    LinearGradient(
                        colors: [Color.accent.opacity(0.62), Color.accent.opacity(0.16)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 64, height: 64)
                .offset(y: -26)
                .overlay(
                    IsometricCube()
                        .stroke(Color.accent.opacity(0.45), lineWidth: 1)
                        .frame(width: 64, height: 64)
                        .offset(y: -26)
                )

            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: CGFloat(14 - index * 3), style: .continuous)
                    .stroke(Color.accent.opacity(0.32 - Double(index) * 0.07), lineWidth: 1)
                    .frame(width: CGFloat(58 + index * 24), height: CGFloat(22 + index * 10))
                    .offset(y: CGFloat(42 + index * 2))
            }

            Circle()
                .fill(Color.accentHover)
                .frame(width: 8, height: 8)
                .shadow(color: Color.accentHover.opacity(0.7), radius: 10)
                .offset(y: 42)
        }
    }
}

private struct WireGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 5
        let xScale = rect.width / CGFloat(steps * 2)
        let yScale = rect.height / CGFloat(steps * 3)

        for i in -steps...steps {
            let start = CGPoint(x: center.x + CGFloat(i) * xScale, y: rect.minY + 12)
            let end = CGPoint(x: center.x + CGFloat(i) * xScale * 2.1, y: rect.maxY - 8)
            path.move(to: start)
            path.addLine(to: end)

            let startMirror = CGPoint(x: center.x + CGFloat(i) * xScale, y: rect.minY + 12)
            let endMirror = CGPoint(x: center.x - CGFloat(i) * xScale * 2.1, y: rect.maxY - 8)
            path.move(to: startMirror)
            path.addLine(to: endMirror)
        }

        for row in 0..<6 {
            let y = rect.minY + 18 + CGFloat(row) * yScale
            path.move(to: CGPoint(x: center.x - CGFloat(row + 1) * 18, y: y))
            path.addLine(to: CGPoint(x: center.x, y: y + CGFloat(row + 1) * 8))
            path.addLine(to: CGPoint(x: center.x + CGFloat(row + 1) * 18, y: y))
        }

        return path
    }
}

private struct IsometricCube: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.28)
        let bottom = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.56)
        let left = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.28)
        let lower = CGPoint(x: rect.midX, y: rect.maxY)

        path.move(to: top)
        path.addLine(to: right)
        path.addLine(to: bottom)
        path.addLine(to: lower)
        path.addLine(to: left)
        path.addLine(to: bottom)
        path.addLine(to: top)
        path.addLine(to: left)
        path.closeSubpath()
        return path
    }
}

private struct TimelineView: View {
    let items: [ActivityFeedItem]
    let byteFormatter: (Int) -> String
    let dateFormatter: DateFormatter
    let visibleItemLimit: Int
    let connectorHeight: CGFloat
    let compact: Bool

    var body: some View {
        let visibleItems = Array(items.prefix(visibleItemLimit))

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                TimelineRow(
                    item: item,
                    isLast: index == visibleItems.count - 1,
                    dateFormatter: dateFormatter,
                    connectorHeight: connectorHeight,
                    compact: compact
                )
            }
        }
    }
}

private struct TimelineRow: View {
    let item: ActivityFeedItem
    let isLast: Bool
    let dateFormatter: DateFormatter
    let connectorHeight: CGFloat
    let compact: Bool

    var body: some View {
        let iconSize: CGFloat = compact ? 30 : 34
        let bodySpacing: CGFloat = compact ? 5 : 7

        HStack(alignment: .top, spacing: compact ? 10 : 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(Color.bgTertiary.opacity(0.92))
                        .frame(width: iconSize, height: iconSize)
                    Image(systemName: item.icon)
                        .font(Typography.headline())
                        .foregroundStyle(item.color)
                        .accessibilityHidden(true)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.borderDefault.opacity(0.8))
                        .frame(width: 1, height: connectorHeight)
                }
            }

            VStack(alignment: .leading, spacing: bodySpacing) {
                Text(item.timestamp, style: .time)
                    .font(Typography.mono())
                    .foregroundStyle(Color.textMuted)
                    .accessibilityLabel(dateFormatter.string(from: item.timestamp))

                Text(item.title)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(item.color)
                    .tracking(0.8)
                    .lineLimit(1)

                Text(item.headline)
                    .font(Typography.mono())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(compact ? 1 : 2)

                HStack(alignment: .firstTextBaseline) {
                    Text(item.detail)
                        .font(Typography.mono())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(compact ? 1 : 2)
                    Spacer(minLength: 4)
                    if let trailing = item.trailing {
                        Text(trailing)
                            .font(Typography.mono())
                            .foregroundStyle(Color.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, isLast ? 0 : (compact ? 2 : 4))
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

private struct MacDestinationBackdrop: View {
    var body: some View {
        ZStack {
            Color.bgPrimary

            LinearGradient(
                colors: [Color.white.opacity(0.035), Color.clear, Color.black.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [Color.accent.opacity(0.22), Color.clear],
                center: UnitPoint(x: 0.2, y: 0.15),
                startRadius: 0,
                endRadius: 620
            )

            RadialGradient(
                colors: [Color.accentHover.opacity(0.11), Color.clear],
                center: UnitPoint(x: 0.9, y: 0.95),
                startRadius: 0,
                endRadius: 520
            )

            MicroDotGrid()
                .stroke(Color.white.opacity(0.025), lineWidth: 0.6)
        }
        .ignoresSafeArea()
    }
}

private struct MicroDotGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 28
        var y = rect.minY
        while y <= rect.maxY {
            var x = rect.minX
            while x <= rect.maxX {
                path.addEllipse(in: CGRect(x: x, y: y, width: 0.8, height: 0.8))
                x += spacing
            }
            y += spacing
        }
        return path
    }
}

#endif
