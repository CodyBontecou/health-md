#if os(iOS)
import SwiftUI

/// The 32-point coloured tile that leads a settings row (SettingsGlass, SettingsMoreG).
/// Tile colours are the boards' fixed category hues, identical in light and dark.
struct GlassIconTile: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: GlassMetrics.iconTileRadius, style: .continuous)
                    .fill(color)
            )
            .accessibilityHidden(true)
    }
}

extension Color {
    /// Board category hues for settings icon tiles.
    static let settingsTileViolet = Color.glassHex(0x6B3FE0)
    static let settingsTileBlue = Color.glassHex(0x3D5BFF)
    static let settingsTileGraphite = Color.glassHex(0x2B2B33)
    static let settingsTileGreen = Color.glassHex(0x0E8A6A)
    static let settingsTilePurple = Color.glassHex(0xB04FD8)
    static let settingsTileRed = Color.glassHex(0xE5484D)
    static let settingsTileOrange = Color.glassHex(0xF08C2E)
    static let settingsTileGray = Color.glassHex(0x5A5A66)
    static let settingsTileDiscord = Color.glassHex(0x5865F2)
}

/// A destination's state, drawn as the boards' capsule badge.
enum GlassSettingsBadgeTone { case ok, attention, off }

struct GlassSettingsBadgeState: Equatable {
    let title: String
    let tone: GlassSettingsBadgeTone

    init(_ title: String, _ tone: GlassSettingsBadgeTone) {
        self.title = title
        self.tone = tone
    }

    /// The boards' Ready / Off pair for a destination that is either configured or not.
    static func readiness(_ isReady: Bool) -> GlassSettingsBadgeState {
        isReady ? .init(String(localized: "Ready"), .ok) : .init(String(localized: "Off"), .off)
    }
}

struct GlassSettingsBadge: View {
    let title: String
    let tone: GlassSettingsBadgeTone

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(palette.surface2))
    }

    private var color: Color {
        switch tone {
        case .ok: return palette.ok
        case .attention: return palette.coral
        case .off: return palette.muted
        }
    }
}

/// One tappable settings row: icon tile, title and subtitle, an optional badge or value, chevron.
struct GlassSettingsRow: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var tile: Color = .clear
    var badge: GlassSettingsBadgeState?
    var value: String?
    var showsDivider = false
    let action: () -> Void

    @Environment(\.glassPalette) private var palette

    var body: some View {
        Button(action: action) {
            GlassRow(title: title, subtitle: subtitle) {
                if let systemImage { GlassIconTile(systemImage: systemImage, color: tile) }
            } trailing: {
                HStack(spacing: 8) {
                    if let badge { GlassSettingsBadge(title: badge.title, tone: badge.tone) }
                    if let value {
                        Text(value).glassFont(.body).foregroundStyle(palette.muted).lineLimit(1)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.muted)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                if showsDivider {
                    Rectangle().fill(palette.line).frame(height: 1)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// A read-only "label · value" row used by the destination Activity and Status sections.
struct GlassSettingsValueRow: View {
    let title: String
    let value: String
    var showsDivider = false

    @Environment(\.glassPalette) private var palette

    var body: some View {
        GlassRow(title: title) {
            Text(value)
                .glassFont(.body)
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle().fill(palette.line).frame(height: 1)
                    .padding(.horizontal, GlassMetrics.panelPadding)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
