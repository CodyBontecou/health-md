#if os(iOS)
#if DEBUG
import Notelet
#endif
import SwiftUI

/// SettingsMoreG. Same actions as `SettingsTabView`, including the lock's navigation
/// request, which must be consumed here or the blocked-change toast keeps redirecting.
struct GlassAppSupportScreen: View {
    private enum Anchor { case protection }

    @EnvironmentObject private var sharedSetupCoordinator: SharedSetupCoordinator
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.glassPalette) private var palette
    @StateObject private var feedbackReporter = FeedbackReporter()
    @State private var showMailCompose = false
    @State private var showMyselfClaim = false
    @State private var showDiagnostics = false
    @State private var showReview = false
    /// "Send feedback instead" waits for the review sheet to close before presenting Mail.
    @State private var feedbackAfterReview = false
    @State private var debugResult = ""
    @State private var showDebugAlert = false
    @State private var isRunningDebug = false
    @State private var confirmingReplay = false

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
                    // Automations (export profiles) are managed in the Automations tab (AutomationsGlass).
                    GlassSharedSetupRows(coordinator: sharedSetupCoordinator)
                    GlassPanel {
                        GlassClearExportHistoryRow()
                    }

                    GlassSectionLabel(title: String(localized: "Account"))
                    GlassPanel {
                        GlassSettingsRow(
                            title: String(localized: "Privacy policy"),
                            subtitle: String(localized: "No analytics"),
                            systemImage: "hand.raised.fill",
                            tile: .settingsTileBlue
                        ) {
                            UIApplication.shared.open(privacyPolicyURL)
                        }
                        if MyselfClaimFeature.isEnabled {
                            GlassSettingsRow(
                                title: String(localized: "Claim myself.md access"),
                                systemImage: "person.crop.circle.badge.checkmark",
                                tile: .settingsTileGreen,
                                showsDivider: true
                            ) { showMyselfClaim = true }
                            .accessibilityIdentifier("settings-myself-claim")
                        }
                    }

                    GlassSectionLabel(title: String(localized: "Help"))
                    GlassPanel {
                        GlassSettingsRow(
                            title: String(localized: "Join our Discord"),
                            systemImage: "bubble.left.fill",
                            tile: .settingsTileDiscord
                        ) { UIApplication.shared.open(discordURL) }
                        GlassSettingsRow(
                            title: String(localized: "Send feedback"),
                            systemImage: "envelope.fill",
                            tile: .settingsTileGreen,
                            showsDivider: true
                        ) {
                            openFeedback()
                        }
                        .accessibilityIdentifier("feedback.sendFeedback")
                        GlassSettingsRow(
                            title: String(localized: "Report a bug"),
                            systemImage: "ladybug.fill",
                            tile: .settingsTileRed,
                            value: "GitHub",
                            showsDivider: true
                        ) { feedbackReporter.open(.github) }
                        .accessibilityIdentifier("feedback.reportBug")
                        GlassSettingsRow(
                            title: String(localized: "Help us grow"),
                            systemImage: "star.fill",
                            tile: .settingsTileOrange,
                            showsDivider: true
                        ) { showReview = true }
                        GlassSettingsRow(
                            title: String(localized: "Diagnostics"),
                            systemImage: "stethoscope",
                            tile: .settingsTileGray,
                            showsDivider: true
                        ) { showDiagnostics = true }
                        GlassSettingsRow(
                            title: String(localized: "Replay onboarding"),
                            systemImage: "heart.fill",
                            tile: .settingsTilePurple,
                            showsDivider: true
                        ) { confirmingReplay = true }
                        .accessibilityIdentifier("settings.replayOnboarding")
                    }

                    #if DEBUG
                    GlassSectionLabel(title: String(localized: "Developer · debug builds only"))
                    GlassPanel {
                        GlassSettingsRow(
                            title: isRunningDebug ? String(localized: "Running…") : String(localized: "Test worker ↔ Apple end-to-end"),
                            action: runReceiptVerification
                        )
                        GlassSettingsRow(title: String(localized: "Reset onboarding state"), showsDivider: true) {
                            // Fresh-install state: onboarding and the release note it marks as seen.
                            UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
                            NoteletStorage.resetSeenVersion()
                            debugResult = "Onboarding state reset. Onboarding will show now."
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
            #if DEBUG
            if TestMode.simulatesFailedMailSheet {
                // Exercise the real deferred fallback/onDismiss path without opening Mail.
                Button {
                    feedbackReporter.completeMail(result: .failed, error: nil)
                    showMailCompose = false
                } label: {
                    Text(verbatim: "Simulate Mail failure")
                }
                .accessibilityIdentifier("feedback.simulateMailFailure")
            } else {
                MailComposeView(onCompletion: feedbackReporter.completeMail)
            }
            #else
            MailComposeView(onCompletion: feedbackReporter.completeMail)
            #endif
        }
        .feedbackFailureSheet($feedbackReporter.failure)
        // MyselfClaimG and DiagnosticsG are pushed pages with Back (no Done).
        .navigationDestination(isPresented: $showMyselfClaim) {
            MyselfClaimView(app: "health.md", presentedModally: false).glassTheme()
        }
        .navigationDestination(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showReview, onDismiss: openFeedbackAfterReview) {
            GlassReviewScreen {
                feedbackAfterReview = true
                showReview = false
            }
            .glassTheme()
        }
        .confirmationDialog(
            String(localized: "Replay onboarding?"),
            isPresented: $confirmingReplay,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Replay onboarding")) {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            }
        } message: {
            Text("Your automations, destinations and exported files stay as they are.")
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

    /// One sheet at a time: Mail (or the mail fallback) opens once the review sheet is gone.
    private func openFeedbackAfterReview() {
        guard feedbackAfterReview else { return }
        feedbackAfterReview = false
        openFeedback()
    }

    private func openFeedback() {
        if TestMode.rejectsFeedbackHandoffs {
            feedbackReporter.open(.email)
        } else if TestMode.simulatesFailedMailSheet || FeedbackHelper.canSendMail {
            showMailCompose = true
        } else {
            feedbackReporter.open(.email)
        }
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

}
#endif
