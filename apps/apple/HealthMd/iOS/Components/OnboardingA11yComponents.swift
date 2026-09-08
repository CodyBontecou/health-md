#if os(iOS)
import SwiftUI

// Display-only components shared by the live setup/purchase screens and isolated
// accessibility tests. Callers continue to own all permissions, billing and state.
private struct OnboardingReadingLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

private struct OnboardingPreviewHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 280
}

extension EnvironmentValues {
    var onboardingReadingLayout: Bool {
        get { self[OnboardingReadingLayoutKey.self] }
        set { self[OnboardingReadingLayoutKey.self] = newValue }
    }

    var onboardingPreviewHeight: CGFloat {
        get { self[OnboardingPreviewHeightKey.self] }
        set { self[OnboardingPreviewHeightKey.self] = newValue }
    }
}

enum OnboardingReadingLayout {
    static func isNeeded(size: CGSize, textSize: DynamicTypeSize) -> Bool {
        textSize >= .xLarge || size.width < 375 || size.height < 500
    }
}

/// Keep the same content subtree when the viewport/text size changes, so local
/// selection state survives reflow. Only stateless navigation/actions move into
/// the scroll at crowded sizes; they cannot consume the whole reading viewport.
struct OnboardingPageLayout<Header: View, Content: View, Footer: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    var pageID: Int? = nil
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        GeometryReader { geometry in
            let reading = OnboardingReadingLayout.isNeeded(size: geometry.size, textSize: textSize)
            let gutter = reading ? Spacing.s4 : Spacing.s6
            VStack(spacing: 0) {
                if !reading {
                    header()
                        .padding(.horizontal, gutter)
                        .padding(.top, Spacing.s4)
                }
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(spacing: reading ? Spacing.s4 : Spacing.s6) {
                            if reading { header() }
                            content()
                                .frame(maxWidth: .infinity)
                            if reading { footer() }
                        }
                        .padding(.horizontal, gutter)
                        .padding(.top, Spacing.s4)
                        .padding(.bottom, Spacing.s6)
                        .id("onboarding.page.top")
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("onboarding.page.scroll")
                    .onChange(of: pageID) { _, _ in
                        // A footer reached by scrolling must open the next page at
                        // its explanation, not inherit the previous bottom offset.
                        scroll.scrollTo("onboarding.page.top", anchor: .top)
                    }
                }
                if !reading {
                    footer()
                        .padding(.horizontal, gutter)
                        .padding(.bottom, Spacing.s6)
                }
            }
            .environment(\.onboardingReadingLayout, reading)
            .environment(\.onboardingPreviewHeight, max(180, geometry.size.height * 0.45))
        }
    }
}

/// Dismissal has its own measured row, never an overlay covering scrolled copy.
struct OnboardingPaywallLayout<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let onDismiss: () -> Void
    let dismissIdentifier: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            let reading = OnboardingReadingLayout.isNeeded(size: geometry.size, textSize: textSize)
            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    OnboardingDismissButton(action: onDismiss)
                        .accessibilityIdentifier(dismissIdentifier)
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s2)

                ScrollView {
                    content()
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, reading ? Spacing.s4 : Spacing.s6)
                        .padding(.top, Spacing.s4)
                        .padding(.bottom, Spacing.s10)
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("onboarding.paywall.scroll")
            }
            .environment(\.onboardingReadingLayout, reading)
        }
    }
}

struct OnboardingDismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(Spacing.s2)
                .frame(minWidth: 44, minHeight: 44)
                .background(Color.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss")
    }
}

struct OnboardingNavigationHeader: View {
    @Environment(\.onboardingReadingLayout) private var reading
    let current: Int
    let total: Int
    let canGoBack: Bool
    let showsMark: Bool
    let onBack: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.s3) {
                if canGoBack { backButton.fixedSize(horizontal: true, vertical: false) }
                Spacer(minLength: 0)
                progressText.fixedSize(horizontal: true, vertical: false)
                if showsMark && !reading {
                    Spacer(minLength: 0)
                    AppIconMark(icon: "heart.text.square.fill", size: 34, symbolSize: 14, usesAppIcon: true)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.s2) {
                if canGoBack { backButton }
                progressText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var progressText: some View {
        Text("Step \(current + 1) of \(total)")
            .font(Typography.label())
            .foregroundStyle(Color.textSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: Spacing.s1) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
                Text("Back")
                    .font(Typography.label())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s2)
            .frame(minWidth: 44, minHeight: 44)
            .background(Color.bgPrimary, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.borderSubtle, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

struct OnboardingPaywallHeader: View {
    @Environment(\.onboardingReadingLayout) private var reading
    let title: String
    let subtitle: String
    let titleIdentifier: String
    let subtitleIdentifier: String

    var body: some View {
        VStack(alignment: reading ? .leading : .center, spacing: Spacing.s6) {
            if !reading {
                AppIconMark(icon: "heart.text.square.fill", size: 72, usesAppIcon: true)
            }
            VStack(alignment: reading ? .leading : .center, spacing: Spacing.s2) {
                Text(title)
                    .font(Typography.displayLarge())
                    .foregroundStyle(Color.textPrimary)
                    .tracking(-1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(titleIdentifier)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(Typography.bodyLarge())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(subtitleIdentifier)
            }
        }
        .multilineTextAlignment(reading ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: reading ? .leading : .center)
    }
}

struct OnboardingHeader: View {
    @Environment(\.onboardingReadingLayout) private var reading
    let eyebrow: String
    let title: String
    let description: String
    let icon: String
    var usesAppIcon = false
    var showsIcon = true

    var body: some View {
        VStack(alignment: reading ? .leading : .center, spacing: showsIcon && !reading ? Spacing.s4 : Spacing.s2) {
            if showsIcon && !reading {
                AppIconMark(icon: icon, size: 64, symbolSize: 24, usesAppIcon: usesAppIcon)
            }
            VStack(alignment: reading ? .leading : .center, spacing: Spacing.s2) {
                Text(eyebrow)
                    .font(Typography.labelUppercase())
                    .foregroundStyle(Color.textSecondary)
                    .tracking(1.4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(title)
                    .font(Typography.displayMedium())
                    .foregroundStyle(Color.textPrimary)
                    .lineSpacing(1)
                    .tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(description)
                    .font(Typography.body())
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(reading ? .leading : .center)
        .frame(maxWidth: .infinity, alignment: reading ? .leading : .center)
    }
}

struct AppIconMark: View {
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
                Image(systemName: icon)
                    .font(Typography.scaled(size: symbolSize, weight: .semibold))
                    .foregroundStyle(Color.accent)
                    .padding(Spacing.s2)
                    .frame(minWidth: size, minHeight: size)
                    .background(Color.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: GeistRadius.lg, style: .continuous)
                            .strokeBorder(Color.borderSubtle, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

struct OnboardingChecklistRow: View {
    @Environment(\.onboardingReadingLayout) private var reading
    let title: String
    let detail: String
    let isComplete: Bool
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                if !reading {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                        .font(Typography.scaled(size: 18, weight: .semibold))
                        .foregroundStyle(isComplete ? Color.success : Color.textMuted)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(title)
                        .font(Typography.headline())
                        .foregroundStyle(Color.textPrimary)
                    Text(detail)
                        .font(Typography.body())
                        .foregroundStyle(Color.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title). \(detail)")
                .accessibilityValue(isComplete ? "Complete" : "Not complete")
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(Typography.bodyEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Spacing.s2)
                        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                        .background(Color.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                                .strokeBorder(Color.borderSubtle, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionTitle)
            }
        }
        .geistCard(cornerRadius: GeistRadius.md, padding: Spacing.s3)
    }
}

struct OnboardingPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var imageAsset: String? = nil
    var accessibilityHint: String = "Double tap to continue"
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OnboardingActionLabel(title: title, icon: icon, imageAsset: imageAsset, isPrimary: true)
                .foregroundStyle(Color.bgPrimary)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 48)
                .background(Color.geistGray1000)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.65 : 1)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
    }
}

struct OnboardingSecondaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OnboardingActionLabel(title: title, icon: icon, isPrimary: false)
                .foregroundStyle(Color.textPrimary)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background(Color.bgPrimary)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous)
                        .strokeBorder(Color.borderSubtle, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct OnboardingActionLabel: View {
    @Environment(\.onboardingReadingLayout) private var reading
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let icon: String?
    var imageAsset: String? = nil
    let isPrimary: Bool

    var body: some View {
        HStack(spacing: Spacing.s2) {
            if !isPrimary { decoration }
            Text(title)
                .font(isPrimary ? Typography.scaled(size: 16, weight: .medium) : Typography.bodyEmphasis())
                .fixedSize(horizontal: false, vertical: true)
            if isPrimary { decoration }
        }
        .multilineTextAlignment(reading || textSize >= .xLarge ? .leading : .center)
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
    }

    @ViewBuilder private var decoration: some View {
        if !reading && textSize < .xLarge {
            if let imageAsset {
                Image(imageAsset)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityHidden(true)
            } else if let icon {
                Image(systemName: icon)
                    .font(Typography.scaled(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Restore/retry are independent native actions, not part of the purchase target.
struct OnboardingTextAction: View {
    let title: LocalizedStringKey
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s2) {
                if isLoading {
                    ProgressView().controlSize(.mini).accessibilityHidden(true)
                }
                Text(title)
                    .font(Typography.bodyEmphasis())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .foregroundStyle(Color.textSecondary)
            .padding(Spacing.s2)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

/// Both live audience pickers use this control with their existing enum binding.
struct OnboardingAudienceChoices<Choice: Hashable & Identifiable>: View {
    @Environment(\.onboardingReadingLayout) private var reading
    @Environment(\.dynamicTypeSize) private var textSize
    let choices: [Choice]
    let selection: Choice
    let title: (Choice) -> String
    let onSelect: (Choice) -> Void

    var body: some View {
        // Measure single-line intrinsic labels before choosing a horizontal row.
        // The vertical candidate wraps freely; Dynamic Type is never reduced.
        Group {
            if reading || textSize >= .xLarge {
                choicesColumn
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.s1) {
                        ForEach(choices) { choice in choiceButton(choice).fixedSize(horizontal: true, vertical: false) }
                    }
                    choicesColumn
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(Color.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan type")
    }

    private var choicesColumn: some View {
        VStack(spacing: Spacing.s1) {
            ForEach(choices) { choice in choiceButton(choice) }
        }
    }

    private func choiceButton(_ choice: Choice) -> some View {
        Button { onSelect(choice) } label: {
            Text(title(choice))
                .font(Typography.bodyEmphasis())
                .foregroundStyle(selection == choice ? Color.bgPrimary : Color.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Spacing.s2)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background(selection == choice ? Color.geistGray1000 : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(choice))
        .accessibilityAddTraits(selection == choice ? .isSelected : [])
    }
}

/// Full offer details and price have their own lines even at standard sizes.
/// A tall offer scrolls with its screen rather than squeezing or shrinking price.
struct OnboardingPurchaseOptionLabel: View {
    @Environment(\.onboardingReadingLayout) private var reading
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let subtitle: String
    let priceLabel: String?
    let icon: String
    let badge: String?
    let isPrimary: Bool
    let isLoading: Bool
    let subtitleFont: Font
    let padding: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            if !reading && textSize < .xLarge {
                Image(systemName: icon)
                    .font(Typography.scaled(size: 16, weight: .semibold))
                    .foregroundStyle(isPrimary ? Color.bgPrimary : Color.accent)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(Typography.headline())
            if let badge {
                Text(badge)
                    .font(Typography.monoCaptionEmphasis())
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, 2)
                    .background((isPrimary ? Color.bgPrimary : Color.accent).opacity(0.12), in: Capsule())
            }
            Text(subtitle)
                .font(subtitleFont)
                .foregroundStyle(isPrimary ? Color.bgPrimary : Color.textSecondary)
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: isPrimary ? Color.bgPrimary : Color.accent))
                    .accessibilityHidden(true)
            }
            Text(priceLabel ?? (isLoading ? "Loading…" : "—"))
                .font(Typography.bodyEmphasis())
        }
        .foregroundStyle(isPrimary ? Color.bgPrimary : Color.textPrimary)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(reading ? Spacing.s3 : padding)
        .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(isPrimary ? Color.geistGray1000 : Color.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(isPrimary ? Color.geistGray1000 : Color.borderSubtle, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct OnboardingPurchaseButton: View {
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
            OnboardingPurchaseOptionLabel(title: title, subtitle: subtitle, priceLabel: priceLabel, icon: icon,
                                          badge: badge, isPrimary: isPrimary, isLoading: isLoading,
                                          subtitleFont: Typography.caption(), padding: Spacing.s3)
                .opacity(isDisabled ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(priceLabel.map { "\(title), \(subtitle), \($0)" } ?? "\(title), \(subtitle)")
        .accessibilityHint(!isDisabled ? "Double tap to purchase" : (isLoading ? "Purchase options are loading" : "Purchase is currently unavailable"))
    }
}

struct PaywallPurchaseOptionButton: View {
    let title: String
    let subtitle: String
    let priceLabel: String?
    let icon: String
    let badge: String?
    let isPrimary: Bool
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OnboardingPurchaseOptionLabel(title: title, subtitle: subtitle, priceLabel: priceLabel, icon: icon,
                                          badge: badge, isPrimary: isPrimary, isLoading: isLoading,
                                          subtitleFont: Typography.body(), padding: Spacing.s4)
                .opacity(isDisabled ? 0.58 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(priceLabel.map { "\(title), \(subtitle), \($0)" } ?? "\(title), \(subtitle)")
        .accessibilityHint(!isDisabled ? "Double tap to purchase" : (isLoading ? "Purchase options are loading" : "Purchase is currently unavailable"))
    }
}

struct OnboardingPurchaseDisclosure: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Lifetime plans are one-time purchases charged to your Apple ID.")
                .font(Typography.caption())
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Keep these independent links, including in VoiceOver traversal.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s4) {
                    terms.fixedSize(horizontal: true, vertical: false)
                    privacy.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    terms
                    privacy
                }
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.s1)
        .accessibilityElement(children: .contain)
    }

    private var terms: some View {
        Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
            linkLabel("Terms")
        }
    }

    private var privacy: some View {
        Link(destination: URL(string: "https://healthmd.app/privacy-policy.html")!) {
            linkLabel("Privacy")
        }
    }

    private func linkLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Typography.caption())
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(Spacing.s2)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
}
#endif
