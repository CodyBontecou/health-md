#if os(iOS)
import CoreGraphics

/// How the window is shaped, as the glass layouts need it.
///
/// "iPhone Duo" is a foldable the boards design for. Nothing in UIKit names a fold, so
/// an unfolded inner display is inferred from what the window reports: a phone idiom
/// with regular width that is also tall enough to be more than a phone in landscape.
/// Once seen, the device is known to unfold, which is the only time the folded
/// (outer display) hint may appear.
enum GlassWindowClass: Equatable {
    /// An ordinary phone window.
    case phone
    /// The outer display of a phone that has been seen unfolded.
    case folded
    /// A compact window narrower than its screen on a device with a regular-width state.
    case splitView
    /// Regular width on a phone: the unfolded inner display, or a large phone in landscape.
    case unfolded
    /// Regular width on iPad.
    case pad

    /// The shortest side of a phone window in landscape is well under this; an unfolded
    /// inner display is not.
    static let unfoldedMinimumShortSide: CGFloat = 500

    static func looksUnfolded(isPad: Bool, isRegularWidth: Bool, windowSize: CGSize) -> Bool {
        !isPad && isRegularWidth && min(windowSize.width, windowSize.height) >= unfoldedMinimumShortSide
    }

    static func resolve(
        isPad: Bool,
        isRegularWidth: Bool,
        windowSize: CGSize,
        screenSize: CGSize,
        hasSeenUnfolded: Bool
    ) -> GlassWindowClass {
        if isRegularWidth { return isPad ? .pad : .unfolded }
        let isNarrowerThanScreen = screenSize.width > 0
            && windowSize.width > 0
            && windowSize.width < screenSize.width - 1
        let hasRegularState = isPad || hasSeenUnfolded
        if isNarrowerThanScreen && hasRegularState { return .splitView }
        if !isPad && hasSeenUnfolded { return .folded }
        return .phone
    }
}
#endif
