import SwiftUI

// MARK: - Onboarding Flow

struct OnboardingView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @Binding var showFolderPicker: Bool
    @ObservedObject var vaultManager: VaultManager
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var healthAuthorized = false
    @State private var animateIn = false

    private let totalSteps = 4

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressBar(current: currentStep, total: totalSteps)
                    .padding(.top, Spacing.md)
                    .padding(.horizontal, Spacing.xl)

                Spacer()

                // Step content
                Group {
                    switch currentStep {
                    case 0:
                        WelcomeStep()
                    case 1:
                        HealthAccessStep(
                            isAuthorized: healthKitManager.isAuthorized,
                            onRequestAccess: {
                                Task {
                                    try? await healthKitManager.requestAuthorization()
                                }
                            }
                        )
                    case 2:
                        FolderSetupStep(
                            vaultManager: vaultManager,
                            onPickFolder: { showFolderPicker = true }
                        )
                    case 3:
                        ReadyStep(
                            healthAuthorized: healthKitManager.isAuthorized,
                            folderSelected: vaultManager.vaultURL != nil,
                            folderName: vaultManager.vaultName
                        )
                    default:
                        EmptyView()
                    }
                }
                .opacity(animateIn ? 1 : 0)
                .offset(y: animateIn ? 0 : 20)

                Spacer()

                // Navigation buttons
                VStack(spacing: Spacing.md) {
                    PrimaryButton(
                        currentStep == totalSteps - 1 ? "Get Started" : "Continue",
                        icon: currentStep == totalSteps - 1 ? "arrow.right" : "chevron.right",
                        action: advance
                    )

                    if currentStep > 0 && currentStep < totalSteps - 1 {
                        Button("Skip") {
                            advance()
                        }
                        .font(Typography.body())
                        .foregroundStyle(Color.textMuted)
                        .padding(.bottom, Spacing.xs)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(AnimationTimings.smooth) {
                animateIn = true
            }
        }
    }

    private func advance() {
        if currentStep >= totalSteps - 1 {
            onComplete()
            return
        }

        withAnimation(AnimationTimings.smooth) {
            animateIn = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            currentStep += 1
            withAnimation(AnimationTimings.smooth) {
                animateIn = true
            }
        }
    }
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
                    .frame(height: 3)
                    .animation(AnimationTimings.standard, value: current)
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: Spacing.lg) {
            // App icon
            ZStack {
                Image("AppIconImage")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .blur(radius: 30)
                    .opacity(0.5)
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

            // Feature highlights
            VStack(spacing: Spacing.md) {
                FeatureRow(
                    icon: "heart.text.clipboard",
                    title: "Export Health Data",
                    description: "Markdown, CSV, or JSON"
                )
                FeatureRow(
                    icon: "calendar.badge.clock",
                    title: "Automatic Scheduling",
                    description: "Set it and forget it"
                )
                FeatureRow(
                    icon: "lock.shield",
                    title: "Private & Local",
                    description: "Data never leaves your devices"
                )
            }
            .padding(.top, Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Step 2: Health Access

private struct HealthAccessStep: View {
    let isAuthorized: Bool
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
                        .opacity(0.5)
                        .accessibilityHidden(true)
                }

                Image(systemName: isAuthorized ? "heart.fill" : "heart")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(isAuthorized ? Color.accent : Color.textMuted)
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

            // Data categories preview
            VStack(spacing: Spacing.sm) {
                DataCategoryRow(icon: "bed.double.fill", label: "Sleep", detail: "Duration, stages, timing")
                DataCategoryRow(icon: "figure.walk", label: "Activity", detail: "Steps, calories, workouts")
                DataCategoryRow(icon: "heart.fill", label: "Heart", detail: "Heart rate, HRV, blood pressure")
                DataCategoryRow(icon: "lungs.fill", label: "Vitals", detail: "Respiratory rate, SpO2, temperature")
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
                .padding(.top, Spacing.sm)
            }
        }
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Step 3: Folder Setup

private struct FolderSetupStep: View {
    @ObservedObject var vaultManager: VaultManager
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
                        .opacity(0.5)
                        .accessibilityHidden(true)
                }

                Image(systemName: vaultManager.vaultURL != nil ? "folder.fill" : "folder")
                    .font(.system(size: 52, weight: .medium))
                    .foregroundStyle(vaultManager.vaultURL != nil ? Color.accent : Color.textMuted)
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

            // Folder status card
            VStack(spacing: Spacing.md) {
                if let url = vaultManager.vaultURL {
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

                    Button(action: onPickFolder) {
                        Text("Change Folder")
                            .font(Typography.bodyEmphasis())
                            .foregroundStyle(Color.accent)
                    }
                } else {
                    // Suggested locations
                    VStack(spacing: Spacing.sm) {
                        SuggestionRow(icon: "book.closed.fill", label: "Obsidian Vault", recommended: true)
                        SuggestionRow(icon: "icloud.fill", label: "iCloud Drive", recommended: false)
                        SuggestionRow(icon: "folder.fill", label: "On My iPhone", recommended: false)
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
                    .padding(.top, Spacing.xs)
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .padding(.horizontal, Spacing.lg)
    }
}

// MARK: - Step 4: Ready

private struct ReadyStep: View {
    let healthAuthorized: Bool
    let folderSelected: Bool
    let folderName: String

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Checkmark icon
            ZStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.success)
                    .blur(radius: 20)
                    .opacity(0.5)
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

            // Setup summary
            VStack(spacing: 0) {
                SetupSummaryRow(
                    icon: "heart.fill",
                    label: "Health Data",
                    status: healthAuthorized ? "Connected" : "Not connected",
                    isComplete: healthAuthorized
                )

                Divider()
                    .background(Color.borderSubtle)

                SetupSummaryRow(
                    icon: "folder.fill",
                    label: "Export Folder",
                    status: folderSelected ? folderName : "Not selected",
                    isComplete: folderSelected
                )
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
            }
        }
        .padding(.horizontal, Spacing.lg)
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
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}
