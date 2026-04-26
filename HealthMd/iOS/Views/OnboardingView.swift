import SwiftUI
import StoreKit

// MARK: - Onboarding Flow

struct OnboardingView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
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
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressBar(current: currentStep, total: totalSteps)
                    .padding(.top, Spacing.md)
                    .padding(.horizontal, Spacing.xl)

                Spacer()

                // Step content with directional slide
                ZStack {
                    switch currentStep {
                    case 0:
                        WelcomeStep(animateIn: animateIn)
                            .transition(stepTransition)
                    case 1:
                        HealthAccessStep(
                            isAuthorized: healthKitManager.isAuthorized,
                            animateIn: animateIn,
                            onRequestAccess: {
                                Task {
                                    try? await healthKitManager.requestAuthorization()
                                }
                            }
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
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentStep)

                Spacer()

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
                    } else {
                        PrimaryButton(
                            currentStep == totalSteps - 1 ? "Get Started" : "Continue",
                            icon: currentStep == totalSteps - 1 ? "arrow.right" : "chevron.right",
                            isDisabled: !canAdvance,
                            action: advance
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: animateIn)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation {
                    animateIn = true
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
        .asymmetric(
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                currentStep = nextStep
            }
            // Trigger stagger animations for the new step
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation {
                    animateIn = true
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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Color.accent : Color.borderDefault)
                    .frame(width: index == current ? 32 : nil, height: 3)
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

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // App icon
            ZStack {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .blur(radius: 30)
                    .breathingGlow()
                    .accessibilityHidden(true)

                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.accent.opacity(0.4), radius: 24, x: 0, y: 12)
            }
            .heroEntrance(animateIn)

            VStack(spacing: Spacing.sm) {
                Text("Health.md")
                    .font(Typography.hero())
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)
                    .tracking(2)

                Text("Your health data,\nyour way")
                    .font(Typography.displayMedium())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .staggerIn(animateIn, index: 1)

            // Feature highlights
            VStack(spacing: Spacing.md) {
                FeatureRow(
                    icon: "heart.text.clipboard",
                    title: "Export Health Data",
                    description: "Markdown, CSV, or JSON"
                )
                .staggerIn(animateIn, index: 2)

                FeatureRow(
                    icon: "calendar.badge.clock",
                    title: "Automatic Scheduling",
                    description: "Set it and forget it"
                )
                .staggerIn(animateIn, index: 3)

                FeatureRow(
                    icon: "lock.shield",
                    title: "Private & Local",
                    description: "Data never leaves your devices"
                )
                .staggerIn(animateIn, index: 4)
            }
            .padding(.top, Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Step 2: Health Access

private struct HealthAccessStep: View {
    let isAuthorized: Bool
    let animateIn: Bool
    let onRequestAccess: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Icon
            ZStack {
                if isAuthorized {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(Color.accent)
                        .blur(radius: 20)
                        .breathingGlow()
                        .accessibilityHidden(true)
                }

                Image(systemName: isAuthorized ? "heart.fill" : "heart")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(isAuthorized ? Color.accent : Color.textMuted)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 100, height: 100)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
            )
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: isAuthorized ? Color.accent.opacity(0.3) : .clear, radius: 20, x: 0, y: 10)
            .heroEntrance(animateIn)

            VStack(spacing: Spacing.sm) {
                Text("Health Data Access")
                    .font(Typography.displayMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)

                Text("Health.md reads your Apple Health data so it can export it to files you own. Nothing is uploaded or shared.")
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, Spacing.md)
            }
            .staggerIn(animateIn, index: 1)

            // Data categories preview
            VStack(spacing: Spacing.sm) {
                DataCategoryRow(icon: "bed.double.fill", label: "Sleep", detail: "Duration, stages, timing")
                    .staggerIn(animateIn, index: 2)
                DataCategoryRow(icon: "figure.walk", label: "Activity", detail: "Steps, calories, workouts")
                    .staggerIn(animateIn, index: 3)
                DataCategoryRow(icon: "heart.fill", label: "Heart", detail: "Heart rate, HRV, blood pressure")
                    .staggerIn(animateIn, index: 4)
                DataCategoryRow(icon: "lungs.fill", label: "Vitals", detail: "Respiratory rate, SpO2, temperature")
                    .staggerIn(animateIn, index: 5)
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

            if isAuthorized {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                    Text("Access granted")
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.success)
                }
                .transition(.scale.combined(with: .opacity))
                .padding(.top, Spacing.sm)
            } else {
                Button(action: onRequestAccess) {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 18))
                        Text("Grant Access")
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
                .staggerIn(animateIn, index: 6)
                .padding(.top, Spacing.sm)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isAuthorized)
    }
}

// MARK: - Step 3: Folder Setup

private struct FolderSetupStep: View {
    @ObservedObject var vaultManager: VaultManager
    let animateIn: Bool
    let onPickFolder: () -> Void

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Icon
            ZStack {
                if vaultManager.vaultURL != nil {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(Color.accent)
                        .blur(radius: 20)
                        .breathingGlow()
                        .accessibilityHidden(true)
                }

                Image(systemName: vaultManager.vaultURL != nil ? "folder.fill" : "folder")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(vaultManager.vaultURL != nil ? Color.accent : Color.textMuted)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 100, height: 100)
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
                            .font(.system(size: 20))
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
                                .font(.system(size: 18))
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

    private var priceLabel: String {
        purchaseManager.product?.displayPrice ?? "$9.99"
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Hero icon
            ZStack {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .blur(radius: 20)
                    .breathingGlow()
                    .accessibilityHidden(true)

                Image(systemName: "lock.open.fill")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(Color.accent)
            }
            .frame(width: 100, height: 100)
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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 28)

            Text(text)
                .font(Typography.body())
                .foregroundStyle(Color.textPrimary)

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

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Checkmark icon with celebration bounce
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.success)
                    .blur(radius: 20)
                    .breathingGlow()
                    .accessibilityHidden(true)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.success)
            }
            .frame(width: 100, height: 100)
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

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.accentSubtle)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.textPrimary)

                Text(description)
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
    }
}

private struct DataCategoryRow: View {
    let icon: String
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.accent)
                .frame(width: 28)

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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(recommended ? Color.accent : Color.textSecondary)
                .frame(width: 28)

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

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isComplete ? Color.accent : Color.textMuted)
                .frame(width: 28)

            Text(label)
                .font(Typography.bodyEmphasis())
                .foregroundStyle(Color.textPrimary)

            Spacer()

            HStack(spacing: 6) {
                Text(status)
                    .font(Typography.caption())
                    .foregroundStyle(isComplete ? Color.success : Color.textMuted)

                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isComplete ? Color.success : Color.textMuted)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}
