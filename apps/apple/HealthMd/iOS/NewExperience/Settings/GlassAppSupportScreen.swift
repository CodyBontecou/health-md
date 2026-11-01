#if os(iOS)
import SwiftUI

/// SettingsMoreG. Same actions as `SettingsTabView`, including the lock's navigation
/// request, which must be consumed here or the blocked-change toast keeps redirecting.
struct GlassAppSupportScreen: View {
    private enum Anchor { case protection }

    var onManageProfiles: () -> Void = {}

    @EnvironmentObject private var sharedSetupCoordinator: SharedSetupCoordinator
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.glassPalette) private var palette
    @StateObject private var feedbackReporter = FeedbackReporter()
    @State private var showMailCompose = false
    @State private var showMyselfClaim = false
    @State private var showDiagnostics = false
    @State private var showReview = false
    @State private var debugResult = ""
    @State private var showDebugAlert = false
    @State private var isRunningDebug = false

    private let discordURL = URL(string: "https://discord.gg/RaQYS4t6gn")!
    private let privacyPolicyURL = URL(string: "https://healthmd.app/privacy-policy.html")!

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    GlassSectionLabel(title: String(localized: "Safety"))
                    GlassPanel {
                        GlassToggleRow(
                            title: String(localized: "Lock configuration"),
                            subtitle: String(localized: "Prevents accidental changes. Manual exports and syncs still work."),
                            isOn: protection
                        )
                        .accessibilityIdentifier(AccessibilityID.ConfigurationProtection.toggle)
                    }
                    .id(Anchor.protection)

                    GlassSectionLabel(title: String(localized: "Configuration"))
                    GlassPanel {
                        row(String(localized: "Export Profiles"), action: onManageProfiles)
                            .accessibilityIdentifier("export.profiles.entry")
                    }
                    SharedSetupConfigurationCard(coordinator: sharedSetupCoordinator)
                        .padding(GlassMetrics.panelPadding)
                        .glassSurface()

                    GlassSectionLabel(title: String(localized: "Account"))
                    GlassPanel {
                        row(String(localized: "Privacy Policy"), subtitle: String(localized: "View how purchases, scheduling, and optional services handle data.")) {
                            UIApplication.shared.open(privacyPolicyURL)
                        }
                        if MyselfClaimFeature.isEnabled {
                            row(String(localized: "Claim myself.md access")) { showMyselfClaim = true }
                                .accessibilityIdentifier("settings-myself-claim")
                        }
                    }

                    GlassSectionLabel(title: String(localized: "Help"))
                    GlassPanel {
                        row(String(localized: "Join Our Discord")) { UIApplication.shared.open(discordURL) }
                        row(String(localized: "Send Feedback")) {
                            if FeedbackHelper.canSendMail {
                                showMailCompose = true
                            } else {
                                feedbackReporter.open(.email)
                            }
                        }
                        row(String(localized: "Report a Bug")) { feedbackReporter.open(.github) }
                        row(String(localized: "Help us grow")) { showReview = true }
                        row(String(localized: "Diagnostics")) { showDiagnostics = true }
                    }

                    #if DEBUG
                    GlassSectionLabel(title: String(localized: "Developer Tools"))
                    GlassPanel {
                        row(
                            isRunningDebug ? String(localized: "Running…") : String(localized: "Verify Receipt"),
                            subtitle: String(localized: "Test worker ↔ Apple end-to-end"),
                            action: runReceiptVerification
                        )
                        row(String(localized: "Replay Onboarding")) {
                            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                            debugResult = "Onboarding will replay now."
                            showDebugAlert = true
                        }
                    }
                    #endif
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, GlassMetrics.scrollBottomInset)
            }
            .onAppear { consumeNavigationRequest(configurationProtection.settingsNavigationRequestID, proxy) }
            .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
                consumeNavigationRequest(requestID, proxy)
            }
        }
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "App & support"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.appSupport")
        .sheet(isPresented: $showMailCompose, onDismiss: feedbackReporter.mailSheetDismissed) {
            MailComposeView(onCompletion: feedbackReporter.completeMail)
        }
        .feedbackFailureSheet($feedbackReporter.failure)
        .sheet(isPresented: $showMyselfClaim) { MyselfClaimView(app: "health.md").glassTheme() }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showReview) {
            GlassReviewScreen {
                showReview = false
                if FeedbackHelper.canSendMail {
                    showMailCompose = true
                } else {
                    feedbackReporter.open(.email)
                }
            }
            .glassTheme()
        }
        .geistDialog(
            isPresented: $showDebugAlert,
            title: Text("Receipt Verification"),
            message: Text(debugResult),
            actions: [.action("Done", role: .secondary)]
        )
    }

    private var protection: Binding<Bool> {
        Binding(
            get: { configurationProtection.isEnabled },
            set: { configurationProtection.setEnabled($0) }
        )
    }

    private func consumeNavigationRequest(_ requestID: UUID?, _ proxy: ScrollViewProxy) {
        guard let requestID else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation { proxy.scrollTo(Anchor.protection, anchor: .center) }
            configurationProtection.consumeSettingsNavigationRequest(requestID)
        }
    }

    private func runReceiptVerification() {
        guard !isRunningDebug else { return }
        isRunningDebug = true
        Task {
            let result = await PurchaseManager.shared.debugVerifyReceipt()
            debugResult = result
            isRunningDebug = false
            showDebugAlert = true
        }
    }

    private func row(_ title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            GlassRow(title: title, subtitle: subtitle) {
                Image(systemName: "chevron.right").foregroundStyle(palette.muted)
            }
        }
        .buttonStyle(.plain)
    }
}
#endif
