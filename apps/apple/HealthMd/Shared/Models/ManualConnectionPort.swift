import Foundation

/// A manually selected endpoint must never silently fall back to another port.
nonisolated enum ManualConnectionPort {
    static func parse(_ text: String) -> UInt16? {
        guard let port = UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
            return nil
        }
        return port
    }
}
