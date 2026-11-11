#if os(iOS)
import SwiftUI

/// Shared by What's New and the review introduction so the two sheets feel
/// like one sequence. Branded content uses white foregrounds without overriding
/// the system appearance of sheets, alerts, or other native controls.
struct UpdateMomentBackground: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomLeading) {
                Color.black
                RadialGradient(
                    colors: [Color.accent.opacity(0.85), Color.accentSubtle.opacity(0.7), .clear],
                    center: .init(x: 0.3, y: 0.9),
                    startRadius: 0,
                    endRadius: max(geometry.size.width, geometry.size.height * 0.7)
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
#endif
