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

    @State private var currentStep = 0
    @State private var animateIn = false
    @State private var direction: TransitionDirection = .forward

    private let totalSteps = 5
    private let unlockStepIndex = 3
    private let readyStepIndex = 4

    private var isTechnicalStep: Bool {
        currentStep == 0
            || currentStep == 1
            || currentStep == 2
            || currentStep == unlockStepIndex
            || currentStep == readyStepIndex
    }

    private var unlockPriceLabel: String {
        purchaseManager.product?.displayPrice ?? "$9.99"
    }

    /// Whether the user has satisfied the current step's requirement and may continue.
    /// The unlock step (index 3) renders its own buttons and is not gated here.
    /// Health Access (step 1) is intentionally not gated — denying the iOS system
    /// permission dialog would otherwise trap the user, since iOS only shows it
    /// once per install. The user can grant later via Settings > Health.
    private var canAdvance: Bool {
        switch currentStep {
        case 2: return vaultManager.vaultURL != nil
        default: return true
        }
    }

    var body: some View {
        ZStack {
            if isTechnicalStep {
                TechnicalBackground()
                    .transition(.opacity)
            } else {
                Color.bgPrimary.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Progress indicator: technical steps render their own header.
                if !isTechnicalStep {
                    OnboardingProgressBar(current: currentStep, total: totalSteps)
                        .padding(.top, Spacing.md)
                        .padding(.horizontal, Spacing.xl)
                }

                // Step content with directional slide
                ScrollView {
                    ZStack {
                        switch currentStep {
                        case 0:
                            WelcomeStep(animateIn: animateIn, totalSteps: totalSteps)
                                .transition(stepTransition)
                        case 1:
                            HealthAccessStep(
                                animateIn: animateIn,
                                totalSteps: totalSteps
                            )
                            .transition(stepTransition)
                        case 2:
                            FolderSetupStep(
                                vaultManager: vaultManager,
                                animateIn: animateIn,
                                totalSteps: totalSteps,
                                onPickFolder: { showFolderPicker = true }
                            )
                            .transition(stepTransition)
                        case 3:
                            TechnicalUnlockStep(
                                purchaseManager: purchaseManager,
                                unlockPriceLabel: unlockPriceLabel,
                                animateIn: animateIn,
                                totalSteps: totalSteps,
                                onPurchase: {
                                    Task { await purchaseManager.purchase() }
                                },
                                onContinueFree: advance,
                                onRestore: {
                                    Task { await purchaseManager.restore() }
                                }
                            )
                            .transition(stepTransition)
                        case 4:
                            TechnicalReadyStep(
                                healthAuthorized: healthKitManager.isAuthorized,
                                folderSelected: vaultManager.vaultURL != nil,
                                folderName: vaultManager.vaultName,
                                animateIn: animateIn
                            )
                            .transition(stepTransition)
                        default:
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, isTechnicalStep ? Spacing.xs : Spacing.lg)
                }
                .scrollIndicators(isTechnicalStep ? .hidden : .automatic)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: currentStep)

                // Navigation buttons. The paywall owns its technical action stack so
                // the price strip and buttons stay in one scrollable composition.
                if currentStep != unlockStepIndex {
                    VStack(spacing: Spacing.md) {
                        if currentStep == 0 {
                            TechnicalPrimaryButton(action: advance)
                        } else if currentStep == 1 {
                            TechnicalAccessButton(
                                isAuthorized: healthKitManager.isAuthorized,
                                action: {
                                    Task {
                                        try? await healthKitManager.requestAuthorization()
                                    }
                                }
                            )
                            TechnicalPrimaryButton(showsArrow: true, action: advance)
                        } else if currentStep == 2 {
                            TechnicalPrimaryButton(
                                showsArrow: canAdvance,
                                leadingArrow: !canAdvance,
                                isDisabled: !canAdvance,
                                action: advance
                            )

                            if !canAdvance {
                                TechnicalContinueHint()
                            }
                        } else if currentStep == readyStepIndex {
                            TechnicalPrimaryButton(
                                title: "GET STARTED",
                                showsArrow: true,
                                accessibilityLabel: "Get Started",
                                action: advance
                            )
                        } else {
                            PrimaryButton(
                                currentStep == totalSteps - 1 ? "Get Started" : "Continue",
                                icon: currentStep == totalSteps - 1 ? "arrow.right" : "chevron.right",
                                isDisabled: !canAdvance,
                                action: advance
                            )
                        }
                    }
                    .padding(.horizontal, isTechnicalStep ? 44 : Spacing.lg)
                    .padding(.bottom, isTechnicalStep ? 20 : Spacing.xl)
                    .opacity(animateIn ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (animateIn ? 0 : 12))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.3), value: animateIn)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.1)) {
                if reduceMotion {
                    animateIn = true
                } else {
                    withAnimation {
                        animateIn = true
                    }
                }
            }
        }
        .onChange(of: purchaseManager.isUnlocked) { _, unlocked in
            if unlocked && currentStep == unlockStepIndex {
                advance()
            }
        }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: direction == .forward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: direction == .forward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private func advance() {
        if currentStep >= totalSteps - 1 {
            onComplete()
            return
        }

        var nextStep = currentStep + 1
        // Skip the paywall for legacy users / re-installs that are already unlocked.
        if nextStep == unlockStepIndex && purchaseManager.isUnlocked {
            nextStep += 1
        }

        direction = .forward
        animateIn = false

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.05)) {
            if reduceMotion {
                currentStep = nextStep
            } else {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    currentStep = nextStep
                }
            }
            // Trigger stagger animations for the new step
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.15)) {
                if reduceMotion {
                    animateIn = true
                } else {
                    withAnimation {
                        animateIn = true
                    }
                }
            }
        }
    }
}

private enum TransitionDirection {
    case forward, backward
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let current: Int
    let total: Int
    @ScaledMetric(relativeTo: .caption) private var selectedSegmentWidth: CGFloat = 32
    @ScaledMetric(relativeTo: .caption) private var segmentHeight: CGFloat = 3

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.accent : Color.borderDefault)
                    .frame(width: index == current ? selectedSegmentWidth : nil, height: segmentHeight)
                    .frame(maxWidth: index == current ? nil : .infinity)
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: current)
            }
        }
    }
}

// MARK: - Staggered Item Modifier

private struct StaggeredItem: ViewModifier {
    let animateIn: Bool
    let index: Int

    func body(content: Content) -> some View {
        content
            .opacity(animateIn ? 1 : 0)
            .offset(y: animateIn ? 0 : 16)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8)
                    .delay(Double(index) * 0.08),
                value: animateIn
            )
    }
}

private extension View {
    func staggerIn(_ animateIn: Bool, index: Int) -> some View {
        modifier(StaggeredItem(animateIn: animateIn, index: index))
    }
}

// MARK: - Breathing Glow Modifier

private struct BreathingGlow: ViewModifier {
    @State private var glowPhase = false

    func body(content: Content) -> some View {
        content
            .opacity(glowPhase ? 0.6 : 0.3)
            .scaleEffect(glowPhase ? 1.08 : 0.95)
            .animation(
                .easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                value: glowPhase
            )
            .onAppear { glowPhase = true }
    }
}

private extension View {
    func breathingGlow() -> some View {
        modifier(BreathingGlow())
    }
}

// MARK: - Hero Icon Entrance

private struct HeroIconEntrance: ViewModifier {
    let animateIn: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(animateIn ? 1.0 : 0.6)
            .opacity(animateIn ? 1 : 0)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.65),
                value: animateIn
            )
    }
}

private extension View {
    func heroEntrance(_ animateIn: Bool) -> some View {
        modifier(HeroIconEntrance(animateIn: animateIn))
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    let animateIn: Bool
    let totalSteps: Int

    var body: some View {
        VStack(spacing: 12) {
            TechnicalHeader(currentStep: 1, totalSteps: totalSteps)
                .staggerIn(animateIn, index: 0)

            WelcomeBrandPanel()
                .heroEntrance(animateIn)
                .padding(.top, 2)

            VStack(spacing: 10) {
                Text("Health.md")
                    .font(.system(size: 36, weight: .regular, design: .monospaced))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .tracking(1.5)
                    .accessibilityAddTraits(.isHeader)

                Capsule()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 38, height: 3)
                    .accessibilityHidden(true)

                Text("Your health data,\nyour way.")
                    .font(.system(size: 22, weight: .regular, design: .monospaced))
                    .minimumScaleFactor(0.74)
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Export, schedule, and keep\neverything on your devices.")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .staggerIn(animateIn, index: 1)

            VStack(spacing: 8) {
                TechnicalFeatureRow(
                    icon: "doc.badge.arrow.up",
                    title: "EXPORT HEALTH DATA",
                    description: "Markdown, CSV, or JSON",
                    index: "01"
                )
                .staggerIn(animateIn, index: 2)

                TechnicalFeatureRow(
                    icon: "clock",
                    title: "AUTOMATIC SCHEDULING",
                    description: "Set it once. We’ll handle the rest.",
                    index: "02"
                )
                .staggerIn(animateIn, index: 3)

                TechnicalFeatureRow(
                    icon: "lock.shield",
                    title: "PRIVATE & LOCAL",
                    description: "Your data never leaves your devices.",
                    index: "03"
                )
                .staggerIn(animateIn, index: 4)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

private enum TechnicalPalette {
    static let background = Color(hex: "FAF9F5")
    static let primaryText = Color(hex: "111113")
    static let secondaryText = Color(hex: "676A73")
    static let hairline = Color(hex: "D8D6D0")
    static let faintStroke = Color(hex: "ECEAE5")
    static let accent = Color(hex: "8F63E8")
}

private enum OnboardingVersionLabel {
    static var current: String {
        let rawVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let version = rawVersion?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let version, !version.isEmpty, !version.contains("$(") else {
            return "v1.0"
        }

        return version.lowercased().hasPrefix("v") ? version : "v\(version)"
    }
}

private struct TechnicalBackground: View {
    var body: some View {
        ZStack {
            TechnicalPalette.background.ignoresSafeArea()

            VStack {
                HStack {
                    DottedGrid(columns: 8, rows: 8, dotSize: 1.25, spacing: 8)
                        .foregroundStyle(TechnicalPalette.faintStroke)
                    Spacer()
                }
                .padding(.top, 92)
                .padding(.leading, 22)

                Spacer()

                HStack {
                    Spacer()
                    DottedGrid(columns: 10, rows: 7, dotSize: 1.25, spacing: 8)
                        .foregroundStyle(TechnicalPalette.faintStroke)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 118)
            }
        }
    }
}

private struct TechnicalHeader: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(alignment: .top) {
            CrosshairMark()
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            Spacer(minLength: 6)

            StepIndicator(
                currentStep: currentStep,
                totalSteps: totalSteps,
                displayTotalSteps: max(totalSteps, 6)
            )
            .padding(.top, 8)
            .accessibilityLabel("Onboarding step \(currentStep) of \(max(totalSteps, 6))")

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text("ONBOARDING")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(TechnicalPalette.primaryText.opacity(0.7))

                Text(OnboardingVersionLabel.current)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(TechnicalPalette.secondaryText)

                Rectangle()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 12, height: 2)
                    .padding(.top, 2)
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CrosshairMark: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(TechnicalPalette.hairline, lineWidth: 1)
                .frame(width: 24, height: 24)
            Rectangle()
                .fill(TechnicalPalette.hairline)
                .frame(width: 36, height: 1)
            Rectangle()
                .fill(TechnicalPalette.hairline)
                .frame(width: 1, height: 36)
            Circle()
                .fill(TechnicalPalette.accent)
                .frame(width: 4, height: 4)
        }
    }
}

private struct StepIndicator: View {
    let currentStep: Int
    let totalSteps: Int
    let displayTotalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d", currentStep))
                .foregroundStyle(TechnicalPalette.accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(TechnicalPalette.accent)
                .frame(width: 32, height: 2)
            ForEach(0..<max(totalSteps - 1, 1), id: \.self) { _ in
                Rectangle()
                    .fill(TechnicalPalette.hairline)
                    .frame(width: 8, height: 2)
            }
            Text(String(format: "%02d", displayTotalSteps))
                .foregroundStyle(TechnicalPalette.secondaryText.opacity(0.68))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.system(size: 15, weight: .regular, design: .monospaced))
        .tracking(0.5)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct WelcomeBrandPanel: View {
    var panelWidth: CGFloat = 158
    var panelHeight: CGFloat = 108
    var heartSize: CGFloat = 78
    var label: String = "HEALTH.MD"
    var labelHeight: CGFloat = 76
    var corner: CGFloat = 20
    var gridOffset: CGSize = CGSize(width: 46, height: -34)
    var blendsHeartIntoBackground = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ChamferedRectangle(corner: corner)
                    .fill(TechnicalPalette.background.opacity(0.8))

                DottedGrid(columns: 5, rows: 4, dotSize: 1.15, spacing: 8)
                    .foregroundStyle(TechnicalPalette.faintStroke)
                    .offset(x: gridOffset.width, y: gridOffset.height)
                    .accessibilityHidden(true)

                heartImage
                    .accessibilityLabel("Health.md crystal heart logo")

                ChamferedRectangle(corner: corner)
                    .stroke(TechnicalPalette.hairline, lineWidth: 1)

                CornerPlusMarks(width: panelWidth, height: panelHeight)
                    .foregroundStyle(TechnicalPalette.hairline)
            }
            .frame(width: panelWidth, height: panelHeight)
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: labelHeight)

                Rectangle()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 2, height: 12)
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var heartImage: some View {
        let image = Image("HealthCrystalHeart")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: heartSize, height: heartSize)

        if blendsHeartIntoBackground {
            image.blendMode(.multiply)
        } else {
            image
        }
    }
}

private struct TechnicalFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    let index: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TechnicalPalette.primaryText.opacity(0.86), lineWidth: 1.35)
                    .frame(width: 38, height: 38)

                Image(systemName: icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .frame(width: 38, height: 38)

                Circle()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 8, height: 8)
                    .offset(x: 3, y: 3)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VerticalDashedLine()
                .stroke(TechnicalPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 1, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                Text(description)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                Text(index)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.accent)

                DottedGrid(columns: 4, rows: 4, dotSize: 1.75, spacing: 4)
                    .foregroundStyle(TechnicalPalette.hairline)

                PlusMark(size: 8)
                    .foregroundStyle(TechnicalPalette.hairline)
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 62)
        .background(
            ChamferedRectangle(corner: 14)
                .fill(TechnicalPalette.background.opacity(0.68))
        )
        .overlay(
            ChamferedRectangle(corner: 14)
                .stroke(TechnicalPalette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index). \(title). \(description)")
    }
}

private struct TechnicalPrimaryButton: View {
    var title: String = "CONTINUE"
    var showsArrow: Bool = false
    var leadingArrow: Bool = false
    var isLoading: Bool = false
    var isDisabled: Bool = false
    var height: CGFloat = 70
    var titleFontSize: CGFloat = 18
    var titleTracking: CGFloat = 2.2
    var arrowTrailingPadding: CGFloat = 24
    var accessibilityLabel: String = "Continue"
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if leadingArrow {
                    HStack(spacing: 16) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 24, weight: .light))
                        buttonTitle
                    }
                } else {
                    buttonTitle
                        .padding(.horizontal, showsArrow ? arrowReserveWidth : 0)
                }

                if showsArrow && !isLoading {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 26, weight: .light))
                            .padding(.trailing, arrowTrailingPadding)
                    }
                    .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color.white.opacity(isDisabled ? 0.72 : 1))
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                ChamferedRectangle(corner: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "8A5BE4").opacity(isDisabled ? 0.34 : 1),
                                Color(hex: "8050DB").opacity(isDisabled ? 0.28 : 1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                ChamferedRectangle(corner: 12)
                    .stroke(Color(hex: "6F43D2").opacity(isDisabled ? 0.18 : 0.5), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                ButtonCornerTicks()
                    .foregroundStyle(Color.white.opacity(isDisabled ? 0.22 : 0.55))
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? (isDisabled ? "Select a folder to continue" : ""))
    }

    private var arrowReserveWidth: CGFloat {
        arrowTrailingPadding + 30
    }

    private var buttonTitle: some View {
        HStack(spacing: 10) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }

            Text(title)
                .font(.system(size: titleFontSize, weight: .regular, design: .monospaced))
                .tracking(titleTracking)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
    }
}

private struct DottedGrid: View {
    let columns: Int
    let rows: Int
    let dotSize: CGFloat
    let spacing: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { _ in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { _ in
                        Circle()
                            .fill(.foreground)
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
        }
    }
}

private struct PlusMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.foreground)
                .frame(width: size, height: 1)
            Rectangle()
                .fill(.foreground)
                .frame(width: 1, height: size)
        }
    }
}

private struct CornerPlusMarks: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            PlusMark(size: 8)
                .position(x: 26, y: 34)
            PlusMark(size: 8)
                .position(x: width - 26, y: 34)
            PlusMark(size: 8)
                .position(x: 26, y: height - 34)
            PlusMark(size: 8)
                .position(x: width - 26, y: height - 34)
        }
    }
}

private struct ButtonCornerTicks: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PlusMark(size: 5)
                    .position(x: 20, y: 14)
                PlusMark(size: 5)
                    .position(x: proxy.size.width - 20, y: 14)
                PlusMark(size: 5)
                    .position(x: 20, y: proxy.size.height - 14)
                PlusMark(size: 5)
                    .position(x: proxy.size.width - 20, y: proxy.size.height - 14)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct VerticalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct ChamferedRectangle: Shape {
    var corner: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        let corner = min(corner, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.closeSubpath()
        return path
    }
}

// MARK: - Step 2: Health Access

private struct HealthAccessStep: View {
    let animateIn: Bool
    let totalSteps: Int

    var body: some View {
        VStack(spacing: 0) {
            TechnicalHeader(currentStep: 2, totalSteps: totalSteps)
                .staggerIn(animateIn, index: 0)

            HealthAccessHeroPanel()
                .heroEntrance(animateIn)
                .padding(.top, 8)

            VStack(spacing: 10) {
                Text("Health Data Access")
                    .font(.system(size: 32, weight: .regular, design: .monospaced))
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .tracking(1.1)
                    .accessibilityAddTraits(.isHeader)

                Capsule()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 38, height: 3)
                    .accessibilityHidden(true)

                Text("Health.md reads your Apple Health data\nonly to export it to files you own.\n\nNothing is uploaded or shared.")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .staggerIn(animateIn, index: 1)
            .padding(.top, 14)

            HealthAccessCategoriesCard()
                .staggerIn(animateIn, index: 2)
                .padding(.top, 16)

        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }
}

private struct HealthAccessHeroPanel: View {
    var body: some View {
        // Match slide 1's brand header exactly; only the step indicator above changes to 02.
        WelcomeBrandPanel()
    }
}

private struct HealthAccessCategoriesCard: View {
    private let rows: [(icon: String, title: String, detail: String)] = [
        ("moon.zzz", "SLEEP", "Duration, stages, timing"),
        ("figure.walk", "ACTIVITY", "Steps, calories, workouts"),
        ("waveform.path.ecg", "HEART", "Heart rate, HRV, blood pressure"),
        ("lungs", "VITALS", "Respiratory rate, SpO2, temperature")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                TechnicalDataCategoryRow(icon: row.icon, title: row.title, detail: row.detail)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(TechnicalPalette.hairline)
                        .frame(height: 1)
                        .overlay {
                            Rectangle()
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                .foregroundStyle(TechnicalPalette.hairline.opacity(0.95))
                        }
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ChamferedRectangle(corner: 16)
                .fill(TechnicalPalette.background.opacity(0.68))
        )
        .overlay(
            ChamferedRectangle(corner: 16)
                .stroke(TechnicalPalette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct TechnicalDataCategoryRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TechnicalPalette.primaryText.opacity(0.86), lineWidth: 1.25)
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(TechnicalPalette.accent)
                    .frame(width: 34, height: 34)
            }
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)

            VerticalDashedLine()
                .stroke(TechnicalPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 1, height: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.footnote, design: .monospaced).weight(.medium))
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .tracking(0.5)

                Text(detail)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
            }

            Spacer(minLength: 6)

            PlusMark(size: 10)
                .foregroundStyle(TechnicalPalette.hairline)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .frame(minHeight: 48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(detail)")
    }
}

private struct TechnicalAccessButton: View {
    let isAuthorized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isAuthorized ? "checkmark.seal" : "lock")
                    .font(.system(size: 17, weight: .regular))
                    .accessibilityHidden(true)

                Text(isAuthorized ? "ACCESS GRANTED" : "GRANT ACCESS")
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .tracking(1.2)
            }
            .foregroundStyle(TechnicalPalette.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                ChamferedRectangle(corner: 12)
                    .fill(TechnicalPalette.background.opacity(0.55))
            )
            .overlay(
                ChamferedRectangle(corner: 12)
                    .stroke(TechnicalPalette.accent.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isAuthorized ? "Access granted" : "Grant Access")
    }
}

// MARK: - Step 3: Folder Setup

private struct FolderSetupStep: View {
    @ObservedObject var vaultManager: VaultManager
    let animateIn: Bool
    let totalSteps: Int
    let onPickFolder: () -> Void

    private var isFolderSelected: Bool {
        vaultManager.vaultURL != nil
    }

    var body: some View {
        Group {
            if isFolderSelected {
                FolderSuccessStepContent(
                    vaultManager: vaultManager,
                    animateIn: animateIn,
                    totalSteps: totalSteps,
                    onChangeFolder: onPickFolder
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                FolderSelectionStepContent(
                    vaultManager: vaultManager,
                    animateIn: animateIn,
                    totalSteps: totalSteps,
                    onPickFolder: onPickFolder
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: isFolderSelected)
    }
}

private struct FolderSelectionStepContent: View {
    @ObservedObject var vaultManager: VaultManager
    let animateIn: Bool
    let totalSteps: Int
    let onPickFolder: () -> Void

    private var selectedFolderHint: String {
        vaultManager.vaultURL == nil
            ? "Opens the folder picker"
            : "Selected folder: \(vaultManager.vaultName)"
    }

    var body: some View {
        VStack(spacing: 0) {
            TechnicalHeader(currentStep: 3, totalSteps: totalSteps)
                .staggerIn(animateIn, index: 0)

            FolderSetupHeroPanel()
                .heroEntrance(animateIn)
                .padding(.top, 8)

            VStack(spacing: 10) {
                Text("Choose Export Folder")
                    .font(.system(size: 30, weight: .regular, design: .monospaced))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)

                Capsule()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 38, height: 3)
                    .accessibilityHidden(true)

                Text("Pick a folder where your health data\nwill be saved. This can be an Obsidian\nvault, iCloud Drive, or any folder on\nyour device.")
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .staggerIn(animateIn, index: 1)
            .padding(.top, 14)

            TechnicalFolderOptionsCard()
                .staggerIn(animateIn, index: 2)
                .padding(.top, 18)

            TechnicalFolderSelectButton(action: onPickFolder)
                .staggerIn(animateIn, index: 3)
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .accessibilityHint(selectedFolderHint)
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }
}

private struct FolderSuccessStepContent: View {
    @ObservedObject var vaultManager: VaultManager
    let animateIn: Bool
    let totalSteps: Int
    let onChangeFolder: () -> Void

    private var folderName: String {
        vaultManager.vaultName.isEmpty ? "Selected Folder" : vaultManager.vaultName
    }

    private var folderPath: String {
        guard let vaultURL = vaultManager.vaultURL else {
            return "\(folderName)/\(vaultManager.healthSubfolder)"
        }

        return vaultURL.path.isEmpty
            ? "\(folderName)/\(vaultManager.healthSubfolder)"
            : vaultURL.path
    }

    var body: some View {
        VStack(spacing: 0) {
            TechnicalHeader(currentStep: 4, totalSteps: totalSteps)
                .staggerIn(animateIn, index: 0)

            FolderSuccessHeroPanel()
                .heroEntrance(animateIn)
                .padding(.top, 10)

            VStack(spacing: 10) {
                Text("Export Folder Ready")
                    .font(.system(size: 30, weight: .regular, design: .monospaced))
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .tracking(0.8)
                    .accessibilityAddTraits(.isHeader)

                Capsule()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 38, height: 3)
                    .accessibilityHidden(true)

                Text("Health.md will save your exports\nto the selected folder.")
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 20)

                Text("Your health data stays private\nand under your control.")
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .staggerIn(animateIn, index: 1)
            .padding(.top, 16)

            TechnicalSelectedFolderCard(
                folderName: folderName,
                folderPath: folderPath
            )
            .staggerIn(animateIn, index: 2)
            .padding(.top, 30)

            TechnicalChangeFolderButton(action: onChangeFolder)
                .staggerIn(animateIn, index: 3)
                .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }
}

private struct FolderSetupHeroPanel: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ChamferedRectangle(corner: 22)
                    .fill(TechnicalPalette.background.opacity(0.72))

                Circle()
                    .fill(TechnicalPalette.faintStroke.opacity(0.64))
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)

                ZStack {
                    Image(systemName: "folder")
                        .font(.system(size: 54, weight: .regular))
                        .foregroundStyle(TechnicalPalette.primaryText.opacity(0.68))
                        .symbolRenderingMode(.monochrome)

                    Capsule()
                        .fill(TechnicalPalette.accent)
                        .frame(width: 44, height: 4)
                        .offset(y: -10)
                }
                .accessibilityHidden(true)

                ChamferedRectangle(corner: 22)
                    .stroke(TechnicalPalette.hairline, lineWidth: 1)

                CornerPlusMarks(width: 156, height: 122)
                    .foregroundStyle(TechnicalPalette.hairline)
            }
            .frame(width: 156, height: 122)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Export folder")

            VStack(spacing: 8) {
                Text("EXPORT FOLDER")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 96)

                Rectangle()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 2, height: 12)
            }
            .accessibilityHidden(true)
        }
    }
}

private struct FolderSuccessHeroPanel: View {
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ChamferedRectangle(corner: 22)
                    .fill(TechnicalPalette.background.opacity(0.72))

                ZStack {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 74, weight: .regular))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "9B6CF2"), Color(hex: "7244D0")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: TechnicalPalette.accent.opacity(0.22), radius: 12, x: 0, y: 8)

                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 74, height: 6)
                        .offset(y: -12)
                }
                .accessibilityHidden(true)

                ChamferedRectangle(corner: 22)
                    .stroke(TechnicalPalette.hairline, lineWidth: 1)

                CornerPlusMarks(width: 158, height: 150)
                    .foregroundStyle(TechnicalPalette.hairline)
            }
            .frame(width: 158, height: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Destination folder ready")

            VStack(spacing: 8) {
                Text("DESTINATION")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 96)

                Rectangle()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 2, height: 12)
            }
            .accessibilityHidden(true)
        }
    }
}

private struct TechnicalSelectedFolderCard: View {
    let folderName: String
    let folderPath: String

    private var statusTitle: String {
        folderName.uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color(hex: "2E9B63"), lineWidth: 1.75)
                    .frame(width: 42, height: 42)

                Image(systemName: "checkmark")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(Color(hex: "2E9B63"))
            }
            .frame(width: 52, height: 54)
            .accessibilityHidden(true)

            VerticalDashedLine()
                .stroke(TechnicalPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 1, height: 58)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(statusTitle)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                Text("Exports will save to \(folderName)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(folderPath)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.72)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                Text("01")
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.accent)
                    .fixedSize()

                DottedGrid(columns: 4, rows: 4, dotSize: 1.35, spacing: 5)
                    .foregroundStyle(TechnicalPalette.secondaryText.opacity(0.5))
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 96)
        .background(
            ChamferedRectangle(corner: 16)
                .fill(TechnicalPalette.background.opacity(0.68))
        )
        .overlay(
            ChamferedRectangle(corner: 16)
                .stroke(TechnicalPalette.hairline, lineWidth: 1)
        )
        .overlay(alignment: .bottomLeading) {
            PlusMark(size: 8)
                .foregroundStyle(TechnicalPalette.hairline)
                .padding(.leading, 18)
                .padding(.bottom, 17)
        }
        .overlay(alignment: .bottomTrailing) {
            PlusMark(size: 8)
                .foregroundStyle(TechnicalPalette.hairline)
                .padding(.trailing, 18)
                .padding(.bottom, 17)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Export folder ready. \(folderName). Exports will save to \(folderPath)")
    }
}

private struct TechnicalChangeFolderButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Change Folder")
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(TechnicalPalette.accent)
                .tracking(0.5)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    HorizontalDashedLine()
                        .stroke(TechnicalPalette.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .frame(height: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change Folder")
    }
}

private struct HorizontalDashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct TechnicalFolderOptionsCard: View {
    private let rows: [(icon: String, title: String, recommended: Bool)] = [
        ("book.closed.fill", "Obsidian Vault", true),
        ("icloud.fill", "iCloud Drive", false),
        ("folder", "On My iPhone", false)
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                TechnicalFolderOptionRow(
                    icon: row.icon,
                    title: row.title,
                    recommended: row.recommended
                )

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(TechnicalPalette.hairline)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            ChamferedRectangle(corner: 16)
                .fill(TechnicalPalette.background.opacity(0.68))
        )
        .overlay(
            ChamferedRectangle(corner: 16)
                .stroke(TechnicalPalette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct TechnicalFolderOptionRow: View {
    let icon: String
    let title: String
    let recommended: Bool

    private var iconColor: Color {
        recommended ? TechnicalPalette.accent : TechnicalPalette.primaryText.opacity(0.65)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 42)
                .accessibilityHidden(true)

            VerticalDashedLine()
                .stroke(TechnicalPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 1, height: 42)
                .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .foregroundStyle(TechnicalPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .layoutPriority(1)

            Spacer(minLength: 4)

            if recommended {
                Text("Recommended")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.accent)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(TechnicalPalette.accent.opacity(0.16))
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .trailing, spacing: 8) {
                DottedGrid(columns: 3, rows: 4, dotSize: 1.55, spacing: 5)
                    .foregroundStyle(TechnicalPalette.secondaryText.opacity(0.58))

                PlusMark(size: 10)
                    .foregroundStyle(TechnicalPalette.secondaryText.opacity(0.58))
            }
            .frame(width: 22)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(minHeight: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recommended ? "\(title), recommended" : title)
    }
}

private struct TechnicalFolderSelectButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 25, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .accessibilityHidden(true)

                Text("Select Folder")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .tracking(0.5)
            }
            .foregroundStyle(TechnicalPalette.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                ChamferedRectangle(corner: 12)
                    .fill(TechnicalPalette.background.opacity(0.46))
            )
            .overlay(
                ChamferedRectangle(corner: 12)
                    .stroke(TechnicalPalette.accent.opacity(0.85), lineWidth: 1.15)
            )
            .overlay(alignment: .topLeading) {
                ButtonCornerTicks()
                    .foregroundStyle(TechnicalPalette.accent.opacity(0.72))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Select Folder")
    }
}

private struct TechnicalContinueHint: View {
    var body: some View {
        HStack(spacing: 12) {
            TechnicalHintBracket(isLeading: true)

            Text("SELECT A FOLDER TO CONTINUE")
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(TechnicalPalette.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            TechnicalHintBracket(isLeading: false)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Select a folder to continue")
    }
}

private struct TechnicalHintBracket: View {
    let isLeading: Bool

    var body: some View {
        Path { path in
            if isLeading {
                path.move(to: CGPoint(x: 12, y: 0))
                path.addLine(to: CGPoint(x: 4, y: 0))
                path.addLine(to: CGPoint(x: 4, y: 7))
                path.move(to: CGPoint(x: 4, y: 11))
                path.addLine(to: CGPoint(x: 4, y: 18))
                path.addLine(to: CGPoint(x: 12, y: 18))
            } else {
                path.move(to: CGPoint(x: 2, y: 0))
                path.addLine(to: CGPoint(x: 10, y: 0))
                path.addLine(to: CGPoint(x: 10, y: 7))
                path.move(to: CGPoint(x: 10, y: 11))
                path.addLine(to: CGPoint(x: 10, y: 18))
                path.addLine(to: CGPoint(x: 2, y: 18))
            }
        }
        .stroke(TechnicalPalette.secondaryText.opacity(0.64), lineWidth: 1)
        .frame(width: 14, height: 18)
        .accessibilityHidden(true)
    }
}

// MARK: - Step 4: Unlock

private struct TechnicalUnlockStep: View {
    @ObservedObject var purchaseManager: PurchaseManager
    let unlockPriceLabel: String
    let animateIn: Bool
    let totalSteps: Int
    let onPurchase: () -> Void
    let onContinueFree: () -> Void
    let onRestore: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Same TechnicalHeader component used by slides 1 and 2; the paywall
            // only overrides the visual step number to display 05 … 06.
            TechnicalHeader(currentStep: 5, totalSteps: totalSteps)
                .staggerIn(animateIn, index: 0)

            TechnicalUnlockHeroPanel()
                .heroEntrance(animateIn)
                .padding(.top, 20)

            VStack(spacing: 8) {
                Text("Unlock Full Access")
                    .font(.system(size: 30, weight: .regular, design: .monospaced))
                    .minimumScaleFactor(0.74)
                    .lineLimit(1)
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .tracking(0.9)
                    .accessibilityAddTraits(.isHeader)

                Capsule()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 38, height: 3)
                    .accessibilityHidden(true)

                Text("A one-time purchase.\nNo subscription.\nAll future updates included.")
                    .font(.system(size: 13.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .staggerIn(animateIn, index: 1)
            .padding(.horizontal, 18)
            .padding(.top, 18)

            TechnicalPaywallBenefitsCard()
                .staggerIn(animateIn, index: 2)
                .padding(.horizontal, 22)
                .padding(.top, 22)

            TechnicalPriceStrip(priceLabel: unlockPriceLabel)
                .staggerIn(animateIn, index: 3)
                .padding(.horizontal, 22)
                .padding(.top, 13)

            if let error = purchaseManager.purchaseError {
                TechnicalPaywallErrorText(error: error)
                    .staggerIn(animateIn, index: 4)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
            }

            TechnicalPrimaryButton(
                title: "UNLOCK FOR \(unlockPriceLabel.uppercased())",
                isLoading: purchaseManager.isPurchasing,
                isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                height: 60,
                titleFontSize: 16,
                titleTracking: 1.9,
                arrowTrailingPadding: 22,
                accessibilityLabel: "Unlock full access for \(unlockPriceLabel)",
                accessibilityHint: purchaseManager.isPurchasing
                    ? "Purchase is in progress"
                    : (purchaseManager.isRestoring ? "Restore is in progress" : ""),
                action: onPurchase
            )
            .overlay(alignment: .leading) {
                VerticalDashedLine()
                    .stroke(TechnicalPalette.secondaryText.opacity(0.58), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .frame(width: 1, height: 34)
                    .offset(x: -10)
                    .accessibilityHidden(true)
            }
            .staggerIn(animateIn, index: 5)
            .padding(.horizontal, 22)
            .padding(.top, 24)

            TechnicalSecondaryButton(
                title: "CONTINUE WITH 3 FREE EXPORTS",
                isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                action: onContinueFree
            )
            .staggerIn(animateIn, index: 6)
            .padding(.horizontal, 22)
            .padding(.top, 14)

            TechnicalRestoreButton(
                isRestoring: purchaseManager.isRestoring,
                isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                action: onRestore
            )
            .staggerIn(animateIn, index: 7)
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 28)
    }
}

private struct TechnicalUnlockHeroPanel: View {
    var body: some View {
        // Reuse the same crystal-heart header/brand component as slides 1 and 2,
        // only scaling it for the paywall composition and using the requested label.
        WelcomeBrandPanel(
            panelWidth: 136,
            panelHeight: 104,
            heartSize: 70,
            label: "HEALTH MD",
            labelHeight: 82,
            corner: 18,
            gridOffset: CGSize(width: 40, height: -30),
            blendsHeartIntoBackground: true
        )
    }
}

private struct TechnicalPaywallBenefitsCard: View {
    private let rows: [(icon: String, title: String, detail: String, index: String)] = [
        (
            icon: "infinity",
            title: "UNLIMITED EXPORTS",
            detail: "Export your health data as often as you need.",
            index: "01"
        ),
        (
            icon: "clock",
            title: "SCHEDULED AUTOMATIC EXPORTS",
            detail: "Set it once. We’ll handle the rest.",
            index: "02"
        ),
        (
            icon: "star",
            title: "ALL FUTURE FEATURES",
            detail: "New tools and capabilities added over time.",
            index: "03"
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                TechnicalPaywallBenefitRow(
                    icon: row.icon,
                    title: row.title,
                    detail: row.detail,
                    index: row.index
                )

                if index < rows.count - 1 {
                    HorizontalDashedLine()
                        .stroke(
                            TechnicalPalette.hairline,
                            style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                        )
                        .frame(height: 1)
                        .padding(.horizontal, 12)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            ChamferedRectangle(corner: 18)
                .fill(TechnicalPalette.background.opacity(0.66))
        )
        .overlay(
            ChamferedRectangle(corner: 18)
                .stroke(TechnicalPalette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

private struct TechnicalPaywallBenefitRow: View {
    let icon: String
    let title: String
    let detail: String
    let index: String

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(TechnicalPalette.primaryText.opacity(0.86), lineWidth: 1.25)
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(TechnicalPalette.accent)
                    .frame(width: 34, height: 34)
            }
            .frame(width: 40, height: 44)
            .accessibilityHidden(true)

            VerticalDashedLine()
                .stroke(TechnicalPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 1, height: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(detail)
                    .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 5) {
                Text(index)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(TechnicalPalette.accent)
                    .fixedSize()

                DottedGrid(columns: 4, rows: 4, dotSize: 1.25, spacing: 3.6)
                    .foregroundStyle(TechnicalPalette.hairline)

                PlusMark(size: 8)
                    .foregroundStyle(TechnicalPalette.hairline)
            }
            .frame(width: 32)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 58)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index). \(title). \(detail)")
    }
}

private struct TechnicalPriceStrip: View {
    let priceLabel: String

    var body: some View {
        HStack(spacing: 12) {
            Text(priceLabel)
                .font(.system(size: 30, weight: .regular, design: .monospaced))
                .foregroundStyle(TechnicalPalette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text("ONCE")
                .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(TechnicalPalette.primaryText.opacity(0.72))

            Spacer(minLength: 8)

            VerticalDashedLine()
                .stroke(TechnicalPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 1, height: 34)
                .accessibilityHidden(true)

            VStack(alignment: .trailing, spacing: 5) {
                DottedGrid(columns: 4, rows: 3, dotSize: 1.35, spacing: 5)
                    .foregroundStyle(TechnicalPalette.hairline)

                PlusMark(size: 8)
                    .foregroundStyle(TechnicalPalette.hairline)
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
            ChamferedRectangle(corner: 15)
                .fill(TechnicalPalette.background.opacity(0.58))
        )
        .overlay(
            ChamferedRectangle(corner: 15)
                .stroke(TechnicalPalette.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(priceLabel) once")
    }
}

private struct TechnicalSecondaryButton: View {
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .tracking(1.15)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
            }
            .foregroundStyle(TechnicalPalette.accent.opacity(isDisabled ? 0.48 : 1))
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                ChamferedRectangle(corner: 12)
                    .fill(TechnicalPalette.background.opacity(isDisabled ? 0.36 : 0.58))
            )
            .overlay(
                ChamferedRectangle(corner: 12)
                    .stroke(TechnicalPalette.hairline.opacity(isDisabled ? 0.55 : 1), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                ButtonCornerTicks()
                    .foregroundStyle(TechnicalPalette.hairline.opacity(isDisabled ? 0.38 : 0.86))
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(title.capitalized)
    }
}

private struct TechnicalRestoreButton: View {
    let isRestoring: Bool
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                TechnicalHintBracket(isLeading: true)

                if isRestoring {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(TechnicalPalette.secondaryText)
                }

                Text("RESTORE PURCHASE")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(1)

                TechnicalHintBracket(isLeading: false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .opacity(isDisabled && !isRestoring ? 0.52 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Restore purchase")
    }
}

private struct TechnicalPaywallErrorText: View {
    let error: String

    private var color: Color {
        error.contains("cody@isolated.tech")
            ? TechnicalPalette.secondaryText
            : Color.error
    }

    var body: some View {
        Text(error)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                ChamferedRectangle(corner: 10)
                    .fill(TechnicalPalette.background.opacity(0.58))
            )
            .overlay(
                ChamferedRectangle(corner: 10)
                    .stroke(TechnicalPalette.hairline, lineWidth: 1)
            )
    }
}

// MARK: - Step 6: Ready

private struct TechnicalReadyStep: View {
    let healthAuthorized: Bool
    let folderSelected: Bool
    let folderName: String
    let animateIn: Bool

    var body: some View {
        VStack(spacing: 0) {
            TechnicalCompletionHeader()
                .staggerIn(animateIn, index: 0)

            CompletionHeroPanel()
                .heroEntrance(animateIn)
                .padding(.top, 14)

            CompletionTitleBlock()
                .staggerIn(animateIn, index: 1)
                .padding(.top, 12)

            CompletionStatusCard(
                healthAuthorized: healthAuthorized,
                folderSelected: folderSelected,
                folderName: folderName
            )
            .staggerIn(animateIn, index: 2)
            .padding(.horizontal, 10)
            .padding(.top, 18)
        }
        .padding(.horizontal, 24)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

private struct TechnicalCompletionHeader: View {
    var body: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top) {
                CrosshairMark()
                    .frame(width: 36, height: 36)
                    .frame(width: 76, alignment: .leading)
                    .accessibilityHidden(true)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("ONBOARDING")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(TechnicalPalette.primaryText.opacity(0.7))

                    Text(OnboardingVersionLabel.current)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(TechnicalPalette.secondaryText)

                    Rectangle()
                        .fill(TechnicalPalette.accent)
                        .frame(width: 12, height: 2)
                        .padding(.top, 2)
                }
                .frame(width: 76, alignment: .trailing)
                .accessibilityHidden(true)
            }

            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    Text("STEP ")
                        .tracking(2.2)
                        .foregroundStyle(TechnicalPalette.primaryText.opacity(0.72))
                    Text("06")
                        .tracking(2.2)
                        .foregroundStyle(TechnicalPalette.accent)
                    Text(" OF ")
                        .tracking(2.2)
                        .foregroundStyle(TechnicalPalette.primaryText.opacity(0.72))
                    Text("06")
                        .tracking(2.2)
                        .foregroundStyle(TechnicalPalette.accent)
                }
                .font(.system(size: 16, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityLabel("Step 6 of 6")

                HStack(spacing: 5) {
                    ForEach(0..<6, id: \.self) { _ in
                        Rectangle()
                            .fill(TechnicalPalette.accent)
                            .frame(width: 26, height: 2)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(.top, 7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
    }
}

private struct CompletionHeroPanel: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                HStack {
                    DottedGrid(columns: 4, rows: 6, dotSize: 1.45, spacing: 8)
                        .foregroundStyle(TechnicalPalette.hairline)
                        .opacity(0.86)

                    Spacer(minLength: 0)

                    DottedGrid(columns: 4, rows: 6, dotSize: 1.45, spacing: 8)
                        .foregroundStyle(TechnicalPalette.hairline)
                        .opacity(0.86)
                }
                .frame(width: 264)
                .accessibilityHidden(true)

                CompletionHeroBrackets()
                    .frame(width: 248, height: 174)
                    .accessibilityHidden(true)

                ZStack {
                    ChamferedRectangle(corner: 24)
                        .fill(TechnicalPalette.background.opacity(0.72))

                    CompletionCheckIcon(strokeWidth: 3.4)
                        .frame(width: 80, height: 80)
                        .accessibilityHidden(true)

                    ChamferedRectangle(corner: 24)
                        .stroke(TechnicalPalette.hairline, lineWidth: 1)

                    CornerPlusMarks(width: 156, height: 148)
                        .foregroundStyle(TechnicalPalette.hairline)
                }
                .frame(width: 156, height: 148)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 174)

            CompletionCompleteLabel()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Onboarding complete")
    }
}

private struct CompletionHeroBrackets: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CompletionCornerBracket(position: .topLeading)
                    .stroke(TechnicalPalette.accent, lineWidth: 2)
                    .frame(width: 13, height: 13)
                    .position(x: 6.5, y: 6.5)

                CompletionCornerBracket(position: .topTrailing)
                    .stroke(TechnicalPalette.accent, lineWidth: 2)
                    .frame(width: 13, height: 13)
                    .position(x: proxy.size.width - 6.5, y: 6.5)

                CompletionCornerBracket(position: .bottomLeading)
                    .stroke(TechnicalPalette.accent, lineWidth: 2)
                    .frame(width: 13, height: 13)
                    .position(x: 6.5, y: proxy.size.height - 6.5)

                CompletionCornerBracket(position: .bottomTrailing)
                    .stroke(TechnicalPalette.accent, lineWidth: 2)
                    .frame(width: 13, height: 13)
                    .position(x: proxy.size.width - 6.5, y: proxy.size.height - 6.5)
            }
        }
    }
}

private enum CompletionCornerPosition {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

private struct CompletionCornerBracket: Shape {
    let position: CompletionCornerPosition

    func path(in rect: CGRect) -> Path {
        var path = Path()

        switch position {
        case .topLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        case .topTrailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomLeading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottomTrailing:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }

        return path
    }
}

private struct CompletionCheckIcon: View {
    var strokeWidth: CGFloat = 3.2

    var body: some View {
        ZStack {
            CompletionOctagon()
                .stroke(
                    TechnicalPalette.accent,
                    style: StrokeStyle(lineWidth: strokeWidth, lineJoin: .round)
                )

            CompletionCheckmarkShape()
                .stroke(
                    TechnicalPalette.accent,
                    style: StrokeStyle(lineWidth: strokeWidth * 1.08, lineCap: .round, lineJoin: .round)
                )
        }
    }
}

private struct CompletionOctagon: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.18
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + inset))
        path.closeSubpath()
        return path
    }
}

private struct CompletionCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.27, y: rect.minY + rect.height * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.70))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.36))
        return path
    }
}

private struct CompletionCompleteLabel: View {
    var body: some View {
        HStack(spacing: 14) {
            Rectangle()
                .fill(TechnicalPalette.accent)
                .frame(width: 22, height: 2)

            Text("COMPLETE")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .tracking(2)
                .foregroundStyle(TechnicalPalette.accent)

            Rectangle()
                .fill(TechnicalPalette.accent)
                .frame(width: 22, height: 2)
        }
        .accessibilityHidden(true)
    }
}

private struct CompletionTitleBlock: View {
    var body: some View {
        VStack(spacing: 11) {
            Text("You’re All Set")
                .font(.system(size: 38, weight: .regular, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(TechnicalPalette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .accessibilityAddTraits(.isHeader)

            Capsule()
                .fill(TechnicalPalette.accent)
                .frame(width: 38, height: 3)
                .padding(.top, 2)
                .accessibilityHidden(true)

            Text("Health.md is ready to\nexport your wellness data.")
                .font(.system(size: 17, weight: .regular, design: .monospaced))
                .foregroundStyle(TechnicalPalette.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)

            Text("Your data stays private, local,\nand under your control.")
                .font(.system(size: 13.5, weight: .regular, design: .monospaced))
                .foregroundStyle(TechnicalPalette.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CompletionStatusCard: View {
    let healthAuthorized: Bool
    let folderSelected: Bool
    let folderName: String

    private var healthStatusText: String {
        healthAuthorized ? "Connected" : "Can connect later"
    }

    private var folderStatusText: String {
        guard folderSelected else { return "Not selected" }

        let trimmedName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "File Provider selected" : trimmedName
    }

    var body: some View {
        VStack(spacing: 0) {
            CompletionStatusRow(
                icon: "heart",
                title: "HEALTH DATA",
                statusText: healthStatusText,
                isComplete: healthAuthorized
            )

            HorizontalDashedLine()
                .stroke(TechnicalPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
                .padding(.horizontal, 12)
                .accessibilityHidden(true)

            CompletionStatusRow(
                icon: "folder",
                title: "EXPORT FOLDER",
                statusText: folderStatusText,
                isComplete: folderSelected
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            ChamferedRectangle(corner: 18)
                .fill(TechnicalPalette.background.opacity(0.68))
        )
        .overlay(
            ChamferedRectangle(corner: 18)
                .stroke(TechnicalPalette.hairline, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            PlusMark(size: 7)
                .foregroundStyle(TechnicalPalette.hairline)
                .padding(.leading, 18)
                .padding(.top, 18)
        }
        .overlay(alignment: .bottomTrailing) {
            PlusMark(size: 7)
                .foregroundStyle(TechnicalPalette.hairline)
                .padding(.trailing, 18)
                .padding(.bottom, 18)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct CompletionStatusRow: View {
    let icon: String
    let title: String
    let statusText: String
    let isComplete: Bool

    var body: some View {
        HStack(spacing: 13) {
            CompletionStatusIcon(systemName: icon)
                .accessibilityHidden(true)

            VerticalDashedLine()
                .stroke(TechnicalPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 1, height: 50)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 16, weight: .regular, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(TechnicalPalette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(statusText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(isComplete ? TechnicalPalette.accent : TechnicalPalette.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .minimumScaleFactor(0.7)
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            VStack(spacing: 7) {
                CompletionStatusIndicator(isComplete: isComplete)
                    .frame(width: 22, height: 22)

                DottedGrid(columns: 4, rows: 3, dotSize: 1.35, spacing: 4)
                    .foregroundStyle(TechnicalPalette.hairline)
            }
            .frame(width: 30)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 8)
        .frame(minHeight: 66)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(statusText)")
    }
}

private struct CompletionStatusIcon: View {
    let systemName: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TechnicalPalette.primaryText.opacity(0.88), lineWidth: 1.25)
                .frame(width: 38, height: 38)

            Image(systemName: systemName)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(TechnicalPalette.primaryText)
                .frame(width: 38, height: 38)

            Circle()
                .fill(TechnicalPalette.accent)
                .frame(width: 8, height: 8)
                .offset(x: 3, y: 3)
        }
        .frame(width: 44, height: 44)
    }
}

private struct CompletionStatusIndicator: View {
    let isComplete: Bool

    var body: some View {
        ZStack {
            if isComplete {
                CompletionCheckIcon(strokeWidth: 1.45)
                    .foregroundStyle(TechnicalPalette.accent)
            } else {
                Circle()
                    .stroke(TechnicalPalette.hairline, lineWidth: 1.25)

                Circle()
                    .fill(TechnicalPalette.hairline)
                    .frame(width: 4, height: 4)
            }
        }
    }
}

// MARK: - Supporting Components

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    @ScaledMetric(relativeTo: .body) private var iconContainerSize: CGFloat = 40

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.accent)
                .frame(width: iconContainerSize, height: iconContainerSize)
                .background(
                    Circle()
                        .fill(Color.accentSubtle)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }
}

private struct DataCategoryRow: View {
    let icon: String
    let label: String
    let detail: String
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accent)
                .frame(width: iconWidth)

            Text(label)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Text(detail)
                .font(Typography.caption())
                .foregroundStyle(Color.textMuted)
        }
        .padding(.vertical, 4)
    }
}

private struct SuggestionRow: View {
    let icon: String
    let label: String
    let recommended: Bool
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(recommended ? Color.accent : Color.textSecondary)
                .frame(width: iconWidth)

            Text(label)
                .font(Typography.body())
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if recommended {
                Text("Recommended")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.accentSubtle)
                    )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SetupSummaryRow: View {
    let icon: String
    let label: String
    let status: String
    let isComplete: Bool
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(isComplete ? Color.accent : Color.textMuted)
                .frame(width: iconWidth)

            Text(label)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.textPrimary)

            Spacer()

            HStack(spacing: 6) {
                Text(status)
                    .font(Typography.caption())
                    .foregroundStyle(isComplete ? Color.success : Color.textMuted)

                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.footnote)
                    .foregroundStyle(isComplete ? Color.success : Color.textMuted)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}
