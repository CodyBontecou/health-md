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
    @EnvironmentObject var sharedSetupCoordinator: SharedSetupCoordinator
    let onComplete: () -> Void
    private let analytics = PricingAnalyticsClient.shared

    @State private var currentStep = 0
    @State private var direction: TransitionDirection = .forward
    @AppStorage("pricing.analytics.onboarding.started.tracked.v1") private var didPersistentlyTrackOnboardingStarted = false
    @AppStorage("pricing.analytics.onboarding.steps.tracked.v1") private var persistedTrackedStepRawValues = ""
    @AppStorage("pricing.analytics.onboarding.skips.tracked.v1") private var persistedSkippedStepRawValues = ""
    @AppStorage("pricing.analytics.onboarding.folder.selected.tracked.v1") private var didPersistentlyTrackFolderSelected = false
    @AppStorage("pricing.analytics.health.authorization.statuses.tracked.v1") private var persistedTrackedHealthAuthorizationStatusRawValues = ""
    @State private var didTrackOnboardingStarted = false
    @State private var trackedStepViews: Set<PricingAnalyticsOnboardingStep> = []
    @State private var didTrackFolderSelected = false
    @State private var isRequestingHealthAuthorization = false
    @State private var isSharedSetupImporterPresented = false

    private let totalSteps = OnboardingStep.allCases.count
    private let sampleExportStepIndex = OnboardingStep.sampleExport.rawValue
    private let folderStepIndex = OnboardingStep.folder.rawValue
    private let readyStepIndex = OnboardingStep.ready.rawValue

    private var step: OnboardingStep {
        OnboardingStep(rawValue: currentStep) ?? .welcome
    }

    private var canGoBack: Bool {
        currentStep > 0 && step != .ready
    }

    /// Setup steps are intentionally not gated. Health access and folder choice
    /// can both be completed later from the app, so onboarding never traps users.
    private var canAdvance: Bool { true }

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            OnboardingPageLayout(pageID: currentStep) {
                VStack(spacing: Spacing.s4) {
                    topBar
                    OnboardingProgressBar(current: currentStep, total: totalSteps)
                }
            } content: {
                stepContent
                    .id(currentStep)
            } footer: {
                footerControls
                    .transition(.opacity)
            }
        }
        .sharedSetupFileImporter(
            isPresented: $isSharedSetupImporterPresented,
            coordinator: sharedSetupCoordinator
        )
        .onAppear {
            trackInitialOnboardingAnalytics()
        }
        .onChange(of: currentStep) { _, stepIndex in
            trackStepViewed(for: stepIndex)
        }
        .onChange(of: vaultManager.vaultURL) { _, folderURL in
            if folderURL != nil {
                trackFolderSelectedIfNeeded()
            }
        }
    }

    private var topBar: some View {
        OnboardingNavigationHeader(
            current: currentStep,
            total: totalSteps,
            canGoBack: canGoBack,
            showsMark: step != .welcome,
            onBack: goBack
        )
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
                hasFolder: vaultManager.vaultURL != nil
            )
            .transition(stepTransition)
        case .ready:
            ReadyStep(
                healthAuthorized: healthKitManager.isAuthorized,
                folderSelected: vaultManager.vaultURL != nil,
                folderName: vaultManager.vaultName,
                onConnectHealth: { requestHealthAuthorization(advanceWhenConnected: false) },
                onSelectFolder: { showFolderPicker = true }
            )
            .transition(stepTransition)
        }
    }

    @ViewBuilder
    private var footerControls: some View {
        VStack(spacing: Spacing.s3) {
            switch step {
            case .welcome:
                VStack(spacing: Spacing.s2) {
                    OnboardingPrimaryButton(title: "Start Setup", icon: "arrow.right", action: advance)
                    Button {
                        sharedSetupCoordinator.beginImport(source: .onboarding)
                        isSharedSetupImporterPresented = true
                    } label: {
                        Label("Use a Shared Setup", systemImage: "doc.badge.gearshape")
                            .font(Typography.body())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier(AccessibilityID.SharedSetup.use)
                }
            case .healthAccess:
                if healthKitManager.isAuthorized {
                    OnboardingPrimaryButton(title: "Continue Setup", icon: "arrow.right", action: advance)
                } else {
                    OnboardingPrimaryButton(
                        title: isRequestingHealthAuthorization ? "Connecting…" : "Connect Apple Health",
                        imageAsset: "AppleHealthIcon",
                        accessibilityHint: "Opens Apple Health permission selection",
                        isDisabled: isRequestingHealthAuthorization,
                        action: { requestHealthAuthorization(advanceWhenConnected: true) }
                    )
                    OnboardingSecondaryButton(title: "Skip for Now", icon: "forward") {
                        skipHealthAccess()
                    }
                }
            case .sampleExport:
                OnboardingPrimaryButton(title: "Continue Setup", icon: "arrow.right", action: advance)
            case .folder:
                if vaultManager.vaultURL == nil {
                    OnboardingPrimaryButton(
                        title: "Select Export Folder",
                        icon: "folder.badge.plus",
                        accessibilityHint: "Opens the folder picker",
                        action: { showFolderPicker = true }
                    )
                    OnboardingSecondaryButton(title: "Skip for Now", icon: "forward") {
                        skipFolderSetup()
                    }
                } else {
                    OnboardingPrimaryButton(title: "Continue Setup", icon: "arrow.right", action: advance)
                }
            case .ready:
                OnboardingPrimaryButton(
                    title: "Create My First Export",
                    icon: "doc.text.magnifyingglass",
                    accessibilityHint: "Completes setup and opens a preview of your first export",
                    action: advance
                )
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

        direction = .forward
        move(to: currentStep + 1)
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

    private func requestHealthAuthorization(advanceWhenConnected: Bool) {
        guard !isRequestingHealthAuthorization else { return }
        isRequestingHealthAuthorization = true

        Task {
            defer { isRequestingHealthAuthorization = false }
            do {
                _ = try await healthKitManager.requestAuthorization()
                trackHealthAuthorizationCompletedIfNeeded(status: healthAuthorizationAnalyticsStatus)
                if advanceWhenConnected && healthKitManager.isAuthorized {
                    advance()
                }
            } catch {
                trackHealthAuthorizationCompletedIfNeeded(status: .unknown)
            }
        }
    }

    private func skipHealthAccess() {
        trackOnboardingSkipIfNeeded(.healthAccess)
        advance()
    }

    private func skipFolderSetup() {
        trackOnboardingSkipIfNeeded(.folderSetup)
        advance()
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
        guard let step = onboardingStep(for: index) else { return }

        if step == .healthAccess {
            if healthKitManager.isAuthorized {
                trackHealthAuthorizationCompletedIfNeeded(status: .authorized)
            } else if !healthKitManager.isHealthDataAvailable {
                trackHealthAuthorizationCompletedIfNeeded(status: .unavailable)
            }
        }
        if step == .folderSetup, vaultManager.vaultURL != nil {
            trackFolderSelectedIfNeeded()
        }

        guard !trackedStepViews.contains(step),
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

    private var persistedSkippedSteps: Set<PricingAnalyticsOnboardingStep> {
        Set(persistedSkippedStepRawValues
            .split(separator: ",")
            .compactMap { PricingAnalyticsOnboardingStep(rawValue: String($0)) })
    }

    private var persistedTrackedHealthAuthorizationStatusRawValueSet: Set<String> {
        Set(persistedTrackedHealthAuthorizationStatusRawValues
            .split(separator: ",")
            .map(String.init))
    }

    private func persistTrackedStep(_ step: PricingAnalyticsOnboardingStep) {
        var steps = persistedTrackedSteps
        steps.insert(step)
        persistedTrackedStepRawValues = steps
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
    }

    private func trackOnboardingSkipIfNeeded(_ step: PricingAnalyticsOnboardingStep) {
        guard !persistedSkippedSteps.contains(step) else { return }

        var steps = persistedSkippedSteps
        steps.insert(step)
        persistedSkippedStepRawValues = steps
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")

        switch step {
        case .healthAccess:
            analytics.trackOnboardingHealthSkipped(quotaState: purchaseManager.analyticsQuotaState)
        case .folderSetup:
            analytics.trackOnboardingFolderSkipped(quotaState: purchaseManager.analyticsQuotaState)
        default:
            break
        }
    }

    private func trackHealthAuthorizationCompletedIfNeeded(status: PricingAnalyticsAuthorizationStatus) {
        let rawValue = status.rawValue
        let trackedStatuses = persistedTrackedHealthAuthorizationStatusRawValueSet
        guard !trackedStatuses.contains(rawValue) else { return }

        // Once authorization succeeds, suppress later transient failures from
        // repeated taps or callback retries. Earlier unknown/not-authorized
        // attempts may still be followed by one useful authorized event.
        if trackedStatuses.contains(PricingAnalyticsAuthorizationStatus.authorized.rawValue),
           rawValue != PricingAnalyticsAuthorizationStatus.authorized.rawValue {
            return
        }

        var updatedStatuses = trackedStatuses
        updatedStatuses.insert(rawValue)
        persistedTrackedHealthAuthorizationStatusRawValues = updatedStatuses.sorted().joined(separator: ",")
        analytics.trackHealthAuthorizationCompleted(status: status)
    }

    private func trackFolderSelectedIfNeeded() {
        guard !didTrackFolderSelected, !didPersistentlyTrackFolderSelected else { return }
        didTrackFolderSelected = true
        didPersistentlyTrackFolderSelected = true
        analytics.trackOnboardingFolderSelected(quotaState: purchaseManager.analyticsQuotaState)
    }

    private func onboardingStep(for index: Int) -> PricingAnalyticsOnboardingStep? {
        switch index {
        case OnboardingStep.welcome.rawValue: return .welcome
        case OnboardingStep.healthAccess.rawValue: return .healthAccess
        case sampleExportStepIndex: return .sampleExport
        case folderStepIndex: return .folderSetup
        case readyStepIndex: return .ready
        default: return nil
        }
    }
}

/// The onboarding flow is intentionally short: welcome → health access →
/// sample export (with the Obsidian-plugin promo folded in) → folder → ready.
/// The unlock paywall no longer blocks onboarding; it surfaces once, after the
/// first real export preview closes (see the post-onboarding paywall in
/// ContentView), alongside the 3rd/7th-export soft prompts.
private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case healthAccess
    case sampleExport
    case folder
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
                description: "Apple Health has years of signal. Health.md turns it into private files you can keep, search, and link from Obsidian.",
                icon: "heart.text.square.fill",
                usesAppIcon: true
            )

            VStack(spacing: Spacing.s3) {
                OnboardingFeatureRow(icon: "archivebox.fill", title: "Build Your Archive", description: "Create a durable copy of sleep, HRV, workouts, vitals, medications, and more.")
                OnboardingFeatureRow(icon: "calendar.badge.clock", title: "Wake Up to a Daily Note", description: "Schedule exports so your health journal stays current automatically.")
                OnboardingFeatureRow(icon: "lock.shield", title: "Stay Local", description: "No account or health-data cloud. Files are written to folders you choose.")
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
                title: "See the Health Note Reveal",
                description: "Watch Apple Health readings become a readable Markdown, CSV, JSON, or Obsidian file.",
                icon: "doc.text.magnifyingglass",
                showsIcon: false
            )

            SampleExportInlinePreview(selectedFormat: $selectedFormat)

            ObsidianPluginLinkCard()
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

/// Compact, non-blocking promo for the Obsidian plugin, folded into the
/// sample-export step. Replaces the former full-screen `obsidian_plugin`
/// onboarding step: the plugin pitch rides along with the file preview
/// instead of gatekeeping the funnel.
private struct ObsidianPluginLinkCard: View {
    private let pluginURL = URL(string: "https://community.obsidian.md/plugins/health-md")!

    var body: some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: "chart.xyaxis.line")
                .font(Typography.scaled(size: 16, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(minWidth: 32, minHeight: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text("Make Your Body Part of Obsidian")
                    .font(Typography.headline())
                    .foregroundStyle(Color.textPrimary)
                Text("Turn these files into vault-native dashboards with the free Health.md plugin.")
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
            }

            Link(destination: pluginURL) {
                Text("Install")
                    .font(Typography.bodyEmphasis())
            }
            .accessibilityHint("Opens the Health.md Obsidian plugin page")
        }
        .padding(Spacing.s3)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct FolderSetupStep: View {
    let vaultName: String
    let hasFolder: Bool

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Destination",
                title: "Choose Where Your Archive Lives",
                description: "Save to an iPhone folder now, or connect the Mac app after onboarding to write exports to a Mac folder.",
                icon: "folder.fill",
                showsIcon: false
            )

            if hasFolder {
                OnboardingStatusCard(
                    icon: "folder.fill",
                    title: vaultName,
                    description: "Health.md will write exports directly into this folder.",
                    tint: .success
                )
            } else {
                FolderPickerCard()
            }

            VStack(spacing: Spacing.s3) {
                OnboardingFeatureRow(icon: "iphone", title: "Local iPhone Folder", description: "Best when you keep notes in iCloud Drive, On My iPhone, or a synced app folder.")
                OnboardingFeatureRow(icon: "desktopcomputer", title: "Connected Mac Later", description: "Install the Mac app later to send iPhone-configured exports to a Mac folder.")
            }
        }
    }
}

private struct ReadyStep: View {
    let healthAuthorized: Bool
    let folderSelected: Bool
    let folderName: String
    let onConnectHealth: () -> Void
    let onSelectFolder: () -> Void

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: "Ready",
                title: "Your Health Archive Is Ready",
                description: "Review your setup, then preview your first private export with the defaults already configured.",
                icon: "checkmark.seal.fill",
                showsIcon: false
            )

            VStack(spacing: Spacing.s3) {
                OnboardingChecklistRow(
                    title: "Apple Health",
                    detail: healthAuthorized ? "Connected" : "Connect to preview your health data",
                    isComplete: healthAuthorized,
                    actionTitle: healthAuthorized ? nil : "Connect",
                    action: healthAuthorized ? nil : onConnectHealth
                )
                OnboardingChecklistRow(
                    title: "Export Folder",
                    detail: folderSelected ? folderName : "Choose now or after previewing",
                    isComplete: folderSelected,
                    actionTitle: folderSelected ? nil : "Choose Folder",
                    action: folderSelected ? nil : onSelectFolder
                )
                OnboardingChecklistRow(
                    title: "Formats",
                    detail: "Markdown is ready by default",
                    isComplete: true
                )
            }
        }
    }
}

// MARK: - Shared Onboarding Components

private struct OnboardingFeatureRow: View {
    @Environment(\.onboardingReadingLayout) private var reading
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            if !reading {
                Image(systemName: icon)
                    .font(Typography.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(minWidth: 32, minHeight: 32)
                    .accessibilityHidden(true)
            }

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

private struct OnboardingInfoChip: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: icon)
                .font(Typography.scaled(size: 14, weight: .semibold))
                .foregroundStyle(Color.accent)
                .accessibilityHidden(true)

            Text(title)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
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
    @Environment(\.onboardingReadingLayout) private var reading

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            if !reading {
                Image(systemName: "folder.badge.plus")
                    .font(Typography.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(minWidth: 36, minHeight: 36)
                    .accessibilityHidden(true)
            }

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
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s3)
    }
}

private struct OnboardingStatusCard: View {
    @Environment(\.onboardingReadingLayout) private var reading
    let icon: String
    let title: String
    let description: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            if !reading {
                Image(systemName: icon)
                    .font(Typography.scaled(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(minWidth: 34, minHeight: 34)
                    .background(tint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                    .accessibilityHidden(true)
            }

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
    @Environment(\.onboardingReadingLayout) private var reading
    @Environment(\.onboardingPreviewHeight) private var previewHeight
    @Binding var selectedFormat: SampleExportPreviewFormat

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Spacing.s3) {
                fileHeader

                OnboardingAudienceChoices(
                    choices: SampleExportPreviewFormat.allCases,
                    selection: selectedFormat,
                    title: { $0.pickerTitle },
                    onSelect: { selectedFormat = $0 }
                )
                .accessibilityLabel("Export format")
            }
            .padding(.horizontal, Spacing.s3)
            .padding(.top, Spacing.s3)
            .padding(.bottom, Spacing.s2)

            Divider()
                .overlay(Color.borderSubtle)

            ScrollView(.vertical) {
                Text(selectedFormat.content)
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Spacing.s4)
            }
            .id(selectedFormat)
            .frame(height: previewHeight)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, alignment: .top)
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
            if !reading {
                Image(systemName: selectedFormat.icon)
                    .font(Typography.scaled(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(minWidth: 36, minHeight: 36)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedFormat.fileName)
                    .font(Typography.monoEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(selectedFormat.subtitle)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            if !reading {
                // The full filename above also retains the extension in reading layout.
                Text(selectedFormat.fileExtension)
                    .font(Typography.monoCaptionEmphasis())
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, Spacing.s1)
                    .background(Color.bgSecondary, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
            }
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
        schema_version: 5
        time_context:
          calendar_timezone: America/Los_Angeles
          timestamp_timezone: UTC
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
          "schema_version": 5,
          "date": "2026-06-19",
          "type": "health-data",
          "time_context": {
            "calendar_timezone": "America/Los_Angeles",
            "timestamp_timezone": "UTC"
          },
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
              "type": "Running",
              "sport": "running",
              "healthKitActivityType": "running",
              "healthKitActivityTypeRawValue": 37,
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
        2026-06-19,Metadata,schema_version,5,,
        2026-06-19,Metadata,unit_system,metric,,
        2026-06-19,Metadata,time_context.calendar_timezone,America/Los_Angeles,,
        2026-06-19,Metadata,time_context.timestamp_timezone,UTC,,
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
        2026-06-19,Workouts,Workout Activity Type,Running,,2026-06-19T14:10:00Z
        2026-06-19,Workouts,Workout Sport,running,,2026-06-19T14:10:00Z
        2026-06-19,Workouts,HealthKit Activity Type,running,,2026-06-19T14:10:00Z
        2026-06-19,Workouts,HealthKit Activity Type Raw Value,37,,2026-06-19T14:10:00Z
        2026-06-19,Workouts,Running Duration,2112,seconds,
        2026-06-19,Workouts,Running Distance,5150,meters,
        2026-06-19,Workouts,Running Calories,312,kcal,
        2026-06-19,Workouts,Running Avg Heart Rate,146,bpm,
        """
    }

    private var obsidianBasesContent: String {
        """
        ---
        schema: healthmd.health_data
        schema_version: 5
        time_context:
          calendar_timezone: America/Los_Angeles
          timestamp_timezone: UTC
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
            activity_type: "Running"
            sport: running
            healthkit_activity_type: running
            healthkit_activity_type_raw_value: 37
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
