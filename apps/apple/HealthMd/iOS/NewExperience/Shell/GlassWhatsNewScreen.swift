#if os(iOS)
import SwiftUI

/// WhatsNewG. The running version's release notes, shown once per version.
struct GlassWhatsNewScreen: View {
    let notes: HealthMdVersionNotes
    let onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Icon tile colours from the board, cycled per row.
    private static let tileColors: [Color] = [.glassHex(0x6B3FE0), .glassHex(0x3D5BFF), .glassHex(0x222228)]

    var body: some View {
        let palette = GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
        ScrollView {
            VStack(spacing: GlassMetrics.sectionGap) {
                VStack(spacing: 10) {
                    Image("HealthCrystalHeart")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    Text("What’s New")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(palette.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("whatsNew.title")
                    Text(verbatim: "Health.md \(notes.version)")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.muted)
                }
                .multilineTextAlignment(.center)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(notes.rows.enumerated()), id: \.offset) { index, row in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: row.symbolSystemName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: GlassMetrics.iconTileRadius, style: .continuous)
                                        .fill(Self.tileColors[index % Self.tileColors.count])
                                )
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(palette.text)
                                Text(row.description)
                                    .font(.system(size: 14))
                                    .foregroundStyle(palette.sec)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface()
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(String(localized: "Continue"), action: onContinue)
                .buttonStyle(GlassPrimaryButtonStyle())
                .accessibilityIdentifier("whatsNew.continue")
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background { Color.clear.glassSurface(in: Rectangle()).ignoresSafeArea(edges: .bottom) }
        }
        .glassSheet(palette: palette)
        .presentationDragIndicator(.visible)
        .tint(palette.accent)
        .glassTheme()
    }
}
#endif
