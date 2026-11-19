import Foundation

/// One-time cleanup of the saved API endpoints Health.md 3.5 created while the
/// user typed a URL.
///
/// 3.5 upserted a named endpoint on every change of the live endpoint field,
/// so typing `https://example.invalid/healthmd` saved one row per keystroke
/// ("ht", "htt", … the final URL), each named after its own URL. Typing past
/// the URL and deleting back left the longer rows behind too. 4.0 lists every
/// saved endpoint, so upgraders saw dozens of near-duplicates.
///
/// The plan is pure; `ProfileDestinationStore.removeKeystrokeAPIEndpointsIfNeeded`
/// supplies the protected ids and applies it once behind `versionKey`.
/// A row is removed only when it is not protected (referenced by any profile
/// or persisted record, or matching the live Settings endpoint) and:
/// - its URL is a strict prefix of another remaining row's URL and its name is
///   its own URL (the 3.5 auto-name), or
/// - it extends a protected row's URL one character at a time with every
///   intermediate row present (typed past the URL, then deleted back), has no
///   token, and is auto-named, or
/// - it duplicates the URL (case-insensitively) and token of a kept row.
enum APIEndpointKeystrokeCleanup {
    static let versionKey = "exportProfileDestinations.apiEndpointKeystrokeCleanupVersion"
    static let currentVersion = 1

    struct Row: Equatable {
        let id: UUID
        let name: String
        let endpointURLString: String
        let token: String?
        let createdAt: Date
    }

    static func removableIDs(in rows: [Row], protectedIDs: Set<UUID>) -> Set<UUID> {
        func url(_ row: Row) -> String { trimmed(row.endpointURLString) }
        func isAutoNamed(_ row: Row) -> Bool { trimmed(row.name) == url(row) }
        func isCandidate(_ row: Row) -> Bool { !protectedIDs.contains(row.id) && !url(row).isEmpty }

        let allURLs = Set(rows.map(url))
        let anchors = rows.filter { protectedIDs.contains($0.id) }.map(url).filter { !$0.isEmpty }
        var removed = Set<UUID>()

        // Typed past a kept URL and deleted back: every one-character step from
        // the anchor to this row was saved, and the row never got a token.
        for row in rows where isCandidate(row) && isAutoNamed(row) && row.token == nil {
            let characters = Array(url(row))
            let extendsAnchor = anchors.contains { anchor in
                anchor.count < characters.count
                    && url(row).hasPrefix(anchor)
                    && (anchor.count + 1 ..< characters.count).allSatisfy {
                        allURLs.contains(String(characters[0 ..< $0]))
                    }
            }
            if extendsAnchor { removed.insert(row.id) }
        }

        // Keystroke prefixes of a row that stays.
        let remainingURLs = rows.filter { !removed.contains($0.id) }.map(url)
        for row in rows where isCandidate(row) && isAutoNamed(row) && !removed.contains(row.id) {
            let candidate = url(row)
            if remainingURLs.contains(where: { $0.count > candidate.count && $0.hasPrefix(candidate) }) {
                removed.insert(row.id)
            }
        }

        // Exact duplicates (same URL and token) of a kept row; protected rows
        // and then the oldest row win.
        let kept = rows.filter { !removed.contains($0.id) }.sorted {
            let lhsProtected = protectedIDs.contains($0.id)
            let rhsProtected = protectedIDs.contains($1.id)
            if lhsProtected != rhsProtected { return lhsProtected }
            return $0.createdAt < $1.createdAt
        }
        var seen: [(url: String, token: String?)] = []
        for row in kept {
            let key = (url: url(row).lowercased(), token: row.token)
            if isCandidate(row), seen.contains(where: { $0.url == key.url && $0.token == key.token }) {
                removed.insert(row.id)
            } else {
                seen.append(key)
            }
        }
        return removed
    }

    /// Ids among `candidates` whose uuid string appears anywhere in `values`
    /// (strings, JSON/plist data, nested arrays and dictionaries, keys included).
    static func idsMentioned(in values: [Any], candidates: Set<UUID>) -> Set<UUID> {
        guard !candidates.isEmpty else { return [] }
        var haystacks: [String] = []
        func collect(_ value: Any) {
            switch value {
            case let string as String:
                haystacks.append(string.lowercased())
            case let data as Data:
                haystacks.append(String(decoding: data, as: UTF8.self).lowercased())
            case let array as [Any]:
                array.forEach(collect)
            case let dictionary as [String: Any]:
                for (key, nested) in dictionary {
                    haystacks.append(key.lowercased())
                    collect(nested)
                }
            default:
                break
            }
        }
        values.forEach(collect)
        return candidates.filter { id in
            let needle = id.uuidString.lowercased()
            return haystacks.contains { $0.contains(needle) }
        }
    }

    static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
