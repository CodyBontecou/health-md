import SwiftUI

// Views for the Health.md Onboarding v2 design (`OnboardingView`). Colours come from
// the Liquid Glass palette; the pack tints are the design's per-pack hues, with a
// lighter variant for dark appearance.

// MARK: - Chrome

struct OnboardingTopBar: View {
    @Environment(\.glassPalette) private var palette
    let progress: Int
    let total: Int
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Label(String(localized: "Back"), systemImage: "chevron.left")
                    .labelStyle(OnboardingBackLabelStyle())
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                    .padding(.horizontal, 16)
                    .frame(minHeight: GlassMetrics.touchTarget)
                    .background(Capsule().fill(palette.glassStrong))
                    .overlay(Capsule().strokeBorder(palette.line, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.back")

            Spacer(minLength: 12)

            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index == progress ? palette.accent : palette.track)
                        .frame(width: index == progress ? 24 : 6, height: 6)
                }
            }
            .animation(AnimationTimings.standard, value: progress)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Setup progress"))
            .accessibilityValue(Text("Step \(progress + 1) of \(total)"))
        }
    }
}

private struct OnboardingBackLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 13, weight: .bold))
            configuration.title
        }
    }
}

/// The design's 56-point pill. Primary is ink-on-paper (inverts in dark mode).
struct OnboardingPillButton: View {
    enum Style { case primary, secondary }

    @Environment(\.glassPalette) private var palette
    let title: String
    var leadingSymbol: String? = nil
    var trailingSymbol: String? = nil
    var imageAsset: String? = nil
    var style: Style = .primary
    var isDisabled = false
    var accessibilityHint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let imageAsset {
                    Image(imageAsset)
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .accessibilityHidden(true)
                } else if let leadingSymbol {
                    Image(systemName: leadingSymbol).font(.system(size: 16, weight: .semibold)).accessibilityHidden(true)
                }
                Text(verbatim: title)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let trailingSymbol {
                    Image(systemName: trailingSymbol).font(.system(size: 16, weight: .semibold)).accessibilityHidden(true)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Capsule().fill(background))
            .overlay {
                if style == .secondary { Capsule().strokeBorder(palette.line, lineWidth: 1) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(accessibilityHint.map { Text(verbatim: $0) } ?? Text(""))
    }

    private var background: Color {
        if isDisabled { return palette.track }
        return style == .primary ? palette.text : palette.glassStrong
    }

    private var foreground: Color {
        if isDisabled { return palette.muted }
        return style == .primary ? palette.bg : palette.text
    }
}

struct OnboardingQuietButton: View {
    @Environment(\.glassPalette) private var palette
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.sec)
                .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingTitle: View {
    @Environment(\.glassPalette) private var palette
    let lead: String
    var accent: String? = nil
    var size: CGFloat = 28

    var body: some View {
        (Text(verbatim: lead) + Text(verbatim: accent.map { " " + $0 } ?? "").foregroundColor(palette.accent))
            .font(.system(size: size, weight: .bold))
            .tracking(-0.5)
            .foregroundStyle(palette.text)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct OnboardingCard<Content: View>: View {
    @Environment(\.glassPalette) private var palette
    var radius: CGFloat = 20
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(palette.glassStrong))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }
}

// MARK: - Pack tints

extension OnboardingMetricPack {
    /// The design's pack hues: a tile background and an icon colour.
    func tint(_ scheme: ColorScheme) -> (background: Color, foreground: Color) {
        let light: (UInt32, UInt32)
        let dark: UInt32
        switch self {
        case .sleep: light = (0xE8E6FF, 0x4B3FD0); dark = 0xB7AEFF
        case .activity: light = (0xFFEBDD, 0xB4520A); dark = 0xFFB27A
        case .heart: light = (0xFFE3EA, 0xB4234A); dark = 0xFF9BB3
        case .body: light = (0xDDF4F1, 0x0F6F66); dark = 0x7FDCCF
        case .mind: light = (0xF1E6FF, 0x7A2FC0); dark = 0xD3A8FF
        case .nutrition: light = (0xE4F4DF, 0x2F6E1F); dark = 0x9FDB8B
        case .cycle: light = (0xFCE4F1, 0xA3266E); dark = 0xFF9CD0
        }
        if scheme == .dark {
            let fg = Color.glassHex(dark)
            return (fg.opacity(0.18), fg)
        }
        return (.glassHex(light.0), .glassHex(light.1))
    }
}

private struct PackIconTile: View {
    @Environment(\.colorScheme) private var scheme
    let pack: OnboardingMetricPack
    var size: CGFloat = 38

    var body: some View {
        let tint = pack.tint(scheme)
        Image(systemName: pack.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint.foreground)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(tint.background))
            .accessibilityHidden(true)
    }
}

// MARK: - 0 · Welcome

struct OnboardingWelcomeStep: View {
    @Environment(\.glassPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WelcomeHero()
                .frame(height: 270)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            (Text("Your health,") + Text(verbatim: "\n") + Text("as notes you own.").foregroundColor(palette.accent))
                .font(.system(size: 36, weight: .bold))
                .tracking(-1)
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text("A daily Markdown note of your sleep, activity and heart data, saved to Obsidian or any folder you choose.")
                .glassFont(.body)
                .foregroundStyle(palette.sec)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 8) {
                stepTile(1, String(localized: "Pick what to track"))
                stepTile(2, String(localized: "Choose a folder"))
                stepTile(3, String(localized: "See your past week"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepTile(_ number: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STEP \(number)")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(palette.accent)
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.glassStrong))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Three stacked day notes with a "Saved to your vault" toast.
private struct WelcomeHero: View {
    @Environment(\.glassPalette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [palette.accent.opacity(0.22), palette.accent.opacity(0.08), .clear],
                center: .init(x: 0.5, y: 0.55), startRadius: 0, endRadius: 190
            )
            backNote(OnboardingWeekState.defaultDates()[4], alignTrailing: false)
                .rotationEffect(.degrees(-9))
                .offset(x: -48, y: 6)
            backNote(OnboardingWeekState.defaultDates()[5], alignTrailing: true)
                .rotationEffect(.degrees(8))
                .offset(x: 48, y: 0)
            frontNote
                .offset(y: -6)
            Label(String(localized: "Saved to your vault"), systemImage: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.bg)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(palette.text))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 6)
                .padding(.bottom, 6)
        }
    }

    private func backNote(_ date: Date, alignTrailing: Bool) -> some View {
        VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 8) {
            Text(verbatim: date.formatted(.iso8601.year().month().day()) + ".md")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.muted)
            Capsule().fill(palette.track).frame(width: 120, height: 8)
            Capsule().fill(palette.track).frame(width: 84, height: 8)
            Spacer()
        }
        .padding(16)
        .frame(width: 190, height: 190, alignment: alignTrailing ? .topTrailing : .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.glassStrong))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 15, y: 10)
    }

    private var frontNote: some View {
        let yesterday = OnboardingWeekState.defaultDates().last ?? Date()
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: yesterday.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                Text(verbatim: ".md")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(palette.track.opacity(0.5)))
            }
            heroRow(.sleep, String(localized: "Sleep"), "7h 42m")
            heroRow(.activity, String(localized: "Steps"), "8,432")
            heroRow(.heart, String(localized: "HRV"), "62 ms")
            SparkLine()
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(height: 28)
        }
        .padding(16)
        .frame(width: 214)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(palette.glassStrong))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        .shadow(color: palette.accent.opacity(0.18), radius: 22, y: 18)
    }

    private func heroRow(_ pack: OnboardingMetricPack, _ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            PackIconTile(pack: pack, size: 30)
            Text(verbatim: label).font(.system(size: 13)).foregroundStyle(palette.sec)
            Spacer()
            Text(verbatim: value).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.text)
        }
    }
}

private struct SparkLine: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [CGFloat] = [20, 16, 22, 10, 14, 6, 12, 4]
        var path = Path()
        for (index, value) in points.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(points.count - 1)
            let y = rect.minY + rect.height * value / 28
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

// MARK: - 1 · Packs

struct OnboardingPacksStep: View {
    @Environment(\.glassPalette) private var palette
    @Binding var selection: Set<OnboardingMetricPack>

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    private var allSelected: Bool { selection.count == OnboardingMetricPack.allCases.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                OnboardingTitle(lead: String(localized: "What goes in your"), accent: String(localized: "daily note?"))
                Text("Health.md asks Apple Health only for these. You can add more anytime.")
                    .font(.system(size: 15))
                    .foregroundStyle(palette.sec)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("\(selection.count) of \(OnboardingMetricPack.allCases.count) packs")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.sec)
                Spacer()
                Button(action: toggleAll) {
                    HStack(spacing: 8) {
                        Image(systemName: allSelected ? "checkmark.square.fill" : (selection.isEmpty ? "square" : "minus.square.fill"))
                            .font(.system(size: 16, weight: .semibold))
                        Text(allSelected ? String(localized: "Deselect all") : String(localized: "Select all"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(allSelected ? palette.accentInk : palette.text)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Capsule().fill(allSelected ? palette.accent : palette.glassStrong))
                    .overlay(Capsule().strokeBorder(allSelected ? palette.accent : palette.line, lineWidth: 1))
                    .frame(minHeight: GlassMetrics.touchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.packs.selectAll")
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingMetricPack.allCases) { pack in
                    PackCard(pack: pack, isSelected: selection.contains(pack)) {
                        if selection.contains(pack) { selection.remove(pack) } else { selection.insert(pack) }
                    }
                }
            }
        }
    }

    private func toggleAll() {
        selection = allSelected ? [] : Set(OnboardingMetricPack.allCases)
    }
}

private struct PackCard: View {
    @Environment(\.glassPalette) private var palette
    let pack: OnboardingMetricPack
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    PackIconTile(pack: pack)
                        .padding(.bottom, 4)
                    Spacer()
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Color.clear : palette.track, lineWidth: 1.5)
                            .background(Circle().fill(isSelected ? palette.accent : Color.clear))
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(palette.accentInk)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                }
                Text(verbatim: pack.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: pack.sample)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.sec)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text("\(pack.metricCount) types")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? palette.accentInk : palette.sec)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(isSelected ? palette.accent : palette.track.opacity(0.5)))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(palette.glassStrong))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? palette.accent : palette.line, lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: isSelected ? palette.accent.opacity(0.16) : .clear, radius: 9, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(pack.title). \(pack.sample). \(String(localized: "\(pack.metricCount) types"))"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("onboarding.pack.\(pack.rawValue)")
    }
}

struct OnboardingPacksSummary: View {
    @Environment(\.glassPalette) private var palette
    let packCount: Int
    let metricCount: Int

    var body: some View {
        OnboardingCard(radius: 16, padding: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(packCount == 0 ? String(localized: "Pick at least one pack") : String(localized: "\(metricCount) Health types selected"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.text)
                Spacer()
                if packCount > 0 {
                    Text(pagesLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.sec)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Apple's sheet shows roughly fourteen types per screen.
    private var pagesLabel: String {
        let pages = max(1, Int((Double(metricCount) / 14).rounded(.up)))
        return pages == 1 ? String(localized: "About 1 page to approve") : String(localized: "About \(pages) pages to approve")
    }
}

// MARK: - 2 · Apple Health

struct OnboardingHealthStep: View {
    @Environment(\.glassPalette) private var palette
    @Environment(\.colorScheme) private var scheme
    let packs: Set<OnboardingMetricPack>
    let isAuthorized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image("AppleHealthIcon")
                    .resizable()
                    .frame(width: 44, height: 44)
                    .frame(width: 76, height: 76)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.glassStrong))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
                HStack(spacing: 6) {
                    ForEach([0.3, 0.6, 1.0], id: \.self) { alpha in
                        Circle().fill(palette.accent.opacity(alpha)).frame(width: 6, height: 6)
                    }
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.accent)
                }
                Image(systemName: "doc.text")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(width: 76, height: 76)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.text))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                OnboardingTitle(lead: String(localized: "Connect"), accent: String(localized: "Apple Health"))
                if isAuthorized {
                    Label(String(localized: "Apple Health is connected. You can change access anytime in the Health app."), systemImage: "checkmark.circle.fill")
                        .glassFont(.body)
                        .foregroundStyle(palette.ok)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    (Text("Next, iOS asks you to approve these. Tap ") + Text("Turn On All").bold() + Text(". You can switch any of them off."))
                        .glassFont(.body)
                        .foregroundStyle(palette.sec)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            OnboardingFlowLayout(spacing: 8) {
                ForEach(OnboardingMetricPack.allCases.filter(packs.contains)) { pack in
                    let tint = pack.tint(scheme)
                    Label {
                        Text(verbatim: "\(pack.title) · \(pack.metricCount)")
                    } icon: {
                        Image(systemName: pack.symbol)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint.foreground)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Capsule().fill(tint.background))
                }
            }

            HStack(alignment: .top, spacing: 8) {
                trust("eye", String(localized: "Read-only"))
                trust("iphone", String(localized: "Stays on device"))
                trust("slider.horizontal.3", String(localized: "Change anytime"))
            }
            .padding(.top, 8)
        }
    }

    private func trust(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium)).foregroundStyle(palette.accent)
            Text(verbatim: title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.sec)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Wraps chips onto as many rows as they need.
struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 3 · Folder

/// The saved endpoint onboarding's Daily note automation sends to.
struct OnboardingAPIEndpoint: Equatable {
    let id: UUID
    let name: String
    let endpointURLString: String

    var shortURL: String {
        guard let url = URL(string: endpointURLString), let host = url.host else { return endpointURLString }
        return host + (url.path == "/" ? "" : url.path)
    }
}

struct OnboardingFolderStep: View {
    @Environment(\.glassPalette) private var palette
    @Binding var destination: OnboardingDestination
    let folderName: String?
    let onChooseFolder: () -> Void
    let previewDates: [Date]
    var apiEndpoint: OnboardingAPIEndpoint? = nil
    /// Opens the endpoint sheet: create when none is saved yet, otherwise edit.
    var onEditAPIEndpoint: () -> Void = {}
    /// The build can connect Google Drive directly; otherwise Drive is a Files folder.
    var driveAvailable: Bool = false
    var driveFolder: OnboardingDriveFolder? = nil
    var driveError: String? = nil
    var isConnectingDrive: Bool = false
    /// Shows the Drive privacy disclosure, then Google consent and the Picker.
    var onChangeDrive: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                OnboardingTitle(lead: String(localized: "Where should your"), accent: String(localized: "notes live?"))
                Text(destination == .api
                     ? String(localized: "One JSON payload per day, sent to your URL.")
                     : String(localized: "One file per day, in a Health folder."))
                    .glassFont(.body)
                    .foregroundStyle(palette.sec)
            }

            if destination == .api { payloadPreview } else { folderPreview }

            VStack(spacing: 8) {
                option(.folder, symbol: "folder.fill",
                       title: String(localized: "Local folder or iCloud"),
                       detail: folderName ?? String(localized: "Your Obsidian vault, or any folder in Files"),
                       recommended: true)
                option(.api, symbol: "chevron.left.forwardslash.chevron.right",
                       title: String(localized: "API endpoint"),
                       detail: String(localized: "Send each day as JSON to your URL"),
                       endpoint: destination == .api ? apiEndpoint : nil)
                option(.drive, symbol: "externaldrive.fill",
                       title: String(localized: "Google Drive"),
                       detail: driveDetail,
                       drive: destination == .drive && driveAvailable ? driveFolder : nil)
                if destination == .drive, let driveError {
                    Text(verbatim: driveError)
                        .glassFont(.caption)
                        .foregroundStyle(palette.coral)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("onboarding.drive.error")
                }
            }
        }
    }

    private var driveDetail: String {
        guard driveAvailable else {
            return folderName ?? String(localized: "Pick a Drive folder in Files")
        }
        if isConnectingDrive { return String(localized: "Waiting for Google…") }
        return String(localized: "Sign in with Google and pick a folder")
    }

    private var folderPreview: some View {
        let root = destination == .drive && driveAvailable
            ? (driveFolder?.folderLabel ?? String(localized: "Google Drive"))
            : (folderName.map { String($0.split(separator: "/").first ?? Substring($0)) } ?? String(localized: "My Vault"))
        return VStack(alignment: .leading, spacing: 6) {
            Label(root, systemImage: "folder").foregroundStyle(Color.white)
            Label(String(localized: "Health"), systemImage: "folder").foregroundStyle(Color.white).padding(.leading, 20)
            ForEach(Array(previewDates.suffix(3).reversed().enumerated()), id: \.offset) { index, date in
                HStack(spacing: 8) {
                    Circle().fill(Color.glassHex(0x9EF0C4)).frame(width: 6, height: 6)
                    Text(verbatim: date.formatted(.iso8601.year().month().day()) + ".md")
                    if index == 0 {
                        Spacer()
                        Text("NEW").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.glassHex(0x9EF0C4))
                    }
                }
                .padding(.leading, 40)
                .opacity(index == 2 ? 0.6 : 1)
            }
            Text("… \(max(0, previewDates.count - 3)) more").padding(.leading, 54).opacity(0.4)
        }
        .font(.system(size: 13, design: .monospaced))
        .foregroundStyle(Color.glassHex(0xCAC4D0))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.glassHex(0x17151F)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Folder preview: one Markdown file per day in a Health folder"))
    }

    /// One day's JSON as the endpoint receives it.
    private var payloadPreview: some View {
        let day = (previewDates.last ?? Date()).formatted(.iso8601.year().month().day())
        let target = apiEndpoint?.shortURL ?? "api.example.com/health"
        let key = Color.glassHex(0xC9B8F7)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(verbatim: "POST")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.glassHex(0x17151F))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.glassHex(0x9EF0C4)))
                Text(verbatim: target).foregroundStyle(Color.white).lineLimit(1).truncationMode(.middle)
            }
            .padding(.bottom, 4)
            Text(verbatim: "{")
            (Text(verbatim: "\"date\"").foregroundColor(key) + Text(verbatim: ": \"\(day)\","))
                .padding(.leading, 14)
            (Text(verbatim: "\"sleep_total_hours\"").foregroundColor(key) + Text(verbatim: ": 7.7,"))
                .padding(.leading, 14)
            (Text(verbatim: "\"steps\"").foregroundColor(key) + Text(verbatim: ": 8432,"))
                .padding(.leading, 14)
            Text(verbatim: "…").padding(.leading, 14).opacity(0.5)
            Text(verbatim: "}")
        }
        .font(.system(size: 12.5, design: .monospaced))
        .foregroundStyle(Color.glassHex(0xCFCBDA))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.glassHex(0x17151F)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Payload preview: one JSON payload per day, sent with a POST to \(target)"))
    }

    private func option(_ value: OnboardingDestination, symbol: String, title: String, detail: String,
                        recommended: Bool = false, endpoint: OnboardingAPIEndpoint? = nil,
                        drive: OnboardingDriveFolder? = nil) -> some View {
        let isOn = destination == value
        let hasRow = endpoint != nil || drive != nil
        return VStack(alignment: .leading, spacing: 12) {
            optionButton(value, symbol: symbol, title: title, detail: detail, recommended: recommended)
            if let endpoint { endpointRow(endpoint) }
            if let drive { driveRow(drive) }
        }
        .padding(hasRow ? 14 : 0)
        .background {
            if hasRow {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.glassStrong)
            }
        }
        .overlay {
            if hasRow {
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isOn ? palette.accent : palette.line, lineWidth: isOn ? 2 : 1)
            }
        }
    }

    private func endpointRow(_ endpoint: OnboardingAPIEndpoint) -> some View {
        HStack(spacing: 10) {
            Circle().fill(palette.ok).frame(width: 8, height: 8).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: endpoint.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                Text(verbatim: endpoint.shortURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.sec)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(action: onEditAPIEndpoint) {
                Label(String(localized: "Edit"), systemImage: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: GlassMetrics.touchTarget)
                    .background(Capsule().fill(palette.tint))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit \(endpoint.name)"))
            .accessibilityIdentifier("onboarding.apiEndpoint.edit")
        }
        .padding(.leading, 12).padding(.vertical, 4).padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bg.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
    }

    private func driveRow(_ folder: OnboardingDriveFolder) -> some View {
        HStack(spacing: 10) {
            Circle().fill(folder.isReady ? palette.ok : palette.coral).frame(width: 8, height: 8).accessibilityHidden(true)
            Image("GoogleDriveLogo")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: folder.folderLabel).font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.text)
                    .lineLimit(1).truncationMode(.middle)
                Text(folder.isReady ? String(localized: "Connected") : String(localized: "Reconnect to upload"))
                    .font(.system(size: 12))
                    .foregroundStyle(folder.isReady ? palette.sec : palette.coral)
            }
            Spacer(minLength: 8)
            Button(action: onChangeDrive) {
                Text(folder.isReady ? String(localized: "Change") : String(localized: "Reconnect"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: GlassMetrics.touchTarget)
                    .background(Capsule().fill(palette.tint))
            }
            .buttonStyle(.plain)
            .disabled(isConnectingDrive)
            .accessibilityLabel(Text(folder.isReady ? "Change Google Drive folder" : "Reconnect Google Drive"))
            .accessibilityIdentifier("onboarding.drive.change")
        }
        .padding(.leading, 12).padding(.vertical, 4).padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bg.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func optionButton(_ value: OnboardingDestination, symbol: String, title: String, detail: String, recommended: Bool) -> some View {
        let isOn = destination == value
        let grouped = (value == .api && destination == .api && apiEndpoint != nil)
            || (value == .drive && destination == .drive && driveAvailable && driveFolder != nil)
        Button {
            destination = value
            if value == .api {
                if apiEndpoint == nil { onEditAPIEndpoint() }
            } else if value == .drive && driveAvailable {
                if driveFolder == nil && !isConnectingDrive { onChangeDrive() }
            } else if folderName == nil {
                onChooseFolder()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.tint))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.system(size: 16, weight: .semibold)).foregroundStyle(palette.text)
                    Text(verbatim: detail).font(.system(size: 13)).foregroundStyle(palette.sec)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if recommended {
                    Text("RECOMMENDED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(palette.accentInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.accent))
                }
            }
            .padding(.horizontal, grouped ? 0 : 16)
            .padding(.vertical, grouped ? 0 : 12)
            .frame(maxWidth: .infinity, minHeight: grouped ? 44 : 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(grouped ? Color.clear : palette.glassStrong))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(grouped ? Color.clear : (isOn ? palette.accent : palette.line), lineWidth: isOn ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("onboarding.destination.\(value.rawValue)")
    }
}

// MARK: - 4 · First note

struct OnboardingFirstNoteStep: View {
    @Environment(\.glassPalette) private var palette
    @Binding var week: OnboardingWeekState
    let healthAuthorized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if week.isLoading || week.days.isEmpty || week.hasRealData {
                    OnboardingTitle(lead: String(localized: "Your week,"), accent: String(localized: "in notes."), size: 26)
                    Text(week.isLoading
                         ? String(localized: "Reading the past 7 days from Apple Health…")
                         : String(localized: "\(week.daysWithData) notes ready. Tap a night to preview it."))
                        .font(.system(size: 14))
                        .foregroundStyle(palette.sec)
                } else {
                    OnboardingTitle(lead: String(localized: "Here’s what a note looks like"), size: 26)
                    Text("Sample data. Real notes will use your Health records.")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.sec)
                }
            }

            if !week.isLoading && !week.days.isEmpty && !week.hasRealData {
                (Text(healthAuthorized
                      ? String(localized: "Apple Health returned no records for these days, so this is a ")
                      : String(localized: "Apple Health isn’t connected, so this is a "))
                 + Text("sample note").bold()
                 + Text(". Your free export is still unused."))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.glassHex(0x6B4105))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.glassHex(0xFFF4E5)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.glassHex(0xF1C98B), lineWidth: 1))
                    .accessibilityIdentifier("onboarding.firstNote.sampleNotice")
            }

            if week.isLoading || week.days.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                sleepChart
                if let day = week.selectedDay { noteCard(day) }
            }
        }
    }

    private var sleepChart: some View {
        let values = week.days.map { $0.sleepMinutes ?? 0 }
        let maxValue = max(values.max() ?? 0, 1)
        let withSleep = values.filter { $0 > 0 }
        let average = withSleep.isEmpty ? nil : withSleep.reduce(0, +) / Double(withSleep.count)
        return OnboardingCard(radius: 20, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sleep").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.text)
                    Spacer()
                    if let average {
                        Text("avg \(Self.duration(minutes: average))")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.sec)
                    }
                }
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(week.days.enumerated()), id: \.element.id) { index, day in
                        let isOn = index == week.selectedIndex
                        Button {
                            week.selectedIndex = index
                            week.showsRaw = false
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(isOn ? palette.accent : palette.accent.opacity(0.28))
                                    .frame(height: max(8, 64 * CGFloat((day.sleepMinutes ?? 0) / maxValue)))
                                    .frame(height: 64, alignment: .bottom)
                                Text(verbatim: day.date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.system(size: 11, weight: isOn ? .bold : .regular))
                                    .foregroundStyle(isOn ? palette.text : palette.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: GlassMetrics.touchTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: day.date.formatted(.dateTime.weekday(.wide).month().day())))
                        .accessibilityValue(Text(verbatim: day.sleepMinutes.map { Self.duration(minutes: $0) } ?? String(localized: "No sleep data")))
                        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
        }
    }

    private func noteCard(_ day: OnboardingDayPreview) -> some View {
        OnboardingCard(radius: 20, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: day.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(palette.text)
                    Spacer()
                    Text(verbatim: day.fileName)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if week.showsRaw {
                    ScrollView(.horizontal) {
                        Text(verbatim: day.rawFile)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    .accessibilityIdentifier("onboarding.firstNote.raw")
                } else {
                    if day.chips.isEmpty && day.sections.isEmpty {
                        Text("No records for this day. The note will say so.")
                            .font(.system(size: 14))
                            .foregroundStyle(palette.sec)
                    }
                    OnboardingFlowLayout(spacing: 6) {
                        ForEach(day.chips, id: \.self) { chip in
                            (Text(verbatim: chip.label + " ").foregroundColor(palette.sec)
                             + Text(verbatim: chip.value).foregroundColor(palette.text).bold())
                                .font(.system(size: 13, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(palette.tint))
                        }
                    }
                    if !day.sections.isEmpty {
                        Divider().overlay(palette.line)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(day.sections, id: \.self) { section in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: section.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(palette.accent)
                                    Text(verbatim: section.text)
                                        .font(.system(size: 14))
                                        .foregroundStyle(palette.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }

                Button {
                    week.showsRaw.toggle()
                } label: {
                    Text(week.showsRaw ? String(localized: "View formatted note") : String(localized: "View raw file"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(minHeight: GlassMetrics.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.firstNote.rawToggle")
            }
        }
    }

    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }
}

// MARK: - 5 · Make it daily

struct OnboardingDailyStep: View {
    @Environment(\.glassPalette) private var palette
    let savedBanner: String
    let destinationLabel: String
    let trialTimeline: [String]
    let fullAccessIncluded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(savedBanner, systemImage: "checkmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.ok)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.ok.opacity(0.12)))
                .accessibilityIdentifier("onboarding.daily.savedBanner")

            OnboardingTitle(lead: String(localized: "Make it daily?"), size: 30)
                .padding(.top, 8)
            Text("Each morning Health.md writes yesterday's note, so your vault stays up to date without opening the app.")
                .glassFont(.body)
                .foregroundStyle(palette.sec)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingCard(radius: 20, padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    (Text("Every morning at ") + Text("8:00").bold() + Text(", write ") + Text("yesterday's").bold()
                     + Text(" note to ") + Text(verbatim: destinationLabel).font(.system(size: 14, design: .monospaced)))
                        .font(.system(size: 16))
                        .foregroundStyle(palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if !fullAccessIncluded {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(trialTimeline, id: \.self) { line in
                                Text(verbatim: line)
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(palette.sec)
                    }
                }
            }
        }
    }
}
