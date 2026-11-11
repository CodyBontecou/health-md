import Foundation

/// App-owned content lets the release screen change without duplicating its
/// customer-facing copy or losing older image/video release pages.
struct ReleaseVersionNotes: Identifiable, Sendable {
    let version: String
    let items: [ReleaseNoteItem]
    var id: String { version }

    /// Missing/empty release content must neither open an empty sheet nor block
    /// an otherwise eligible export-milestone review introduction.
    static func pending(
        currentVersion: String,
        lastSeenVersion: String?,
        isEnabled: Bool,
        catalog: [Self]
    ) -> Self? {
        guard isEnabled, currentVersion != lastSeenVersion,
              let notes = catalog.first(where: { $0.version == currentVersion }),
              !notes.items.isEmpty else { return nil }
        return notes
    }
}

enum ReleaseNoteItem: Sendable {
    case list(title: LocalizedStringResource, rows: [Row])
    case media(kind: MediaKind, url: URL, title: LocalizedStringResource, description: LocalizedStringResource)

    enum MediaKind: Sendable { case image, video }

    struct Row: Sendable {
        let symbolSystemName: String
        let title: LocalizedStringResource
        let description: LocalizedStringResource
    }
}
