#if os(macOS)
import SwiftUI

// MARK: - Settings Window (⌘,) — Branded

struct MacSettingsWindow: View {
    @State private var selection: MacSettingsDestination = .general

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            Rectangle()
                .fill(Color.borderSubtle)
                .frame(height: 1)

            selectedView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MacSettingsBackdrop())
        .frame(
            minWidth: 880,
            idealWidth: 1_100,
            maxWidth: .infinity,
            minHeight: 640,
            idealHeight: 760,
            maxHeight: .infinity
        )
        .foregroundStyle(Color.textPrimary)
        .tint(Color.accent)
    }

    private var settingsHeader: some View {
        HStack(spacing: Spacing.s6) {
            HStack(spacing: Spacing.s3) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(Typography.headline())
                    Text("Configure this Mac and the local CLI")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.s4)

            HStack(spacing: Spacing.s1) {
                ForEach(MacSettingsDestination.allCases) { destination in
                    Button {
                        withAnimation(AnimationTimings.fast) {
                            selection = destination
                        }
                    } label: {
                        Label(destination.title, systemImage: destination.systemImage)
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(MacSettingsTabButtonStyle(isSelected: selection == destination))
                    .accessibilityAddTraits(selection == destination ? .isSelected : [])
                }
            }
            .padding(Spacing.s1)
            .background(Color.bgSecondary, in: RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
        }
        .padding(.horizontal, Spacing.s8)
        .padding(.vertical, Spacing.s4)
        .background(Color.bgPrimary.opacity(0.96))
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selection {
        case .general:
            MacGeneralSettingsView()
        case .cli:
            MacCLIView()
        }
    }
}

private enum MacSettingsDestination: String, CaseIterable, Identifiable {
    case general
    case cli

    var id: Self { self }

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .cli: return String(localized: "CLI")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .cli: return "terminal"
        }
    }
}

private struct MacSettingsTabButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.caption().weight(.semibold))
            .foregroundStyle(isSelected ? Color.textPrimary : Color.textMuted)
            .padding(.horizontal, Spacing.s3)
            .frame(height: 34)
            .background(
                isSelected
                    ? Color.bgPrimary
                    : (configuration.isPressed ? Color.bgTertiary : Color.clear),
                in: RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(isSelected ? Color.borderSubtle : Color.clear, lineWidth: 1)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.08) : .clear, radius: 2, y: 1)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

// MARK: - Sidebar Settings View

struct MacDetailSettingsView: View {
    var body: some View {
        MacSettingsWindow()
            .navigationTitle("Settings")
    }
}

// MARK: - General Settings

struct MacGeneralSettingsView: View {
    @EnvironmentObject var vaultManager: VaultManager
    @EnvironmentObject var syncService: SyncService
    @EnvironmentObject var healthDataStore: HealthDataStore
    @EnvironmentObject var encryptedHealthContextManager: MacEncryptedHealthContextManager
    @State private var showClearConfirmation = false
    @State private var showEncryptedContextDeleteConfirmation = false
    @State private var showRetentionConfirmation = false
    @State private var retentionBoundary = Date()
    private let privacyPolicyURL = URL(string: "https://healthmd.app/privacy-policy.html")!

    var body: some View {
        Form {
            Section {
                Text("Health.md for Mac works as a local export destination. Configure formats, metrics, date ranges, filenames, write modes, and Data Detail on iPhone, then send the export to this Mac.")
                    .font(BrandTypography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Detailed Time-Series keeps selected timestamped samples without the canonical archive. Lossless Health Records adds the complete selected HealthKit source representation and can create much larger files.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                BrandLabel("iPhone-Controlled Exports")
            }

            Section {
                HStack(spacing: 8) {
                    Circle()
                        .fill(syncService.connectionState == .connected ? Color.success : Color.textMuted)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(connectionStatusText)
                        .font(BrandTypography.bodyMedium())
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Connection status")
                .accessibilityValue(connectionStatusText)

                HStack {
                    Text("Readiness")
                    Spacer()
                    Text(readinessText)
                        .font(BrandTypography.value())
                        .foregroundStyle(readinessColor)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Mac export readiness")
                .accessibilityValue(readinessText)
            } header: {
                BrandLabel("Status")
            }

            MacVaultFolderSection(showSubfolder: false, showClearButton: true)

            Section {
                if encryptedHealthContextManager.hasLoadedStatus {
                    HStack {
                        Text("Encrypted context days")
                        Spacer()
                        Text("\(encryptedHealthContextManager.ownerDateCount)")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }

                    if let earliest = encryptedHealthContextManager.earliestOwnerDate,
                       let latest = encryptedHealthContextManager.latestOwnerDate {
                        LabeledContent("Owner-date range") {
                            Text(earliest == latest ? earliest : "\(earliest) – \(latest)")
                                .font(Typography.mono())
                        }
                    }

                    DatePicker(
                        "Delete days before",
                        selection: $retentionBoundary,
                        displayedComponents: .date
                    )
                    Button("Delete Older Context…") {
                        showRetentionConfirmation = true
                    }
                    .disabled(encryptedHealthContextManager.isWorking
                        || encryptedHealthContextManager.ownerDateCount == 0)

                    Button("Delete All Encrypted Context…", role: .destructive) {
                        showEncryptedContextDeleteConfirmation = true
                    }
                    .disabled(encryptedHealthContextManager.isWorking
                        || encryptedHealthContextManager.ownerDateCount == 0)
                } else {
                    Text("Context status is not loaded automatically, so ordinary Mac app use does not access Keychain.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)

                    Button("Load Encrypted Context Status…") {
                        Task { await encryptedHealthContextManager.refresh() }
                    }
                    .disabled(encryptedHealthContextManager.isWorking)
                }

                if let error = encryptedHealthContextManager.lastError {
                    Text(error)
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.error)
                }
            } header: {
                BrandLabel("Local Query Context")
            } footer: {
                Text("This Keychain-encrypted store is independent from exported files. Retention is never automatic; deleting it does not change Apple Health on iPhone.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }

            if healthDataStore.recordCount > 0 {
                Section {
                    HStack {
                        Text("Cached legacy records")
                        Spacer()
                        Text("\(healthDataStore.recordCount)")
                            .font(BrandTypography.value())
                            .foregroundStyle(Color.accent)
                    }

                    Button("Delete Legacy Cache", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .tint(Color.error)
                    .accessibilityHint("Removes cached Health data from the old Mac sync flow")
                } header: {
                    BrandLabel("Legacy Cache")
                } footer: {
                    Text("New Mac-targeted exports are built on iPhone and sent directly to the selected folder. This cache is only for the old manual sync flow.")
                        .font(BrandTypography.caption())
                        .foregroundStyle(Color.textMuted)
                }
            }

            Section {
                Text("Health.md collects limited product events using a random app-install identifier for setup, export-shape, and purchase-flow analytics.")
                    .font(BrandTypography.bodyMedium())
                    .fixedSize(horizontal: false, vertical: true)

                Text("Analytics never includes health values, metric names, health dates, exported files, paths, peer names, or credentials. It is not used for advertising or cross-app tracking.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Link("View Privacy Policy", destination: privacyPolicyURL)
            } header: {
                BrandLabel("Privacy & Analytics")
            } footer: {
                Text("Analytics events are automatically deleted within 13 months.")
                    .font(BrandTypography.caption())
                    .foregroundStyle(Color.textMuted)
            }

            Section {
                Button {
                    FeedbackHelper.openMailClient()
                } label: {
                    Label("Send Feedback", systemImage: "envelope")
                }

                Button {
                    FeedbackHelper.openGitHubIssue()
                } label: {
                    Label("Report a Bug on GitHub", systemImage: "ladybug")
                }
            } header: {
                BrandLabel("Feedback")
            }
        }
        .formStyle(.grouped)
        .geistDialog(
            isPresented: $showClearConfirmation,
            title: Text("Delete Legacy Synced Data?"),
            message: Text("This removes the old iPhone→Mac cache from this Mac. It does not affect Health data on iPhone or exported files."),
            actions: [
                .cancel(),
                .destructive("Delete") {
                    healthDataStore.deleteAll()
                }
            ]
        )
        .geistDialog(
            isPresented: $showEncryptedContextDeleteConfirmation,
            title: Text("Delete All Encrypted Query Context?"),
            message: Text("This removes every compact context day and its dedicated Keychain key. Exported files and Apple Health remain unchanged."),
            actions: [
                .cancel(),
                .destructive("Delete All") {
                    Task { await encryptedHealthContextManager.deleteAll() }
                }
            ]
        )
        .geistDialog(
            isPresented: $showRetentionConfirmation,
            title: Text("Delete Context Before \(retentionOwnerDate)?"),
            message: Text("Every encrypted owner day earlier than this date will be permanently removed. The boundary date and newer days remain."),
            actions: [
                .cancel(),
                .destructive("Delete Older Days") {
                    let boundary = retentionOwnerDate
                    Task { await encryptedHealthContextManager.delete(before: boundary) }
                }
            ]
        )
    }

    private var retentionOwnerDate: String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: retentionBoundary)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private var folderAccessHealthy: Bool {
        vaultManager.vaultURL != nil && vaultManager.canAccessSelectedVaultFolder()
    }

    private var connectionStatusText: String {
        #if DEBUG
        if MacMarketingCapture.isActive {
            let peerName = String(localized: "iPhone")
            return String(localized: "Connected to \(peerName)")
        }
        #endif
        guard syncService.connectionState == .connected else {
            return String(localized: "Not connected")
        }
        let peerName = syncService.connectedPeerName ?? String(localized: "iPhone")
        return String(localized: "Connected to \(peerName)")
    }

    private var readinessText: String {
        #if DEBUG
        if MacMarketingCapture.isActive { return String(localized: "Ready") }
        #endif
        if syncService.isSyncing { return String(localized: "Receiving export") }
        if syncService.connectionState != .connected { return String(localized: "Connect iPhone") }
        if !iPhoneSupportsMacExports { return String(localized: "Update iPhone app") }
        if !vaultManager.hasVaultSelection { return String(localized: "Choose folder") }
        if !folderAccessHealthy { return vaultManager.vaultAvailabilityText }
        return String(localized: "Ready")
    }

    private var readinessColor: Color {
        iPhoneSupportsMacExports && folderAccessHealthy && !syncService.isSyncing
            ? Color.success
            : Color.warning
    }

    private var iPhoneSupportsMacExports: Bool {
        #if DEBUG
        if MacMarketingCapture.isActive { return true }
        #endif
        guard syncService.connectionState == .connected else { return false }
        guard let capabilities = syncService.remoteCapabilities else { return false }
        return capabilities.platform == .iOS && capabilities.isCompatibleWithMacExportJobs
    }
}

// MARK: - Settings Background

struct MacSettingsBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color.bgTertiary.opacity(0.72), Color.bgSecondary],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

#endif
