import SwiftUI
import StoreKit
import WebKit

// MARK: - Onboarding Flow

struct OnboardingView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showFolderPicker: Bool
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    let onComplete: () -> Void
    private let analytics = PricingAnalyticsClient.shared

    @State private var currentStep = 0
    @State private var direction: TransitionDirection = .forward
    @AppStorage("pricing.analytics.onboarding.started.tracked.v1") private var didPersistentlyTrackOnboardingStarted = false
    @AppStorage("pricing.analytics.onboarding.steps.tracked.v1") private var persistedTrackedStepRawValues = ""
    @State private var didTrackOnboardingStarted = false
    @State private var trackedStepViews: Set<PricingAnalyticsOnboardingStep> = []
    @State private var didTrackFolderSelected = false
    @State private var didTrackUnlockStepPaywallShown = false

    private let totalSteps = OnboardingStep.allCases.count
    private let sampleExportStepIndex = OnboardingStep.sampleExport.rawValue
    private let obsidianPluginStepIndex = OnboardingStep.obsidianPlugin.rawValue
    private let folderStepIndex = OnboardingStep.folder.rawValue
    private let unlockStepIndex = OnboardingStep.unlock.rawValue
    private let readyStepIndex = OnboardingStep.ready.rawValue

    private var step: OnboardingStep {
        OnboardingStep(rawValue: currentStep) ?? .welcome
    }

    private var canGoBack: Bool {
        currentStep > 0 && step != .ready
    }

    private var individualUnlockOptions: [HealthMdPurchaseOption] {
        [.monthly, .yearly, .individual]
    }

    private var familyUnlockOptions: [HealthMdPurchaseOption] {
        [.familyMonthly, .familyYearly, .family]
    }

    /// Setup steps are intentionally not gated. Health access and folder choice
    /// can both be completed later from the app, so onboarding never traps users.
    private var canAdvance: Bool { true }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, Spacing.s6)
                    .padding(.top, Spacing.s4)

                OnboardingProgressBar(current: currentStep, total: totalSteps)
                    .padding(.horizontal, Spacing.s6)
                    .padding(.top, Spacing.s4)

                ScrollView {
                    stepContent
                        .id(currentStep)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Spacing.s6)
                        .padding(.top, step == .sampleExport ? Spacing.s4 : Spacing.s6)
                        .padding(.bottom, step == .unlock ? Spacing.s8 : Spacing.s6)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)

                if step != .unlock {
                    footerControls
                        .padding(.horizontal, Spacing.s6)
                        .padding(.bottom, Spacing.s6)
                        .transition(.opacity)
                }
            }
        }
        .onAppear {
            trackInitialOnboardingAnalytics()
        }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked && step == .unlock {
                advance()
            }
        }
        .onChange(of: currentStep) { _, stepIndex in
            trackStepViewed(for: stepIndex)
            if stepIndex == unlockStepIndex {
                trackUnlockStepPaywallShown()
            }
        }
        .onChange(of: vaultManager.vaultURL) { _, folderURL in
            if folderURL != nil {
                trackFolderSelectedIfNeeded()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s3) {
            if canGoBack {
                Button(action: goBack) {
                    HStack(spacing: Spacing.s1) {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                        Text("Back")
                            .font(Typography.label())
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                    .background(Color.bgPrimary, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            } else {
                Color.clear.frame(width: 68, height: 34)
                    .accessibilityHidden(true)
            }

            Spacer()

            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(Typography.label())
                .foregroundStyle(Color.textMuted)
                .monospacedDigit()

            Spacer()

            if step == .welcome {
                Color.clear.frame(width: 68, height: 34)
                    .accessibilityHidden(true)
            } else {
                AppIconMark(icon: "heart.text.square.fill", size: 34, symbolSize: 14, usesAppIcon: true)
                    .frame(width: 68, height: 34, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStep()
                .transition(stepTransition)
        case .healthAccess:
            HealthAccessStep(isAuthorized: healthKitManager.isAuthorized)
                .transition(stepTransition)
        case .sampleExport:
            SampleExportStep()
                .transition(stepTransition)
        case .obsidianPlugin:
            ObsidianPluginStep()
                .transition(stepTransition)
        case .folder:
            FolderSetupStep(
                vaultName: vaultManager.vaultName,
                hasFolder: vaultManager.vaultURL != nil,
                onPickFolder: { showFolderPicker = true }
            )
            .transition(stepTransition)
        case .unlock:
            UnlockStep(
                purchaseManager: purchaseManager,
                individualOptions: individualUnlockOptions,
                familyOptions: familyUnlockOptions,
                priceLabel: displayPrice(for:),
                onPurchase: { option in
                    analytics.trackOnboardingPurchaseTapped(
                        productId: option.analyticsProductID,
                        quotaState: purchaseManager.analyticsQuotaState
                    )
                    Task { await purchaseManager.purchase(option) }
                },
                onContinueFree: continueFreeFromUnlock,
                onRestore: { Task { await purchaseManager.restore() } }
            )
            .transition(stepTransition)
        case .ready:
            ReadyStep(
                healthAuthorized: healthKitManager.isAuthorized,
                folderSelected: vaultManager.vaultURL != nil,
                folderName: vaultManager.vaultName
            )
            .transition(stepTransition)
        }
    }

    @ViewBuilder
    private var footerControls: some View {
        VStack(spacing: Spacing.s3) {
            switch step {
            case .welcome:
                OnboardingPrimaryButton(title: "Start Setup", icon: "arrow.right", action: advance)
            case .healthAccess:
                if !healthKitManager.isAuthorized {
                    OnboardingSecondaryButton(title: "Connect Apple Health", icon: "heart.text.square") {
                        Task {
                            do {
                                try await healthKitManager.requestAuthorization()
                                analytics.trackHealthAuthorizationCompleted(status: healthAuthorizationAnalyticsStatus)
                            } catch {
                                analytics.trackHealthAuthorizationCompleted(status: .unknown)
                            }
                        }
                    }
                }
                OnboardingPrimaryButton(title: healthKitManager.isAuthorized ? "Continue Setup" : "Continue Without Access", icon: "arrow.right", action: advance)
            case .sampleExport, .obsidianPlugin:
                OnboardingPrimaryButton(title: "Continue Setup", icon: "arrow.right", action: advance)
            case .folder:
                OnboardingPrimaryButton(
                    title: vaultManager.vaultURL == nil ? "Choose Later" : "Continue Setup",
                    icon: "arrow.right",
                    accessibilityHint: vaultManager.vaultURL == nil ? "You can select an export folder before your first export" : "Continue to the next setup step",
                    action: advance
                )
            case .ready:
                OnboardingPrimaryButton(title: "Get Started", icon: "checkmark", action: advance)
            case .unlock:
                EmptyView()
            }
        }
        .disabled(!canAdvance)
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        let insertionOffset = direction == .forward ? 20 : -20
        let removalOffset = direction == .forward ? -12 : 12

        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: CGFloat(insertionOffset), y: 0)),
            removal: .opacity.combined(with: .offset(x: CGFloat(removalOffset), y: 0))
        )
    }

    private func advance() {
        if currentStep >= totalSteps - 1 {
            analytics.trackOnboardingCompleted(quotaState: purchaseManager.analyticsQuotaState)
            onComplete()
            return
        }

        var nextStep = currentStep + 1
        if nextStep == unlockStepIndex && purchaseManager.isUnlocked {
            nextStep += 1
        }

        direction = .forward
        move(to: nextStep)
    }

    private func goBack() {
        guard currentStep > 0 else { return }
        direction = .backward
        move(to: currentStep - 1)
    }

    private func move(to stepIndex: Int) {
        let update = { currentStep = max(0, min(stepIndex, totalSteps - 1)) }
        if reduceMotion {
            update()
        } else {
            withAnimation(AnimationTimings.standard, update)
        }
    }

    private var healthAuthorizationAnalyticsStatus: PricingAnalyticsAuthorizationStatus {
        guard healthKitManager.isHealthDataAvailable else { return .unavailable }
        return healthKitManager.isAuthorized ? .authorized : .notAuthorized
    }

    private func continueFreeFromUnlock() {
        analytics.trackOnboardingContinueFreeTapped(quotaState: purchaseManager.analyticsQuotaState)
        advance()
    }

    private func displayPrice(for option: HealthMdPurchaseOption) -> String? {
        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices {
            switch option {
            case .monthly: return "$4.99/mo"
            case .yearly: return "$24.99/yr"
            case .individual: return "$59.99"
            case .familyMonthly: return "$7.99/mo"
            case .familyYearly: return "$39.99/yr"
            case .family: return "$89.99"
            case .familyUpgrade: return nil
            }
        }
        #endif

        return purchaseManager.product(for: option)?.displayPrice
    }

    private func trackInitialOnboardingAnalytics() {
        guard !didTrackOnboardingStarted else { return }
        didTrackOnboardingStarted = true
        if !didPersistentlyTrackOnboardingStarted {
            didPersistentlyTrackOnboardingStarted = true
            analytics.trackOnboardingStarted(quotaState: purchaseManager.analyticsQuotaState)
        }
        trackStepViewed(for: currentStep)
    }

    private func trackStepViewed(for index: Int) {
        guard let step = onboardingStep(for: index),
              !trackedStepViews.contains(step),
              !persistedTrackedSteps.contains(step) else { return }
        trackedStepViews.insert(step)
        persistTrackedStep(step)
        analytics.trackOnboardingStepViewed(step, quotaState: purchaseManager.analyticsQuotaState)
    }

    private var persistedTrackedSteps: Set<PricingAnalyticsOnboardingStep> {
        Set(persistedTrackedStepRawValues
            .split(separator: ",")
            .compactMap { PricingAnalyticsOnboardingStep(rawValue: String($0)) })
    }

    private func persistTrackedStep(_ step: PricingAnalyticsOnboardingStep) {
        var steps = persistedTrackedSteps
        steps.insert(step)
        persistedTrackedStepRawValues = steps
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    private func trackFolderSelectedIfNeeded() {
        guard !didTrackFolderSelected else { return }
        didTrackFolderSelected = true
        analytics.trackOnboardingFolderSelected(quotaState: purchaseManager.analyticsQuotaState)
    }

    private func onboardingStep(for index: Int) -> PricingAnalyticsOnboardingStep? {
        switch index {
        case OnboardingStep.welcome.rawValue: return .welcome
        case OnboardingStep.healthAccess.rawValue: return .healthAccess
        case sampleExportStepIndex: return .sampleExport
        case obsidianPluginStepIndex: return .obsidianPlugin
        case folderStepIndex: return .folderSetup
        case unlockStepIndex: return .unlock
        case readyStepIndex: return .ready
        default: return nil
        }
    }

    private func trackUnlockStepPaywallShown() {
        guard !didTrackUnlockStepPaywallShown else { return }
        didTrackUnlockStepPaywallShown = true
        analytics.trackPaywallShown(context: .onboarding, quotaState: purchaseManager.analyticsQuotaState)
    }
}

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case healthAccess
    case sampleExport
    case obsidianPlugin
    case folder
    case unlock
    case ready
}

private enum TransitionDirection {
    case forward
    case backward
}

// MARK: - Progress

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: Spacing.s2) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.geistGray1000 : Color.borderSubtle)
                    .frame(height: 3)
                    .frame(maxWidth: index == current ? 32 : .infinity)
                    .animation(AnimationTimings.standard, value: current)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue("Step \(current + 1) of \(total)")
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Health.md",
                title: "Own Your Health Data",
                description: "Export Apple Health into readable files you can keep, search, and link from Obsidian.",
                icon: "heart.text.square.fill",
                usesAppIcon: true
            )

            VStack(spacing: Spacing.s3) {
                OnboardingFeatureRow(icon: "doc.badge.arrow.up", title: "Export Files", description: "Create Markdown, CSV, JSON, and Obsidian Bases from your health data.")
                OnboardingFeatureRow(icon: "clock", title: "Schedule Runs", description: "Set a recurring export and keep your notes current.")
                OnboardingFeatureRow(icon: "lock.shield", title: "Stay Local", description: "Health data is read on-device and written to folders you choose.")
            }
        }
    }
}

private struct HealthAccessStep: View {
    let isAuthorized: Bool

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Apple Health",
                title: "Choose What Health.md Can Read",
                description: "Grant read access for the categories you want to export. You can adjust this later in the Health app.",
                icon: "heart.fill",
                showsIcon: false
            )

            VStack(spacing: Spacing.s3) {
                OnboardingStatusCard(
                    icon: isAuthorized ? "checkmark.circle.fill" : "circle.dotted",
                    title: isAuthorized ? "Apple Health Connected" : "Apple Health Not Connected",
                    description: isAuthorized ? "You’re ready to generate real previews and exports." : "You can continue now and connect before your first export.",
                    tint: isAuthorized ? .success : .textMuted
                )

                OnboardingFeatureRow(icon: "slider.horizontal.3", title: "You Stay in Control", description: "iOS lets you approve or deny each health category.")
                OnboardingFeatureRow(icon: "eye.slash", title: "No Account Required", description: "Health.md does not need a server account to export local files.")
            }
        }
    }
}

private struct SampleExportStep: View {
    @State private var selectedFormat: SampleExportPreviewFormat = .markdown

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Example File",
                title: "Preview Your Export",
                description: "This is an example of what exported health data may look like.",
                icon: "doc.text.magnifyingglass",
                showsIcon: false
            )

            SampleExportInlinePreview(selectedFormat: $selectedFormat)
        }
    }
}

private struct ObsidianPluginStep: View {
    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Obsidian Plugin",
                title: "Visualize Your Health Notes",
                description: "Install the Health.md Obsidian plugin to turn exported files into vault-native dashboards.",
                icon: "chart.xyaxis.line",
                showsIcon: false
            )

            ObsidianPluginVisualizationCard()
        }
    }
}

private struct ObsidianPluginVisualizationCard: View {
    private let pluginURL = URL(string: "https://community.obsidian.md/plugins/health-md")!
    private let visualizations = ObsidianPluginPreviewVisualization.allCases

    var body: some View {
        VStack(spacing: Spacing.s4) {
            carousel
            descriptionText
            pluginLink
        }
        .padding(Spacing.s3)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var carousel: some View {
        TabView {
            ForEach(visualizations) { visualization in
                ObsidianPluginPreviewPage(visualization: visualization)
                    .tag(visualization)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 306)
        .accessibilityLabel("Swipe through Health.md Obsidian plugin visualization previews")
        .accessibilityHint("Shows example plugin charts rendered from Health.md exports")
    }

    private var descriptionText: some View {
        Text("Swipe to preview activity, heart, and workout dashboards rendered from local Health.md files.")
            .font(Typography.body())
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var pluginLink: some View {
        Link(destination: pluginURL) {
            HStack(spacing: Spacing.s2) {
                Text("View Obsidian Plugin")
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .font(Typography.label())
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .background(Color.bgSecondary, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
        }
        .accessibilityHint("Opens the Health.md Obsidian plugin page")
    }
}

private struct ObsidianPluginPreviewPage: View {
    let visualization: ObsidianPluginPreviewVisualization

    var body: some View {
        VStack(spacing: Spacing.s2) {
            ObsidianPluginVisualizationWebPreview(visualizationID: visualization.rawValue)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .accessibilityHidden(true)

            Text(visualization.title)
                .font(Typography.label())
                .foregroundStyle(Color.textSecondary)
                .accessibilityHidden(true)
        }
    }
}

private enum ObsidianPluginPreviewVisualization: String, CaseIterable, Identifiable {
    case activityRings = "activity-rings"
    case heartRange = "heart-range"
    case workoutLog = "workout-log"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activityRings: return "Activity Rings"
        case .heartRange: return "Heart Range"
        case .workoutLog: return "Workout Log"
        }
    }
}

private struct ObsidianPluginVisualizationWebPreview: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let visualizationID: String

    func makeCoordinator() -> Coordinator {
        Coordinator(visualizationID: visualizationID)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false

        context.coordinator.webView = webView
        loadPreview(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.theme = themeName
        context.coordinator.visualizationID = visualizationID
        context.coordinator.applyVisualizationIfReady()
    }

    private var themeName: String {
        colorScheme == .dark ? "dark" : "light"
    }

    private func loadPreview(into webView: WKWebView) {
        guard let url = Bundle.main.url(
            forResource: "plugin-activity-rings-preview",
            withExtension: "html"
        ) else {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            return
        }

        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var theme = "light"
        var visualizationID: String
        private var didFinishLoading = false

        init(visualizationID: String) {
            self.visualizationID = visualizationID
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishLoading = true
            self.webView = webView
            applyVisualizationIfReady()
        }

        func applyVisualizationIfReady() {
            guard didFinishLoading else { return }
            let escapedTheme = theme.replacingOccurrences(of: "'", with: "\\'")
            let escapedVisualizationID = visualizationID.replacingOccurrences(of: "'", with: "\\'")
            webView?.evaluateJavaScript("window.renderHealthMdVisualization && window.renderHealthMdVisualization('\(escapedTheme)', '\(escapedVisualizationID)')")
        }
    }
}

private struct FolderSetupStep: View {
    let vaultName: String
    let hasFolder: Bool
    let onPickFolder: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Destination",
                title: "Pick a Folder or Choose Later",
                description: "Exports can go to an iPhone folder now. Connected Mac setup happens after onboarding from the Sync tab.",
                icon: "folder.fill",
                showsIcon: false
            )

            if hasFolder {
                OnboardingStatusCard(
                    icon: "folder.fill.badge.checkmark",
                    title: vaultName,
                    description: "Health.md will write exports into a Health subfolder here.",
                    tint: .success
                )
            } else {
                FolderPickerCard(onPickFolder: onPickFolder)
            }

            VStack(spacing: Spacing.s3) {
                OnboardingFeatureRow(icon: "iphone", title: "Local iPhone Folder", description: "Best when you keep notes in iCloud Drive, On My iPhone, or a synced app folder.")
                OnboardingFeatureRow(icon: "desktopcomputer", title: "Connected Mac Later", description: "Install the Mac app later to send iPhone-configured exports to a Mac folder.")
            }
        }
    }
}

private struct UnlockStep: View {
    @ObservedObject var purchaseManager: PurchaseManager
    let individualOptions: [HealthMdPurchaseOption]
    let familyOptions: [HealthMdPurchaseOption]
    let priceLabel: (HealthMdPurchaseOption) -> String?
    let onPurchase: (HealthMdPurchaseOption) -> Void
    let onContinueFree: () -> Void
    let onRestore: () -> Void

    @State private var selectedAudience: OnboardingPricingAudience = .individual

    private var selectedOptions: [HealthMdPurchaseOption] {
        switch selectedAudience {
        case .individual: return individualOptions
        case .family: return familyOptions
        }
    }

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Full Access",
                title: "Unlock Unlimited Exports",
                description: "Start with 3 free exports, then choose monthly, yearly, or lifetime access.",
                icon: "lock.open.fill",
                showsIcon: false
            )

            OnboardingMiniFeatureList {
                OnboardingMiniFeatureRow(icon: "arrow.up.doc.fill", title: "Unlimited Exports", description: "Remove the free export limit while your plan is active.")
                OnboardingMiniFeatureRow(icon: "calendar.badge.clock", title: "Scheduled Exports", description: "Automations are included with every paid plan.")
            }

            VStack(spacing: Spacing.s3) {
                OnboardingPricingAudiencePicker(selection: $selectedAudience)

                OnboardingPlanSection(title: selectedAudience.sectionTitle) {
                    ForEach(selectedOptions) { option in
                        OnboardingPurchaseButton(
                            title: option.displayTitle,
                            subtitle: option.displaySubtitle,
                            priceLabel: priceLabel(option),
                            icon: option.iconName,
                            badge: option.badge,
                            isPrimary: option == .yearly || option == .familyYearly,
                            isLoading: purchaseManager.purchasingOption == option,
                            isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                            action: { onPurchase(option) }
                        )
                    }
                }

                if let error = purchaseManager.purchaseError {
                    Text(error)
                        .font(Typography.caption())
                        .foregroundStyle(error.contains("cody@isolated.tech") ? Color.textMuted : Color.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.s3)
                        .accessibilityLabel(error)
                }

                Button(action: onContinueFree) {
                    Text("continue as free")
                        .font(Typography.caption())
                        .foregroundStyle(Color.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Continue as free")

                Button(action: onRestore) {
                    HStack(spacing: Spacing.s2) {
                        if purchaseManager.isRestoring {
                            ProgressView()
                                .controlSize(.mini)
                                .accessibilityHidden(true)
                        }
                        Text("Restore Purchase")
                            .font(Typography.bodyEmphasis())
                    }
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                }
                .buttonStyle(.plain)
                .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
                .accessibilityLabel("Restore previous purchase")
            }
        }
    }
}

private struct ReadyStep: View {
    let healthAuthorized: Bool
    let folderSelected: Bool
    let folderName: String

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Ready",
                title: "Health.md Is Set Up",
                description: "Review your setup, then open the Export tab to preview or write your first files.",
                icon: "checkmark.seal.fill",
                showsIcon: false
            )

            VStack(spacing: Spacing.s3) {
                OnboardingChecklistRow(title: "Apple Health", detail: healthAuthorized ? "Connected" : "Connect before your first export", isComplete: healthAuthorized)
                OnboardingChecklistRow(title: "Export Folder", detail: folderSelected ? folderName : "Choose before exporting", isComplete: folderSelected)
                OnboardingChecklistRow(title: "Formats", detail: "Markdown is ready by default", isComplete: true)
            }
        }
    }
}

// MARK: - Shared Onboarding Components

private struct OnboardingHeader: View {
    let eyebrow: String
    let title: String
    let description: String
    let icon: String
    var usesAppIcon = false
    var showsIcon = true

    var body: some View {
        VStack(spacing: showsIcon ? Spacing.s4 : Spacing.s2) {
            if showsIcon {
                AppIconMark(icon: icon, size: 64, symbolSize: 24, usesAppIcon: usesAppIcon)
            }

            VStack(spacing: Spacing.s2) {
                Text(eyebrow)
                    .font(Typography.labelUppercase())
                    .foregroundStyle(Color.textMuted)
                    .tracking(1.4)

                Text(title)
                    .font(Typography.displayMedium())
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .tracking(-0.6)
                    .accessibilityAddTraits(.isHeader)

                Text(description)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AppIconMark: View {
    let icon: String
    var size: CGFloat = 84
    var symbolSize: CGFloat = 30
    var usesAppIcon = false

    var body: some View {
        Group {
            if usesAppIcon {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                            .strokeBorder(Color.borderSubtle, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                        .fill(Color.bgPrimary)
                        .frame(width: size, height: size)
                        .overlay(
                            RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                                .strokeBorder(Color.borderSubtle, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
                        .accessibilityHidden(true)

                    Image(systemName: icon)
                        .font(.system(size: symbolSize, weight: .semibold, design: .default))
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold, design: .default))
                .foregroundStyle(Color.accent)
                .frame(width: 32, height: 32)
                .background(Color.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

private struct OnboardingMiniFeatureList<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: Spacing.s3) {
            content
        }
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s3)
    }
}

private struct OnboardingMiniFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(Color.accent)
                .frame(width: 28, height: 28)
                .background(Color.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

private struct OnboardingInfoChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)

            Text(title)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s3)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

private struct FolderPickerCard: View {
    let onPickFolder: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(Color.accent)
                    .frame(width: 36, height: 36)
                    .background(Color.accentSubtle)
                    .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text("Select Folder Now")
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)
                    Text("Choose an Obsidian vault or any Files folder on this iPhone.")
                        .font(Typography.body())
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            OnboardingSecondaryButton(title: "Select Folder Now", icon: "folder") {
                onPickFolder()
            }
        }
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s3)
    }
}

private struct OnboardingStatusCard: View {
    let icon: String
    let title: String
    let description: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                Text(description)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.s3)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
    }
}

private struct SampleExportInlinePreview: View {
    @Binding var selectedFormat: SampleExportPreviewFormat

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Spacing.s3) {
                fileHeader

                Picker("Export format", selection: $selectedFormat) {
                    ForEach(SampleExportPreviewFormat.allCases) { format in
                        Text(format.pickerTitle).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Export format")
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s2)

            Divider()
                .overlay(Color.borderSubtle)

            GeometryReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    Text(selectedFormat.content)
                        .font(Typography.monoCaption())
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .frame(
                            minWidth: max(0, proxy.size.width - (Spacing.s4 * 2)),
                            alignment: .topLeading
                        )
                        .padding(Spacing.s4)
                }
                .id(selectedFormat)
            }
            .frame(height: 280)
        }
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .contain)
    }

    private var fileHeader: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: selectedFormat.icon)
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(Color.accent)
                .frame(width: 36, height: 36)
                .background(Color.accentSubtle)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedFormat.fileName)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)

                Text(selectedFormat.subtitle)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            Text(selectedFormat.fileExtension)
                .font(Typography.monoCaptionEmphasis())
                .foregroundStyle(Color.textMuted)
                .padding(.horizontal, Spacing.s2)
                .padding(.vertical, Spacing.s1)
                .background(Color.bgSecondary, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example file: \(selectedFormat.fileName). \(selectedFormat.subtitle)")
    }
}

private enum SampleExportPreviewFormat: String, CaseIterable, Identifiable {
    case markdown
    case json
    case csv
    case obsidianBases

    var id: Self { self }

    var pickerTitle: String {
        switch self {
        case .markdown: return "Markdown"
        case .json: return "JSON"
        case .csv: return "CSV"
        case .obsidianBases: return "Bases"
        }
    }

    var fileName: String {
        switch self {
        case .markdown: return "2026-06-19 Health.md"
        case .json: return "2026-06-19 Health.json"
        case .csv: return "2026-06-19 Health.csv"
        case .obsidianBases: return "2026-06-19 Health.md"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown, .obsidianBases: return "md"
        case .json: return "json"
        case .csv: return "csv"
        }
    }

    var subtitle: String {
        switch self {
        case .markdown: return "Readable daily note"
        case .json: return "Structured nested data"
        case .csv: return "Rows for spreadsheets"
        case .obsidianBases: return "Query-ready frontmatter"
        }
    }

    var icon: String {
        switch self {
        case .markdown, .obsidianBases: return "doc.text"
        case .json: return "curlybraces"
        case .csv: return "tablecells"
        }
    }

    var content: String {
        switch self {
        case .markdown: return markdownContent
        case .json: return jsonContent
        case .csv: return csvContent
        case .obsidianBases: return obsidianBasesContent
        }
    }

    private var markdownContent: String {
        """
        ---
        schema: healthmd.health_data
        schema_version: 2
        date: 2026-06-19
        type: health-data
        active_calories: 624
        exercise_minutes: 42
        hrv_ms: 62.0
        resting_heart_rate: 58
        sleep_deep_hours: 1.30
        sleep_rem_hours: 1.87
        sleep_total_hours: 7.70
        sleep_bedtime: 10:44 PM
        sleep_wake: 6:32 AM
        steps: 8432
        walking_running_mi: 4.10
        workout_minutes: 35
        workouts: 1
        units:
          active_calories: kcal
          exercise_minutes: min
          hrv_ms: ms
          resting_heart_rate: bpm
          sleep_total_hours: hr
          steps: count
          walking_running_mi: mi
          workout_minutes: min
        ---

        # Health Data — 2026-06-19

        7h 42m sleep · 8,432 steps · 1 workout

        ## 😴 Sleep

        - **Total:** 7h 42m
        - **Bedtime:** 10:44 PM
        - **Wake:** 6:32 AM
        - **Deep:** 1h 18m
        - **REM:** 1h 52m
        - **Core:** 4h 12m
        - **Awake:** 18m

        <details>
        <summary>Sleep Stages Timeline (4 intervals)</summary>

        | Time | Stage | Duration |
        |------|-------|----------|
        | 10:44 PM | Core | 2h 10m |
        | 12:54 AM | Deep | 1h 18m |
        | 2:12 AM | REM | 1h 52m |
        | 4:04 AM | Core | 2h 02m |

        </details>

        ## 🏃 Activity

        - **Steps:** 8,432
        - **Active Calories:** 624 kcal
        - **Exercise:** 42 min
        - **Stand Hours:** 11
        - **Walking/Running Distance:** 4.10 mi

        ## ❤️ Heart

        - **Resting HR:** 58 bpm
        - **Average HR:** 74 bpm
        - **HRV:** 62.0 ms

        ## 💪 Workouts
        - **Outdoor Run** — 35m 12s, 3.2 mi, 312 kcal
          - Avg HR: 146 bpm
          - Max HR: 174 bpm
          - Pace: 11'00" /mi
        """
    }

    private var jsonContent: String {
        """
        {
          "schema": "healthmd.health_data",
          "schema_version": 2,
          "date": "2026-06-19",
          "type": "health-data",
          "unit_system": "metric",
          "units": {
            "active_calories": "kcal",
            "exercise_minutes": "min",
            "hrv_ms": "ms",
            "resting_heart_rate": "bpm",
            "sleep_total_hours": "hr",
            "steps": "count",
            "walking_running_mi": "mi"
          },
          "sleep": {
            "totalDuration": 27720,
            "totalDurationFormatted": "7h 42m",
            "bedtime": "10:44 PM",
            "wakeTime": "6:32 AM",
            "deepSleep": 4680,
            "deepSleepFormatted": "1h 18m",
            "remSleep": 6720,
            "remSleepFormatted": "1h 52m"
          },
          "activity": {
            "steps": 8432,
            "activeCalories": 624,
            "exerciseMinutes": 42,
            "walkingRunningDistanceKm": 6.60,
            "walkingRunningDistanceMi": 4.10
          },
          "heart": {
            "restingHeartRate": 58,
            "averageHeartRate": 74,
            "hrv": 62.0,
            "heartRateSamples": [
              { "timestamp": "2026-06-19T08:15:00Z", "value": 62 },
              { "timestamp": "2026-06-19T12:30:00Z", "value": 78 },
              { "timestamp": "2026-06-19T18:45:00Z", "value": 91 }
            ]
          },
          "workouts": [
            {
              "type": "Outdoor Run",
              "duration": 2112,
              "durationFormatted": "35m 12s",
              "distanceKm": 5.15,
              "distanceMi": 3.20,
              "activeCalories": 312,
              "avgHeartRate": 146,
              "maxHeartRate": 174,
              "avgPacePerMiFormatted": "11'00\" /mi"
            }
          ]
        }
        """
    }

    private var csvContent: String {
        """
        Date,Category,Metric,Value,Unit,Timestamp
        2026-06-19,Metadata,schema,healthmd.health_data,,
        2026-06-19,Metadata,schema_version,2,,
        2026-06-19,Metadata,unit_system,metric,,
        2026-06-19,Sleep,Total Duration,27720,seconds,
        2026-06-19,Sleep,Bedtime,10:44 PM,time,
        2026-06-19,Sleep,Wake Time,6:32 AM,time,
        2026-06-19,Sleep,Deep Sleep,4680,seconds,
        2026-06-19,Sleep,REM Sleep,6720,seconds,
        2026-06-19,Activity,Steps,8432,count,
        2026-06-19,Activity,Active Calories,624,kcal,
        2026-06-19,Activity,Exercise Minutes,42,minutes,
        2026-06-19,Activity,Walking Running Distance,6600,meters,
        2026-06-19,Heart,Resting Heart Rate,58,bpm,
        2026-06-19,Heart,Average Heart Rate,74,bpm,
        2026-06-19,Heart,HRV,62.0,ms,
        2026-06-19,Heart,Heart Rate Sample,62,bpm,2026-06-19T08:15:00Z
        2026-06-19,Heart,Heart Rate Sample,78,bpm,2026-06-19T12:30:00Z
        2026-06-19,Workouts,Outdoor Run Duration,2112,seconds,
        2026-06-19,Workouts,Outdoor Run Distance,5150,meters,
        2026-06-19,Workouts,Outdoor Run Calories,312,kcal,
        2026-06-19,Workouts,Outdoor Run Avg Heart Rate,146,bpm,
        """
    }

    private var obsidianBasesContent: String {
        """
        ---
        schema: healthmd.health_data
        schema_version: 2
        date: 2026-06-19
        type: health-data
        active_calories: 624
        exercise_minutes: 42
        hrv_ms: 62.0
        resting_heart_rate: 58
        sleep_deep_hours: 1.30
        sleep_rem_hours: 1.87
        sleep_total_hours: 7.70
        sleep_bedtime: 10:44 PM
        sleep_wake: 6:32 AM
        steps: 8432
        walking_running_mi: 4.10
        workout_minutes: 35
        workouts: 1
        workout_details:
          - workout: 1
            type: "Outdoor Run"
            start: 2026-06-19 07:10:00
            end: 2026-06-19 07:45:12
            duration_sec: 2112
            duration: "35:12"
            distance_m: 5150
            distance_km: 5.15
            distance_mi: 3.20
            active_energy_kcal: 312
            avg_heart_rate: 146
            max_heart_rate: 174
            avg_pace_per_mi: "11'00\" /mi"
            sample_counts:
              heart_rate: 840
              speed: 840
        units:
          active_calories: kcal
          exercise_minutes: min
          hrv_ms: ms
          resting_heart_rate: bpm
          sleep_total_hours: hr
          steps: count
          walking_running_mi: mi
          workout_minutes: min
        ---
        """
    }
}

private struct OnboardingChecklistRow: View {
    let title: String
    let detail: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(isComplete ? Color.success : Color.textMuted)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                Text(detail)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue(isComplete ? "Complete" : "Not complete")
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let icon: String
    var accessibilityHint: String = "Double tap to continue"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium, design: .default))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.bgPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(Color.geistGray1000)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}

private struct OnboardingSecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .default))
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 40)
            .background(Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private enum OnboardingPricingAudience: String, CaseIterable, Identifiable {
    case individual
    case family

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individual: return "Individual"
        case .family: return "Family"
        }
    }

    var sectionTitle: String {
        switch self {
        case .individual: return "Individual"
        case .family: return "Family Sharing"
        }
    }
}

private struct OnboardingPricingAudiencePicker: View {
    @Binding var selection: OnboardingPricingAudience

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OnboardingPricingAudience.allCases) { audience in
                Button {
                    withAnimation(AnimationTimings.fast) {
                        selection = audience
                    }
                } label: {
                    Text(audience.title)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(selection == audience ? Color.bgPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selection == audience ? Color.geistGray1000 : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(audience.title)
                .accessibilityAddTraits(selection == audience ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan type")
    }
}

private struct OnboardingPlanSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(title)
                .font(Typography.label())
                .foregroundStyle(Color.textMuted)
                .textCase(.uppercase)
                .tracking(0.4)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: Spacing.s3) {
                content()
            }
        }
    }
}

private struct OnboardingPurchaseButton: View {
    let title: String
    let subtitle: String
    let priceLabel: String?
    let icon: String
    var badge: String? = nil
    let isPrimary: Bool
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundStyle(isPrimary ? Color.bgPrimary : Color.accent)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    HStack(spacing: Spacing.s2) {
                        Text(title)
                            .font(Typography.headline())
                            .foregroundStyle(isPrimary ? Color.bgPrimary : Color.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(Typography.monoCaptionEmphasis())
                                .foregroundStyle(isPrimary ? Color.bgPrimary : Color.accent)
                                .padding(.horizontal, Spacing.s2)
                                .padding(.vertical, 2)
                                .background((isPrimary ? Color.bgPrimary : Color.accent).opacity(0.12), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(Typography.caption())
                        .foregroundStyle(isPrimary ? Color.bgPrimary.opacity(0.78) : Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Spacing.s2)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: isPrimary ? Color.bgPrimary : Color.accent))
                        .accessibilityHidden(true)
                } else {
                    Text(priceLabel ?? "—")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(isPrimary ? Color.bgPrimary : Color.textPrimary)
                        .lineLimit(1)
                }
            }
            .padding(Spacing.s3)
            .background(isPrimary ? Color.geistGray1000 : Color.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                    .strokeBorder(isPrimary ? Color.geistGray1000 : Color.borderSubtle, lineWidth: 1)
            )
            .opacity(isDisabled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isDisabled ? "Purchase is currently unavailable" : "Double tap to purchase")
    }

    private var accessibilityText: String {
        if let priceLabel {
            return "\(title), \(subtitle), \(priceLabel)"
        }
        return "\(title), \(subtitle)"
    }
}
