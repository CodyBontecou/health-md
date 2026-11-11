import SwiftUI

enum GlassSurfaceStyle {
    case regular, strong
}

/// The one place that decides between system Liquid Glass and the solid fallback.
private struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let style: GlassSurfaceStyle
    let isInteractive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            solid(content)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        } else {
            solid(content)
        }
    }

    private func solid(_ content: Content) -> some View {
        let palette = GlassPalette.solid(colorScheme: colorScheme)
        return content
            .background(shape.fill(style == .strong ? palette.glassStrong : palette.glass))
            .overlay(shape.strokeBorder(palette.edge, lineWidth: 1))
    }
}

extension View {
    func glassSurface<S: InsettableShape>(
        in shape: S,
        style: GlassSurfaceStyle = .regular,
        isInteractive: Bool = false
    ) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, style: style, isInteractive: isInteractive))
    }

    func glassSurface(
        cornerRadius: CGFloat = GlassMetrics.panelRadius,
        style: GlassSurfaceStyle = .regular,
        isInteractive: Bool = false
    ) -> some View {
        glassSurface(
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            style: style,
            isInteractive: isInteractive
        )
    }

    /// Sheet chrome: 34 pt top radius on the palette's background.
    func glassSheet(palette: GlassPalette) -> some View {
        presentationCornerRadius(GlassMetrics.sheetTopRadius)
            .presentationBackground(palette.bg)
    }
}
