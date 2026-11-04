#if os(iOS)
import SwiftUI

/// Purchase story told across three slides: the archive, the trial, the plans.
/// One decorative signal line runs through every slide at the same height so it
/// reads as continuous while paging. Pricing, eligibility, and purchase actions
/// come from `PaywallView`; this view owns only slide and plan selection.
struct SignalPaywallCarousel<Status: View>: View {
    @Environment(\.glassPalette) private var palette
    struct Pricing {
        let priceLabel: (HealthMdPurchaseOption) -> String?
        let weeklyEquivalent: (HealthMdPurchaseOption) -> String?
        let isTrialEligible: (HealthMdPurchaseOption) -> Bool
        let footerLine: (HealthMdPurchaseOption) -> String
        let isLoading: (HealthMdPurchaseOption) -> Bool
        let isDisabled: (HealthMdPurchaseOption) -> Bool
    }

    @ObservedObject var purchaseManager: PurchaseManager
    let pricing: Pricing
    let allowsDismissal: Bool
    let onDismiss: () -> Void
    let onPurchase: (HealthMdPurchaseOption) -> Void
    let onRestore: () -> Void
    @ViewBuilder let status: () -> Status

    @State private var slide: SignalSlide = .archive
    @State private var audience: SignalAudience = .individual
    @State private var selection: [SignalAudience: HealthMdPurchaseOption] = [.individual: .yearly, .family: .familyYearly]

    init(
        purchaseManager: PurchaseManager,
        pricing: Pricing,
        allowsDismissal: Bool,
        onDismiss: @escaping () -> Void,
        onPurchase: @escaping (HealthMdPurchaseOption) -> Void,
        onRestore: @escaping () -> Void,
        @ViewBuilder status: @escaping () -> Status
    ) {
        self.purchaseManager = purchaseManager
        self.pricing = pricing
        self.allowsDismissal = allowsDismissal
        self.onDismiss = onDismiss
        self.onPurchase = onPurchase
        self.onRestore = onRestore
        self.status = status
    }

    private var options: [HealthMdPurchaseOption] { audience.options }
    private var selected: HealthMdPurchaseOption { selection[audience] ?? audience.options[0] }

    /// The trial slide promises a free week, so it appears only when the store
    /// may still offer one: before products load, or when an option is eligible.
    private var visibleSlides: [SignalSlide] {
        let offersTrial = purchaseManager.productsByID.isEmpty || options.contains(where: pricing.isTrialEligible)
        return offersTrial ? SignalSlide.allCases : [.archive, .plans]
    }

    /// The subscription a trial converts to when Lifetime is selected.
    private var trialOption: HealthMdPurchaseOption {
        selected.isSubscription ? selected : audience.options[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            if allowsDismissal {
                HStack {
                    Spacer(minLength: 0)
                    Button(String(localized: "Close"), action: onDismiss)
                        .buttonStyle(.plain)
                        .glassFont(.navTitle)
                        .foregroundStyle(palette.accent)
                        .frame(minHeight: GlassMetrics.touchTarget)
                        .accessibilityIdentifier(AccessibilityID.Paywall.dismissButton)
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s2)
            }

            TabView(selection: $slide) {
                ForEach(visibleSlides) { slide in
                    slideContent(slide)
                        .tag(slide)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .background(palette.bg.ignoresSafeArea())
        .onChange(of: visibleSlides) { _, slides in
            if !slides.contains(slide) { slide = .plans }
        }
    }

    // MARK: - Slides

    @ViewBuilder
    private func slideContent(_ slide: SignalSlide) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                switch slide {
                case .archive: archiveSlide
                case .trial: trialSlide
                case .plans: plansSlide
                }
            }
            .padding(.horizontal, Spacing.s6)
            .padding(.bottom, Spacing.s6)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var archiveSlide: some View {
        Group {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text("Every heartbeat, written down.")
                    .glassFont(.screenTitle)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(AccessibilityID.Paywall.title)
                Text("Health.md turns Apple Health into a Markdown note for every day, saved to the folder you choose.")
                    .glassFont(.body)
                    .foregroundStyle(palette.sec)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(AccessibilityID.Paywall.subtitle)
            }
            .frame(minHeight: SignalLayout.headerHeight, alignment: .topLeading)
            SignalBand(kind: .archive)
            SignalExampleNote()
        }
    }

    private var trialSlide: some View {
        Group {
            Text("Seven days, on us.")
                .glassFont(.screenTitle)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .frame(minHeight: SignalLayout.headerHeight, alignment: .topLeading)
            SignalBand(kind: .trial)
            VStack(alignment: .leading, spacing: Spacing.s4) {
                SignalDayRow(day: 1, title: String(localized: "Today"), detail: String(localized: "Unlimited exports, schedules, and automations."))
                SignalDayRow(day: 5, title: String(localized: "Cancel anytime"), detail: String(localized: "Cancel in App Store subscriptions at least 24 hours before the trial ends."))
                SignalDayRow(day: 7, title: String(localized: "Trial ends"), detail: trialEndDetail)
            }
            if let review = AppStoreReview.verifiedExcerpts.first(where: { $0.rating == 5 }) {
                SignalReviewCard(review: review)
            }
        }
    }

    private var trialEndDetail: String {
        guard let price = pricing.priceLabel(trialOption) else { return trialOption.displaySubtitle }
        return String(localized: "Then \(price).")
    }

    private var plansSlide: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                Text("Pick a path.")
                    .glassFont(.screenTitle)
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                SignalAudienceSwitch(selection: audience) { choice in
                    withAnimation(AnimationTimings.fast) { audience = choice }
                }
            }
            .frame(minHeight: SignalLayout.plansHeaderHeight, alignment: .topLeading)
            VStack(spacing: Spacing.s3) {
                ForEach(Array(options.enumerated()), id: \.element) { index, option in
                    SignalPlanCard(
                        title: option.displayTitle,
                        detail: planDetail(for: option),
                        price: pricing.priceLabel(option) ?? String(localized: "Loading…"),
                        badge: badge(for: option),
                        isSelected: option == selected
                    ) {
                        withAnimation(AnimationTimings.fast) { selection[audience] = option }
                    }
                    .anchorPreference(key: SignalPlanAnchors.self, value: .bounds) { [index: $0] }
                    .accessibilityIdentifier(option == .individual ? AccessibilityID.Paywall.unlockButton : (option == .family ? AccessibilityID.Paywall.familyUnlockButton : "paywall-option-\(option.rawValue)"))
                }
            }
            .padding(.leading, SignalPlanBranches.cardInset)
            if audience == .family {
                Text("Family Sharing shares access, not health data, with up to 5 others.")
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.sec)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Eligible subscriptions include a 7-day free trial, then renew automatically at the displayed price unless canceled at least 24 hours before the trial or current period ends. Payment is charged to your Apple ID. Manage or cancel in App Store subscriptions. Lifetime plans are charged immediately as one-time purchases with no trial. Deleting the app or buying Lifetime does not cancel an existing subscription.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.sec)
                .fixedSize(horizontal: false, vertical: true)
        }
        .backgroundPreferenceValue(SignalPlanAnchors.self) { anchors in
            SignalPlanBranches(anchors: anchors, selected: options.firstIndex(of: selected) ?? 0)
        }
    }

    /// Yearly is the best value; Lifetime is the plan you own outright.
    private func badge(for option: HealthMdPurchaseOption) -> String? {
        if option == .yearly || option == .familyYearly { return String(localized: "Best value") }
        if !option.isSubscription { return String(localized: "Own it") }
        return nil
    }

    private func planDetail(for option: HealthMdPurchaseOption) -> String {
        guard option.isSubscription else { return option.displaySubtitle }
        let weekly = pricing.weeklyEquivalent(option).map { String(localized: "About \($0) a week") }
        if pricing.isTrialEligible(option) {
            return [String(localized: "7 days free"), weekly].compactMap { $0 }.joined(separator: " · ")
        }
        return weekly ?? option.displaySubtitle
    }

    // MARK: - Footer

    private var ctaTitle: String {
        if !selected.isSubscription { return String(localized: "Buy Lifetime") }
        return pricing.isTrialEligible(selected) ? String(localized: "Start 7-day free trial") : String(localized: "Subscribe")
    }

    private var footer: some View {
        VStack(spacing: Spacing.s3) {
            HStack(spacing: Spacing.s2) {
                ForEach(Array(visibleSlides.enumerated()), id: \.element) { index, item in
                    SignalStepButton(number: index + 1, title: item.title, isReached: item.rawValue <= slide.rawValue, isCurrent: item == slide) {
                        withAnimation(AnimationTimings.smooth) { slide = item }
                    }
                }
            }

            status()

            Text(pricing.footerLine(selected))
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.sec)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button { onPurchase(selected) } label: {
                Group {
                    if pricing.isLoading(selected) || purchaseManager.purchasingOption == selected {
                        ProgressView().tint(palette.accentInk)
                    } else {
                        Text(ctaTitle)
                            .glassFont(.navTitle)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Spacing.s4)
            }
            .buttonStyle(GlassPrimaryButtonStyle())
            .disabled(pricing.isDisabled(selected))
            .accessibilityIdentifier("paywall.purchaseButton")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s1) { footerLinks }
                VStack(spacing: Spacing.s1) { footerLinks }
            }
        }
        .padding(.horizontal, Spacing.s6)
        .padding(.top, Spacing.s2)
        .padding(.bottom, Spacing.s2)
        .background {
            Color.clear
                .glassSurface(in: Rectangle(), style: .strong)
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.edge).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// Restore, Terms and Privacy stay on every slide; "See all plans" joins them
    /// until the Plans slide is showing.
    @ViewBuilder
    private var footerLinks: some View {
        if slide != .plans {
            Button {
                withAnimation(AnimationTimings.smooth) { slide = .plans }
            } label: {
                SignalFooterLinkLabel(title: String(localized: "See all plans"))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paywall.seeAllPlans")
        }
        SignalFooterLink(title: String(localized: "Restore Purchase"), isLoading: purchaseManager.isRestoring, action: onRestore)
            .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
            .accessibilityIdentifier(AccessibilityID.Paywall.restoreButton)
            .accessibilityLabel("Restore previous purchase")
        Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
            SignalFooterLinkLabel(title: String(localized: "Terms"))
        }
        Link(destination: URL(string: "https://healthmd.app/privacy-policy.html")!) {
            SignalFooterLinkLabel(title: String(localized: "Privacy"))
        }
    }
}

// MARK: - Model

private enum SignalSlide: Int, CaseIterable, Identifiable, Hashable {
    case archive, trial, plans

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .archive: return String(localized: "Archive")
        case .trial: return String(localized: "Trial")
        case .plans: return String(localized: "Plans")
        }
    }
}

private enum SignalAudience: String, CaseIterable, Identifiable, Hashable {
    case individual, family

    var id: String { rawValue }

    var title: String {
        switch self {
        case .individual: return String(localized: "Just me")
        case .family: return String(localized: "Family · up to 6")
        }
    }

    /// Yearly first: it is the default selection and the "Best value" plan.
    var options: [HealthMdPurchaseOption] {
        switch self {
        case .individual: return [.yearly, .weekly, .individual]
        case .family: return [.familyYearly, .familyWeekly, .family]
        }
    }
}

// MARK: - Signal band

/// Decorative trace. Every kind meets the leading and trailing edges at the
/// band's mid-height so adjacent slides join into one line while paging.
private struct SignalBand: View {
    @Environment(\.glassPalette) private var palette
    enum Kind: Equatable {
        case archive
        case trial
    }

    let kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var textSize

    private let height = SignalLayout.bandHeight

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(in: &context, size: size, time: time)
            } symbols: {
                ForEach(labels.indices, id: \.self) { index in
                    Text(verbatim: labels[index].text)
                        .glassFont(.monoBody).fontWeight(.semibold)
                        .foregroundStyle(labels[index].isStrong ? palette.text : palette.sec)
                        .padding(.horizontal, labels[index].isChip ? Spacing.s2 : 0)
                        .padding(.vertical, labels[index].isChip ? Spacing.s1 : 0)
                        .background {
                            if labels[index].isChip {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(palette.bg)
                                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(palette.line))
                            }
                        }
                        .tag(index)
                }
            }
        }
        .frame(height: height)
        // Bleed to the screen edges so neighboring slides meet.
        .padding(.horizontal, -Spacing.s6)
        .accessibilityHidden(true)
    }

    private struct BandLabel {
        let text: String
        var isStrong = false
        var isChip = false
    }

    /// Example readings and day markers are decorative data, not copy.
    private var labels: [BandLabel] {
        switch kind {
        case .archive:
            return [BandLabel(text: "06:12 · 58 bpm", isStrong: true, isChip: true), BandLabel(text: "hrv · 46 ms", isStrong: true, isChip: true)]
        case .trial:
            return (1...7).map { BandLabel(text: "D\($0)", isStrong: [1, 5, 7].contains($0)) }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let mid = size.height / 2
        drawGrid(in: &context, size: size)
        switch kind {
        case .archive: drawArchive(in: &context, size: size, mid: mid, time: time)
        case .trial: drawTrial(in: &context, size: size, mid: mid, time: time)
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var dots = Path()
        stride(from: CGFloat(8), to: size.width, by: 16).forEach { x in
            stride(from: CGFloat(8), to: size.height, by: 16).forEach { y in
                dots.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
            }
        }
        context.fill(dots, with: .color(palette.line))
    }

    private func stroke(_ path: Path, in context: inout GraphicsContext, time: TimeInterval) {
        signalStroke(path, in: &context, time: time, animated: !reduceMotion, palette: palette)
    }

    private func pulse(at point: CGPoint, radius: CGFloat, in context: inout GraphicsContext, time: TimeInterval) {
        signalPulse(at: point, radius: radius, in: &context, time: time, animated: !reduceMotion, palette: palette)
    }

    private func drawArchive(in context: inout GraphicsContext, size: CGSize, mid: CGFloat, time: TimeInterval) {
        let baseline = mid + 14
        var path = Path()
        path.move(to: CGPoint(x: 0, y: mid))
        path.addLine(to: CGPoint(x: size.width * 0.03, y: baseline))
        var peaks: [CGPoint] = []
        for fraction in [0.06, 0.31, 0.56, 0.80] as [CGFloat] {
            let x = size.width * fraction
            path.addLine(to: CGPoint(x: x, y: baseline))
            path.addQuadCurve(to: CGPoint(x: x + 12, y: baseline), control: CGPoint(x: x + 6, y: baseline - 8))
            path.addLine(to: CGPoint(x: x + 18, y: baseline))
            path.addLine(to: CGPoint(x: x + 21, y: baseline + 6))
            path.addLine(to: CGPoint(x: x + 26, y: baseline - 48))
            peaks.append(CGPoint(x: x + 26, y: baseline - 48))
            path.addLine(to: CGPoint(x: x + 31, y: baseline + 22))
            path.addLine(to: CGPoint(x: x + 35, y: baseline))
            path.addLine(to: CGPoint(x: x + 45, y: baseline))
            path.addQuadCurve(to: CGPoint(x: x + 63, y: baseline), control: CGPoint(x: x + 54, y: baseline - 16))
        }
        path.addLine(to: CGPoint(x: size.width * 0.97, y: baseline))
        path.addLine(to: CGPoint(x: size.width, y: mid))
        stroke(path, in: &context, time: time)

        // Readout chips hang above the first and third peaks.
        guard textSize < .accessibility1 else { return }
        for (tag, peak) in [(0, peaks[0]), (1, peaks[2])] {
            var stem = Path()
            stem.move(to: CGPoint(x: peak.x, y: peak.y - 12))
            stem.addLine(to: peak)
            context.stroke(stem, with: .color(palette.edge), lineWidth: 1)
            context.fill(Path(ellipseIn: CGRect(x: peak.x - 3, y: peak.y - 3, width: 6, height: 6)), with: .color(palette.text))
            if let chip = context.resolveSymbol(id: tag) {
                context.draw(chip, at: CGPoint(x: peak.x - 12, y: peak.y - 14), anchor: .bottomLeading)
            }
        }
    }

    private func drawTrial(in context: inout GraphicsContext, size: CGSize, mid: CGFloat, time: TimeInterval) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: mid))
        path.addLine(to: CGPoint(x: size.width, y: mid))
        stroke(path, in: &context, time: time)

        let inset = Spacing.s8
        let step = (size.width - inset * 2) / 6
        for day in 0..<7 {
            let point = CGPoint(x: inset + CGFloat(day) * step, y: mid)
            switch day {
            case 0:
                pulse(at: point, radius: 7, in: &context, time: time)
            case 4, 6:
                let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: rect), with: .color(palette.bg))
                context.stroke(Path(ellipseIn: rect), with: .color(day == 6 ? palette.text : palette.accent), lineWidth: 2)
            default:
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(palette.muted))
            }
            if let label = context.resolveSymbol(id: day) {
                context.draw(label, at: CGPoint(x: point.x, y: mid - 18), anchor: .bottom)
            }
        }
    }
}

/// The glowing trace, with a short bright comet travelling it every few seconds.
private func signalStroke(_ path: Path, in context: inout GraphicsContext, time: TimeInterval, animated: Bool, palette: GlassPalette) {
    var glow = context
    glow.addFilter(.blur(radius: 5))
    glow.stroke(path, with: .color(palette.accent.opacity(0.55)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
    context.stroke(path, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    guard animated else { return }
    let head = (time.truncatingRemainder(dividingBy: 4.8)) / 4.8
    let comet = path.trimmedPath(from: max(0, head - 0.05), to: head)
    context.stroke(comet, with: .color(palette.text), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
}

/// Shared vertical rhythm: the line sits at the same height on every slide.
private enum SignalLayout {
    static let bandHeight: CGFloat = 132
    /// Room above the band for each slide's headline (and lede).
    static let headerHeight: CGFloat = 176
    /// Line height measured from the top of a slide.
    static let lineY = headerHeight + Spacing.s4 + bandHeight / 2
    static let cardHeight: CGFloat = 72
    /// Plans header height that centers the middle of three cards on the line.
    static let plansHeaderHeight = lineY - Spacing.s4 - (cardHeight * 1.5 + Spacing.s3)
}

private func signalPulse(at point: CGPoint, radius: CGFloat, in context: inout GraphicsContext, time: TimeInterval, animated: Bool, palette: GlassPalette) {
    if animated {
        let phase = CGFloat(time.truncatingRemainder(dividingBy: 2) / 2)
        let ring = radius + phase * radius * 2.2
        context.fill(Path(ellipseIn: CGRect(x: point.x - ring, y: point.y - ring, width: ring * 2, height: ring * 2)), with: .color(palette.accent.opacity(0.5 * (1 - phase))))
    }
    context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)), with: .color(palette.accent))
}

// MARK: - Plan branches

/// Bounds of each plan card, keyed by its index.
private struct SignalPlanAnchors: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Picks up the trace where the previous slide leaves it and forks it into
/// every plan card: the selected plan's branch is lit, the rest are dashed.
private struct SignalPlanBranches: View {
    @Environment(\.glassPalette) private var palette
    /// Leading room the cards leave for the fork.
    static let cardInset: CGFloat = 20

    let anchors: [Int: Anchor<CGRect>]
    let selected: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    draw(in: &context, size: size, proxy: proxy, time: time)
                }
            }
        }
        // Reach the screen edge, where the previous slide's trace ends.
        .padding(.horizontal, -Spacing.s6)
        .accessibilityHidden(true)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, proxy: GeometryProxy, time: TimeInterval) {
        let lineY = SignalLayout.lineY
        var grid = Path()
        stride(from: CGFloat(8), to: size.width, by: 16).forEach { x in
            stride(from: lineY - SignalLayout.bandHeight / 2 + 8, to: lineY + SignalLayout.bandHeight / 2, by: 16).forEach { y in
                grid.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
            }
        }
        context.fill(grid, with: .color(palette.line))

        let cards = anchors.keys.sorted().compactMap { anchors[$0].map { proxy[$0] } }
        guard !cards.isEmpty else { return }
        let fork = CGPoint(x: Spacing.s2, y: lineY)
        func branch(to card: CGRect) -> Path {
            var path = Path()
            path.move(to: fork)
            path.addCurve(
                to: CGPoint(x: card.minX, y: card.midY),
                control1: CGPoint(x: fork.x + 20, y: fork.y),
                control2: CGPoint(x: card.minX - 22, y: card.midY)
            )
            return path
        }

        let dash = StrokeStyle(lineWidth: 1.25, lineCap: .round, dash: [3, 4])
        for (index, card) in cards.enumerated() where index != selected {
            context.stroke(branch(to: card), with: .color(palette.edge), style: dash)
            context.fill(Path(ellipseIn: CGRect(x: card.minX - 3, y: card.midY - 3, width: 6, height: 6)), with: .color(palette.muted))
        }

        guard cards.indices.contains(selected) else { return }
        let target = cards[selected]
        var lit = Path()
        lit.move(to: CGPoint(x: 0, y: lineY))
        lit.addLine(to: fork)
        lit.addPath(branch(to: target))
        signalStroke(lit, in: &context, time: time, animated: !reduceMotion, palette: palette)
        signalPulse(at: CGPoint(x: target.minX, y: target.midY), radius: 5, in: &context, time: time, animated: !reduceMotion, palette: palette)
    }
}

/// Full-width two-part switch; stacks at accessibility text sizes.
private struct SignalAudienceSwitch: View {
    @Environment(\.glassPalette) private var palette
    let selection: SignalAudience
    let onSelect: (SignalAudience) -> Void
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            ForEach(SignalAudience.allCases) { choice in
                let isOn = choice == selection
                Button { onSelect(choice) } label: {
                    Text(choice.title)
                        .glassFont(.caption)
                        .foregroundStyle(isOn ? palette.accentInk : palette.sec)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Spacing.s3)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isOn ? palette.accent : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(palette.track, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.line))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Plan type")
    }
}

// MARK: - Slide components

private struct SignalExampleNote: View {
    @Environment(\.glassPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let fields: [(String, String)] = [
        ("resting_heart_rate", "58"),
        ("hrv_ms", "46.2"),
        ("steps", "9412"),
        ("sleep_total_hours", "7.3"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.s2) {
                Text(verbatim: "Obsidian › Health › 2026-11-01.md")
                    .glassFont(.monoBody)
                    .foregroundStyle(palette.sec)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("Example")
                    .glassFont(.caption)
                    .foregroundStyle(palette.sec)
            }
            .padding(Spacing.s3)

            Rectangle().fill(palette.line).frame(height: 1)

            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(verbatim: "---").foregroundStyle(palette.sec)
                ForEach(fields, id: \.0) { key, value in
                    (Text(verbatim: key + ":").foregroundStyle(palette.accent) + Text(verbatim: " " + value).foregroundStyle(palette.text))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Spacing.s1) {
                    Text(verbatim: "---").foregroundStyle(palette.sec)
                    TimelineView(.periodic(from: .now, by: 0.55)) { timeline in
                        let visible = reduceMotion || Int(timeline.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: 8, height: 15)
                            .opacity(visible ? 1 : 0)
                    }
                    .accessibilityHidden(true)
                }
            }
            .glassFont(.monoBody)
            .padding(Spacing.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22)
        .accessibilityElement(children: .combine)
    }
}

private struct SignalDayRow: View {
    @Environment(\.glassPalette) private var palette
    let day: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Text(verbatim: "D\(day)")
                .glassFont(.monoBody).fontWeight(.semibold)
                .foregroundStyle(palette.accent)
                .frame(minWidth: 28, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title)
                    .glassFont(.navTitle)
                    .foregroundStyle(palette.text)
                Text(detail)
                    .glassFont(.body)
                    .foregroundStyle(palette.sec)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short verified App Store review under the trial timeline.
private struct SignalReviewCard: View {
    @Environment(\.glassPalette) private var palette
    let review: AppStoreReview

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(verbatim: "“\(review.body)”")
                .glassFont(.body)
                .fontWeight(.semibold)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "\(String(repeating: "★", count: review.rating)) · \(review.author) · App Store")
                .glassFont(.monoBody)
                .foregroundStyle(palette.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.vertical, Spacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("paywall.review")
    }
}

private struct SignalPlanCard: View {
    @Environment(\.glassPalette) private var palette
    let title: String
    let detail: String
    let price: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Button(action: action) {
            // The price keeps its trailing column; descriptions wrap beside it.
            // Accessibility sizes give the price its own row instead.
            Group {
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Spacing.s2) {
                        labels
                        priceText
                    }
                } else {
                    HStack(spacing: Spacing.s3) {
                        labels
                            .frame(maxWidth: .infinity, alignment: .leading)
                        priceText
                            .fixedSize()
                    }
                }
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s3)
            .frame(maxWidth: .infinity, minHeight: SignalLayout.cardHeight, alignment: .leading)
            .glassSurface(cornerRadius: 22)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(isSelected ? palette.accent : Color.clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            HStack(spacing: Spacing.s2) {
                Text(title)
                    .glassFont(.navTitle)
                    .foregroundStyle(palette.text)
                if let badge {
                    Text(badge)
                        .glassFont(.caption)
                        .foregroundStyle(palette.bg)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, 2)
                        .background(palette.accent, in: Capsule())
                }
            }
            Text(detail)
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.sec)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var priceText: some View {
        Text(price)
            .glassFont(.body).fontWeight(.bold).monospacedDigit()
            .foregroundStyle(palette.text)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Footer components

private struct SignalStepButton: View {
    @Environment(\.glassPalette) private var palette
    let number: Int
    let title: String
    let isReached: Bool
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Capsule()
                    .fill(isReached ? palette.accent : palette.edge)
                    .frame(height: 3)
                (Text(verbatim: String(format: "%02d ", number)) + Text(title))
                    .glassFont(.monoBody).fontWeight(.semibold)
                    .foregroundStyle(isCurrent ? palette.text : palette.sec)
                    .textCase(.uppercase)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

private struct SignalFooterLink: View {
    @Environment(\.glassPalette) private var palette
    let title: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s1) {
                if isLoading { ProgressView().controlSize(.mini) }
                SignalFooterLinkLabel(title: title)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct SignalFooterLinkLabel: View {
    @Environment(\.glassPalette) private var palette
    let title: String

    var body: some View {
        Text(title)
            .glassFont(.caption)
            .foregroundStyle(palette.accent)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.s2)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
#endif
