import SwiftUI
import StoreKit

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
    @State private var animateIn = false
    @State private var direction: TransitionDirection = .forward
    @State private var didTrackOnboardingStarted = false
    @State private var trackedStepViews: Set<PricingAnalyticsOnboardingStep> = []
    @State private var didTrackFolderSelected = false
    @State private var didTrackUnlockStepPaywallShown = false

    private let totalSteps = OnboardingStep.allCases.count
    private let sampleExportStepIndex = OnboardingStep.sampleExport.rawValue
    private let folderStepIndex = OnboardingStep.folder.rawValue
    private let unlockStepIndex = OnboardingStep.unlock.rawValue
    private let readyStepIndex = OnboardingStep.ready.rawValue

    private var step: OnboardingStep {
        OnboardingStep(rawValue: currentStep) ?? .welcome
    }

    private var canGoBack: Bool {
        currentStep > 0 && step != .ready
    }

    private var individualUnlockPriceLabel: String? {
        displayPrice(for: .individual)
    }

    private var familyUnlockPriceLabel: String? {
        displayPrice(for: .family)
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
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, Spacing.s6)
                        .padding(.top, Spacing.s8)
                        .padding(.bottom, step == .unlock ? Spacing.s8 : Spacing.s6)
                        .opacity(animateIn ? 1 : 0)
                        .offset(x: reduceMotion ? 0 : (animateIn ? 0 : direction.offset), y: reduceMotion ? 0 : (animateIn ? 0 : 8))
                }
                .scrollIndicators(.hidden)

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
            showStep()
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
            showStep()
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

            Color.clear.frame(width: 68, height: 34)
                .accessibilityHidden(true)
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
                individualPriceLabel: individualUnlockPriceLabel,
                familyPriceLabel: familyUnlockPriceLabel,
                onPurchaseIndividual: {
                    analytics.trackOnboardingPurchaseTapped(
                        productId: .lifetimeUnlock,
                        quotaState: purchaseManager.analyticsQuotaState
                    )
                    Task { await purchaseManager.purchase(.individual) }
                },
                onPurchaseFamily: {
                    analytics.trackOnboardingPurchaseTapped(
                        productId: .familyLifetimeUnlock,
                        quotaState: purchaseManager.analyticsQuotaState
                    )
                    Task { await purchaseManager.purchase(.family) }
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
            case .sampleExport:
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
        return .asymmetric(
            insertion: .move(edge: direction == .forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: direction == .forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func showStep() {
        animateIn = false
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.06)) {
            if reduceMotion {
                animateIn = true
            } else {
                withAnimation(AnimationTimings.standard) {
                    animateIn = true
                }
            }
        }
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
        animateIn = false
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
        if let displayPrice = purchaseManager.product(for: option)?.displayPrice {
            return displayPrice
        }

        #if DEBUG
        if MarketingCapture.usesStaticPurchasePrices {
            switch option {
            case .individual: return "$14.99"
            case .family: return "$24.99"
            case .familyUpgrade: return nil
            }
        }
        #endif

        return nil
    }

    private func trackInitialOnboardingAnalytics() {
        guard !didTrackOnboardingStarted else { return }
        didTrackOnboardingStarted = true
        analytics.trackOnboardingStarted(quotaState: purchaseManager.analyticsQuotaState)
        trackStepViewed(for: currentStep)
    }

    private func trackStepViewed(for index: Int) {
        guard let step = onboardingStep(for: index), !trackedStepViews.contains(step) else { return }
        trackedStepViews.insert(step)
        analytics.trackOnboardingStepViewed(step, quotaState: purchaseManager.analyticsQuotaState)
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
    case folder
    case unlock
    case ready
}

private enum TransitionDirection {
    case forward
    case backward

    var offset: CGFloat {
        switch self {
        case .forward: return 18
        case .backward: return -18
        }
    }
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
        VStack(spacing: Spacing.s8) {
            OnboardingHeader(
                eyebrow: "Health.md",
                title: "Own Your Health Data",
                description: "Export Apple Health into readable files you can keep, search, and link from Obsidian.",
                icon: "heart.text.square.fill"
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
        VStack(spacing: Spacing.s8) {
            OnboardingHeader(
                eyebrow: "Apple Health",
                title: "Choose What Health.md Can Read",
                description: "Grant read access for the categories you want to export. You can adjust this later in the Health app.",
                icon: "heart.fill"
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
    var body: some View {
        VStack(spacing: Spacing.s8) {
            OnboardingHeader(
                eyebrow: "Preview",
                title: "See the Note Before You Export",
                description: "Daily notes are plain text, so your health history remains portable and easy to review.",
                icon: "doc.text.magnifyingglass"
            )

            SampleMarkdownCard()

            VStack(spacing: Spacing.s3) {
                OnboardingFeatureRow(icon: "number", title: "Readable Sections", description: "Sleep, activity, workouts, vitals, and nutrition are grouped in predictable Markdown.")
                OnboardingFeatureRow(icon: "tablecells", title: "Structured Data", description: "Use CSV or JSON when you want spreadsheets, charts, or automation.")
            }
        }
    }
}

private struct FolderSetupStep: View {
    let vaultName: String
    let hasFolder: Bool
    let onPickFolder: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s8) {
            OnboardingHeader(
                eyebrow: "Destination",
                title: "Pick a Folder or Choose Later",
                description: "Exports can go to an iPhone folder now. Connected Mac setup happens after onboarding from the Sync tab.",
                icon: "folder.fill"
            )

            if hasFolder {
                OnboardingStatusCard(
                    icon: "folder.fill.badge.checkmark",
                    title: vaultName,
                    description: "Health.md will write exports into a Health subfolder here.",
                    tint: .success
                )
            } else {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    OnboardingFeatureRow(icon: "folder.badge.plus", title: "Select Folder Now", description: "Choose an Obsidian vault or any Files folder on this iPhone.")

                    OnboardingSecondaryButton(title: "Select Folder Now", icon: "folder") {
                        onPickFolder()
                    }
                }
                .geistCard()
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
    let individualPriceLabel: String?
    let familyPriceLabel: String?
    let onPurchaseIndividual: () -> Void
    let onPurchaseFamily: () -> Void
    let onContinueFree: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s8) {
            OnboardingHeader(
                eyebrow: "Full Access",
                title: "Unlock Unlimited Exports",
                description: "Start with 3 free exports, or unlock lifetime access before your first run.",
                icon: "lock.open.fill"
            )

            VStack(spacing: Spacing.s3) {
                OnboardingFeatureRow(icon: "arrow.up.doc.fill", title: "Unlimited Exports", description: "Remove the free export limit permanently.")
                OnboardingFeatureRow(icon: "calendar.badge.clock", title: "Scheduled Exports", description: "Automations are included with lifetime access.")
                OnboardingFeatureRow(icon: "creditcard", title: "One-Time Purchase", description: "No subscription. Individual and Family Sharing options are available.")
            }

            VStack(spacing: Spacing.s3) {
                OnboardingPurchaseButton(
                    title: "Individual Lifetime",
                    subtitle: "Unlock on your Apple ID",
                    priceLabel: individualPriceLabel,
                    icon: "person.fill",
                    isPrimary: true,
                    isLoading: purchaseManager.purchasingOption == .individual,
                    isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                    action: onPurchaseIndividual
                )

                OnboardingPurchaseButton(
                    title: "Family Lifetime",
                    subtitle: "Share with up to 5 family members",
                    priceLabel: familyPriceLabel,
                    icon: "person.3.fill",
                    badge: "Family",
                    isPrimary: false,
                    isLoading: purchaseManager.purchasingOption == .family,
                    isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                    action: onPurchaseFamily
                )

                if let error = purchaseManager.purchaseError {
                    Text(error)
                        .font(Typography.caption())
                        .foregroundStyle(error.contains("cody@isolated.tech") ? Color.textMuted : Color.error)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.s3)
                        .accessibilityLabel(error)
                }

                OnboardingPrimaryButton(title: "Continue With 3 Free Exports", icon: "arrow.right", action: onContinueFree)

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
        VStack(spacing: Spacing.s8) {
            OnboardingHeader(
                eyebrow: "Ready",
                title: "Health.md Is Set Up",
                description: "Review your setup, then open the Export tab to preview or write your first files.",
                icon: "checkmark.seal.fill"
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

    var body: some View {
        VStack(spacing: Spacing.s6) {
            AppIconMark(icon: icon)

            VStack(spacing: Spacing.s3) {
                Text(eyebrow)
                    .font(Typography.labelUppercase())
                    .foregroundStyle(Color.textMuted)
                    .tracking(1.4)

                Text(title)
                    .font(Typography.displayLarge())
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .tracking(-1.0)
                    .accessibilityAddTraits(.isHeader)

                Text(description)
                    .font(Typography.bodyLarge())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AppIconMark: View {
    let icon: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                .fill(Color.bgPrimary)
                .frame(width: 84, height: 84)
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
                .accessibilityHidden(true)

            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold, design: .default))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)
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
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
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
        .padding(Spacing.s4)
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

private struct SampleMarkdownCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.accent)
                    .accessibilityHidden(true)
                Text("2026-06-19 Health.md")
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("md")
                    .font(Typography.monoCaptionEmphasis())
                    .foregroundStyle(Color.textMuted)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, Spacing.s1)
                    .background(Color.bgSecondary, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: Spacing.s2) {
                MarkdownLine(text: "# Health Summary", tint: .textPrimary)
                MarkdownLine(text: "- Steps: 8,432", tint: .textSecondary)
                MarkdownLine(text: "- Sleep: 7h 42m", tint: .textSecondary)
                MarkdownLine(text: "- Resting HR: 58 bpm", tint: .textSecondary)
                MarkdownLine(text: "[[Workouts]] · [[Vitals]]", tint: .accent)
            }
        }
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample Markdown export with steps, sleep, resting heart rate, and links")
    }
}

private struct MarkdownLine: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(Typography.mono())
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s4)
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
            .padding(Spacing.s4)
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
