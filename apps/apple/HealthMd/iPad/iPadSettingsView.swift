import SwiftUI
import StoreKit
import UIKit

// MARK: - iPad Settings View (matching macOS MacDetailSettingsView Form layout)

struct iPadSettingsView: View {
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject var advancedSettings: AdvancedExportSettings
    @ObservedObject var healthKitManager: HealthKitManager
    @EnvironmentObject var sharedSetupCoordinator: SharedSetupCoordinator
    @Binding var showFolderPicker: Bool
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var metricProgressWidth: CGFloat = 100
    @State private var showMailCompose = false
    @State private var showPaywall = false
    @State private var debugResult = ""
    @State private var showDebugAlert = false
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    private let discordURL = URL(string: "https://discord.gg/RaQYS4t6gn")!
    private let privacyPolicyURL = URL(string: "https://healthmd.app/privacy-policy.html")!
    private var usesVerticalControlRows: Bool { dynamicTypeSize.isAccessibilitySize }

    private var showDebugTools: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var purchaseStatusTitle: String {
        if purchaseManager.isFamilyUnlocked {
            return "Family Lifetime active"
        }
        if purchaseManager.isUnlocked {
            return "Full access active"
        }
        return "Unlock Full Access"
    }

    private var purchaseStatusDetail: String {
        if purchaseManager.isFamilyUnlocked {
            return "Family Sharing enabled"
        }
        if purchaseManager.canBuyFamilyUpgrade {
            return "Family upgrade available"
        }
        if purchaseManager.isUnlocked {
            return "Full access active"
        }
        if let individualPrice = purchaseManager.product(for: .individual)?.displayPrice,
           let familyPrice = purchaseManager.product(for: .family)?.displayPrice {
            return "Lifetime: Individual \(individualPrice) or Family \(familyPrice)"
        }
        return "Individual and Family lifetime options"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    HealthMdPageHeader(
                        title: "Settings",
                        subtitle: "Configure formats, naming, metrics, and support"
                    )

                    configurationProtectionSection

                    // MARK: Export Folder
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Export Folder")

                    if usesVerticalControlRows {
                        VStack(alignment: .leading, spacing: 12) {
                            folderStatus
                            folderPickerButton
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                folderStatus
                                Spacer()
                                folderPickerButton
                            }

                            VStack(alignment: .leading, spacing: 12) {
                                folderStatus
                                folderPickerButton
                            }
                        }
                    }

                    if vaultManager.vaultURL != nil {
                        Divider().background(Color.borderSubtle)

                        LabeledContent("Subfolder") {
                            TextField("Optional", text: $vaultManager.healthSubfolder)
                                .font(Typography.body())
                                .frame(minWidth: 160, maxWidth: 280, alignment: .trailing)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: vaultManager.healthSubfolder) {
                                    vaultManager.saveSubfolderSetting()
                                }
                        }
                    }

                    if vaultManager.hasVaultSelection {
                        Button("Clear Folder Selection", role: .destructive) {
                            vaultManager.clearVaultFolder()
                        }
                        .tint(Color.error)
                    }
                }
                .padding(Spacing.s4)
                .iPadLiquidGlass()
                .configurationChangesProtected()

                // MARK: Configuration
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Configuration")
                    SharedSetupConfigurationCard(coordinator: sharedSetupCoordinator)
                }
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: Purchases
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Purchases")

                    Button {
                        showPaywall = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: purchaseManager.isFamilyUnlocked ? "person.3.fill" : (purchaseManager.isUnlocked ? "checkmark.seal.fill" : "lock.fill"))
                                .foregroundStyle(purchaseManager.isUnlocked ? Color.accent : Color.textMuted)
                                .frame(width: 20)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(purchaseStatusTitle)
                                    .font(Typography.bodyEmphasis())
                                    .foregroundStyle(Color.textPrimary)
                                Text(purchaseStatusDetail)
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textMuted)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                                .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Purchases and Family Sharing")
                    .accessibilityValue("\(purchaseStatusTitle), \(purchaseStatusDetail)")
                }
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // Configuration now lives on the Export page so iPad matches the iOS workflow.

                // MARK: Privacy & Analytics
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Privacy & Analytics")

                    Text("Health.md collects limited product events using a random app-install identifier for setup, export-shape, and purchase-flow analytics.")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Analytics never includes health values, metric names, health dates, exported files, paths, peer names, or credentials. It is not used for advertising or cross-app tracking.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().background(Color.borderSubtle)

                    Link(destination: privacyPolicyURL) {
                        Label("View Privacy Policy", systemImage: "hand.raised.fill")
                    }
                }
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: Community
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Community")

                    Button {
                        UIApplication.shared.open(discordURL)
                    } label: {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(Color.accent)
                                .frame(width: 20)
                            Text("Join our Discord")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Join our Discord")

                    Text("Chat with other Health.md users, share feedback, and get help.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                }
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                // MARK: Feedback
                VStack(alignment: .leading, spacing: Spacing.s3) {
                    iPadBrandLabel("Feedback")

                    Button {
                        if FeedbackHelper.canSendMail {
                            showMailCompose = true
                        } else if let url = FeedbackHelper.mailtoURL() {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundStyle(Color.accent)
                                .frame(width: 20)
                            Text("Send Feedback")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Send feedback")

                    Divider().background(Color.borderSubtle)

                    Button {
                        FeedbackHelper.openGitHubIssue()
                    } label: {
                        HStack {
                            Image(systemName: "ladybug")
                                .foregroundStyle(Color.accent)
                                .frame(width: 20)
                            Text("Report a Bug on GitHub")
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Report a bug on GitHub")
                }
                .padding(Spacing.s4)
                .iPadLiquidGlass()

                debugToolsSection
            }
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s8)
                .iPadContentColumn()
            }
            .scrollIndicators(.hidden)
            .iPadPageBackground()
            .onAppear {
                guard let requestID = configurationProtection.settingsNavigationRequestID else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(AnimationTimings.smooth) {
                        proxy.scrollTo(AccessibilityID.ConfigurationProtection.section, anchor: .center)
                    }
                    configurationProtection.consumeSettingsNavigationRequest(requestID)
                }
            }
            .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
                guard let requestID else { return }
                Task { @MainActor in
                    await Task.yield()
                    withAnimation(AnimationTimings.smooth) {
                        proxy.scrollTo(AccessibilityID.ConfigurationProtection.section, anchor: .center)
                    }
                    configurationProtection.consumeSettingsNavigationRequest(requestID)
                }
            }
        }
        .navigationTitle("Settings")
        .iPadHiddenSystemNavigationTitle()
        .sheet(isPresented: $showMailCompose) {
            MailComposeView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(context: .settings)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .geistDialog(
            isPresented: $showDebugAlert,
            title: Text("Developer Tools"),
            message: Text(debugResult),
            actions: [.action("OK", role: .secondary)]
        )
    }

    private var configurationProtectionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            iPadBrandLabel("Prevent Accidental Changes")

            Toggle(isOn: Binding(
                get: { configurationProtection.isEnabled },
                set: { configurationProtection.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Lock Configuration Changes")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                    Text("Keeps export, sync, schedule, folder, and connection settings from being changed by mistake. Manual exports and syncs remain available.")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Color.accent)
            .accessibilityLabel("Prevent Accidental Changes")
            .accessibilityValue(configurationProtection.isEnabled ? "On" : "Off")
            .accessibilityIdentifier(AccessibilityID.ConfigurationProtection.toggle)
        }
        .padding(Spacing.s4)
        .iPadLiquidGlass()
        .id(AccessibilityID.ConfigurationProtection.section)
    }

    @ViewBuilder
    private var debugToolsSection: some View {
        if showDebugTools {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                iPadBrandLabel("Developer Tools")

                Button(action: replayOnboarding) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(Color.accent)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Replay Onboarding")
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)
                            Text("Show the onboarding flow again")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textMuted)
                        }
                        Spacer()
                        Text("Replay")
                            .font(Typography.caption())
                            .foregroundStyle(Color.textMuted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Replay onboarding")
            }
            .padding(Spacing.s4)
            .iPadLiquidGlass()
        }
    }

    private func replayOnboarding() {
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        debugResult = "Onboarding will replay now."
        showDebugAlert = true
    }

    private var folderStatus: some View {
        HStack(spacing: 8) {
            if vaultManager.hasVaultSelection {
                Image(systemName: vaultManager.vaultURL == nil ? "folder.badge.exclamationmark" : "folder.fill")
                    .foregroundStyle(vaultManager.vaultURL == nil ? Color.warning : Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vaultManager.vaultName)
                        .font(Typography.bodyEmphasis())
                    Text(vaultManager.pathForDisplay ?? vaultManager.vaultAvailabilityText)
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(Color.textMuted)
                Text("No folder selected")
                    .font(Typography.body())
                    .foregroundStyle(Color.textMuted)
            }
        }
    }

    private var folderPickerButton: some View {
        Button(vaultManager.hasVaultSelection ? "Change…" : "Choose…") {
            showFolderPicker = true
        }
        .tint(Color.accent)
    }
}

// MARK: - Placeholder Fields View for iPad

struct iPadPlaceholderFieldsView: View {
    @ObservedObject var config: FrontmatterConfiguration
    @State private var newPlaceholderKey = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // List existing placeholder fields
            ForEach(config.placeholderFields.sorted(), id: \.self) { key in
                HStack {
                    Text(key)
                        .font(Typography.body())
                    Spacer()
                    Text("(empty)")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                    Button {
                        config.placeholderFields.removeAll { $0 == key }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove placeholder field \(key)")
                }
            }
            
            // Add new placeholder field
            HStack {
                TextField("Field name (e.g., omron_systolic)", text: $newPlaceholderKey)
                    .font(Typography.body())
                    .textFieldStyle(.roundedBorder)
                
                Button("Add") {
                    if !newPlaceholderKey.isEmpty && !config.placeholderFields.contains(newPlaceholderKey) {
                        config.placeholderFields.append(newPlaceholderKey)
                        newPlaceholderKey = ""
                    }
                }
                .disabled(newPlaceholderKey.isEmpty)
                .tint(Color.accent)
            }
        }
    }
}
