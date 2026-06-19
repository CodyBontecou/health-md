import SwiftUI

// MARK: - Sync Settings View (iOS)

struct SyncSettingsView: View {
    @EnvironmentObject var syncService: SyncService
    @AppStorage("syncEnabled") private var syncEnabled = false

    private let macAppURL = URL(string: "https://apps.apple.com/us/app/health-md/id6757763969")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                syncHeader
                syncToggleSection
                downloadMacSection
                connectionSection
                macExportFlowSection
                errorSection
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, 120)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .navigationTitle("Mac Destination")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if syncEnabled && !TestMode.isUITesting {
                syncService.startAdvertising()
            }
        }
        .onChange(of: syncService.connectionState) { oldValue, newValue in
            guard oldValue != newValue else { return }
            let announcement: String
            switch newValue {
            case .connected: announcement = "Connected to Mac"
            case .connecting: announcement = "Connecting to Mac"
            case .disconnected: announcement = "Disconnected from Mac"
            }
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    // MARK: - Header

    private var syncHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: "desktopcomputer")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentSubtle)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.accent.opacity(0.22), lineWidth: 1)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Mac Destination")
                        .font(Typography.displayMedium())
                        .foregroundStyle(Color.textPrimary)

                    Text("Let Health.md on Mac receive iPhone-configured exports over your local network.")
                        .font(Typography.body())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: Spacing.sm) {
                SyncStatusPill(text: syncEnabled ? "Enabled" : "Disabled", tone: syncEnabled ? .success : .muted)
                if syncEnabled {
                    SyncStatusPill(text: connectionStatusLabel, tone: connectionTone)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(headerAccessibilityLabel)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.bgTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Sections

    private var syncToggleSection: some View {
        SyncCard(
            title: "Connection",
            subtitle: "Turn this on to make the Mac app available as an export target."
        ) {
            Toggle(isOn: $syncEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable Mac Destination")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text("Advertise this iPhone on your local network so Health.md on Mac can connect.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.accent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .onChange(of: syncEnabled) { _, newValue in
                if newValue {
                    if !TestMode.isUITesting {
                        syncService.startAdvertising()
                    }
                    UIAccessibility.post(notification: .announcement, argument: "Mac destination enabled")
                } else {
                    if !TestMode.isUITesting {
                        syncService.stopAdvertising()
                        syncService.disconnect()
                    }
                    UIAccessibility.post(notification: .announcement, argument: "Mac destination disabled")
                }
            }
            .accessibilityIdentifier(AccessibilityID.Sync.syncToggle)
            .accessibilityLabel("Mac export destination")
            .accessibilityValue(syncEnabled ? "Enabled" : "Disabled")
            .accessibilityHint("Double tap to \(syncEnabled ? "disable" : "enable") this Mac as an export destination")
        }
    }

    @ViewBuilder
    private var downloadMacSection: some View {
        if !syncEnabled {
            SyncCard(
                title: "Get the Mac App",
                subtitle: "Install the companion app before using Mac destinations."
            ) {
                Link(destination: macAppURL) {
                    downloadMacLinkContent
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Download Health.md for macOS")
                .accessibilityHint("Double tap to open download page in browser")
                .accessibilityAddTraits(.isLink)
            }
        }
    }

    private var downloadMacLinkContent: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "arrow.down.app.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.18), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Health.md for macOS")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Download from the App Store")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var connectionSection: some View {
        if syncEnabled {
            SyncCard(
                title: "Connection Status",
                subtitle: "Keep both devices nearby on the same network."
            ) {
                connectionStatusRow

                if syncService.connectionState == .connected {
                    SyncRowDivider()
                    destinationStatusRow
                }
            }
        }
    }

    private var connectionStatusRow: some View {
        SyncInfoRow(
            icon: connectionStatusIconName,
            title: connectionTitle,
            subtitle: connectionSubtitle,
            tone: connectionTone,
            isLoading: syncService.connectionState == .connecting
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.Sync.connectionStatus)
        .accessibilityLabel("Connection status")
        .accessibilityValue("\(connectionTitle). \(connectionSubtitle)")
    }

    private var destinationStatusRow: some View {
        SyncInfoRow(
            icon: destinationStatusIcon,
            title: destinationStatusTitle,
            subtitle: destinationStatusSubtitle,
            tone: syncService.canExportToConnectedMac ? .success : .warning,
            isLoading: false
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mac destination readiness")
        .accessibilityValue("\(destinationStatusTitle). \(destinationStatusSubtitle)")
    }

    @ViewBuilder
    private var macExportFlowSection: some View {
        if syncEnabled {
            SyncCard(
                title: "Export to Mac",
                subtitle: "The Mac writes files using the setup you choose on iPhone."
            ) {
                SyncStepRow(number: 1, text: "Open Health.md on Mac and choose a destination folder")
                SyncRowDivider()
                SyncStepRow(number: 2, text: "Return to the iPhone Export tab")
                SyncRowDivider()
                SyncStepRow(number: 3, text: "Choose Connected Mac and tap Export")
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = syncService.lastError {
            SyncCard(title: "Needs Attention") {
                SyncInfoRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "Connection Error",
                    subtitle: error,
                    tone: .warning,
                    isLoading: false
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Error")
                .accessibilityValue(error)
            }
        }
    }

    // MARK: - Helpers

    private var headerAccessibilityLabel: String {
        if syncEnabled {
            return "Mac destination enabled. Connection status: \(connectionStatusLabel)."
        }
        return "Mac destination disabled."
    }

    private var connectionStatusLabel: String {
        switch syncService.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Waiting"
        }
    }

    private var connectionTone: SyncStatusTone {
        switch syncService.connectionState {
        case .connected: return .success
        case .connecting: return .accent
        case .disconnected: return .muted
        }
    }

    private var connectionStatusIconName: String {
        switch syncService.connectionState {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "circle.dotted"
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
        case .connected: return "Connected locally; check destination readiness below"
        case .connecting: return "Establishing connection…"
        case .disconnected: return "Open Health.md on your Mac to connect"
        }
    }

    private var destinationStatusIcon: String {
        syncService.canExportToConnectedMac ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var destinationStatusTitle: String {
        syncService.canExportToConnectedMac ? "Ready for Mac Exports" : "Mac Needs Attention"
    }

    private var destinationStatusSubtitle: String {
        if syncService.canExportToConnectedMac {
            if let path = syncService.macDestinationStatus?.destinationPathForDisplay {
                return "Exports will be written to \(path)"
            }
            return "Select Connected Mac in the Export tab."
        }

        guard let capabilities = syncService.remoteCapabilities else {
            return "Waiting for destination status from Mac."
        }
        guard capabilities.platform == .macOS,
              capabilities.isCompatibleWithMacExportJobs else {
            return "Update Health.md on Mac to receive iPhone-configured export jobs."
        }
        guard let status = syncService.macDestinationStatus else {
            return "Waiting for destination status from Mac."
        }
        if status.activeJobID != nil { return "Mac is currently writing another export." }
        if !status.destinationFolderSelected { return "Choose a destination folder in Health.md on Mac." }
        if !status.folderAccessHealthy { return "Re-select the Mac destination folder to restore write access." }
        return status.lastError ?? syncService.macExportReadinessMessage
    }
}

// MARK: - Sync Components

private struct SyncCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.bgTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
        }
    }
}

private struct SyncRowDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.borderSubtle)
            .padding(.leading, 64)
    }
}

private enum SyncStatusTone {
    case accent
    case success
    case warning
    case muted

    var foreground: Color {
        switch self {
        case .accent: return Color.accent
        case .success: return Color.success
        case .warning: return Color.warning
        case .muted: return Color.textMuted
        }
    }

    var background: Color {
        switch self {
        case .accent: return Color.accent.opacity(0.12)
        case .success: return Color.success.opacity(0.12)
        case .warning: return Color.warning.opacity(0.14)
        case .muted: return Color.bgSecondary
        }
    }

    var border: Color {
        switch self {
        case .accent: return Color.accent.opacity(0.24)
        case .success: return Color.success.opacity(0.22)
        case .warning: return Color.warning.opacity(0.25)
        case .muted: return Color.borderSubtle
        }
    }
}

private struct SyncStatusPill: View {
    let text: String
    let tone: SyncStatusTone

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.foreground)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(tone.background))
            .overlay(Capsule().strokeBorder(tone.border, lineWidth: 1))
    }
}

private struct SyncInfoRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tone: SyncStatusTone
    let isLoading: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tone.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(tone.border, lineWidth: 1)
                    )

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tone.foreground)
                }
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SyncStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accent)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.accent.opacity(0.18), lineWidth: 1)
                )
                .accessibilityHidden(true)

            Text(text)
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Spacing.sm)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
    }
}
