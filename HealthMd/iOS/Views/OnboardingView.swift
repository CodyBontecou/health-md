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
            if currentStep == 0 || currentStep == 1 {
                TechnicalBackground()
                    .transition(.opacity)
            } else {
                Color.bgPrimary.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                // Progress indicator: the welcome step uses its own technical header.
                if currentStep != 0 && currentStep != 1 {
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
                                onPickFolder: { showFolderPicker = true }
                            )
                            .transition(stepTransition)
                        case 3:
                            UnlockStep(
                                purchaseManager: purchaseManager,
                                animateIn: animateIn
                            )
                            .transition(stepTransition)
                        case 4:
                            ReadyStep(
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
                    .padding(.vertical, currentStep == 0 || currentStep == 1 ? Spacing.xs : Spacing.lg)
                }
                .scrollIndicators(currentStep == 0 || currentStep == 1 ? .hidden : .automatic)
                .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85), value: currentStep)

                // Navigation buttons
                VStack(spacing: Spacing.md) {
                    if currentStep == unlockStepIndex {
                        if let error = purchaseManager.purchaseError {
                            Text(error)
                                .font(Typography.caption())
                                .foregroundStyle(
                                    error.contains("cody@isolated.tech")
                                        ? Color.textMuted
                                        : Color.error
                                )
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Spacing.md)
                        }

                        PrimaryButton(
                            "Unlock for \(unlockPriceLabel)",
                            icon: "lock.open.fill",
                            isLoading: purchaseManager.isPurchasing,
                            isDisabled: purchaseManager.isPurchasing || purchaseManager.isRestoring,
                            action: {
                                Task { await purchaseManager.purchase() }
                            }
                        )

                        Button("Continue with 3 free exports") {
                            advance()
                        }
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textSecondary)
                        .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)

                        Button {
                            Task { await purchaseManager.restore() }
                        } label: {
                            HStack(spacing: 6) {
                                if purchaseManager.isRestoring {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(Color.textMuted)
                                }
                                Text("Restore Purchase")
                                    .font(Typography.caption())
                                    .foregroundStyle(Color.textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
                    } else if currentStep == 0 {
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
                    } else {
                        PrimaryButton(
                            currentStep == totalSteps - 1 ? "Get Started" : "Continue",
                            icon: currentStep == totalSteps - 1 ? "arrow.right" : "chevron.right",
                            isDisabled: !canAdvance,
                            action: advance
                        )
                    }
                }
                .padding(.horizontal, currentStep == 0 || currentStep == 1 ? 44 : Spacing.lg)
                .padding(.bottom, currentStep == 0 || currentStep == 1 ? 20 : Spacing.xl)
                .opacity(animateIn ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (animateIn ? 0 : 12))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.3), value: animateIn)
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

                Text("v1.0")
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
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                ChamferedRectangle(corner: 20)
                    .fill(TechnicalPalette.background.opacity(0.8))

                DottedGrid(columns: 5, rows: 4, dotSize: 1.15, spacing: 8)
                    .foregroundStyle(TechnicalPalette.faintStroke)
                    .offset(x: 46, y: -34)
                    .accessibilityHidden(true)

                Image("HealthCrystalHeart")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 78, height: 78)
                    .accessibilityLabel("Health.md crystal heart logo")

                ChamferedRectangle(corner: 20)
                    .stroke(TechnicalPalette.hairline, lineWidth: 1)

                CornerPlusMarks(width: 158, height: 108)
                    .foregroundStyle(TechnicalPalette.hairline)
            }
            .frame(width: 158, height: 108)
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                Text("HEALTH.MD")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(TechnicalPalette.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 16, height: 76)

                Rectangle()
                    .fill(TechnicalPalette.accent)
                    .frame(width: 2, height: 12)
            }
            .accessibilityHidden(true)
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
    var showsArrow: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text("CONTINUE")
                    .font(.system(size: 18, weight: .regular, design: .monospaced))
                    .tracking(2.2)

                if showsArrow {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 26, weight: .light))
                            .padding(.trailing, 24)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                ChamferedRectangle(corner: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "8A5BE4"), Color(hex: "8050DB")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                ChamferedRectangle(corner: 12)
                    .stroke(Color(hex: "6F43D2").opacity(0.5), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                ButtonCornerTicks()
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue")
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
    let onPickFolder: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconContainerSize: CGFloat = 100

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Icon
            ZStack {
                if vaultManager.vaultURL != nil {
                    Image(systemName: "folder.fill")
                        .accessibilityHidden(true)
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(Color.accent)
                        .blur(radius: 20)
                        .breathingGlow()
                        .accessibilityHidden(true)
                }

                Image(systemName: vaultManager.vaultURL != nil ? "folder.fill" : "folder")
                    .accessibilityHidden(true)
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(vaultManager.vaultURL != nil ? Color.accent : Color.textMuted)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: heroIconContainerSize, height: heroIconContainerSize)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
            )
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: vaultManager.vaultURL != nil ? Color.accent.opacity(0.3) : .clear, radius: 20, x: 0, y: 10)
            .heroEntrance(animateIn)

            VStack(spacing: Spacing.sm) {
                Text("Choose Export Folder")
                    .font(Typography.displayMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("Pick a folder where your health data will be saved. This can be an Obsidian vault, iCloud Drive, or any folder on your device.")
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.md)
            }
            .staggerIn(animateIn, index: 1)

            // Folder status card
            VStack(spacing: Spacing.md) {
                if vaultManager.vaultURL != nil {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .accessibilityHidden(true)
                            .font(.title3)
                            .foregroundStyle(Color.success)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(vaultManager.vaultName)
                                .font(Typography.bodyEmphasis())
                                .foregroundStyle(Color.textPrimary)

                            Text("Exports will save to \(vaultManager.vaultName)/\(vaultManager.healthSubfolder)")
                                .font(Typography.caption())
                                .foregroundStyle(Color.textSecondary)
                        }

                        Spacer()
                    }
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.success.opacity(0.3), lineWidth: 1)
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))

                    Button(action: onPickFolder) {
                        Text("Change Folder")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.accent)
                    }
                } else {
                    // Suggested locations
                    VStack(spacing: Spacing.sm) {
                        SuggestionRow(icon: "book.closed.fill", label: "Obsidian Vault", recommended: true)
                            .staggerIn(animateIn, index: 2)
                        SuggestionRow(icon: "icloud.fill", label: "iCloud Drive", recommended: false)
                            .staggerIn(animateIn, index: 3)
                        SuggestionRow(icon: "folder.fill", label: "On My iPhone", recommended: false)
                            .staggerIn(animateIn, index: 4)
                    }
                    .padding(.vertical, Spacing.md)
                    .padding(.horizontal, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )

                    Button(action: onPickFolder) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title3)
                            Text("Select Folder")
                                .font(Typography.bodyEmphasis())
                        }
                        .foregroundStyle(Color.accent)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            Capsule()
                                .fill(Color.accentSubtle)
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.accent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .staggerIn(animateIn, index: 5)
                    .padding(.top, Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: vaultManager.vaultURL != nil)
        }
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Step 4: Unlock

private struct UnlockStep: View {
    @ObservedObject var purchaseManager: PurchaseManager
    let animateIn: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconContainerSize: CGFloat = 100

    private var priceLabel: String {
        purchaseManager.product?.displayPrice ?? "$9.99"
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Hero icon
            ZStack {
                Image(systemName: "lock.open.fill")
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Color.accent)
                    .blur(radius: 20)
                    .breathingGlow()
                    .accessibilityHidden(true)

                Image(systemName: "lock.open.fill")
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: heroIconContainerSize, height: heroIconContainerSize)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
            )
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.accent.opacity(0.3), radius: 20, x: 0, y: 10)
            .heroEntrance(animateIn)

            VStack(spacing: Spacing.sm) {
                Text("Unlock Full Access")
                    .font(Typography.displayMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("One-time purchase. No subscription.\nAll future updates included.")
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.md)
            }
            .staggerIn(animateIn, index: 1)

            // Feature highlights
            VStack(spacing: Spacing.sm) {
                UnlockFeatureRow(icon: "arrow.up.doc.fill", text: "Unlimited exports")
                    .staggerIn(animateIn, index: 2)
                UnlockFeatureRow(icon: "calendar.badge.clock", text: "Scheduled automatic exports")
                    .staggerIn(animateIn, index: 3)
                UnlockFeatureRow(icon: "checkmark.seal.fill", text: "All future features included")
                    .staggerIn(animateIn, index: 4)
            }
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, Spacing.sm)

            // Price headline
            HStack(spacing: 6) {
                Text(priceLabel)
                    .font(Typography.displayMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)
                Text("once")
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
            }
            .staggerIn(animateIn, index: 5)
        }
        .padding(.horizontal, Spacing.lg)
    }
}

private struct UnlockFeatureRow: View {
    let icon: String
    let text: String
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.accent)
                .frame(width: iconWidth)

            Text(text)
                .font(Typography.body())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Step 5: Ready

private struct ReadyStep: View {
    let healthAuthorized: Bool
    let folderSelected: Bool
    let folderName: String
    let animateIn: Bool

    @State private var celebrationBounce = false
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconContainerSize: CGFloat = 100

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Checkmark icon with celebration bounce
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Color.success)
                    .blur(radius: 20)
                    .breathingGlow()
                    .accessibilityHidden(true)

                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle.weight(.medium))
                    .foregroundStyle(Color.success)
            }
            .frame(width: heroIconContainerSize, height: heroIconContainerSize)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
            )
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.success.opacity(0.3), radius: 20, x: 0, y: 10)
            .scaleEffect(celebrationBounce ? 1.0 : 0.0)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.5),
                value: celebrationBounce
            )

            VStack(spacing: Spacing.sm) {
                Text("You're All Set")
                    .font(Typography.displayMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("Health.md is ready to export your wellness data")
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .staggerIn(animateIn, index: 1)

            // Setup summary
            VStack(spacing: 0) {
                SetupSummaryRow(
                    icon: "heart.fill",
                    label: "Health Data",
                    status: healthAuthorized ? "Connected" : "Not connected",
                    isComplete: healthAuthorized
                )
                .staggerIn(animateIn, index: 2)

                Divider()
                    .background(Color.borderSubtle)

                SetupSummaryRow(
                    icon: "folder.fill",
                    label: "Export Folder",
                    status: folderSelected ? folderName : "Not selected",
                    isComplete: folderSelected
                )
                .staggerIn(animateIn, index: 3)
            }
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, Spacing.sm)

            if !healthAuthorized || !folderSelected {
                Text("You can configure these anytime in Settings")
                    .font(Typography.caption())
                    .foregroundStyle(Color.textMuted)
                    .staggerIn(animateIn, index: 4)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .onAppear {
            // Delay the celebration bounce slightly for dramatic effect
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                celebrationBounce = true
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
