#if os(macOS)
import AppKit
import HealthMdConnectionCore
import MultipeerConnectivity
import SwiftUI

// MARK: - Mac Destination View

/// Geist-based destination dashboard. iPhone owns export configuration; macOS
/// listens, validates the local destination, writes received jobs, and exposes
/// recent activity.
struct MacSyncView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var healthDataStore: HealthDataStore

    @ObservedObject private var historyManager = SyncEventHistoryManager.shared
    @ObservedObject private var exportHistoryManager = ExportHistoryManager.shared

    @StateObject private var feedbackReporter = FeedbackReporter()
    @State private var receivingPaused = false
    @State private var showClearConfirmation = false
    @State private var showActivityClearConfirmation = false

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                            .id("marketing-sync")

                        if let progress = activeExportProgress {
                            activeExportCard(progress)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .move(edge: .top).combined(with: .opacity)
                                )
                        }

                        if !syncService.discoveredPeers.isEmpty && displayConnectionState != .connected {
                            nearbyDevicesCard
                        }

                        if let error = displayLastError {
                            errorBanner(error)
                        }

                        readinessSection
                        manualIPSection
                        activitySection

                        if displayConnectionState != .connected && historyManager.history.isEmpty {
                            setupStepsCard
                        }
                    }
                    .padding(.horizontal, horizontalPadding(for: proxy.size.width))
                    .padding(.vertical, 24)
                    .frame(maxWidth: 900, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .background(Color.glassAdaptive(\.bg).ignoresSafeArea())
                #if DEBUG
                .task {
                    guard MacMarketingCapture.isActive,
                          let target = MacMarketingCapture.scrollTarget else { return }
                    try? await Task.sleep(for: .milliseconds(650))
                    scrollProxy.scrollTo(target, anchor: .top)
                }
                #endif
            }
        }
        .foregroundStyle(Color.glassAdaptive(\.text))
        .tint(Color.glassAdaptive(\.accent))
        .toolbar { destinationToolbar }
        .feedbackFailureSheet($feedbackReporter.failure)
        .animation(
            reduceMotion ? nil : AnimationTimings.standard,
            value: activeExportProgress
        )
        .onAppear {
            receivingPaused = false
            #if DEBUG
            if MacMarketingCapture.isActive { return }
            #endif
            syncService.startBrowsing()
            // The Addresses row has no Refresh button on the board; re-read them on every visit.
            if syncService.manualIPServerEnabled { syncService.refreshManualIPAddresses() }
        }
        .geistDialog(
            isPresented: $showClearConfirmation,
            title: Text("Delete Legacy Synced Data?"),
            message: Text("This removes the old iPhone→Mac cache from this Mac. It does not affect Health data on iPhone or files already exported to your destination folder."),
            actions: [
                .cancel(),
                .destructive("Delete Data") {
                    healthDataStore.deleteAll()
                }
            ]
        )
        .geistDialog(
            isPresented: $showActivityClearConfirmation,
            title: Text("Clear Activity Feed?"),
            message: Text("This removes recorded iPhone→Mac sync and export events from this Mac. Your synced health data and exported files are not affected."),
            actions: [
                .cancel(),
                .destructive("Clear Activity") {
                    historyManager.clearHistory()
                }
            ]
        )
    }
    // MARK: - Layout

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        if width < 720 { return Spacing.s4 }
        if width < 1_080 { return Spacing.s6 }
        return Spacing.s8
    }

    // MARK: - Header

    /// MacHomeG: title, paragraph and the readiness pill. Pausing and clearing activity live in
    /// the window toolbar, outside the board's page.
    private var header: some View {
        MacGlassPageHeader(
            title: String(localized: "Mac destination"),
            subtitle: String(localized: "Receive exports from your iPhone and write them straight into a folder. Configure everything on iPhone.")
        ) {
            MacGlassStatusPill(title: readinessText, color: readinessPillColor)
                .accessibilityLabel(String(localized: "Mac export readiness"))
                .accessibilityValue(readinessText)
        }
    }

    @ToolbarContentBuilder
    private var destinationToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            pauseReceivingButton
            if !historyManager.history.isEmpty {
                Button(String(localized: "Clear Activity")) {
                    showActivityClearConfirmation = true
                }
                .accessibilityLabel("Clear activity feed")
            }
        }
    }

    private var readinessPillColor: Color {
        switch readinessState {
        case .ready: return Color.glassAdaptive(\.ok)
        case .active: return Color.glassAdaptive(\.accent)
        case .paused, .attention: return Color.glassAdaptive(\.coral)
        }
    }

    private var pauseReceivingButton: some View {
        Button {
            toggleReceivingPaused()
        } label: {
            Label(
                receivingPaused
                    ? String(localized: "Resume Receiving")
                    : String(localized: "Pause Receiving"),
                systemImage: receivingPaused ? "play.fill" : "pause.fill"
            )
        }
        .disabled(displayConnectionState == .connecting)
    }

    // MARK: - Active Export

    private var activeExportProgress: MacExportProgress? {
        guard let progress = syncService.activeMacExportProgress,
              ![MacExportPhase.completed, .failed, .cancelled].contains(progress.phase) else {
            return nil
        }
        return progress
    }

    private func activeExportCard(_ progress: MacExportProgress) -> some View {
        let clampedProgress = min(max(progress.fractionComplete, 0), 0.99)
        let percentage = Int((clampedProgress * 100).rounded())

        return GeistMacCard(padding: Spacing.s6) {
            VStack(alignment: .leading, spacing: Spacing.s6) {
                HStack(alignment: .center, spacing: Spacing.s4) {
                    Image(systemName: exportPhaseIcon(progress.phase))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.glassAdaptive(\.accent))
                        .frame(width: 48, height: 48)
                        .background(
                            Color.accentSubtle,
                            in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                                .strokeBorder(Color.glassAdaptive(\.accent).opacity(0.25), lineWidth: 1)
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Spacing.s1) {
                        HStack(spacing: Spacing.s2) {
                            Text(exportPhaseTitle(progress.phase))
                                .font(Typography.heading20())
                                .foregroundStyle(Color.glassAdaptive(\.text))
                                .accessibilityAddTraits(.isHeader)

                            Text(String(localized: "In Progress"))
                                .font(Typography.label())
                                .foregroundStyle(Color.glassAdaptive(\.accent))
                                .padding(.horizontal, Spacing.s2)
                                .padding(.vertical, 3)
                                .background(Color.accentSubtle, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.glassAdaptive(\.accent).opacity(0.25), lineWidth: 1))
                        }

                        Text(localizedProgressMessage(progress))
                            .font(Typography.body())
                            .foregroundStyle(Color.glassAdaptive(\.sec))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Spacing.s4)

                    if progress.totalDays > 0 {
                        Text(String(localized: "\(percentage) percent complete"))
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.glassAdaptive(\.text))
                            .monospacedDigit()
                    } else {
                        VStack(alignment: .trailing, spacing: Spacing.s1) {
                            ProgressView()
                                .controlSize(.small)
                            Text(String(localized: "In Progress"))
                                .font(Typography.caption())
                                .foregroundStyle(Color.glassAdaptive(\.muted))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(String(localized: "Export in Progress"))
                    }
                }

                exportPhaseRail(progress)

                if progress.totalDays > 0 {
                    ProgressView(value: clampedProgress)
                        .progressViewStyle(.linear)
                        .tint(Color.glassAdaptive(\.accent))
                        .accessibilityLabel(String(localized: "Export progress"))
                        .accessibilityValue(String(localized: "\(percentage) percent complete"))
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Color.glassAdaptive(\.accent))
                        .accessibilityLabel(String(localized: "Export in Progress"))
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.s3)],
                    alignment: .leading,
                    spacing: Spacing.s3
                ) {
                    if progress.totalDays > 0 {
                        GeistInfoChip(
                            icon: "calendar",
                            title: String(localized: "Source days processed"),
                            value: "\(min(max(progress.processedDays, 0), progress.totalDays)) / \(progress.totalDays)",
                            color: Color.glassAdaptive(\.sec)
                        )
                    }

                    GeistInfoChip(
                        icon: "doc.on.doc",
                        title: String(localized: "Files Exported"),
                        value: "\(max(progress.filesWritten, 0))",
                        color: progress.filesWritten > 0 ? Color.success : Color.glassAdaptive(\.sec)
                    )

                    GeistInfoChip(
                        icon: "folder",
                        title: String(localized: "Destination"),
                        value: vaultManager.hasVaultSelection
                            ? vaultManager.vaultName
                            : String(localized: "Mac folder"),
                        color: Color.glassAdaptive(\.sec)
                    )
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.glassAdaptive(\.accent).opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Mac.exportActivity)
    }

    private func exportPhaseRail(_ progress: MacExportProgress) -> some View {
        let currentIndex = exportPhaseIndex(progress.phase)
        let steps: [(title: String, icon: String)] = [
            (String(localized: "Receiving export"), "arrow.down.doc"),
            (String(localized: "Validating export"), "checkmark.shield"),
            (String(localized: "Preparing export"), "gearshape.2"),
            (String(localized: "Writing export files"), "externaldrive")
        ]

        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let isComplete = index < currentIndex
                let isCurrent = index == currentIndex
                let stepColor = isComplete ? Color.success : (isCurrent ? Color.glassAdaptive(\.accent) : Color.glassAdaptive(\.muted))

                VStack(spacing: Spacing.s2) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(index == 0
                                  ? Color.clear
                                  : (index <= currentIndex ? Color.success.opacity(0.65) : Color.glassAdaptive(\.edge)))
                            .frame(height: 2)

                        ZStack {
                            Circle()
                                .fill(isComplete || isCurrent ? stepColor.opacity(0.14) : Color.glassAdaptive(\.surface2))
                            Circle()
                                .strokeBorder(stepColor.opacity(isComplete || isCurrent ? 0.75 : 0.35), lineWidth: 1)
                            Image(systemName: isComplete ? "checkmark" : step.icon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(stepColor)
                        }
                        .frame(width: 28, height: 28)

                        Rectangle()
                            .fill(index == steps.count - 1
                                  ? Color.clear
                                  : (index < currentIndex ? Color.success.opacity(0.65) : Color.glassAdaptive(\.edge)))
                            .frame(height: 2)
                    }

                    Text(step.title)
                        .font(Typography.label())
                        .foregroundStyle(stepColor)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(step.title)
                .accessibilityValue(
                    isComplete
                        ? String(localized: "Done")
                        : (isCurrent ? String(localized: "In Progress") : String(localized: "Pending"))
                )
            }
        }
    }

    private func exportPhaseIndex(_ phase: MacExportPhase) -> Int {
        switch phase {
        case .receiving: return 0
        case .validating: return 1
        case .exporting: return 2
        case .writing: return 3
        case .completed, .failed, .cancelled: return 3
        }
    }

    private func exportPhaseTitle(_ phase: MacExportPhase) -> String {
        switch phase {
        case .receiving: return String(localized: "Receiving export")
        case .validating: return String(localized: "Validating export")
        case .exporting: return String(localized: "Preparing export")
        case .writing: return String(localized: "Writing export files")
        case .completed: return String(localized: "Export complete")
        case .failed: return String(localized: "Export failed")
        case .cancelled: return String(localized: "Export cancelled")
        }
    }

    private func exportPhaseIcon(_ phase: MacExportPhase) -> String {
        switch phase {
        case .receiving: return "arrow.down.doc.fill"
        case .validating: return "checkmark.shield.fill"
        case .exporting: return "gearshape.2.fill"
        case .writing: return "externaldrive.fill.badge.checkmark"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    // MARK: - Cards

    private var nearbyDevicesCard: some View {
        GeistMacCard(padding: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                GeistSectionHeader(
                    title: String(localized: "Nearby iPhones"),
                    subtitle: String(localized: "Select a discovered device to connect over the local network.")
                )

                HStack(spacing: Spacing.s2) {
                    ForEach(syncService.discoveredPeers.prefix(3), id: \.self) { peer in
                        let displayName = syncService.nearbyPeerDisplayName(peer)
                        Button {
                            syncService.connectToPeer(peer)
                        } label: {
                            Label(displayName, systemImage: "iphone")
                        }
                        .buttonStyle(GeistMacButtonStyle(kind: .secondary, size: .small))
                        .accessibilityLabel("Connect to \(displayName)")
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - MacHomeG sections

    private var readinessSection: some View {
        MacGlassSection(title: String(localized: "Readiness")) {
            MacGlassRow(title: String(localized: "Destination folder")) {
                if folderAccessHealthy {
                    // MacHomeG shows only the path; clicking it (or the context menu) changes it.
                    Button {
                        chooseDestinationFolder()
                    } label: {
                        MacGlassValue(destinationFolderText, monospaced: true)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Change destination folder"))
                    .accessibilityLabel(String(localized: "Change destination folder"))
                } else {
                    MacGlassValue(destinationFolderText, tone: .warning)
                    Button(String(localized: "Choose Folder")) {
                        chooseDestinationFolder()
                    }
                    .buttonStyle(MacGlassRowButtonStyle())
                    .accessibilityLabel(String(localized: "Choose destination folder"))
                }
            }
            .contextMenu {
                Button(String(localized: "Change destination folder")) {
                    chooseDestinationFolder()
                }
            }
            .accessibilityLabel("Destination folder")
            .accessibilityValue(folderAccessibilityValue)
            MacGlassDivider()
            MacGlassRow(
                String(localized: "Storage"),
                value: String(localized: "\(storageSummary.free) free of \(storageSummary.total)")
            )
            MacGlassDivider()
            MacGlassRow(String(localized: "Last export"), value: lastExportText)
            if displayConnectionState != .connected {
                MacGlassDivider()
                MacGlassRow(String(localized: "iPhone"), value: statusPrimaryLine, tone: .warning)
            }
        }
        .id("marketing-destination")
    }

    private var destinationFolderText: String {
        guard vaultManager.hasVaultSelection else { return String(localized: "No folder selected") }
        guard folderAccessHealthy else { return vaultManager.vaultAvailabilityText }
        guard let path = vaultManager.pathForDisplay else { return vaultManager.vaultName }
        return MacDisplayPath.abbreviatingHome(path)
    }

    private var lastExportText: String {
        #if DEBUG
        if MacMarketingCapture.isActive { return MacMarketingCapture.lastExport.lastExportHomeLine }
        #endif
        return exportHistoryManager.history.first?.lastExportHomeLine ?? String(localized: "None yet")
    }

    // MARK: Manual IP display state (the capture fixture replaces the live server's values)

    private var displayManualIPEnabled: Bool {
        #if DEBUG
        if MacMarketingCapture.isActive { return true }
        #endif
        return syncService.manualIPServerEnabled
    }

    private var displayManualIPAddresses: [String] {
        #if DEBUG
        // Never the capturing Mac's real LAN or Tailscale addresses.
        if MacMarketingCapture.isActive { return MacMarketingCapture.manualIPAddresses }
        #endif
        return syncService.manualIPAddresses.map(\.address)
    }

    private var displayManualIPPairingCode: String? {
        #if DEBUG
        if MacMarketingCapture.isActive { return MacMarketingCapture.manualIPPairingCode }
        #endif
        return syncService.manualIPPairingCode
    }

    private func isPairingCodeExpired(now: Date) -> Bool {
        #if DEBUG
        // The fixture code stays live whatever time the capture runs.
        if MacMarketingCapture.isActive { return false }
        #endif
        return syncService.manualIPPairingCodeExpiresAt.map { $0 <= now } ?? false
    }

    private var displayManualIPPairingCodeExpiresAt: Date? {
        #if DEBUG
        if MacMarketingCapture.isActive { return MacMarketingCapture.manualIPPairingCodeExpiresAt }
        #endif
        return syncService.manualIPPairingCodeExpiresAt
    }

    /// MacHomeG: an accent On/Off value, then addresses, port and pairing code. Refreshing the
    /// addresses and replacing a live code are in each row's context menu; an empty or expired
    /// value shows its action inline.
    private var manualIPSection: some View {
        MacGlassSection(title: String(localized: "Manual IP & Tailscale")) {
            MacGlassRow(title: String(localized: "Allow manual IP connections")) {
                MacGlassOnOffButton(
                    title: String(localized: "Allow manual IP connections"),
                    isOn: Binding(
                        get: { displayManualIPEnabled },
                        set: { syncService.setManualIPServerEnabled($0) }
                    )
                )
            }

            if displayManualIPEnabled {
                MacGlassDivider()
                MacGlassRow(title: String(localized: "Addresses")) {
                    if displayManualIPAddresses.isEmpty {
                        MacGlassValue(String(localized: "None found"), tone: .warning)
                        Button(String(localized: "Refresh")) {
                            syncService.refreshManualIPAddresses()
                        }
                        .buttonStyle(MacGlassRowButtonStyle())
                    } else {
                        MacGlassValue(
                            displayManualIPAddresses.joined(separator: " · "),
                            monospaced: true
                        )
                    }
                }
                .contextMenu {
                    Button(String(localized: "Refresh")) {
                        syncService.refreshManualIPAddresses()
                    }
                }
                MacGlassDivider()
                MacGlassRow(String(localized: "Port"), value: "\(SyncService.manualIPPort)", monospaced: true)
                MacGlassDivider()
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    pairingCodeRow(now: context.date)
                }
            }
        }
        .id("marketing-system-status")
    }

    @ViewBuilder
    private func pairingCodeRow(now: Date) -> some View {
        let isExpired = isPairingCodeExpired(now: now)
        MacGlassRow(title: String(localized: "Pairing code")) {
            if let code = displayManualIPPairingCode, !isExpired {
                MacGlassValue(pairingCodeText(code), tone: .text, monospaced: true)
            } else {
                Button(
                    syncService.manualIPPairingCode == nil
                        ? String(localized: "Generate Code")
                        : String(localized: "New Code")
                ) {
                    syncService.generateManualIPPairingCode()
                }
                .buttonStyle(MacGlassRowButtonStyle())
            }
        }
        .contextMenu {
            Button(String(localized: "New Code")) {
                syncService.generateManualIPPairingCode()
            }
        }
    }

    /// "4821 · expires 11:40 PM".
    private func pairingCodeText(_ code: String) -> String {
        guard let expiry = displayManualIPPairingCodeExpiresAt else { return code }
        let time = expiry.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(code) · expires \(time)", comment: "Mac pairing code with its expiry time, e.g. 4821 · expires 11:40 PM")
    }

    private var activitySection: some View {
        MacGlassSection(title: String(localized: "Activity")) {
            if let progress = activeExportProgress {
                MacGlassRow(String(localized: "Now"), value: localizedProgressMessage(progress), tone: .accent)
                if !historyManager.history.isEmpty { MacGlassDivider() }
            }
            if historyManager.history.isEmpty && activeExportProgress == nil {
                MacGlassRow(String(localized: "No activity yet"), value: String(localized: "Exports received from iPhone appear here."))
            }
            // MacHomeG lists the three most recent events; History holds the full record.
            ForEach(Array(historyManager.history.prefix(3).enumerated()), id: \.element.id) { index, event in
                if index > 0 { MacGlassDivider() }
                MacGlassRow(
                    ExportHistorySummaryFormat.shortWhen(event.timestamp),
                    value: event.activityLine,
                    tone: event.isSuccess ? .muted : .coral
                )
            }
        }
        .id("marketing-activity")
    }

    private var setupStepsCard: some View {
        GeistMacCard {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                GeistSectionHeader(
                    title: String(localized: "Setup Steps"),
                    subtitle: String(localized: "Use your iPhone to configure and send exports.")
                )

                VStack(alignment: .leading, spacing: Spacing.s3) {
                    setupStep(1, String(localized: "Open Health.md on iPhone"))
                    setupStep(2, String(localized: "Enable Mac Destination"))
                    setupStep(3, String(localized: "Choose a destination folder"))
                    setupStep(4, String(localized: "Select this Mac and export"))
                }

                GeistDivider()

                Button {
                    feedbackReporter.open(.github)
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
                .foregroundStyle(Color.glassAdaptive(\.bg))
                .frame(width: 24, height: 24)
                .background(Color.glassAdaptive(\.accent), in: Circle())

            Text(text)
                .font(Typography.body())
                .foregroundStyle(Color.glassAdaptive(\.sec))
                .lineLimit(2)
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
                        .foregroundStyle(Color.glassAdaptive(\.text))
                    Text(error)
                        .font(Typography.body())
                        .foregroundStyle(Color.glassAdaptive(\.sec))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - State

    private var displayConnectionState: SyncConnectionState {
        #if DEBUG
        if MacMarketingCapture.isActive { return .connected }
        #endif
        return syncService.connectionState
    }

    private var displayConnectedPeerName: String? {
        #if DEBUG
        if MacMarketingCapture.isActive { return String(localized: "iPhone") }
        #endif
        return syncService.connectedPeerName
    }

    private var displayRemoteCapabilities: SyncPeerCapabilities? {
        #if DEBUG
        if MacMarketingCapture.isActive {
            return SyncPeerCapabilities.current(platform: .iOS)
        }
        #endif
        return syncService.remoteCapabilities
    }

    private var displayLastError: String? {
        #if DEBUG
        if MacMarketingCapture.isActive { return nil }
        #endif
        return syncService.lastError
    }

    private var connectionDotColor: Color {
        if receivingPaused { return Color.warning }
        switch displayConnectionState {
        case .connected: return Color.success
        case .connecting: return Color.warning
        case .disconnected: return Color.glassAdaptive(\.muted)
        }
    }

    private var connectionStatusIcon: String {
        if receivingPaused { return "pause.fill" }
        switch displayConnectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "dot.radiowaves.left.and.right"
        }
    }

    private enum ReadinessState: Equatable {
        case paused
        case active
        case ready
        case attention
    }

    private var readinessState: ReadinessState {
        if receivingPaused { return .paused }
        if hasActiveExport { return .active }
        return isReadyForExports ? .ready : .attention
    }

    private var readinessHeroTitle: String {
        if readinessState == .paused { return String(localized: "Receiving Paused") }
        if readinessState == .active { return String(localized: "Receiving Export") }
        if readinessState == .ready { return String(localized: "Ready to Receive") }
        if displayConnectionState == .connected && !folderAccessHealthy {
            return vaultManager.hasVaultSelection
                ? vaultManager.vaultAvailabilityText
                : String(localized: "Choose Destination")
        }
        if displayConnectionState == .connecting {
            return String(localized: "Connecting to iPhone")
        }
        return String(localized: "Listening for iPhone")
    }

    private var readinessText: String {
        if readinessState == .paused { return String(localized: "Paused") }
        if readinessState == .active { return String(localized: "Receiving Export") }
        if displayConnectionState != .connected { return String(localized: "Connect iPhone") }
        if !iPhoneSupportsMacExports { return String(localized: "Update iPhone App") }
        if !vaultManager.hasVaultSelection { return String(localized: "Choose Folder") }
        if !folderAccessHealthy { return vaultManager.vaultAvailabilityText }
        return String(localized: "Ready")
    }

    private var readinessColor: Color {
        switch readinessState {
        case .ready: return Color.success
        case .active: return Color.glassAdaptive(\.accent)
        case .paused, .attention: return Color.warning
        }
    }

    private var readinessIcon: String {
        switch readinessState {
        case .ready: return "checkmark.circle.fill"
        case .active: return "arrow.down.doc.fill"
        case .paused: return "pause.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        }
    }

    private var statusPrimaryLine: String {
        switch displayConnectionState {
        case .connected:
            let peerName = displayConnectedPeerName ?? String(localized: "iPhone")
            return String(localized: "Connected to \(peerName)")
        case .connecting:
            return String(localized: "Establishing local connection")
        case .disconnected:
            return receivingPaused
                ? String(localized: "Discovery paused")
                : String(localized: "Searching nearby devices")
        }
    }

    private var statusSecondaryLine: String {
        #if DEBUG
        if MacMarketingCapture.isActive {
            let device = displayConnectedPeerName ?? String(localized: "iPhone")
            let localizedStatus = String(localized: "\(device) · local network · encrypted handoff")
            let devicePrefix = "\(device) · "
            return localizedStatus.hasPrefix(devicePrefix)
                ? String(localizedStatus.dropFirst(devicePrefix.count))
                : localizedStatus
        }
        #endif
        if let progress = syncService.activeMacExportProgress,
           ![MacExportPhase.completed, .failed, .cancelled].contains(progress.phase) {
            return localizedProgressMessage(progress)
        }
        if let error = displayLastError {
            return localizedStatusSummary(
                String(localized: "Receiver needs attention"),
                technicalDetail: error
            )
        }
        if displayConnectionState == .connected {
            let device = displayConnectedPeerName ?? String(localized: "iPhone")
            return String(localized: "\(device) · local network · encrypted handoff")
        }
        if folderAccessHealthy {
            return String(localized: "Destination validated · waiting on iPhone")
        }
        return vaultManager.hasVaultSelection
            ? "\(vaultManager.vaultName): \(vaultManager.vaultAvailabilityText)"
            : String(localized: "Choose a folder to start receiving")
    }

    private var folderAccessHealthy: Bool {
        vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
    }

    private var folderExists: Bool {
        guard let url = vaultManager.vaultURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private var folderTitle: String {
        guard vaultManager.hasVaultSelection else { return String(localized: "No folder selected") }
        return vaultManager.vaultName
    }

    private var folderSubtitle: String {
        guard let url = vaultManager.vaultURL else {
            return vaultManager.hasVaultSelection
                ? (vaultManager.pathForDisplay ?? vaultManager.vaultAvailabilityText)
                : String(localized: "Choose where this Mac should save exports.")
        }
        if folderAccessHealthy {
            return vaultManager.pathForDisplay ?? url.path(percentEncoded: false)
        }
        return String(localized: "Re-select \(url.lastPathComponent) so Health.md can write exports.")
    }

    private var folderAccessibilityValue: String {
        guard vaultManager.hasVaultSelection else { return String(localized: "No folder selected") }
        return folderAccessHealthy
            ? String(localized: "Selected and accessible: \(vaultManager.vaultName)")
            : "\(vaultManager.vaultName): \(vaultManager.vaultAvailabilityText)"
    }

    private var hasActiveExport: Bool {
        if syncService.isSyncing { return true }
        guard let phase = syncService.activeMacExportProgress?.phase else { return false }
        return ![MacExportPhase.completed, .failed, .cancelled].contains(phase)
    }

    private var isReadyForExports: Bool {
        !receivingPaused
            && !hasActiveExport
            && displayConnectionState == .connected
            && iPhoneSupportsMacExports
            && folderAccessHealthy
    }

    private var iPhoneSupportsMacExports: Bool {
        guard displayConnectionState == .connected else { return false }
        guard let capabilities = displayRemoteCapabilities else { return false }
        return capabilities.platform == .iOS && capabilities.isCompatibleWithMacExportJobs
    }

    private var permissionValue: String {
        folderAccessHealthy
            ? String(localized: "Folder Access")
            : String(localized: "Select Folder")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var lastCheckText: String {
        if hasActiveExport { return String(localized: "In Progress") }
        if displayConnectionState == .connected { return String(localized: "Just Now") }
        return receivingPaused ? String(localized: "Paused") : String(localized: "Scanning")
    }

    private var legacyCacheText: String {
        if healthDataStore.recordCount > 0 {
            return String(localized: "\(healthDataStore.recordCount) cached days from the old sync flow. New exports are received directly.")
        }
        return String(localized: "No legacy records cached from the old sync flow.")
    }

    private var volumeKind: String {
        #if DEBUG
        if MacMarketingCapture.isActive { return "APFS" }
        #endif
        guard let url = vaultManager.vaultURL,
              let values = try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]),
              let description = values.volumeLocalizedFormatDescription,
              !description.isEmpty else {
            return "APFS"
        }
        return description
    }

    private var storageSummary: StorageSummary {
        #if DEBUG
        if MacMarketingCapture.isActive {
            return StorageSummary(
                freeBytes: 750_000_000_000,
                totalBytes: 1_000_000_000_000
            )
        }
        #endif
        let targetURL = vaultManager.vaultURL ?? FileManager.default.homeDirectoryForCurrentUser
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: targetURL.path),
              let total = attributes[.systemSize] as? NSNumber,
              let free = attributes[.systemFreeSize] as? NSNumber else {
            return StorageSummary(freeBytes: 0, totalBytes: 0)
        }
        return StorageSummary(freeBytes: free.int64Value, totalBytes: total.int64Value)
    }

    private func activityItem(for event: SyncEvent) -> ActivityFeedItem {
        let title: String
        let icon: String
        let color: Color

        switch event.kind {
        case .dataReceived:
            title = String(localized: "Export Received")
            icon = "tray.and.arrow.down.fill"
            color = Color.glassAdaptive(\.accent)
        case .progressComplete:
            title = String(localized: "Sync Complete")
            icon = "checkmark.seal.fill"
            color = Color.success
        case .failed:
            title = String(localized: "Sync Failed")
            icon = "xmark.circle.fill"
            color = Color.error
        case .macExportSucceeded:
            title = String(localized: "Export Written")
            icon = "checkmark"
            color = Color.success
        case .macExportPartialSuccess:
            title = String(localized: "Export Partial")
            icon = "exclamationmark"
            color = Color.warning
        case .macExportFailed:
            title = String(localized: "Export Failed")
            icon = "xmark"
            color = Color.error
        case .macExportCancelled:
            title = String(localized: "Export Cancelled")
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

    private func localizedProgressMessage(_ progress: MacExportProgress) -> String {
        let summary: String
        switch progress.phase {
        case .receiving: summary = String(localized: "Receiving export from iPhone")
        case .validating: summary = String(localized: "Validating export")
        case .exporting: summary = String(localized: "Preparing export")
        case .writing: summary = String(localized: "Writing export files")
        case .completed: summary = String(localized: "Export complete")
        case .failed: summary = String(localized: "Export failed")
        case .cancelled: summary = String(localized: "Export cancelled")
        }
        return localizedStatusSummary(summary, technicalDetail: progress.message)
    }

    private func localizedStatusSummary(_ summary: String, technicalDetail: String?) -> String {
        guard let technicalDetail = technicalDetail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !technicalDetail.isEmpty,
              technicalDetail != summary else {
            return summary
        }
        return String(localized: "\(summary). Details: \(technicalDetail)")
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
        Color.glassAdaptive(\.surface2)
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
            .background(Color.glassAdaptive(\.glassStrong), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.glassAdaptive(\.line), lineWidth: 1)
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
                    .foregroundStyle(Color.glassAdaptive(\.text))
                    .tracking(-0.2)
                if let subtitle {
                    Text(subtitle)
                        .font(Typography.caption())
                        .foregroundStyle(Color.glassAdaptive(\.muted))
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
            .fill(Color.glassAdaptive(\.line))
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
        case .primary: return Color.glassAdaptive(\.bg)
        case .secondary, .tertiary: return Color.glassAdaptive(\.text)
        case .danger: return Color.glassAdaptive(\.bg)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return Color.glassAdaptive(\.accent)
        case .secondary: return Color.glassAdaptive(\.line)
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
            return Color.glassAdaptive(\.accent).opacity(configuration.isPressed ? 0.84 : 1)
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
                    .foregroundStyle(Color.glassAdaptive(\.text))
                    .lineLimit(1)
                if let subtitle, !compact {
                    Text(subtitle)
                        .font(Typography.caption())
                        .foregroundStyle(Color.glassAdaptive(\.muted))
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
                    .foregroundStyle(Color.glassAdaptive(\.muted))
                Text(value)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.glassAdaptive(\.text))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Typography.caption())
                    .foregroundStyle(Color.glassAdaptive(\.sec))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.glassAdaptive(\.surface2), in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.glassAdaptive(\.line), lineWidth: 1)
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
                    .foregroundStyle(Color.glassAdaptive(\.sec))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(value)
                    .font(Typography.label())
                    .foregroundStyle(color)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.glassAdaptive(\.surface2), in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.glassAdaptive(\.line), lineWidth: 1)
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
                    .fill(Color.glassAdaptive(\.surface2))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.glassAdaptive(\.sec))
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.caption())
                    .foregroundStyle(Color.glassAdaptive(\.muted))
                Text(value)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.glassAdaptive(\.text))
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
        .background(Color.glassAdaptive(\.surface2), in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.glassAdaptive(\.line), lineWidth: 1)
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
                        .fill(Color.glassAdaptive(\.accent))
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
            .foregroundStyle(Color.glassAdaptive(\.muted))
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
                        .fill(Color.glassAdaptive(\.line))
                        .frame(width: 1, height: 52)
                }
            }

            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    Text(item.title)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.glassAdaptive(\.text))
                        .lineLimit(1)

                    Spacer(minLength: Spacing.s2)

                    Text(item.timestamp, style: .time)
                        .font(Typography.caption())
                        .foregroundStyle(Color.glassAdaptive(\.muted))
                        .accessibilityLabel(dateFormatter.string(from: item.timestamp))
                }

                Text(item.headline)
                    .font(Typography.caption())
                    .foregroundStyle(Color.glassAdaptive(\.sec))
                    .lineLimit(2)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    Text(item.detail)
                        .font(Typography.caption())
                        .foregroundStyle(Color.glassAdaptive(\.muted))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if let trailing = item.trailing {
                        Text(trailing)
                            .font(Typography.monoCaption())
                            .foregroundStyle(Color.glassAdaptive(\.muted))
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
        if freeBytes == 0 { return String(localized: "— free") }
        return String(localized: "\(free) free")
    }
    var volumeLabel: String {
        totalBytes > 0 ? String(localized: "Local SSD") : String(localized: "Unknown")
    }

    private static func format(bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#endif
