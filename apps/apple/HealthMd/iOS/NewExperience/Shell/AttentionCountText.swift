import Foundation

/// AttentionG spells small repeat counts the way the board does: "returned 503 three times".
enum AttentionCountText {
    /// The spelled-out count for 1 through 10 in `locale`, digits beyond that.
    static func spelled(_ count: Int, locale: Locale = .current) -> String {
        guard (1...10).contains(count) else { return count.formatted(.number.locale(locale)) }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: count)) ?? count.formatted(.number.locale(locale))
    }
}
