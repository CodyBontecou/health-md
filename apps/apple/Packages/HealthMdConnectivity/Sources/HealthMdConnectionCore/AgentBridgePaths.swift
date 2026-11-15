import Foundation

/// Lexical checks only. This is not native root registration, symlink safety, or a commit engine.
public enum AgentBridgePaths {
    public enum Tokens: Sendable { case none, daily, entries }

    public static func validate(_ path: String, filename: Bool = false, tokens: Tokens = .none) throws {
        guard path.utf8.count <= 4096,
              path.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }),
              !path.hasPrefix("/"), !path.hasPrefix("~"),
              !path.contains(where: { "\\:%".contains($0) }) else { throw AgentBridgeValidationError.unsafePath }
        if path.isEmpty {
            guard !filename else { throw AgentBridgeValidationError.unsafePath }
            return
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 16, !filename || parts.count == 1 else { throw AgentBridgeValidationError.unsafePath }
        let allowed: Set<String>
        switch tokens {
        case .none: allowed = []
        case .daily: allowed = ["year", "month", "day", "date"]
        case .entries: allowed = ["year", "month", "day", "date", "metric", "category", "record_id"]
        }
        for part in parts {
            guard !part.isEmpty, part != ".", part != "..", part.utf8.count <= 255,
                  part == part.trimmingCharacters(in: .whitespacesAndNewlines), !part.hasSuffix("."),
                  !part.contains(where: { "<>\"|?*".contains($0) }) else { throw AgentBridgeValidationError.unsafePath }
            var literal = ""
            var token: String?
            for scalar in part.unicodeScalars {
                if scalar == "{" {
                    guard token == nil else { throw AgentBridgeValidationError.unsafePath }
                    token = ""
                } else if scalar == "}" {
                    guard let name = token, allowed.contains(name) else { throw AgentBridgeValidationError.unsafePath }
                    token = nil; literal += "x"
                } else if token != nil { token?.unicodeScalars.append(scalar) }
                else { literal.unicodeScalars.append(scalar) }
            }
            guard token == nil else { throw AgentBridgeValidationError.unsafePath }
            let stem = literal.split(separator: ".", omittingEmptySubsequences: false).first?.lowercased() ?? ""
            let devices = ["con", "prn", "aux", "nul"] + (1...9).map { "com\($0)" } + (1...9).map { "lpt\($0)" }
            guard !devices.contains(stem) else { throw AgentBridgeValidationError.unsafePath }
        }
    }

    public static func validateCollisions(_ paths: [String]) throws {
        var aliases = Set<String>()
        for path in paths {
            try validate(path)
            guard !path.isEmpty else { throw AgentBridgeValidationError.unsafePath }
            let alias = path.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX")).precomposedStringWithCanonicalMapping
            guard aliases.insert(alias).inserted else { throw AgentBridgeValidationError.pathCollision }
        }
    }

    public static func predictedPaths(dates: AgentBridgeDates, settings: AgentBridgeOutputSettings) throws -> [String] {
        let resolved = try dates.resolved()
        guard case .exact(let range) = resolved else { return [] }
        guard let start = bridgeDate(range.startDate.rawValue), let end = bridgeDate(range.endDate.rawValue) else { throw AgentBridgeValidationError.invalidRequest }
        let count = Int(end.timeIntervalSince(start) / 86_400) + 1
        guard count > 0, count * settings.formats.count <= 4096 else { throw AgentBridgeValidationError.queryBudgetExceeded }
        func expand(_ template: String, _ day: String) -> String {
            template.replacingOccurrences(of: "{date}", with: day)
                .replacingOccurrences(of: "{year}", with: String(day.prefix(4)))
                .replacingOccurrences(of: "{month}", with: String(day.dropFirst(5).prefix(2)))
                .replacingOccurrences(of: "{day}", with: String(day.suffix(2)))
        }
        func join(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: "/") }
        var paths: [String] = []
        for index in 0..<count {
            let day = bridgeCivil(start.addingTimeInterval(Double(index) * 86_400))
            let parent = join([expand(settings.subfolder, day), expand(settings.folderTemplate, day)])
            let base = expand(settings.filenameTemplate, day)
            if !settings.dailyNotes.only {
                for format in settings.formats {
                    let ext = format == .json ? "json" : format == .csv ? "csv" : "md"
                    let suffix = format == .obsidianBases && settings.formats.contains(.markdown) ? "-bases" : ""
                    paths.append(join([parent, base + suffix + "." + ext]))
                }
            }
            if settings.dailyNotes.enabled {
                paths.append(join([expand(settings.dailyNotes.folderTemplate, day), expand(settings.dailyNotes.filenameTemplate, day) + ".md"]))
            }
        }
        let anchor = range.endDate.rawValue
        let root = expand(settings.subfolder, anchor)
        if case .profileDictionary(let format, let name) = settings.dictionary {
            paths.append(join([root, expand(name, anchor) + (format == .json ? ".json" : ".md")]))
        }
        try validateCollisions(paths)
        if case .zip(let name, let loose, _, let maxEntries) = settings.packaging {
            guard paths.count <= maxEntries else { throw AgentBridgeValidationError.queryBudgetExceeded }
            let archive = join([root, expand(name, anchor) + ".zip"])
            try validateCollisions(paths + [archive])
            paths = loose ? paths + [archive] : [archive]
        }
        guard paths.count <= 4096 else { throw AgentBridgeValidationError.queryBudgetExceeded }
        return paths.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }
}
