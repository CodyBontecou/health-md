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

    @State private var currentStep = 0
    @State private var direction: TransitionDirection = .forward
    @State private var isRequestingHealthAuthorization = false

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
            Color.glassAdaptive(\.bg).ignoresSafeArea()

            OnboardingPageLayout(pageID: currentStep) {
                VStack(spacing: Spacing.s4) {
                    topBar
                    OnboardingProgressBar(current: step.phase.rawValue, total: OnboardingPhase.allCases.count)
                }
            } content: {
                stepContent
                    .id(currentStep)
            } footer: {
                footerControls
                    .transition(.opacity)
            }
        }
        .onChange(of: vaultManager.vaultURL) { _, folderURL in
            if folderURL != nil {
            }
        }
    }

    private var topBar: some View {
        OnboardingNavigationHeader(
            current: step.phase.rawValue,
            total: OnboardingPhase.allCases.count,
            canGoBack: canGoBack,
            showsMark: step != .welcome,
            onBack: goBack
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            GlassWelcomeStep()
                .glassTheme()
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
                // The Health step still explains access and makes the request. Importing a
                // shared setup lives in Settings › More (ImportSetupG), not on the welcome board.
                OnboardingPrimaryButton(
                    title: String(localized: "Connect Apple Health"),
                    icon: "arrow.right",
                    accessibilityHint: String(localized: "Double tap to continue"),
                    action: advance
                )
            case .healthAccess:
                if healthKitManager.isAuthorized {
                    OnboardingPrimaryButton(title: String(localized: "Continue Setup"), icon: "arrow.right", action: advance)
                } else {
                    OnboardingPrimaryButton(
                        title: isRequestingHealthAuthorization ? String(localized: "Connecting…") : String(localized: "Connect Apple Health"),
                        imageAsset: "AppleHealthIcon",
                        accessibilityHint: String(localized: "Opens Apple Health permission selection"),
                        isDisabled: isRequestingHealthAuthorization,
                        action: { requestHealthAuthorization(advanceWhenConnected: true) }
                    )
                    OnboardingSecondaryButton(title: String(localized: "Skip for Now"), icon: "forward") {
                        skipHealthAccess()
                    }
                }
            case .sampleExport:
                OnboardingPrimaryButton(title: String(localized: "Continue Setup"), icon: "arrow.right", action: advance)
            case .folder:
                if vaultManager.vaultURL == nil {
                    OnboardingPrimaryButton(
                        title: String(localized: "Select Export Folder"),
                        icon: "folder.badge.plus",
                        accessibilityHint: String(localized: "Opens the folder picker"),
                        action: { showFolderPicker = true }
                    )
                    OnboardingSecondaryButton(title: String(localized: "Skip for Now"), icon: "forward") {
                        skipFolderSetup()
                    }
                } else {
                    OnboardingPrimaryButton(title: String(localized: "Continue Setup"), icon: "arrow.right", action: advance)
                }
            case .ready:
                OnboardingPrimaryButton(
                    title: String(localized: "Create My First Export"),
                    icon: "doc.text.magnifyingglass",
                    accessibilityHint: String(localized: "Completes setup and opens a preview of your first export"),
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

    private func requestHealthAuthorization(advanceWhenConnected: Bool) {
        guard !isRequestingHealthAuthorization else { return }
        isRequestingHealthAuthorization = true

        Task {
            defer { isRequestingHealthAuthorization = false }
            do {
                _ = try await healthKitManager.requestAuthorization()
                if advanceWhenConnected && healthKitManager.isAuthorized {
                    advance()
                }
            } catch {
            }
        }
    }

    private func skipHealthAccess() {
        advance()
    }

    private func skipFolderSetup() {
        advance()
    }

}

/// The onboarding flow is intentionally short: welcome → health access → folder →
/// sample export (with the Obsidian-plugin promo folded in) → ready, matching
/// OnboardingG's phase order (read → archive location → preview).
/// The unlock paywall no longer blocks onboarding; it surfaces once, after the
/// first real export preview closes (see the post-onboarding paywall in
/// ContentView), alongside the 3rd/7th-export soft prompts.
private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case healthAccess
    case folder
    case sampleExport
    case ready

    /// The welcome page's three phases, which the progress bar and "Step x of 3" count.
    var phase: OnboardingPhase {
        switch self {
        case .welcome, .healthAccess: return .read
        case .folder: return .archive
        case .sampleExport, .ready: return .preview
        }
    }
}

/// OnboardingG's three phases: choose what Health.md can read, pick where the archive
/// lives (the sample file shows what will be written there), then preview the first
/// export, which the ready step leads to.
enum OnboardingPhase: Int, CaseIterable {
    case read
    case archive
    case preview
}

private enum TransitionDirection {
    case forward
    case backward
}

// MARK: - Progress

/// OnboardingG's progress: one 24-point pill for the current phase, 6-point dots for the rest.
struct OnboardingProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.glassAdaptive(\.accent) : Color.glassAdaptive(\.line))
                    .frame(width: index == current ? 24 : 6, height: 6)
                    .animation(AnimationTimings.standard, value: current)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Setup progress"))
        .accessibilityValue(Text("Step \(current + 1) of \(total)"))
    }
}

// MARK: - Steps

/// OnboardingG's opening page. Later steps, including the Health request, are unchanged.
private struct GlassWelcomeStep: View {
    @Environment(\.glassPalette) private var palette

    private let privacyPolicyURL = URL(string: "https://healthmd.app/privacy-policy.html")!

    var body: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            // OnboardingG's hero: the crystal heart on a 168-point glass tile.
            Image("HealthCrystalHeart")
                .resizable()
                .scaledToFit()
                .frame(width: 104, height: 104)
                .frame(width: 168, height: 168)
                .glassSurface(cornerRadius: 48)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityHidden(true)
            Text("Make your body part of Obsidian")
                .glassFont(.largeTitle)
                .foregroundStyle(palette.text)
            Text("Create a durable copy of sleep, HRV, workouts, vitals, medications and more — as files you own.")
                .glassFont(.body)
                .foregroundStyle(palette.sec)
            GlassPanel {
                step(1, "Choose what Health.md can read")
                step(2, "Pick where your archive lives")
                step(3, "Preview your first export")
            }
            Text("No account or health-data cloud. Files go to folders you choose.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
            Link("How Health.md handles data", destination: privacyPolicyURL)
                .glassFont(.caption)
                .foregroundStyle(palette.accent)
                .frame(minHeight: GlassMetrics.touchTarget)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ number: Int, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(number)")
                .glassFont(.caption)
                .foregroundStyle(palette.accentInk)
                .frame(width: 26, height: 26)
                .background(Circle().fill(palette.accent))
                .accessibilityHidden(true)
            Text(title).glassFont(.body).foregroundStyle(palette.text)
            Spacer(minLength: 0)
        }
        .padding(GlassMetrics.panelPadding)
    }
}

private struct HealthAccessStep: View {
    let isAuthorized: Bool

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: String(localized: "Apple Health"),
                title: String(localized: "Choose What Health.md Can Read"),
                description: String(localized: "Grant read access for the categories you want to export. You can adjust this later in the Health app."),
                icon: "heart.fill",
                showsIcon: false
            )

            VStack(spacing: Spacing.s3) {
                OnboardingStatusCard(
                    icon: isAuthorized ? "checkmark.circle.fill" : "circle.dotted",
                    title: isAuthorized ? String(localized: "Apple Health Connected") : String(localized: "Apple Health Not Connected"),
                    description: isAuthorized ? String(localized: "You’re ready to generate real previews and exports.") : String(localized: "You can continue now and connect before your first export."),
                    tint: isAuthorized ? .success : .textMuted
                )

                OnboardingFeatureRow(icon: "slider.horizontal.3", title: String(localized: "You Stay in Control"), description: String(localized: "iOS lets you approve or deny each health category."))
                OnboardingFeatureRow(icon: "eye.slash", title: String(localized: "No Account Required"), description: String(localized: "Health.md does not need a server account to export local files."))
            }
        }
    }
}

private struct SampleExportStep: View {
    @State private var selectedFormat: SampleExportPreviewFormat = .markdown

    var body: some View {
        VStack(spacing: Spacing.s6) {
            OnboardingHeader(
                eyebrow: String(localized: "Example File"),
                title: String(localized: "See the Health Note Reveal"),
                description: String(localized: "Watch Apple Health readings become a readable Markdown, CSV, JSON, or Obsidian file."),
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
                    .foregroundStyle(Color.glassAdaptive(\.text))
                Text("Turn these files into vault-native dashboards with the free Health.md plugin.")
                    .font(Typography.body())
                    .foregroundStyle(Color.glassAdaptive(\.sec))
            }

            Link(destination: pluginURL) {
                Text("Install")
                    .font(Typography.bodyEmphasis())
            }
            .accessibilityHint("Opens the Health.md Obsidian plugin page")
        }
        .padding(Spacing.s3)
        .background(Color.glassAdaptive(\.surface2))
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.glassAdaptive(\.line), lineWidth: 1)
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
                eyebrow: String(localized: "Destination"),
                title: String(localized: "Choose Where Your Archive Lives"),
                description: String(localized: "Save to an iPhone folder now, or connect the Mac app after onboarding to write exports to a Mac folder."),
                icon: "folder.fill",
                showsIcon: false
            )

            if hasFolder {
                OnboardingStatusCard(
                    icon: "folder.fill",
                    title: vaultName,
                    description: String(localized: "Health.md will write exports directly into this folder."),
                    tint: .success
                )
            } else {
                FolderPickerCard()
            }

            VStack(spacing: Spacing.s3) {
                OnboardingFeatureRow(icon: "iphone", title: String(localized: "Local iPhone Folder"), description: String(localized: "Best when you keep notes in iCloud Drive, On My iPhone, or a synced app folder."))
                OnboardingFeatureRow(icon: "desktopcomputer", title: String(localized: "Connected Mac Later"), description: String(localized: "Install the Mac app later to send iPhone-configured exports to a Mac folder."))
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
                eyebrow: String(localized: "Ready"),
                title: String(localized: "Your Health Archive Is Ready"),
                description: String(localized: "Review your setup, then preview your first private export with the defaults already configured."),
                icon: "checkmark.seal.fill",
                showsIcon: false
            )

            VStack(spacing: Spacing.s3) {
                OnboardingChecklistRow(
                    title: String(localized: "Apple Health"),
                    detail: healthAuthorized ? String(localized: "Connected") : String(localized: "Connect to preview your health data"),
                    isComplete: healthAuthorized,
                    actionTitle: healthAuthorized ? nil : String(localized: "Connect"),
                    action: healthAuthorized ? nil : onConnectHealth
                )
                OnboardingChecklistRow(
                    title: String(localized: "Export Folder"),
                    detail: folderSelected ? folderName : String(localized: "Choose now or after previewing"),
                    isComplete: folderSelected,
                    actionTitle: folderSelected ? nil : String(localized: "Choose Folder"),
                    action: folderSelected ? nil : onSelectFolder
                )
                OnboardingChecklistRow(
                    title: String(localized: "Formats"),
                    detail: String(localized: "Markdown is ready by default"),
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
                    .foregroundStyle(Color.glassAdaptive(\.text))
                Text(description)
                    .font(Typography.body())
                    .foregroundStyle(Color.glassAdaptive(\.sec))
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
                .foregroundStyle(Color.glassAdaptive(\.accent))
                .accessibilityHidden(true)

            Text(title)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.glassAdaptive(\.text))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s3)
        .background(Color.glassAdaptive(\.bg))
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                .strokeBorder(Color.glassAdaptive(\.line), lineWidth: 1)
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
                    .foregroundStyle(Color.glassAdaptive(\.text))
                Text("Choose an Obsidian vault or any Files folder on this iPhone.")
                    .font(Typography.body())
                    .foregroundStyle(Color.glassAdaptive(\.sec))
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
                    .foregroundStyle(Color.glassAdaptive(\.text))
                Text(description)
                    .font(Typography.body())
                    .foregroundStyle(Color.glassAdaptive(\.sec))
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
                .overlay(Color.glassAdaptive(\.line))

            ScrollView(.vertical) {
                Text(selectedFormat.content)
                    .font(Typography.monoCaption())
                    .foregroundStyle(Color.glassAdaptive(\.text))
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
        .background(Color.glassAdaptive(\.bg))
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.glassAdaptive(\.line), lineWidth: 1)
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
                    .foregroundStyle(Color.glassAdaptive(\.text))
                    .fixedSize(horizontal: false, vertical: true)

                Text(selectedFormat.subtitle)
                    .font(Typography.caption())
                    .foregroundStyle(Color.glassAdaptive(\.sec))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            if !reading {
                // The full filename above also retains the extension in reading layout.
                Text(selectedFormat.fileExtension)
                    .font(Typography.monoCaptionEmphasis())
                    .foregroundStyle(Color.glassAdaptive(\.sec))
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, Spacing.s1)
                    .background(Color.glassAdaptive(\.surface2), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.glassAdaptive(\.line), lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example file: \(selectedFormat.fileName). \(selectedFormat.subtitle)")
    }
}
