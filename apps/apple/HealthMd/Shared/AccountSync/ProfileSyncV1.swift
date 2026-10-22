import Foundation
import CoreFoundation
import CryptoKit

// Source-only contract codec: no accounts, stores, bindings, permissions or execution effects.
enum ProfileSyncV1Error: Error { case invalid, size, json, integer, duplicateKey, depth, unicode, hash, version, prohibited }

enum ProfileSyncV1 {
    static let contentMaximum = 262_144
    static let wireMaximum = 4_194_304
    static let safeMaximum: Int64 = 9_007_199_254_740_991
    private static let null = NSNull()

    struct Content: Sendable {
        let contentJSON: String
        let hash: String
        let requiresAction: [String]
        private init(_ raw: String, _ hash: String, _ flags: [String]) {
            self.contentJSON = raw; self.hash = hash; self.requiresAction = flags
        }
        static func parse(_ data: Data, expectedHash: String? = nil) throws -> Content {
            let root = try ProfileSyncV1.object(ProfileSyncV1.parseJSON(data, maximum: contentMaximum))
            try ProfileSyncV1.shape(root, ProfileSyncV1.portableSchema)
            let flags = try ProfileSyncV1.validateContent(root)
            let digest = ProfileSyncV1.contentHash(data)
            guard expectedHash == nil || expectedHash == digest else { throw ProfileSyncV1Error.hash }
            guard let raw = String(data: data, encoding: .utf8) else { throw ProfileSyncV1Error.unicode }
            return Content(raw, digest, flags)
        }
    }
    struct Record: Sendable {
        let profileID: String
        let objectRevision: Int64
        let eventSequence: Int64
        let orderKey: Int64?
        let contentRevision: Int64?
        let content: Content?
        var deleted: Bool { content == nil }
        private init(_ id: String, _ revision: Int64, _ sequence: Int64, _ order: Int64?, _ contentRevision: Int64?, _ content: Content?) {
            self.profileID = id; self.objectRevision = revision; self.eventSequence = sequence
            self.orderKey = order; self.contentRevision = contentRevision; self.content = content
        }
        static func parse(_ data: Data) throws -> Record {
            let root = try object(parseJSON(data)); try discriminate(root)
            try exact(root, "schema schema_version profile_id object_revision event_sequence order_key deleted content_revision content_hash content_json")
            let id = try opaque(root["profile_id"], "psp_")
            let revision = try integer(root["object_revision"]), sequence = try integer(root["event_sequence"])
            if try boolean(root["deleted"]) {
                try need(["order_key", "content_revision", "content_hash", "content_json"].allSatisfy { root[$0] is NSNull })
                return Record(id, revision, sequence, nil, nil, nil)
            }
            let order = try integer(root["order_key"], minimum: 0), contentRevision = try integer(root["content_revision"])
            try need(contentRevision <= revision)
            let content = try Content.parse(Data(string(root["content_json"]).utf8), expectedHash: opaque(root["content_hash"], "", length: 64))
            return Record(id, revision, sequence, order, contentRevision, content)
        }
    }
    struct Mutation: Sendable {
        let operation: String
        let mutationID: String
        let baseRevision: Int64
        let profileID: String?
        let orderKey: Int64?
        let content: Content?
        let requestHash: String
        fileprivate init(_ operation: String, _ id: String, _ base: Int64, _ profile: String?, _ order: Int64?, _ content: Content?, _ requestHash: String) {
            self.operation = operation; self.mutationID = id; self.baseRevision = base
            self.profileID = profile; self.orderKey = order; self.content = content; self.requestHash = requestHash
        }
    }
    struct Page: Sendable {
        let mode: String
        let snapshotID: String
        let highWatermark: Int64
        let items: [Record]
        let nextCursor: String?
        fileprivate init(_ mode: String, _ id: String, _ high: Int64, _ items: [Record], _ cursor: String?) {
            self.mode = mode; self.snapshotID = id; self.highWatermark = high; self.items = items; self.nextCursor = cursor
        }
    }
    // Immutable selectors only; parsing does not authenticate owner/cursor authority.
    enum ReadRequest: Sendable, Equatable {
        enum PageMode: String, Sendable { case changes, snapshot }
        case page(mode: PageMode, cursor: String?, limit: Int)
        case revision(profileID: String, contentRevision: Int64, contentHash: String)
    }
    enum ErrorResult: String, Sendable, CaseIterable {
        case unavailable, invalid, conflict, gone
        case requiresUpgrade = "requires_upgrade", notFound = "not_found", resyncRequired = "resync_required"
        case idempotencyMismatch = "idempotency_mismatch", intentExpired = "intent_expired"
        case verificationPending = "verification_pending", quotaExceeded = "quota_exceeded"
    }
    struct FixedError: Sendable, Equatable {
        let result: ErrorResult
        fileprivate init(_ result: ErrorResult) { self.result = result }
    }
    static func parseMutation(_ data: Data) throws -> Mutation {
        let root = try object(parseJSON(data)); try discriminate(root)
        let op = try string(root["operation"]); try need(["create", "update", "reorder", "delete"].contains(op))
        var fields = "schema schema_version operation mutation_id base_revision"
        if op != "create" { fields += " profile_id" }
        if ["create", "update"].contains(op) { fields += " content_json content_hash" }
        if op == "reorder" { fields += " order_key" }
        try exact(root, fields)
        let id = try opaque(root["mutation_id"], "psm_"), base = try integer(root["base_revision"], minimum: op == "create" ? 0 : 1)
        if op == "create" { try need(base == 0) }
        let profile = op == "create" ? nil : try opaque(root["profile_id"], "psp_")
        let content = ["create", "update"].contains(op) ? try Content.parse(Data(string(root["content_json"]).utf8), expectedHash: opaque(root["content_hash"], "", length: 64)) : nil
        return Mutation(op, id, base, profile, op == "reorder" ? try integer(root["order_key"], minimum: 0) : nil, content, mutationHash(data))
    }
    static func parseRead(_ data: Data) throws -> ReadRequest {
        let root = try object(parseJSON(data, maximum: 8192)); try discriminate(root)
        let mode = try string(root["mode"])
        if mode == "revision" {
            try exact(root, "schema schema_version mode profile_id content_revision content_hash")
            return .revision(profileID: try opaque(root["profile_id"], "psp_"), contentRevision: try integer(root["content_revision"]), contentHash: try opaque(root["content_hash"], "", length: 64))
        }
        guard let pageMode = ReadRequest.PageMode(rawValue: mode) else { throw ProfileSyncV1Error.invalid }
        try exact(root, "schema schema_version mode cursor limit")
        let limit = try integer(root["limit"]); try need(limit <= 8)
        let cursor = root["cursor"] is NSNull ? nil : try opaque(root["cursor"], "psc_", length: 64)
        return .page(mode: pageMode, cursor: cursor, limit: Int(limit))
    }
    // Fixed non-success only; no private reflection, cursor progression or retry effects.
    static func parseError(_ data: Data) throws -> FixedError {
        let root = try object(parseJSON(data, maximum: 8192)); try discriminate(root)
        try exact(root, "schema schema_version result")
        guard let result = try ErrorResult(rawValue: string(root["result"])) else { throw ProfileSyncV1Error.invalid }
        return FixedError(result)
    }
    static func parsePage(_ data: Data) throws -> Page {
        let root = try object(parseJSON(data)); try discriminate(root)
        try exact(root, "schema schema_version mode snapshot_id high_watermark items next_cursor complete")
        let mode = try string(root["mode"]); try need(["snapshot", "changes"].contains(mode))
        let id = try opaque(root["snapshot_id"], "pss_"), high = try integer(root["high_watermark"], minimum: 0)
        let complete = try boolean(root["complete"]); try need(complete == (root["next_cursor"] is NSNull))
        let cursor = root["next_cursor"] is NSNull ? nil : try opaque(root["next_cursor"], "psc_", length: 64)
        let rows = try array(root["items"]); try need(rows.count <= 8 && (complete || !rows.isEmpty))
        let records = try rows.map { try Record.parse(JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes])) }
        try need(records.allSatisfy { $0.eventSequence <= high })
        if mode == "snapshot" {
            try need(records.allSatisfy { !$0.deleted } && Set(records.map(\.profileID)).count == records.count)
        }
        for index in records.indices.dropFirst() {
            let a = records[index - 1], b = records[index]
            try need(mode == "changes" ? a.eventSequence < b.eventSequence :
                (a.orderKey! < b.orderKey! || (a.orderKey == b.orderKey && a.profileID < b.profileID)))
        }
        return Page(mode, id, high, records, cursor)
    }
    static func contentHash(_ data: Data) -> String { hashExactBytes(data, domain: "healthmd.profile_sync.portable/v1\0") }
    static func mutationHash(_ data: Data) -> String { hashExactBytes(data, domain: "healthmd.profile_sync.mutate/v1\0") }
    private static func hashExactBytes(_ data: Data, domain: String) -> String {
        let joined = Data(domain.utf8) + data
        return SHA256.hash(data: joined).map { String(format: "%02x", $0) }.joined()
    }
    private static func need(_ ok: Bool) throws { if !ok { throw ProfileSyncV1Error.invalid } }
    private static func object(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw ProfileSyncV1Error.invalid }; return value
    }
    private static func array(_ value: Any?) throws -> [Any] {
        guard let value = value as? [Any] else { throw ProfileSyncV1Error.invalid }; return value
    }
    private static func string(_ value: Any?) throws -> String {
        guard let value = value as? String else { throw ProfileSyncV1Error.invalid }; return value
    }
    private static func boolean(_ value: Any?) throws -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw ProfileSyncV1Error.invalid }
        return number.boolValue
    }
    private static func integer(_ value: Any?, minimum: Int64 = 1) throws -> Int64 {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              !["f", "d"].contains(String(cString: n.objCType)), n.int64Value >= minimum, n.int64Value <= safeMaximum else { throw ProfileSyncV1Error.integer }
        return n.int64Value
    }
    private static func opaque(_ value: Any?, _ prefix: String, length: Int = 32) throws -> String {
        let s = try string(value); try need(s.utf8.count == prefix.utf8.count + length && matches(s, "^" + prefix + "[0-9a-f]{" + String(length) + "}$")); return s
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
    private static func exact(_ root: [String: Any], _ fields: String) throws { try need(Set(root.keys) == Set(fields.split(separator: " ").map(String.init))) }
    private static func discriminate(_ root: [String: Any]) throws {
        try need(string(root["schema"]) == "healthmd.profile_sync")
        guard try integer(root["schema_version"]) == 1 else { throw ProfileSyncV1Error.version }
    }

    /// Bounded lexical parser constructs no lossy object before duplicate/number checks.
    static func parseJSON(_ data: Data, maximum: Int = wireMaximum) throws -> Any {
        guard data.count <= maximum else { throw ProfileSyncV1Error.size }
        guard String(data: data, encoding: .utf8) != nil else { throw ProfileSyncV1Error.unicode }
        var parser = Parser(bytes: Array(data), maximumString: maximum == contentMaximum ? 65_536 : wireMaximum)
        let result = try parser.value(depth: 0); parser.space()
        guard parser.position == parser.bytes.count else { throw ProfileSyncV1Error.json }; return result
    }
    private struct Parser {
        let bytes: [UInt8]
        let maximumString: Int
        var position = 0
        var nodes = 0
        var current: UInt8? { position < bytes.count ? bytes[position] : nil }
        mutating func space() { while let c = current, [9, 10, 13, 32].contains(c) { position += 1 } }
        mutating func consume(_ c: UInt8) throws { guard current == c else { throw ProfileSyncV1Error.json }; position += 1 }
        mutating func text() throws -> String {
            try consume(34); var output: [UInt8] = []; let input = bytes
            func hex(_ c: UInt8) -> UInt32? {
                switch c { case 48...57: return UInt32(c - 48); case 65...70: return UInt32(c - 55); case 97...102: return UInt32(c - 87); default: return nil }
            }
            func unit(_ start: Int) throws -> UInt32 {
                guard start + 4 <= input.count else { throw ProfileSyncV1Error.json }
                var value: UInt32 = 0
                for c in input[start..<(start + 4)] { guard let h = hex(c) else { throw ProfileSyncV1Error.json }; value = value * 16 + h }
                return value
            }
            while let c = current {
                position += 1
                if c == 34 {
                    // String(decoding:) preserves U+FEFF, unlike Foundation string-token decoding.
                    let s = String(decoding: output, as: UTF8.self)
                    guard Array(s.utf8) == output, s.unicodeScalars.count <= maximumString else { throw ProfileSyncV1Error.unicode }
                    return s
                }
                guard c >= 32 else { throw ProfileSyncV1Error.json }
                if c != 92 { output.append(c); continue }
                guard let escaped = current else { throw ProfileSyncV1Error.json }; position += 1
                switch escaped {
                case 34, 47, 92: output.append(escaped)
                case 98: output.append(8)
                case 102: output.append(12)
                case 110: output.append(10)
                case 114: output.append(13)
                case 116: output.append(9)
                case 117:
                    var scalar = try unit(position); position += 4
                    if (0xD800...0xDBFF).contains(scalar) {
                        try consume(92); try consume(117)
                        let low = try unit(position); position += 4
                        guard (0xDC00...0xDFFF).contains(low) else { throw ProfileSyncV1Error.unicode }
                        scalar = 0x10000 + (scalar - 0xD800) * 0x400 + low - 0xDC00
                    } else if (0xDC00...0xDFFF).contains(scalar) { throw ProfileSyncV1Error.unicode }
                    guard let unicode = UnicodeScalar(scalar) else { throw ProfileSyncV1Error.unicode }
                    output.append(contentsOf: String(unicode).utf8)
                default: throw ProfileSyncV1Error.json
                }
            }
            throw ProfileSyncV1Error.json
        }
        mutating func value(depth: Int) throws -> Any {
            guard depth <= 20 else { throw ProfileSyncV1Error.depth }; nodes += 1
            guard nodes <= 16_384 else { throw ProfileSyncV1Error.size }; space()
            if current == 34 { return try text() }
            if current == 123 || current == 91 {
                let isObject = current == 123; position += 1; space(); let end: UInt8 = isObject ? 125 : 93
                var object: [String: Any] = [:], list: [Any] = []; var keys = Set<String>(); var count = 0
                if current == end { position += 1; return isObject ? object : list }
                while true {
                    count += 1; guard count <= 512 else { throw ProfileSyncV1Error.size }; space()
                    if isObject {
                        let key = try text(); guard key.unicodeScalars.count <= 65_536 else { throw ProfileSyncV1Error.size }
                        // Swift String equality includes canonical equivalence; v1 explicitly rejects
                        // NFC-equivalent duplicate keys on ALL platforms instead of silently collapsing them.
                        guard keys.insert(key.precomposedStringWithCanonicalMapping).inserted else { throw ProfileSyncV1Error.duplicateKey }
                        space(); try consume(58); object[key] = try value(depth: depth + 1)
                    } else { list.append(try value(depth: depth + 1)) }
                    space(); if current == end { position += 1; return isObject ? object : list }; try consume(44)
                }
            }
            for (token, result) in [("true", NSNumber(value: true) as Any), ("false", NSNumber(value: false) as Any), ("null", NSNull() as Any)] {
                let tokenBytes = Array(token.utf8)
                if bytes.count - position >= tokenBytes.count && Array(bytes[position..<(position + tokenBytes.count)]) == tokenBytes { position += tokenBytes.count; return result }
            }
            let start = position
            if current == 45 { position += 1 }
            guard let first = current, (48...57).contains(first) else { throw ProfileSyncV1Error.json }
            if first == 48 { position += 1 } else { while let c = current, (48...57).contains(c) { position += 1 } }
            guard current != 46, current != 101, current != 69, !(current.map { (48...57).contains($0) } ?? false),
                  let token = String(bytes: bytes[start..<position], encoding: .utf8), token != "-0",
                  let n = Int64(token), n >= -safeMaximum, n <= safeMaximum else { throw ProfileSyncV1Error.integer }
            return NSNumber(value: n)
        }
    }
    private static func equal(_ a: Any, _ b: Any) -> Bool {
        // Schema constants/enum values and unique arrays are JSON values, never authority/hash material.
        guard let aa = try? JSONSerialization.data(withJSONObject: a, options: [.fragmentsAllowed, .sortedKeys]),
              let bb = try? JSONSerialization.data(withJSONObject: b, options: [.fragmentsAllowed, .sortedKeys]) else { return false }
        return aa == bb
    }
    private static func shape(_ value: Any, _ candidate: [String: Any]) throws {
        if let ref = candidate["$ref"] as? String {
            try need(ref.hasPrefix("#/$defs/")); try shape(value, object(object(portableSchema["$defs"])[String(ref.dropFirst(8))])); return
        }
        if let branches = candidate["oneOf"] as? [[String: Any]] {
            guard let branch = branches.first(where: { ($0["type"] as? String == "null") == (value is NSNull) }) else { throw ProfileSyncV1Error.invalid }
            try shape(value, branch); return
        }
        if let constant = candidate["const"] { try need(equal(value, constant)) }
        if let values = candidate["enum"] as? [Any] { try need(values.contains { equal(value, $0) }) }
        switch candidate["type"] as? String {
        case "null": try need(value is NSNull)
        case "boolean": _ = try boolean(value)
        case "integer":
            let n = try integer(value, minimum: (candidate["minimum"] as? NSNumber)?.int64Value ?? -safeMaximum)
            try need(n <= ((candidate["maximum"] as? NSNumber)?.int64Value ?? safeMaximum))
        case "string":
            let s = try string(value), length = s.unicodeScalars.count
            try need(length >= ((candidate["minLength"] as? NSNumber)?.intValue ?? 0) && length <= ((candidate["maxLength"] as? NSNumber)?.intValue ?? 65_536))
            if let pattern = candidate["pattern"] as? String { try need(matches(s, pattern)) }
        case "object":
            let o = try object(value), properties = try object(candidate["properties"] ?? [:])
            let required = candidate["required"] as? [String] ?? []; try need(required.allSatisfy { o.keys.contains($0) })
            try need(o.count <= ((candidate["maxProperties"] as? NSNumber)?.intValue ?? 512))
            for (key, child) in o {
                if let names = candidate["propertyNames"] { try shape(key, object(names)) }
                if let field = properties[key] { try shape(child, object(field)) }
                else { try shape(child, object(candidate["additionalProperties"])) }
            }
        case "array":
            let list = try array(value)
            try need(list.count >= ((candidate["minItems"] as? NSNumber)?.intValue ?? 0) && list.count <= ((candidate["maxItems"] as? NSNumber)?.intValue ?? 512))
            if (candidate["uniqueItems"] as? Bool) == true {
                for i in list.indices { for j in list.indices where j < i { try need(!equal(list[i], list[j])) } }
            }
            for child in list { try shape(child, object(candidate["items"])) }
        default: break
        }
    }
    // Explicit finite v1 policy, before frozen v2's platform-specific trimming check.
    private static let nameEdgeWhitespace: Set<UInt32> = [0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x0085, 0x00A0, 0x1680,
        0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
    private static let nameLineBreaks: Set<UInt32> = [0x0085, 0x2028, 0x2029]
    private static func validateContent(_ root: [String: Any]) throws -> [String] {
        // Actual existing v2 grammar/semantics validator, not an injected success oracle.
        var profile = try object(root["profile"])
        let nameScalars = try string(profile["name"]).unicodeScalars.map(\.value)
        try need(!nameScalars.isEmpty && !nameEdgeWhitespace.contains(nameScalars.first!) && !nameEdgeWhitespace.contains(nameScalars.last!))
        try need(!nameScalars.contains { $0 < 32 || $0 == 127 || nameLineBreaks.contains($0) })
        profile["bundle_id"] = "profile-001"
        let witness: [String: Any] = ["schema": "healthmd.shared_setup", "schema_version": 2,
            "created_by": ["platform": try string(root["origin_platform"]), "app_version": "profile-sync-v1-witness"],
            "metric_registry": root["metric_registry"]!, "metric_aliases": root["metric_aliases"]!,
            "profiles": [profile], "active_profile": "profile-001"]
        do { _ = try SharedSetupV2Codec.decode(JSONSerialization.data(withJSONObject: witness, options: [.sortedKeys, .withoutEscapingSlashes])) }
        catch { throw ProfileSyncV1Error.invalid }
        // v1 rejects empty relative-path components, including trailing separators;
        // the frozen Apple v2 validator permits a trailing empty component.
        let exp = try object(profile["export"]), individual = try object(profile["individual_entries"]), daily = try object(profile["daily_notes"])
        for path in [try string(exp["folder_template"]), try string(individual["entries_folder"]), try string(daily["folder"])] { try strictRelative(path) }
        for row in try object(individual["metrics"]).values {
            let folder = try object(row)["custom_folder"]!
            if !(folder is NSNull) { try strictRelative(string(folder)) }
        }
        let extensions = try object(profile["platform_extensions"])
        if !(extensions["android"] is NSNull) { try strictRelative(string(object(object(extensions["android"])["export"])["subfolder"])) }
        // Independent v1 adds foreign Apple schedule congruence (v2 native readers only check origin).
        let ext = try object(profile["platform_extensions"])
        if !(ext["apple"] is NSNull) {
            let apple = try object(ext["apple"])["schedule"]!
            try need((apple is NSNull) == (profile["schedule"] is NSNull))
            if !(apple is NSNull) {
                let a = try object(apple), c = try object(object(profile["schedule"])["cadence"])
                let f = try string(a["frequency"]), unit = try string(c["unit"])
                try need((f == "daily" && integer(c["value"]) == 1 && unit == "days") ||
                         (f == "weekly" && integer(c["value"]) == 1 && unit == "weeks") ||
                         (f == "custom" && unit == string(a["custom_unit"])))
            }
        }
        let dest = try object(profile["destination"])
        if !(dest["api_endpoint"] is NSNull) { try need(!matches(string(object(dest["api_endpoint"])["path"]), "[@%?#\\\\]")) }
        let registry = try object(root["metric_registry"])
        let matchesRegistry = try string(registry["registry_sha256"]) == string(pinnedRegistry["sha256"])
        if matchesRegistry {
            let bindings = try object(pinnedRegistry["aliases"])
            for row in try array(root["metric_aliases"]) {
                let alias = try object(row), id = try string(alias["semantic_id"]), binding = try array(bindings[id])
                try need(equal(alias["equivalence"]!, binding[0]) && equal(alias["apple_selection_id"]!, binding[1]) && equal(alias["android_selection_id"]!, binding[2]))
            }
        }
        try security(root, path: [])
        var flags = ["unbound_destination", "local_review_required", "platform_review"]
        if !matchesRegistry { flags.append("registry_review") }
        if !(profile["schedule"] is NSNull) { flags.append("schedule_disabled") }
        if try string(object(object(profile["presentation"])["markdown"])["style"]) == "custom" { flags.append("template_review") }
        return flags.sorted()
    }
    private static func strictRelative(_ path: String) throws {
        try need(path.isEmpty || path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." })
    }
    private static func security(_ value: Any, path: [String], endpoint: Bool = false) throws {
        if let root = value as? [String: Any] {
            let forbidden = Set(pinnedData["forbidden_exact"] as! [String]), fragments = pinnedData["forbidden_fragments"] as! [String]
            for (key, child) in root {
                let snake = key.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1_$2", options: .regularExpression)
                let k = snake.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
                let endpointParent = Array(path.suffix(2)) == ["destination", "api_endpoint"]
                let markdownParent = Array(path.suffix(2)) == ["presentation", "markdown"]
                let safe = (k == "credentials_required" && endpointParent) || (k == "header_level" && markdownParent)
                let rawAllowed = k == "raw_snapshot" && Array(path.suffix(3)) == ["platform_extensions", "android", "export"]
                guard (k != "raw_snapshot" || rawAllowed), !(k == "enabled" && path.contains("schedule")),
                      !matches(k, "(_timestamp|_millis|_at)$"), safe || (!forbidden.contains(k) && !fragments.contains(where: k.contains)) else { throw ProfileSyncV1Error.prohibited }
                try security(child, path: path + [k], endpoint: endpointParent && ["host", "path"].contains(key) && (root["scheme"] as? String) == "https")
            }
        } else if let list = value as? [Any] { for child in list { try security(child, path: path + ["[]"]) } }
        else if let s = value as? String {
            guard !matches(s, #"(?i)(content|file|saf)://|authorization:|\b(?:bearer|basic)\s+[a-z0-9+/=_-]|-----begin private key|https?://[^\s/@]+(?::[^\s/@]*)?@|[?&](?:access_?token|api_?key|password|secret|authorization)="#) else { throw ProfileSyncV1Error.prohibited }
            if !endpoint {
                guard !matches(s, #"(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}(?![0-9a-f])|(?:^|[\s"'])(?:[a-z]:[\\/])|/(users|home|private|var/mobile|data/user|storage/emulated|sdcard|mnt)/|^~/"#) else { throw ProfileSyncV1Error.prohibited }
            }
        }
    }

    // BEGIN GENERATED PINNED DATA (build_source_artifacts.py --embed)
    private static let dataBase64 = "eyJmb3JiaWRkZW5fZXhhY3QiOlsiYWNjZXNzX3Rva2VuIiwiYWNjb3VudF9pZCIsImFsYXJtX2lkIiwiYW5hbHl0aWNzIiwiYXBpX2tleSIsImF1dGhvcml6YXRpb24iLCJhdXRob3JpemF0aW9uX2hlYWRlciIsImF1dGhvcml6YXRpb25faGVhZGVyX3ZhbHVlIiwiYm9va21hcmsiLCJjYWxlbmRhcl90aW1lX3pvbmUiLCJjYWxlbmRhcl90aW1lem9uZSIsImNvbnRlbnRfdXJpIiwiY29va2llIiwiY3JlYXRlZF9hdCIsImNyZWRlbnRpYWwiLCJjcmVkZW50aWFscyIsImRlc2lyZWRfdGFyZ2V0IiwiZGVzdGluYXRpb25fZmluZ2VycHJpbnQiLCJkZXN0aW5hdGlvbl9pZCIsImRlc3RpbmF0aW9uX3BhdGgiLCJkZXZpY2VfaWQiLCJlbWFpbCIsImVuYWJsZWRfYXQiLCJlbmRwb2ludF9pZCIsImVuZ2luZV9hdXRob3JpdHkiLCJlbmdpbmVfcGluIiwiZW50aXRsZW1lbnQiLCJleHBvcnRfaGlzdG9yeSIsImZpbmdlcnByaW50IiwiZmlyc3RfbmFtZSIsImZvbGRlcl9kaXNwbGF5X25hbWUiLCJmb2xkZXJfZ3JhbnQiLCJmb2xkZXJfcGF0aCIsImZvbGRlcl91cmkiLCJmdWxsX25hbWUiLCJoZWFkZXJzIiwiaGVhbHRoX2RhdGEiLCJoZWFsdGhfcGVybWlzc2lvbnMiLCJoZWFsdGhfcmVjb3JkcyIsImhpc3RvcnkiLCJpZCIsImluY2x1ZGVfZ3JhbnVsYXJfZGF0YSIsImluc3RhbGxhdGlvbl9pZCIsImlzX2VuYWJsZWQiLCJsYXN0X2V4cG9ydF9kYXRlIiwibGFzdF9uYW1lIiwibGFzdF9ydW4iLCJsYXN0X3N1Y2Nlc3MiLCJsYXN0X3RvZGF5X3JlZnJlc2hfZGF0ZSIsIm1lYXN1cmVtZW50cyIsIm1pZ3JhdGlvbl9tYXJrZXIiLCJtb2RpZmllZF9hdCIsIm1vbnRobHlfcm9sbHVwIiwibmF0aXZlX2lkIiwibmF0aXZlX3BhdGgiLCJuYXRpdmVfcHJvZmlsZV9pZCIsIm9hdXRoIiwib25ib2FyZGluZyIsIm9wZXJhdGlvbl9pZCIsInBhaXJpbmdfaWQiLCJwYXNzd29yZCIsInBlbmRpbmdfcmVxdWVzdHMiLCJwZW5kaW5nX3dvcmsiLCJwZXJtaXNzaW9ucyIsInByb2ZpbGVfaWQiLCJwdXJjaGFzZSIsInB1cmNoYXNlcyIsInJhd19wZXJzaXN0ZW5jZV9zbmFwc2hvdCIsInJlY29yZHMiLCJyZWZyZXNoX3Rva2VuIiwicmVxdWVzdF9oZWFkZXJzIiwicmV0cmllcyIsInJldHJ5Iiwicm9sbHVwcyIsInJvb3RfcGF0aCIsInNhZl91cmkiLCJzYW1wbGVzIiwic2NoZWR1bGVfZW5hYmxlZCIsInNjaGVkdWxlX2VudHJ5X2lkIiwic2VjcmV0Iiwic2VjdXJpdHlfc2NvcGVkX2Jvb2ttYXJrIiwic2Vzc2lvbl9pZCIsInNvdXJjZV9kYXRhIiwidGltZV96b25lIiwidGltZXN0YW1wIiwidGltZXpvbmUiLCJ0b2tlbiIsInVwZGF0ZWRfYXQiLCJ1c2VyX2lkIiwidXVpZCIsIndlZWtseV9yb2xsdXAiLCJ3b3JrZXJfaWQiLCJ5ZWFybHlfcm9sbHVwIiwiem9uZV9pZCJdLCJmb3JiaWRkZW5fZnJhZ21lbnRzIjpbImNyZWRlbnRpYWwiLCJwYXNzd29yZCIsInRva2VuIiwic2VjcmV0IiwiYXV0aG9yaXphdGlvbiIsImhlYWRlciIsImJvb2ttYXJrIiwic2FmX3VyaSIsImNvbnRlbnRfdXJpIiwiZm9sZGVyX2dyYW50IiwicGVybWlzc2lvbiIsInB1cmNoYXNlIiwiZW50aXRsZW1lbnQiLCJoaXN0b3J5IiwiZGV2aWNlX2lkIiwiZGV2aWNlX2lkZW50aWZpZXIiLCJpbnN0YWxsYXRpb25faWQiLCJpbnN0YWxsYXRpb25faWRlbnRpZmllciIsImFjY291bnRfaWQiLCJhY2NvdW50X2lkZW50aWZpZXIiLCJ1c2VyX2lkIiwidXNlcl9pZGVudGlmaWVyIiwibmF0aXZlX3Byb2ZpbGUiLCJuYXRpdmVfaWQiLCJwcm9maWxlX2lkIiwicHJvZmlsZV91dWlkIiwiZGVzdGluYXRpb25faWQiLCJkZXN0aW5hdGlvbl91dWlkIiwiZW5kcG9pbnRfaWQiLCJlbmRwb2ludF91dWlkIiwiZm9sZGVyX2lkIiwiZm9sZGVyX3V1aWQiLCJzY2hlZHVsZV9lbnRyeSIsImhlYWx0aF9yZWNvcmQiLCJoZWFsdGhfZGF0YSIsInNvdXJjZV9kYXRhIiwiYW5hbHl0aWNzIiwiYXBpX2tleSIsInJhd19wZXJzaXN0ZW5jZSIsInNlc3Npb25faWQiLCJwZW5kaW5nXyIsIm9wZXJhdGlvbl9pZCIsImRlc3RpbmF0aW9uX2ZpbmdlcnByaW50IiwiZW5naW5lX3BpbiIsImVuZ2luZV9hdXRob3JpdHkiLCJwYWlyaW5nIiwicnVudGltZV8iLCJ0aW1lX3pvbmUiLCJ0aW1lem9uZSIsIm1pZ3JhdGlvbiIsImZvbGRlcl9kaXNwbGF5IiwiZW5kcG9pbnRfdXJsIiwiYXBpX3VybCIsIndvcmtlcl8iLCJhbGFybV8iLCJwcm9ncmVzcyIsImxhc3RfIiwid2Vla2x5X3JvbGx1cCIsIm1vbnRobHlfcm9sbHVwIiwieWVhcmx5X3JvbGx1cCJdLCJyZWdpc3RyeSI6eyJhbGlhc2VzIjp7ImFjdGl2ZV9lbmVyZ3kiOlsibWFwcGVkX2FsaWFzIiwiYWN0aXZlX2VuZXJneSIsImFjdGl2ZV9jYWxvcmllcyJdLCJhY3Rpdml0eV9tb3ZlX21vZGUiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJhY3Rpdml0eV9tb3ZlX21vZGUiLG51bGxdLCJhY3Rpdml0eV9zdW1tYXJ5IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiYWN0aXZpdHlfc3VtbWFyeSIsbnVsbF0sImFmaWJfYnVyZGVuIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiYWZpYl9idXJkZW4iLG51bGxdLCJhbGNvaG9saWNfYmV2ZXJhZ2VzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiYWxjb2hvbGljX2JldmVyYWdlcyIsbnVsbF0sImFuZHJvaWQuYWN0aXZpdHlfaW50ZW5zaXR5X21pbnV0ZXMiOlsicGxhdGZvcm1fZGlzdGluY3QiLG51bGwsImFjdGl2aXR5X2ludGVuc2l0eV9taW51dGVzIl0sImFuZHJvaWQuYm9keV93YXRlcl9tYXNzIjpbInBsYXRmb3JtX2Rpc3RpbmN0IixudWxsLCJib2R5X3dhdGVyX21hc3MiXSwiYW5kcm9pZC5ib25lX21hc3MiOlsicGxhdGZvcm1fZGlzdGluY3QiLG51bGwsImJvbmVfbWFzcyJdLCJhbmRyb2lkLmVsZXZhdGlvbl9nYWluZWQiOlsicGxhdGZvcm1fZGlzdGluY3QiLG51bGwsImVsZXZhdGlvbl9nYWluZWQiXSwiYW5kcm9pZC5lbmVyZ3lfZnJvbV9mYXQiOlsicGxhdGZvcm1fZGlzdGluY3QiLG51bGwsImVuZXJneV9mcm9tX2ZhdCJdLCJhbmRyb2lkLmZvbGljX2FjaWQiOlsicGxhdGZvcm1fZGlzdGluY3QiLG51bGwsImZvbGljX2FjaWQiXSwiYW5kcm9pZC5ocnZfcm1zc2QiOlsicGxhdGZvcm1fZGlzdGluY3QiLG51bGwsImhydiJdLCJhbmRyb2lkLm1lZGljYWxfcmVzb3VyY2VzIjpbInBsYXRmb3JtX2Rpc3RpbmN0IixudWxsLCJtZWRpY2FsX3Jlc291cmNlcyJdLCJhbmRyb2lkLm1lbnN0cnVhdGlvbl9wZXJpb2RfZGF5cyI6WyJwbGF0Zm9ybV9kaXN0aW5jdCIsbnVsbCwibWVuc3RydWF0aW9uX3BlcmlvZF9kYXlzIl0sImFuZHJvaWQubWVuc3RydWF0aW9uX3BlcmlvZHMiOlsicGxhdGZvcm1fZGlzdGluY3QiLG51bGwsIm1lbnN0cnVhdGlvbl9wZXJpb2RzIl0sImFuZHJvaWQubnV0cml0aW9uX21lYWxzIjpbInBsYXRmb3JtX2Rpc3RpbmN0IixudWxsLCJudXRyaXRpb25fbWVhbHMiXSwiYW5kcm9pZC5wbGFubmVkX3dvcmtvdXRzIjpbInBsYXRmb3JtX2Rpc3RpbmN0IixudWxsLCJwbGFubmVkX3dvcmtvdXRzIl0sImFuZHJvaWQucG93ZXJfbWF4IjpbInBsYXRmb3JtX2Rpc3RpbmN0IixudWxsLCJwb3dlcl9tYXgiXSwiYW5kcm9pZC5za2luX3RlbXBlcmF0dXJlIjpbInBsYXRmb3JtX2Rpc3RpbmN0IixudWxsLCJza2luX3RlbXBlcmF0dXJlIl0sImFuZHJvaWQuc3RlcHNfY2FkZW5jZSI6WyJwbGF0Zm9ybV9kaXN0aW5jdCIsbnVsbCwic3RlcHNfY2FkZW5jZSJdLCJhbmRyb2lkLnRvdGFsX2NhbG9yaWVzIjpbInBsYXRmb3JtX2Rpc3RpbmN0IixudWxsLCJ0b3RhbF9jYWxvcmllcyJdLCJhbmRyb2lkLnRyYW5zX2ZhdCI6WyJwbGF0Zm9ybV9kaXN0aW5jdCIsbnVsbCwidHJhbnNfZmF0Il0sImFuZHJvaWQudW5zYXR1cmF0ZWRfZmF0IjpbInBsYXRmb3JtX2Rpc3RpbmN0IixudWxsLCJ1bnNhdHVyYXRlZF9mYXQiXSwiYXVkaW9ncmFtcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImF1ZGlvZ3JhbXMiLG51bGxdLCJhdmVyYWdlX3ZhbGVuY2UiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJhdmVyYWdlX3ZhbGVuY2UiLG51bGxdLCJiYXNhbF9ib2R5X3RlbXBlcmF0dXJlIjpbIm1hcHBlZF9hbGlhcyIsImJhc2FsX2JvZHlfdGVtcGVyYXR1cmUiLCJiYXNhbF9ib2R5X3RlbXAiXSwiYmFzYWxfZW5lcmd5IjpbIm1hcHBlZF9hbGlhcyIsImJhc2FsX2VuZXJneSIsImJhc2FsX2NhbG9yaWVzIl0sImJpb2xvZ2ljYWxfc2V4IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiYmlvbG9naWNhbF9zZXgiLG51bGxdLCJiaW90aW4iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJiaW90aW4iLCJiaW90aW4iXSwiYmxlZWRpbmdfYWZ0ZXJfcHJlZ25hbmN5IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiYmxlZWRpbmdfYWZ0ZXJfcHJlZ25hbmN5IixudWxsXSwiYmxlZWRpbmdfZHVyaW5nX3ByZWduYW5jeSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImJsZWVkaW5nX2R1cmluZ19wcmVnbmFuY3kiLG51bGxdLCJibG9vZF9hbGNvaG9sIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiYmxvb2RfYWxjb2hvbCIsbnVsbF0sImJsb29kX2dsdWNvc2UiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJibG9vZF9nbHVjb3NlIiwiYmxvb2RfZ2x1Y29zZSJdLCJibG9vZF9veHlnZW4iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJibG9vZF9veHlnZW4iLCJibG9vZF9veHlnZW4iXSwiYmxvb2RfcHJlc3N1cmVfZGlhc3RvbGljIjpbIm1hcHBlZF9hbGlhcyIsImJsb29kX3ByZXNzdXJlX2RpYXN0b2xpYyIsImJwX2RpYXN0b2xpYyJdLCJibG9vZF9wcmVzc3VyZV9zeXN0b2xpYyI6WyJtYXBwZWRfYWxpYXMiLCJibG9vZF9wcmVzc3VyZV9zeXN0b2xpYyIsImJwX3N5c3RvbGljIl0sImJsb29kX3R5cGUiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJibG9vZF90eXBlIixudWxsXSwiYm1pIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiYm1pIiwiYm1pIl0sImJvZHlfZmF0IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiYm9keV9mYXQiLCJib2R5X2ZhdCJdLCJib2R5X3RlbXBlcmF0dXJlIjpbIm1hcHBlZF9hbGlhcyIsImJvZHlfdGVtcGVyYXR1cmUiLCJib2R5X3RlbXAiXSwiY2FsY2l1bSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImNhbGNpdW0iLCJjYWxjaXVtIl0sImNkYV9kb2N1bWVudHMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJjZGFfZG9jdW1lbnRzIixudWxsXSwiY2VydmljYWxfbXVjdXMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJjZXJ2aWNhbF9tdWN1cyIsImNlcnZpY2FsX211Y3VzIl0sImNobG9yaWRlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiY2hsb3JpZGUiLCJjaGxvcmlkZSJdLCJjaHJvbWl1bSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImNocm9taXVtIiwiY2hyb21pdW0iXSwiY2xpbmljYWxfYWxsZXJneV9yZWNvcmRzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiY2xpbmljYWxfYWxsZXJneV9yZWNvcmRzIixudWxsXSwiY2xpbmljYWxfY29uZGl0aW9uX3JlY29yZHMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJjbGluaWNhbF9jb25kaXRpb25fcmVjb3JkcyIsbnVsbF0sImNsaW5pY2FsX2NvdmVyYWdlX3JlY29yZHMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJjbGluaWNhbF9jb3ZlcmFnZV9yZWNvcmRzIixudWxsXSwiY2xpbmljYWxfaW1tdW5pemF0aW9uX3JlY29yZHMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJjbGluaWNhbF9pbW11bml6YXRpb25fcmVjb3JkcyIsbnVsbF0sImNsaW5pY2FsX2xhYl9yZXN1bHRfcmVjb3JkcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImNsaW5pY2FsX2xhYl9yZXN1bHRfcmVjb3JkcyIsbnVsbF0sImNsaW5pY2FsX21lZGljYXRpb25fcmVjb3JkcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImNsaW5pY2FsX21lZGljYXRpb25fcmVjb3JkcyIsbnVsbF0sImNsaW5pY2FsX25vdGVfcmVjb3JkcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImNsaW5pY2FsX25vdGVfcmVjb3JkcyIsbnVsbF0sImNsaW5pY2FsX3Byb2NlZHVyZV9yZWNvcmRzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiY2xpbmljYWxfcHJvY2VkdXJlX3JlY29yZHMiLG51bGxdLCJjbGluaWNhbF92aXRhbF9zaWduX3JlY29yZHMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJjbGluaWNhbF92aXRhbF9zaWduX3JlY29yZHMiLG51bGxdLCJjb250cmFjZXB0aXZlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiY29udHJhY2VwdGl2ZSIsbnVsbF0sImNvcHBlciI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImNvcHBlciIsImNvcHBlciJdLCJjcm9zc19jb3VudHJ5X3NraWluZ19zcGVlZCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImNyb3NzX2NvdW50cnlfc2tpaW5nX3NwZWVkIixudWxsXSwiY3ljbGluZ19jYWRlbmNlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiY3ljbGluZ19jYWRlbmNlIiwiY3ljbGluZ19jYWRlbmNlIl0sImN5Y2xpbmdfZGlzdGFuY2UiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJjeWNsaW5nX2Rpc3RhbmNlIiwiY3ljbGluZ19kaXN0YW5jZSJdLCJjeWNsaW5nX2Z0cCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImN5Y2xpbmdfZnRwIixudWxsXSwiY3ljbGluZ19wb3dlciI6WyJtYXBwZWRfYWxpYXMiLCJjeWNsaW5nX3Bvd2VyIiwicG93ZXJfYXZnIl0sImN5Y2xpbmdfc3BlZWQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJjeWNsaW5nX3NwZWVkIixudWxsXSwiZGFpbHlfbW9vZCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImRhaWx5X21vb2QiLG51bGxdLCJkYXRlX29mX2JpcnRoIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiZGF0ZV9vZl9iaXJ0aCIsbnVsbF0sImRpZXRhcnlfY2FmZmVpbmUiOlsibWFwcGVkX2FsaWFzIiwiZGlldGFyeV9jYWZmZWluZSIsImNhZmZlaW5lIl0sImRpZXRhcnlfY2FyYnMiOlsibWFwcGVkX2FsaWFzIiwiZGlldGFyeV9jYXJicyIsImNhcmJzIl0sImRpZXRhcnlfY2hvbGVzdGVyb2wiOlsibWFwcGVkX2FsaWFzIiwiZGlldGFyeV9jaG9sZXN0ZXJvbCIsImNob2xlc3Rlcm9sIl0sImRpZXRhcnlfZW5lcmd5IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiZGlldGFyeV9lbmVyZ3kiLCJkaWV0YXJ5X2VuZXJneSJdLCJkaWV0YXJ5X2ZhdCI6WyJtYXBwZWRfYWxpYXMiLCJkaWV0YXJ5X2ZhdCIsImZhdCJdLCJkaWV0YXJ5X2ZhdF9tb25vIjpbIm1hcHBlZF9hbGlhcyIsImRpZXRhcnlfZmF0X21vbm8iLCJtb25vdW5zYXR1cmF0ZWRfZmF0Il0sImRpZXRhcnlfZmF0X3BvbHkiOlsibWFwcGVkX2FsaWFzIiwiZGlldGFyeV9mYXRfcG9seSIsInBvbHl1bnNhdHVyYXRlZF9mYXQiXSwiZGlldGFyeV9mYXRfc2F0dXJhdGVkIjpbIm1hcHBlZF9hbGlhcyIsImRpZXRhcnlfZmF0X3NhdHVyYXRlZCIsInNhdHVyYXRlZF9mYXQiXSwiZGlldGFyeV9maWJlciI6WyJtYXBwZWRfYWxpYXMiLCJkaWV0YXJ5X2ZpYmVyIiwiZmliZXIiXSwiZGlldGFyeV9wcm90ZWluIjpbIm1hcHBlZF9hbGlhcyIsImRpZXRhcnlfcHJvdGVpbiIsInByb3RlaW4iXSwiZGlldGFyeV9zb2RpdW0iOlsibWFwcGVkX2FsaWFzIiwiZGlldGFyeV9zb2RpdW0iLCJzb2RpdW0iXSwiZGlldGFyeV9zdWdhciI6WyJtYXBwZWRfYWxpYXMiLCJkaWV0YXJ5X3N1Z2FyIiwic3VnYXIiXSwiZGlldGFyeV93YXRlciI6WyJtYXBwZWRfYWxpYXMiLCJkaWV0YXJ5X3dhdGVyIiwid2F0ZXIiXSwiZGlzdGFuY2VfY3Jvc3NfY291bnRyeV9za2lpbmciOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJkaXN0YW5jZV9jcm9zc19jb3VudHJ5X3NraWluZyIsbnVsbF0sImRpc3RhbmNlX2Rvd25oaWxsX3Nub3ciOlsibWFwcGVkX2FsaWFzIiwiZGlzdGFuY2VfZG93bmhpbGxfc25vdyIsImRvd25oaWxsX3Nub3dfZGlzdGFuY2UiXSwiZGlzdGFuY2VfcGFkZGxlX3Nwb3J0cyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImRpc3RhbmNlX3BhZGRsZV9zcG9ydHMiLG51bGxdLCJkaXN0YW5jZV9yb3dpbmciOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJkaXN0YW5jZV9yb3dpbmciLG51bGxdLCJkaXN0YW5jZV9za2F0aW5nX3Nwb3J0cyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImRpc3RhbmNlX3NrYXRpbmdfc3BvcnRzIixudWxsXSwiZGlzdGFuY2Vfc3dpbW1pbmciOlsibWFwcGVkX2FsaWFzIiwiZGlzdGFuY2Vfc3dpbW1pbmciLCJzd2ltbWluZ19kaXN0YW5jZSJdLCJkaXN0YW5jZV93YWxraW5nX3J1bm5pbmciOlsibWFwcGVkX2FsaWFzIiwiZGlzdGFuY2Vfd2Fsa2luZ19ydW5uaW5nIiwiZGlzdGFuY2UiXSwiZGlzdGFuY2Vfd2hlZWxjaGFpciI6WyJtYXBwZWRfYWxpYXMiLCJkaXN0YW5jZV93aGVlbGNoYWlyIiwid2hlZWxjaGFpcl9kaXN0YW5jZSJdLCJlbGVjdHJvY2FyZGlvZ3JhbXMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJlbGVjdHJvY2FyZGlvZ3JhbXMiLG51bGxdLCJlbGVjdHJvZGVybWFsX2FjdGl2aXR5IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiZWxlY3Ryb2Rlcm1hbF9hY3Rpdml0eSIsbnVsbF0sImVudmlyb25tZW50YWxfYXVkaW8iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJlbnZpcm9ubWVudGFsX2F1ZGlvIixudWxsXSwiZW52aXJvbm1lbnRhbF9hdWRpb19leHBvc3VyZV9ldmVudCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImVudmlyb25tZW50YWxfYXVkaW9fZXhwb3N1cmVfZXZlbnQiLG51bGxdLCJlbnZpcm9ubWVudGFsX3NvdW5kX3JlZHVjdGlvbiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImVudmlyb25tZW50YWxfc291bmRfcmVkdWN0aW9uIixudWxsXSwiZXN0aW1hdGVkX3dvcmtvdXRfZWZmb3J0X3Njb3JlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiZXN0aW1hdGVkX3dvcmtvdXRfZWZmb3J0X3Njb3JlIixudWxsXSwiZXhlcmNpc2VfdGltZSI6WyJtYXBwZWRfYWxpYXMiLCJleGVyY2lzZV90aW1lIiwiZXhlcmNpc2VfbWludXRlcyJdLCJmZXYxIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiZmV2MSIsbnVsbF0sImZpdHpwYXRyaWNrX3NraW5fdHlwZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImZpdHpwYXRyaWNrX3NraW5fdHlwZSIsbnVsbF0sImZsaWdodHNfY2xpbWJlZCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImZsaWdodHNfY2xpbWJlZCIsImZsaWdodHNfY2xpbWJlZCJdLCJmb2xhdGUiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJmb2xhdGUiLCJmb2xhdGUiXSwiZm9yY2VkX3ZpdGFsX2NhcGFjaXR5IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiZm9yY2VkX3ZpdGFsX2NhcGFjaXR5IixudWxsXSwiZ2FkN19hc3Nlc3NtZW50cyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImdhZDdfYXNzZXNzbWVudHMiLG51bGxdLCJoYW5kd2FzaGluZyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImhhbmR3YXNoaW5nIixudWxsXSwiaGVhZHBob25lX2F1ZGlvIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiaGVhZHBob25lX2F1ZGlvIixudWxsXSwiaGVhZHBob25lX2F1ZGlvX2V4cG9zdXJlX2V2ZW50IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiaGVhZHBob25lX2F1ZGlvX2V4cG9zdXJlX2V2ZW50IixudWxsXSwiaGVhcnRfcmF0ZV9hdmciOlsibWFwcGVkX2FsaWFzIiwiaGVhcnRfcmF0ZV9hdmciLCJhdmdfaHIiXSwiaGVhcnRfcmF0ZV9tYXgiOlsibWFwcGVkX2FsaWFzIiwiaGVhcnRfcmF0ZV9tYXgiLCJtYXhfaHIiXSwiaGVhcnRfcmF0ZV9taW4iOlsibWFwcGVkX2FsaWFzIiwiaGVhcnRfcmF0ZV9taW4iLCJtaW5faHIiXSwiaGVhcnRfcmF0ZV9yZWNvdmVyeSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImhlYXJ0X3JhdGVfcmVjb3ZlcnkiLG51bGxdLCJoZWFydGJlYXRfc2VyaWVzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiaGVhcnRiZWF0X3NlcmllcyIsbnVsbF0sImhlaWdodCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImhlaWdodCIsImhlaWdodCJdLCJoaWdoX2hlYXJ0X3JhdGVfZXZlbnQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJoaWdoX2hlYXJ0X3JhdGVfZXZlbnQiLG51bGxdLCJocnYiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJocnYiLG51bGxdLCJoeXBlcnRlbnNpb25fZXZlbnQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJoeXBlcnRlbnNpb25fZXZlbnQiLG51bGxdLCJpbmZyZXF1ZW50X21lbnN0cnVhbF9jeWNsZXMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJpbmZyZXF1ZW50X21lbnN0cnVhbF9jeWNsZXMiLG51bGxdLCJpbmhhbGVyX3VzYWdlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiaW5oYWxlcl91c2FnZSIsbnVsbF0sImluc3VsaW5fZGVsaXZlcnkiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJpbnN1bGluX2RlbGl2ZXJ5IixudWxsXSwiaW50ZXJtZW5zdHJ1YWxfYmxlZWRpbmciOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJpbnRlcm1lbnN0cnVhbF9ibGVlZGluZyIsImludGVybWVuc3RydWFsX2JsZWVkaW5nIl0sImlvZGluZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImlvZGluZSIsImlvZGluZSJdLCJpcm9uIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiaXJvbiIsImlyb24iXSwiaXJyZWd1bGFyX2hlYXJ0X3JoeXRobV9ldmVudCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImlycmVndWxhcl9oZWFydF9yaHl0aG1fZXZlbnQiLG51bGxdLCJpcnJlZ3VsYXJfbWVuc3RydWFsX2N5Y2xlcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsImlycmVndWxhcl9tZW5zdHJ1YWxfY3ljbGVzIixudWxsXSwibGFjdGF0aW9uIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwibGFjdGF0aW9uIixudWxsXSwibGVhbl9ib2R5X21hc3MiOlsibWFwcGVkX2FsaWFzIiwibGVhbl9ib2R5X21hc3MiLCJsZWFuX21hc3MiXSwibG93X2NhcmRpb19maXRuZXNzX2V2ZW50IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwibG93X2NhcmRpb19maXRuZXNzX2V2ZW50IixudWxsXSwibG93X2hlYXJ0X3JhdGVfZXZlbnQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJsb3dfaGVhcnRfcmF0ZV9ldmVudCIsbnVsbF0sIm1hZ25lc2l1bSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsIm1hZ25lc2l1bSIsIm1hZ25lc2l1bSJdLCJtYW5nYW5lc2UiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJtYW5nYW5lc2UiLCJtYW5nYW5lc2UiXSwibWVkaWNhdGlvbnMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJtZWRpY2F0aW9ucyIsbnVsbF0sIm1lbnN0cnVhbF9mbG93IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwibWVuc3RydWFsX2Zsb3ciLCJtZW5zdHJ1YWxfZmxvdyJdLCJtaW5kZnVsX21pbnV0ZXMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJtaW5kZnVsX21pbnV0ZXMiLCJtaW5kZnVsX21pbnV0ZXMiXSwibWluZGZ1bF9zZXNzaW9ucyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsIm1pbmRmdWxfc2Vzc2lvbnMiLCJtaW5kZnVsX3Nlc3Npb25zIl0sIm1vbHliZGVudW0iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJtb2x5YmRlbnVtIiwibW9seWJkZW51bSJdLCJtb21lbnRhcnlfZW1vdGlvbnMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJtb21lbnRhcnlfZW1vdGlvbnMiLG51bGxdLCJtb3ZlX3RpbWUiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJtb3ZlX3RpbWUiLG51bGxdLCJuaWFjaW4iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJuaWFjaW4iLCJuaWFjaW4iXSwibmlrZV9mdWVsIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwibmlrZV9mdWVsIixudWxsXSwibnVtYmVyX29mX2ZhbGxzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwibnVtYmVyX29mX2ZhbGxzIixudWxsXSwib3Z1bGF0aW9uX3Rlc3QiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJvdnVsYXRpb25fdGVzdCIsIm92dWxhdGlvbl90ZXN0Il0sInBhZGRsZV9zcG9ydHNfc3BlZWQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJwYWRkbGVfc3BvcnRzX3NwZWVkIixudWxsXSwicGFudG90aGVuaWNfYWNpZCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInBhbnRvdGhlbmljX2FjaWQiLCJwYW50b3RoZW5pY19hY2lkIl0sInBlYWtfZXhwaXJhdG9yeV9mbG93IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicGVha19leHBpcmF0b3J5X2Zsb3ciLG51bGxdLCJwZXJpcGhlcmFsX3BlcmZ1c2lvbl9pbmRleCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInBlcmlwaGVyYWxfcGVyZnVzaW9uX2luZGV4IixudWxsXSwicGVyc2lzdGVudF9pbnRlcm1lbnN0cnVhbF9ibGVlZGluZyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInBlcnNpc3RlbnRfaW50ZXJtZW5zdHJ1YWxfYmxlZWRpbmciLG51bGxdLCJwaG9zcGhvcnVzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicGhvc3Bob3J1cyIsInBob3NwaG9ydXMiXSwicGhxOV9hc3Nlc3NtZW50cyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInBocTlfYXNzZXNzbWVudHMiLG51bGxdLCJwaHlzaWNhbF9lZmZvcnQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJwaHlzaWNhbF9lZmZvcnQiLG51bGxdLCJwb3Rhc3NpdW0iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJwb3Rhc3NpdW0iLCJwb3Rhc3NpdW0iXSwicHJlZ25hbmN5IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicHJlZ25hbmN5IixudWxsXSwicHJlZ25hbmN5X3Rlc3RfcmVzdWx0IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicHJlZ25hbmN5X3Rlc3RfcmVzdWx0IixudWxsXSwicHJvZ2VzdGVyb25lX3Rlc3RfcmVzdWx0IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicHJvZ2VzdGVyb25lX3Rlc3RfcmVzdWx0IixudWxsXSwicHJvbG9uZ2VkX21lbnN0cnVhbF9wZXJpb2RzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicHJvbG9uZ2VkX21lbnN0cnVhbF9wZXJpb2RzIixudWxsXSwicHVzaF9jb3VudCI6WyJtYXBwZWRfYWxpYXMiLCJwdXNoX2NvdW50Iiwid2hlZWxjaGFpcl9wdXNoZXMiXSwicmVzcGlyYXRvcnlfcmF0ZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInJlc3BpcmF0b3J5X3JhdGUiLCJyZXNwaXJhdG9yeV9yYXRlIl0sInJlc3RpbmdfaGVhcnRfcmF0ZSI6WyJtYXBwZWRfYWxpYXMiLCJyZXN0aW5nX2hlYXJ0X3JhdGUiLCJyZXN0aW5nX2hyIl0sInJpYm9mbGF2aW4iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJyaWJvZmxhdmluIiwicmlib2ZsYXZpbiJdLCJyb3dpbmdfc3BlZWQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJyb3dpbmdfc3BlZWQiLG51bGxdLCJydW5uaW5nX2dyb3VuZF9jb250YWN0IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicnVubmluZ19ncm91bmRfY29udGFjdCIsbnVsbF0sInJ1bm5pbmdfcG93ZXIiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJydW5uaW5nX3Bvd2VyIiwicnVubmluZ19wb3dlciJdLCJydW5uaW5nX3NwZWVkIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicnVubmluZ19zcGVlZCIsInJ1bm5pbmdfc3BlZWQiXSwicnVubmluZ19zdHJpZGVfbGVuZ3RoIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwicnVubmluZ19zdHJpZGVfbGVuZ3RoIixudWxsXSwicnVubmluZ192ZXJ0aWNhbF9vc2NpbGxhdGlvbiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInJ1bm5pbmdfdmVydGljYWxfb3NjaWxsYXRpb24iLG51bGxdLCJzY2hlZHVsZWRfd29ya291dF9wbGFucyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInNjaGVkdWxlZF93b3Jrb3V0X3BsYW5zIixudWxsXSwic2VsZW5pdW0iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzZWxlbml1bSIsInNlbGVuaXVtIl0sInNleHVhbF9hY3Rpdml0eSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInNleHVhbF9hY3Rpdml0eSIsInNleHVhbF9hY3Rpdml0eSJdLCJzaXhfbWludXRlX3dhbGsiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzaXhfbWludXRlX3dhbGsiLG51bGxdLCJzbGVlcF9hcG5lYV9ldmVudCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInNsZWVwX2FwbmVhX2V2ZW50IixudWxsXSwic2xlZXBfYXdha2UiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzbGVlcF9hd2FrZSIsInNsZWVwX2F3YWtlIl0sInNsZWVwX2JlZHRpbWUiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzbGVlcF9iZWR0aW1lIixudWxsXSwic2xlZXBfY29yZSI6WyJtYXBwZWRfYWxpYXMiLCJzbGVlcF9jb3JlIiwic2xlZXBfbGlnaHQiXSwic2xlZXBfZGVlcCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInNsZWVwX2RlZXAiLCJzbGVlcF9kZWVwIl0sInNsZWVwX2luX2JlZCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInNsZWVwX2luX2JlZCIsInNsZWVwX2luX2JlZCJdLCJzbGVlcF9yZW0iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzbGVlcF9yZW0iLCJzbGVlcF9yZW0iXSwic2xlZXBfdG90YWwiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzbGVlcF90b3RhbCIsInNsZWVwX3RvdGFsIl0sInNsZWVwX3dha2UiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzbGVlcF93YWtlIixudWxsXSwic2xlZXBpbmdfYnJlYXRoaW5nX2Rpc3R1cmJhbmNlcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInNsZWVwaW5nX2JyZWF0aGluZ19kaXN0dXJiYW5jZXMiLG51bGxdLCJzdGFpcl9hc2NlbnRfc3BlZWQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzdGFpcl9hc2NlbnRfc3BlZWQiLG51bGxdLCJzdGFpcl9kZXNjZW50X3NwZWVkIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3RhaXJfZGVzY2VudF9zcGVlZCIsbnVsbF0sInN0YW5kX2hvdXJzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3RhbmRfaG91cnMiLG51bGxdLCJzdGFuZF90aW1lIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3RhbmRfdGltZSIsbnVsbF0sInN0YXRlX29mX21pbmRfZW50cmllcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN0YXRlX29mX21pbmRfZW50cmllcyIsbnVsbF0sInN0ZXBzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3RlcHMiLCJzdGVwcyJdLCJzd2ltbWluZ19zdHJva2VzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3dpbW1pbmdfc3Ryb2tlcyIsInN3aW1taW5nX3N0cm9rZXMiXSwic3ltcHRvbV9hYmRvbWluYWxfY3JhbXBzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9hYmRvbWluYWxfY3JhbXBzIixudWxsXSwic3ltcHRvbV9hY25lIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9hY25lIixudWxsXSwic3ltcHRvbV9hcHBldGl0ZV9jaGFuZ2VzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9hcHBldGl0ZV9jaGFuZ2VzIixudWxsXSwic3ltcHRvbV9ibGFkZGVyX2luY29udGluZW5jZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fYmxhZGRlcl9pbmNvbnRpbmVuY2UiLG51bGxdLCJzeW1wdG9tX2Jsb2F0aW5nIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9ibG9hdGluZyIsbnVsbF0sInN5bXB0b21fYm9keV9hY2hlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9ib2R5X2FjaGUiLG51bGxdLCJzeW1wdG9tX2JyZWFzdF9wYWluIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9icmVhc3RfcGFpbiIsbnVsbF0sInN5bXB0b21fY2hlc3RfcGFpbiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fY2hlc3RfcGFpbiIsbnVsbF0sInN5bXB0b21fY2hpbGxzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9jaGlsbHMiLG51bGxdLCJzeW1wdG9tX2NvbnN0aXBhdGlvbiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fY29uc3RpcGF0aW9uIixudWxsXSwic3ltcHRvbV9jb3VnaGluZyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fY291Z2hpbmciLG51bGxdLCJzeW1wdG9tX2RpYXJyaGVhIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9kaWFycmhlYSIsbnVsbF0sInN5bXB0b21fZGl6emluZXNzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9kaXp6aW5lc3MiLG51bGxdLCJzeW1wdG9tX2RyeV9za2luIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9kcnlfc2tpbiIsbnVsbF0sInN5bXB0b21fZmFpbnRpbmciOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzeW1wdG9tX2ZhaW50aW5nIixudWxsXSwic3ltcHRvbV9mYXRpZ3VlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9mYXRpZ3VlIixudWxsXSwic3ltcHRvbV9mZXZlciI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fZmV2ZXIiLG51bGxdLCJzeW1wdG9tX2hhaXJfbG9zcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21faGFpcl9sb3NzIixudWxsXSwic3ltcHRvbV9oZWFkYWNoZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21faGVhZGFjaGUiLG51bGxdLCJzeW1wdG9tX2hlYXJ0YnVybiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21faGVhcnRidXJuIixudWxsXSwic3ltcHRvbV9ob3RfZmxhc2hlcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21faG90X2ZsYXNoZXMiLG51bGxdLCJzeW1wdG9tX2xvc3Nfb2Zfc21lbGwiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzeW1wdG9tX2xvc3Nfb2Zfc21lbGwiLG51bGxdLCJzeW1wdG9tX2xvc3Nfb2ZfdGFzdGUiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzeW1wdG9tX2xvc3Nfb2ZfdGFzdGUiLG51bGxdLCJzeW1wdG9tX2xvd2VyX2JhY2tfcGFpbiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fbG93ZXJfYmFja19wYWluIixudWxsXSwic3ltcHRvbV9tZW1vcnlfbGFwc2UiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzeW1wdG9tX21lbW9yeV9sYXBzZSIsbnVsbF0sInN5bXB0b21fbW9vZF9jaGFuZ2VzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9tb29kX2NoYW5nZXMiLG51bGxdLCJzeW1wdG9tX25hdXNlYSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fbmF1c2VhIixudWxsXSwic3ltcHRvbV9uaWdodF9zd2VhdHMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzeW1wdG9tX25pZ2h0X3N3ZWF0cyIsbnVsbF0sInN5bXB0b21fcGVsdmljX3BhaW4iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzeW1wdG9tX3BlbHZpY19wYWluIixudWxsXSwic3ltcHRvbV9yYXBpZF9oZWFydGJlYXQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzeW1wdG9tX3JhcGlkX2hlYXJ0YmVhdCIsbnVsbF0sInN5bXB0b21fcnVubnlfbm9zZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fcnVubnlfbm9zZSIsbnVsbF0sInN5bXB0b21fc2hvcnRuZXNzX29mX2JyZWF0aCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fc2hvcnRuZXNzX29mX2JyZWF0aCIsbnVsbF0sInN5bXB0b21fc2ludXNfY29uZ2VzdGlvbiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fc2ludXNfY29uZ2VzdGlvbiIsbnVsbF0sInN5bXB0b21fc2tpcHBlZF9oZWFydGJlYXQiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJzeW1wdG9tX3NraXBwZWRfaGVhcnRiZWF0IixudWxsXSwic3ltcHRvbV9zbGVlcF9jaGFuZ2VzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV9zbGVlcF9jaGFuZ2VzIixudWxsXSwic3ltcHRvbV9zb3JlX3Rocm9hdCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fc29yZV90aHJvYXQiLG51bGxdLCJzeW1wdG9tX3ZhZ2luYWxfZHJ5bmVzcyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fdmFnaW5hbF9kcnluZXNzIixudWxsXSwic3ltcHRvbV92b21pdGluZyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInN5bXB0b21fdm9taXRpbmciLG51bGxdLCJzeW1wdG9tX3doZWV6aW5nIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwic3ltcHRvbV93aGVlemluZyIsbnVsbF0sInRoaWFtaW4iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJ0aGlhbWluIiwidGhpYW1pbiJdLCJ0aW1lX2luX2RheWxpZ2h0IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwidGltZV9pbl9kYXlsaWdodCIsbnVsbF0sInRvb3RoYnJ1c2hpbmciOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJ0b290aGJydXNoaW5nIixudWxsXSwidW5kZXJ3YXRlcl9kZXB0aCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInVuZGVyd2F0ZXJfZGVwdGgiLG51bGxdLCJ1dl9leHBvc3VyZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInV2X2V4cG9zdXJlIixudWxsXSwidmVyaWZpYWJsZV9jbGluaWNhbF9yZWNvcmRzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwidmVyaWZpYWJsZV9jbGluaWNhbF9yZWNvcmRzIixudWxsXSwidmlzaW9uX3ByZXNjcmlwdGlvbnMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJ2aXNpb25fcHJlc2NyaXB0aW9ucyIsbnVsbF0sInZpdGFtaW5fYSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInZpdGFtaW5fYSIsInZpdGFtaW5fYSJdLCJ2aXRhbWluX2IxMiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInZpdGFtaW5fYjEyIiwidml0YW1pbl9iMTIiXSwidml0YW1pbl9iNiI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInZpdGFtaW5fYjYiLCJ2aXRhbWluX2I2Il0sInZpdGFtaW5fYyI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInZpdGFtaW5fYyIsInZpdGFtaW5fYyJdLCJ2aXRhbWluX2QiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJ2aXRhbWluX2QiLCJ2aXRhbWluX2QiXSwidml0YW1pbl9lIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwidml0YW1pbl9lIiwidml0YW1pbl9lIl0sInZpdGFtaW5fayI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsInZpdGFtaW5fayIsInZpdGFtaW5fayJdLCJ2bzJfbWF4IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwidm8yX21heCIsInZvMl9tYXgiXSwid2Fpc3RfY2lyY3VtZmVyZW5jZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsIndhaXN0X2NpcmN1bWZlcmVuY2UiLG51bGxdLCJ3YWxraW5nX2FzeW1tZXRyeSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsIndhbGtpbmdfYXN5bW1ldHJ5IixudWxsXSwid2Fsa2luZ19kb3VibGVfc3VwcG9ydCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsIndhbGtpbmdfZG91YmxlX3N1cHBvcnQiLG51bGxdLCJ3YWxraW5nX2hlYXJ0X3JhdGUiOlsibWFwcGVkX2FsaWFzIiwid2Fsa2luZ19oZWFydF9yYXRlIiwid2Fsa2luZ19ociJdLCJ3YWxraW5nX3NwZWVkIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwid2Fsa2luZ19zcGVlZCIsIndhbGtpbmdfc3BlZWQiXSwid2Fsa2luZ19zdGVhZGluZXNzIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwid2Fsa2luZ19zdGVhZGluZXNzIixudWxsXSwid2Fsa2luZ19zdGVhZGluZXNzX2V2ZW50IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwid2Fsa2luZ19zdGVhZGluZXNzX2V2ZW50IixudWxsXSwid2Fsa2luZ19zdGVwX2xlbmd0aCI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsIndhbGtpbmdfc3RlcF9sZW5ndGgiLG51bGxdLCJ3YXRlcl90ZW1wZXJhdHVyZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsIndhdGVyX3RlbXBlcmF0dXJlIixudWxsXSwid2VpZ2h0IjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwid2VpZ2h0Iiwid2VpZ2h0Il0sIndoZWVsY2hhaXJfdXNlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwid2hlZWxjaGFpcl91c2UiLG51bGxdLCJ3b3Jrb3V0X2VmZm9ydF9zY29yZSI6WyJwbGF0Zm9ybV9leGFjdF9vcl91bmF2YWlsYWJsZSIsIndvcmtvdXRfZWZmb3J0X3Njb3JlIixudWxsXSwid29ya291dHMiOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJ3b3Jrb3V0cyIsIndvcmtvdXRzIl0sIndyaXN0X3RlbXBlcmF0dXJlIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwid3Jpc3RfdGVtcGVyYXR1cmUiLG51bGxdLCJ6aW5jIjpbInBsYXRmb3JtX2V4YWN0X29yX3VuYXZhaWxhYmxlIiwiemluYyIsInppbmMiXX0sInNoYTI1NiI6IjU2ZGVmNjQ0YmFhM2Q4MWUwYzZjMmVkYTM3MzNiZmRkN2NlZWU2NTU0Y2E5ZWM2MDlkYTgwMzU2YzY1NzhjOTkifSwic2hhcGUiOnsiJGRlZnMiOnsiYW5kcm9pZEV4dGVuc2lvbiI6eyJhZGRpdGlvbmFsUHJvcGVydGllcyI6ZmFsc2UsInByb3BlcnRpZXMiOnsiZXhwb3J0Ijp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJjb21wYXRpYmlsaXR5X3Byb2ZpbGUiOnsiZW51bSI6WyJmcm96ZW5fdjQiLCJhbmFseXRpY2FsX3Y1Il19LCJmb2xkZXJfb3JnYW5pemF0aW9uIjp7ImVudW0iOlsiZmxhdCIsImJ5X3llYXIiLCJieV9tb250aCIsImJ5X3llYXJfbW9udGgiXX0sImluY2x1ZGVfYW5kcm9pZF9uYXRpdmVfZmllbGRzIjp7InR5cGUiOiJib29sZWFuIn0sImluY2x1ZGVfbGVnYWN5X2FsaWFzZXMiOnsidHlwZSI6ImJvb2xlYW4ifSwibGVnYWN5X2RhdGFfdHlwZXMiOnsiJHJlZiI6IiMvJGRlZnMvbGVnYWN5RGF0YVR5cGVzIn0sImxlZ2FjeV9wcmltYXJ5X2Zvcm1hdCI6eyJlbnVtIjpbIm1hcmtkb3duIiwib2JzaWRpYW5fYmFzZXMiLCJqc29uIiwiY3N2Il19LCJtb2RlIjp7ImVudW0iOlsiY29tcGF0aWJpbGl0eSIsInJhd19zbmFwc2hvdCJdfSwicmF3X3NuYXBzaG90Ijp7IiRyZWYiOiIjLyRkZWZzL3Jhd1NuYXBzaG90In0sInN1YmZvbGRlciI6eyIkcmVmIjoiIy8kZGVmcy9yZWxhdGl2ZVBhdGgifX0sInJlcXVpcmVkIjpbIm1vZGUiLCJsZWdhY3lfcHJpbWFyeV9mb3JtYXQiLCJjb21wYXRpYmlsaXR5X3Byb2ZpbGUiLCJpbmNsdWRlX2xlZ2FjeV9hbGlhc2VzIiwiaW5jbHVkZV9hbmRyb2lkX25hdGl2ZV9maWVsZHMiLCJsZWdhY3lfZGF0YV90eXBlcyIsInN1YmZvbGRlciIsImZvbGRlcl9vcmdhbml6YXRpb24iLCJyYXdfc25hcHNob3QiXSwidHlwZSI6Im9iamVjdCJ9LCJleHRlbnNpb25fdmVyc2lvbiI6eyJjb25zdCI6MiwidHlwZSI6ImludGVnZXIifX0sInJlcXVpcmVkIjpbImV4dGVuc2lvbl92ZXJzaW9uIiwiZXhwb3J0Il0sInR5cGUiOiJvYmplY3QifSwiYXBpRW5kcG9pbnQiOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7ImNyZWRlbnRpYWxzX3JlcXVpcmVkIjp7ImNvbnN0Ijp0cnVlfSwiaG9zdCI6eyJtYXhMZW5ndGgiOjI1MywibWluTGVuZ3RoIjoxLCJwYXR0ZXJuIjoiXig/PS57MSwyNTN9JClbQS1aYS16MC05XSg/OltBLVphLXowLTktXXswLDYxfVtBLVphLXowLTldKT8oPzpcXC5bQS1aYS16MC05XSg/OltBLVphLXowLTktXXswLDYxfVtBLVphLXowLTldKT8pKiQoPyFbXFxzXFxTXSkiLCJ0eXBlIjoic3RyaW5nIn0sInBhdGgiOnsibWF4TGVuZ3RoIjoyMDQ4LCJwYXR0ZXJuIjoiXi8oPyEvKVtBLVphLXowLTkvLl9+ISQmJygpKissOz06LV0qJCg/IVtcXHNcXFNdKSIsInR5cGUiOiJzdHJpbmcifSwicG9ydCI6eyJvbmVPZiI6W3sidHlwZSI6Im51bGwifSx7Im1heGltdW0iOjY1NTM1LCJtaW5pbXVtIjoxLCJ0eXBlIjoiaW50ZWdlciJ9XX0sInF1ZXJ5X29taXR0ZWQiOnsidHlwZSI6ImJvb2xlYW4ifSwic2NoZW1lIjp7ImNvbnN0IjoiaHR0cHMifX0sInJlcXVpcmVkIjpbInNjaGVtZSIsImhvc3QiLCJwb3J0IiwicGF0aCIsInF1ZXJ5X29taXR0ZWQiLCJjcmVkZW50aWFsc19yZXF1aXJlZCJdLCJ0eXBlIjoib2JqZWN0In0sImFwcGxlRXh0ZW5zaW9uIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJkYWlseV9ub3RlcyI6eyJhZGRpdGlvbmFsUHJvcGVydGllcyI6ZmFsc2UsInByb3BlcnRpZXMiOnsib25seSI6eyJ0eXBlIjoiYm9vbGVhbiJ9fSwicmVxdWlyZWQiOlsib25seSJdLCJ0eXBlIjoib2JqZWN0In0sImV4cG9ydCI6eyJhZGRpdGlvbmFsUHJvcGVydGllcyI6ZmFsc2UsInByb3BlcnRpZXMiOnsiYXJjaGl2ZV9maWxlcyI6eyJ0eXBlIjoiYm9vbGVhbiJ9LCJnZW5lcmF0ZV9yYW5nZV9zdW1tYXJ5Ijp7InR5cGUiOiJib29sZWFuIn0sImhlYWx0aGtpdF9zb3VyY2VfYXJjaGl2ZSI6eyJlbnVtIjpbIm5vbmUiLCJjYW5vbmljYWxfdjEiXX0sImluY2x1ZGVfZGF0YV9kaWN0aW9uYXJ5Ijp7InR5cGUiOiJib29sZWFuIn0sIm9yZ2FuaXplX2Zvcm1hdHNfaW50b19mb2xkZXJzIjp7InR5cGUiOiJib29sZWFuIn0sInN1bW1hcnlfb25seSI6eyJ0eXBlIjoiYm9vbGVhbiJ9fSwicmVxdWlyZWQiOlsib3JnYW5pemVfZm9ybWF0c19pbnRvX2ZvbGRlcnMiLCJhcmNoaXZlX2ZpbGVzIiwiaW5jbHVkZV9kYXRhX2RpY3Rpb25hcnkiLCJzdW1tYXJ5X29ubHkiLCJoZWFsdGhraXRfc291cmNlX2FyY2hpdmUiLCJnZW5lcmF0ZV9yYW5nZV9zdW1tYXJ5Il0sInR5cGUiOiJvYmplY3QifSwiZXh0ZW5zaW9uX3ZlcnNpb24iOnsiY29uc3QiOjIsInR5cGUiOiJpbnRlZ2VyIn0sInNjaGVkdWxlIjp7Im9uZU9mIjpbeyJ0eXBlIjoibnVsbCJ9LHsiJHJlZiI6IiMvJGRlZnMvYXBwbGVTY2hlZHVsZSJ9XX19LCJyZXF1aXJlZCI6WyJleHRlbnNpb25fdmVyc2lvbiIsImV4cG9ydCIsImRhaWx5X25vdGVzIiwic2NoZWR1bGUiXSwidHlwZSI6Im9iamVjdCJ9LCJhcHBsZVNjaGVkdWxlIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJjdXN0b21fdW5pdCI6eyJlbnVtIjpbImRheXMiLCJ3ZWVrcyIsIm1vbnRocyJdfSwiZnJlcXVlbmN5Ijp7ImVudW0iOlsiZGFpbHkiLCJ3ZWVrbHkiLCJjdXN0b20iXX0sInRvZGF5X3JlZnJlc2hfaW50ZXJ2YWxfaG91cnMiOnsiZW51bSI6WzMsNiwxMl0sInR5cGUiOiJpbnRlZ2VyIn0sInRvZGF5X3JlZnJlc2hfcmVxdWVzdGVkIjp7InR5cGUiOiJib29sZWFuIn19LCJyZXF1aXJlZCI6WyJmcmVxdWVuY3kiLCJjdXN0b21fdW5pdCIsInRvZGF5X3JlZnJlc2hfcmVxdWVzdGVkIiwidG9kYXlfcmVmcmVzaF9pbnRlcnZhbF9ob3VycyJdLCJ0eXBlIjoib2JqZWN0In0sImJvdW5kZWRTdHJpbmciOnsibWF4TGVuZ3RoIjo0MDk2LCJ0eXBlIjoic3RyaW5nIn0sImNhZGVuY2UiOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7ImFuY2hvcl9kYXRlIjp7ImZvcm1hdCI6ImRhdGUiLCJwYXR0ZXJuIjoiXlswLTldezR9LVswLTldezJ9LVswLTldezJ9JCg/IVtcXHNcXFNdKSIsInR5cGUiOiJzdHJpbmcifSwidW5pdCI6eyJlbnVtIjpbImRheXMiLCJ3ZWVrcyIsIm1vbnRocyJdfSwidmFsdWUiOnsibWF4aW11bSI6MzY1LCJtaW5pbXVtIjoxLCJ0eXBlIjoiaW50ZWdlciJ9fSwicmVxdWlyZWQiOlsidmFsdWUiLCJ1bml0IiwiYW5jaG9yX2RhdGUiXSwidHlwZSI6Im9iamVjdCJ9LCJkYWlseU5vdGVzIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJjcmVhdGVfaWZfbWlzc2luZyI6eyJ0eXBlIjoiYm9vbGVhbiJ9LCJlbmFibGVkIjp7InR5cGUiOiJib29sZWFuIn0sImZpbGVuYW1lX3RlbXBsYXRlIjp7IiRyZWYiOiIjLyRkZWZzL2ZpbGVuYW1lVGVtcGxhdGUifSwiZm9sZGVyIjp7IiRyZWYiOiIjLyRkZWZzL3JlbGF0aXZlUGF0aCJ9LCJpbmplY3Rfc2VjdGlvbnMiOnsidHlwZSI6ImJvb2xlYW4ifX0sInJlcXVpcmVkIjpbImVuYWJsZWQiLCJmb2xkZXIiLCJmaWxlbmFtZV90ZW1wbGF0ZSIsImNyZWF0ZV9pZl9taXNzaW5nIiwiaW5qZWN0X3NlY3Rpb25zIl0sInR5cGUiOiJvYmplY3QifSwiZGVzdGluYXRpb24iOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7ImFwaV9lbmRwb2ludCI6eyJvbmVPZiI6W3sidHlwZSI6Im51bGwifSx7IiRyZWYiOiIjLyRkZWZzL2FwaUVuZHBvaW50In1dfSwia2luZCI6eyJlbnVtIjpbImRldmljZV9mb2xkZXIiLCJjb25uZWN0ZWRfbWFjIiwiYXBpX2VuZHBvaW50IiwiY2xvdWQiXX19LCJyZXF1aXJlZCI6WyJraW5kIiwiYXBpX2VuZHBvaW50Il0sInR5cGUiOiJvYmplY3QifSwiZXhwb3J0Ijp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJjb21wYXRpYmlsaXR5X2RldGFpbCI6eyJlbnVtIjpbInN1bW1hcnkiLCJzZWxlY3RlZF90aW1lX3NlcmllcyJdfSwiZmlsZW5hbWVfdGVtcGxhdGUiOnsiJHJlZiI6IiMvJGRlZnMvZmlsZW5hbWVUZW1wbGF0ZSJ9LCJmb2xkZXJfdGVtcGxhdGUiOnsiJHJlZiI6IiMvJGRlZnMvcmVsYXRpdmVQYXRoIn0sImZvcm1hdHMiOnsiaXRlbXMiOnsiZW51bSI6WyJtYXJrZG93biIsIm9ic2lkaWFuX2Jhc2VzIiwianNvbiIsImNzdiJdfSwibWF4SXRlbXMiOjQsInR5cGUiOiJhcnJheSIsInVuaXF1ZUl0ZW1zIjp0cnVlfSwiZ3JvdXBfYnlfY2F0ZWdvcnkiOnsidHlwZSI6ImJvb2xlYW4ifSwiaW5jbHVkZV9tZXRhZGF0YSI6eyJ0eXBlIjoiYm9vbGVhbiJ9LCJ3cml0ZV9tb2RlIjp7ImVudW0iOlsib3ZlcndyaXRlIiwiYXBwZW5kIiwidXBkYXRlIl19fSwicmVxdWlyZWQiOlsiZm9ybWF0cyIsImluY2x1ZGVfbWV0YWRhdGEiLCJncm91cF9ieV9jYXRlZ29yeSIsImZpbGVuYW1lX3RlbXBsYXRlIiwiZm9sZGVyX3RlbXBsYXRlIiwid3JpdGVfbW9kZSIsImNvbXBhdGliaWxpdHlfZGV0YWlsIl0sInR5cGUiOiJvYmplY3QifSwiZmlsZW5hbWVUZW1wbGF0ZSI6eyJtYXhMZW5ndGgiOjQwOTYsIm1pbkxlbmd0aCI6MSwicGF0dGVybiI6Il4oPyFcXC57MSwyfSQpKD8hW0EtWmEtel06KSg/IS4qWy9cXFxcJV0pKD8hLipbXFx1MDAwMC1cXHUwMDFmXSkuKyQoPyFbXFxzXFxTXSkiLCJ0eXBlIjoic3RyaW5nIn0sImZyb250bWF0dGVyIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJjdXN0b21fdmFsdWVzIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjp7IiRyZWYiOiIjLyRkZWZzL2JvdW5kZWRTdHJpbmcifSwibWF4UHJvcGVydGllcyI6MTI4LCJwcm9wZXJ0eU5hbWVzIjp7IiRyZWYiOiIjLyRkZWZzL25vbkVtcHR5U2hvcnRTdHJpbmcifSwidHlwZSI6Im9iamVjdCJ9LCJkYXRlX2tleSI6eyIkcmVmIjoiIy8kZGVmcy9ub25FbXB0eVNob3J0U3RyaW5nIn0sImZpZWxkcyI6eyJpdGVtcyI6eyIkcmVmIjoiIy8kZGVmcy9mcm9udG1hdHRlckZpZWxkIn0sIm1heEl0ZW1zIjoyNTYsInR5cGUiOiJhcnJheSJ9LCJpbmNsdWRlX2RhdGUiOnsidHlwZSI6ImJvb2xlYW4ifSwiaW5jbHVkZV90eXBlIjp7InR5cGUiOiJib29sZWFuIn0sImtleV9zdHlsZSI6eyJlbnVtIjpbInNuYWtlX2Nhc2UiLCJjYW1lbF9jYXNlIl19LCJwbGFjZWhvbGRlcnMiOnsiaXRlbXMiOnsiJHJlZiI6IiMvJGRlZnMvbm9uRW1wdHlTaG9ydFN0cmluZyJ9LCJtYXhJdGVtcyI6MTI4LCJ0eXBlIjoiYXJyYXkiLCJ1bmlxdWVJdGVtcyI6dHJ1ZX0sInR5cGVfa2V5Ijp7IiRyZWYiOiIjLyRkZWZzL25vbkVtcHR5U2hvcnRTdHJpbmcifSwidHlwZV92YWx1ZSI6eyIkcmVmIjoiIy8kZGVmcy9ib3VuZGVkU3RyaW5nIn19LCJyZXF1aXJlZCI6WyJmaWVsZHMiLCJjdXN0b21fdmFsdWVzIiwicGxhY2Vob2xkZXJzIiwiaW5jbHVkZV9kYXRlIiwiaW5jbHVkZV90eXBlIiwiZGF0ZV9rZXkiLCJ0eXBlX2tleSIsInR5cGVfdmFsdWUiLCJrZXlfc3R5bGUiXSwidHlwZSI6Im9iamVjdCJ9LCJmcm9udG1hdHRlckZpZWxkIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJlbmFibGVkIjp7InR5cGUiOiJib29sZWFuIn0sIm91dHB1dF9rZXkiOnsiJHJlZiI6IiMvJGRlZnMvbm9uRW1wdHlTaG9ydFN0cmluZyJ9LCJzb3VyY2Vfa2V5Ijp7IiRyZWYiOiIjLyRkZWZzL25vbkVtcHR5U2hvcnRTdHJpbmcifX0sInJlcXVpcmVkIjpbInNvdXJjZV9rZXkiLCJvdXRwdXRfa2V5IiwiZW5hYmxlZCJdLCJ0eXBlIjoib2JqZWN0In0sImlkZW50aWZpZXIiOnsibWF4TGVuZ3RoIjoxMjgsIm1pbkxlbmd0aCI6MSwicGF0dGVybiI6Il5bYS16XVthLXowLTlfXSooPzpbLi1dW2EtejAtOV9dKykqJCg/IVtcXHNcXFNdKSIsInR5cGUiOiJzdHJpbmcifSwiaW5kaXZpZHVhbEVudHJpZXMiOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7ImVuYWJsZWQiOnsidHlwZSI6ImJvb2xlYW4ifSwiZW50cmllc19mb2xkZXIiOnsiJHJlZiI6IiMvJGRlZnMvcmVsYXRpdmVQYXRoIn0sImZpbGVuYW1lX3RlbXBsYXRlIjp7IiRyZWYiOiIjLyRkZWZzL2ZpbGVuYW1lVGVtcGxhdGUifSwibWV0cmljcyI6eyJhZGRpdGlvbmFsUHJvcGVydGllcyI6eyIkcmVmIjoiIy8kZGVmcy9pbmRpdmlkdWFsTWV0cmljIn0sIm1heFByb3BlcnRpZXMiOjI1NiwicHJvcGVydHlOYW1lcyI6eyIkcmVmIjoiIy8kZGVmcy9pZGVudGlmaWVyIn0sInR5cGUiOiJvYmplY3QifSwib3JnYW5pemVfYnlfY2F0ZWdvcnkiOnsidHlwZSI6ImJvb2xlYW4ifX0sInJlcXVpcmVkIjpbImVuYWJsZWQiLCJtZXRyaWNzIiwiZW50cmllc19mb2xkZXIiLCJvcmdhbml6ZV9ieV9jYXRlZ29yeSIsImZpbGVuYW1lX3RlbXBsYXRlIl0sInR5cGUiOiJvYmplY3QifSwiaW5kaXZpZHVhbE1ldHJpYyI6eyJhZGRpdGlvbmFsUHJvcGVydGllcyI6ZmFsc2UsInByb3BlcnRpZXMiOnsiY3VzdG9tX2ZvbGRlciI6eyJvbmVPZiI6W3sidHlwZSI6Im51bGwifSx7IiRyZWYiOiIjLyRkZWZzL3JlbGF0aXZlUGF0aCJ9XX0sImVuYWJsZWQiOnsidHlwZSI6ImJvb2xlYW4ifX0sInJlcXVpcmVkIjpbImVuYWJsZWQiLCJjdXN0b21fZm9sZGVyIl0sInR5cGUiOiJvYmplY3QifSwibGVnYWN5RGF0YVR5cGVzIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJhY3Rpdml0eSI6eyJ0eXBlIjoiYm9vbGVhbiJ9LCJib2R5Ijp7InR5cGUiOiJib29sZWFuIn0sImhlYXJ0Ijp7InR5cGUiOiJib29sZWFuIn0sIm1lZGljYWxfcmVzb3VyY2VzIjp7InR5cGUiOiJib29sZWFuIn0sIm1pbmRmdWxuZXNzIjp7InR5cGUiOiJib29sZWFuIn0sIm1vYmlsaXR5Ijp7InR5cGUiOiJib29sZWFuIn0sIm51dHJpdGlvbiI6eyJ0eXBlIjoiYm9vbGVhbiJ9LCJwbGFubmVkX3dvcmtvdXRzIjp7InR5cGUiOiJib29sZWFuIn0sInJlcHJvZHVjdGl2ZV9oZWFsdGgiOnsidHlwZSI6ImJvb2xlYW4ifSwic2xlZXAiOnsidHlwZSI6ImJvb2xlYW4ifSwidml0YWxzIjp7InR5cGUiOiJib29sZWFuIn0sIndvcmtvdXRzIjp7InR5cGUiOiJib29sZWFuIn19LCJyZXF1aXJlZCI6WyJzbGVlcCIsImFjdGl2aXR5IiwiaGVhcnQiLCJ2aXRhbHMiLCJib2R5IiwibnV0cml0aW9uIiwibW9iaWxpdHkiLCJyZXByb2R1Y3RpdmVfaGVhbHRoIiwibWluZGZ1bG5lc3MiLCJ3b3Jrb3V0cyIsInBsYW5uZWRfd29ya291dHMiLCJtZWRpY2FsX3Jlc291cmNlcyJdLCJ0eXBlIjoib2JqZWN0In0sImxvY2FsVGltZSI6eyJhZGRpdGlvbmFsUHJvcGVydGllcyI6ZmFsc2UsInByb3BlcnRpZXMiOnsiaG91ciI6eyJtYXhpbXVtIjoyMywibWluaW11bSI6MCwidHlwZSI6ImludGVnZXIifSwibWludXRlIjp7Im1heGltdW0iOjU5LCJtaW5pbXVtIjowLCJ0eXBlIjoiaW50ZWdlciJ9fSwicmVxdWlyZWQiOlsiaG91ciIsIm1pbnV0ZSJdLCJ0eXBlIjoib2JqZWN0In0sIm1hcmtkb3duIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJidWxsZXRfc3R5bGUiOnsiZW51bSI6WyJkYXNoIiwiYXN0ZXJpc2siLCJwbHVzIl19LCJjdXN0b21fdGV4dCI6eyJtYXhMZW5ndGgiOjY1NTM2LCJ0eXBlIjoic3RyaW5nIn0sImhlYWRlcl9sZXZlbCI6eyJtYXhpbXVtIjo2LCJtaW5pbXVtIjoxLCJ0eXBlIjoiaW50ZWdlciJ9LCJpbmNsdWRlX3N1bW1hcnkiOnsidHlwZSI6ImJvb2xlYW4ifSwib3JpZ2luX2RpYWxlY3QiOnsiZW51bSI6WyJwb3J0YWJsZSIsImFwcGxlIiwiYW5kcm9pZCJdfSwic3R5bGUiOnsiZW51bSI6WyJzdGFuZGFyZCIsImNvbXBhY3QiLCJkZXRhaWxlZCIsImN1c3RvbSJdfSwidXNlX2Vtb2ppIjp7InR5cGUiOiJib29sZWFuIn19LCJyZXF1aXJlZCI6WyJzdHlsZSIsImN1c3RvbV90ZXh0IiwiaGVhZGVyX2xldmVsIiwidXNlX2Vtb2ppIiwiaW5jbHVkZV9zdW1tYXJ5IiwiYnVsbGV0X3N0eWxlIiwib3JpZ2luX2RpYWxlY3QiXSwidHlwZSI6Im9iamVjdCJ9LCJtZXRyaWNBbGlhcyI6eyJhZGRpdGlvbmFsUHJvcGVydGllcyI6ZmFsc2UsInByb3BlcnRpZXMiOnsiYW5kcm9pZF9zZWxlY3Rpb25faWQiOnsib25lT2YiOlt7InR5cGUiOiJudWxsIn0seyIkcmVmIjoiIy8kZGVmcy9pZGVudGlmaWVyIn1dfSwiYXBwbGVfc2VsZWN0aW9uX2lkIjp7Im9uZU9mIjpbeyJ0eXBlIjoibnVsbCJ9LHsiJHJlZiI6IiMvJGRlZnMvaWRlbnRpZmllciJ9XX0sImVxdWl2YWxlbmNlIjp7ImVudW0iOlsicGxhdGZvcm1fZXhhY3Rfb3JfdW5hdmFpbGFibGUiLCJtYXBwZWRfYWxpYXMiLCJwbGF0Zm9ybV9kaXN0aW5jdCJdfSwic2VtYW50aWNfaWQiOnsiJHJlZiI6IiMvJGRlZnMvaWRlbnRpZmllciJ9fSwicmVxdWlyZWQiOlsic2VtYW50aWNfaWQiLCJlcXVpdmFsZW5jZSIsImFwcGxlX3NlbGVjdGlvbl9pZCIsImFuZHJvaWRfc2VsZWN0aW9uX2lkIl0sInR5cGUiOiJvYmplY3QifSwibWV0cmljUmVnaXN0cnkiOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7InJlZ2lzdHJ5X3NoYTI1NiI6eyJwYXR0ZXJuIjoiXlswLTlhLWZdezY0fSQoPyFbXFxzXFxTXSkiLCJ0eXBlIjoic3RyaW5nIn0sInJlZ2lzdHJ5X3ZlcnNpb24iOnsiY29uc3QiOjEsInR5cGUiOiJpbnRlZ2VyIn0sInNjaGVtYSI6eyJjb25zdCI6ImhlYWx0aG1kLm1ldHJpY19yZWdpc3RyeSJ9fSwicmVxdWlyZWQiOlsic2NoZW1hIiwicmVnaXN0cnlfdmVyc2lvbiIsInJlZ2lzdHJ5X3NoYTI1NiJdLCJ0eXBlIjoib2JqZWN0In0sIm1ldHJpY3MiOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7ImVuYWJsZWRfaWRzIjp7Iml0ZW1zIjp7IiRyZWYiOiIjLyRkZWZzL2lkZW50aWZpZXIifSwibWF4SXRlbXMiOjI1NiwidHlwZSI6ImFycmF5IiwidW5pcXVlSXRlbXMiOnRydWV9fSwicmVxdWlyZWQiOlsiZW5hYmxlZF9pZHMiXSwidHlwZSI6Im9iamVjdCJ9LCJub25FbXB0eVNob3J0U3RyaW5nIjp7Im1heExlbmd0aCI6MjU2LCJtaW5MZW5ndGgiOjEsInBhdHRlcm4iOiJeW15cXHUwMDAwLVxcdTAwMWZcXHUwMDdmXSskKD8hW1xcc1xcU10pIiwidHlwZSI6InN0cmluZyJ9LCJwbGF0Zm9ybUV4dGVuc2lvbnMiOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7ImFuZHJvaWQiOnsib25lT2YiOlt7InR5cGUiOiJudWxsIn0seyIkcmVmIjoiIy8kZGVmcy9hbmRyb2lkRXh0ZW5zaW9uIn1dfSwiYXBwbGUiOnsib25lT2YiOlt7InR5cGUiOiJudWxsIn0seyIkcmVmIjoiIy8kZGVmcy9hcHBsZUV4dGVuc2lvbiJ9XX19LCJyZXF1aXJlZCI6WyJhcHBsZSIsImFuZHJvaWQiXSwidHlwZSI6Im9iamVjdCJ9LCJwcmVzZW50YXRpb24iOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7ImRhdGVfZm9ybWF0Ijp7ImVudW0iOlsiaXNvODYwMSIsInVzX3Nob3J0IiwidXNfbG9uZyIsImV1X3Nob3J0IiwiZXVfbG9uZyIsImNvbXBhY3QiLCJmcmllbmRseSJdfSwiZnJvbnRtYXR0ZXIiOnsiJHJlZiI6IiMvJGRlZnMvZnJvbnRtYXR0ZXIifSwibWFya2Rvd24iOnsiJHJlZiI6IiMvJGRlZnMvbWFya2Rvd24ifSwidGltZV9mb3JtYXQiOnsiZW51bSI6WyJob3VyXzI0IiwiaG91cl8yNF9zZWNvbmRzIiwiaG91cl8xMiIsImhvdXJfMTJfc2Vjb25kcyJdfSwidW5pdHMiOnsiZW51bSI6WyJtZXRyaWMiLCJpbXBlcmlhbCJdfX0sInJlcXVpcmVkIjpbImRhdGVfZm9ybWF0IiwidGltZV9mb3JtYXQiLCJ1bml0cyIsImZyb250bWF0dGVyIiwibWFya2Rvd24iXSwidHlwZSI6Im9iamVjdCJ9LCJwcm9maWxlIjp7ImFkZGl0aW9uYWxQcm9wZXJ0aWVzIjpmYWxzZSwicHJvcGVydGllcyI6eyJkYWlseV9ub3RlcyI6eyIkcmVmIjoiIy8kZGVmcy9kYWlseU5vdGVzIn0sImRlc3RpbmF0aW9uIjp7IiRyZWYiOiIjLyRkZWZzL2Rlc3RpbmF0aW9uIn0sImV4cG9ydCI6eyIkcmVmIjoiIy8kZGVmcy9leHBvcnQifSwiaW5kaXZpZHVhbF9lbnRyaWVzIjp7IiRyZWYiOiIjLyRkZWZzL2luZGl2aWR1YWxFbnRyaWVzIn0sIm1ldHJpY3MiOnsiJHJlZiI6IiMvJGRlZnMvbWV0cmljcyJ9LCJuYW1lIjp7IiRyZWYiOiIjLyRkZWZzL3Byb2ZpbGVOYW1lIn0sInBsYXRmb3JtX2V4dGVuc2lvbnMiOnsiJHJlZiI6IiMvJGRlZnMvcGxhdGZvcm1FeHRlbnNpb25zIn0sInByZXNlbnRhdGlvbiI6eyIkcmVmIjoiIy8kZGVmcy9wcmVzZW50YXRpb24ifSwic2NoZWR1bGUiOnsib25lT2YiOlt7InR5cGUiOiJudWxsIn0seyIkcmVmIjoiIy8kZGVmcy9zY2hlZHVsZSJ9XX19LCJyZXF1aXJlZCI6WyJuYW1lIiwiZXhwb3J0IiwibWV0cmljcyIsInByZXNlbnRhdGlvbiIsImluZGl2aWR1YWxfZW50cmllcyIsImRhaWx5X25vdGVzIiwiZGVzdGluYXRpb24iLCJzY2hlZHVsZSIsInBsYXRmb3JtX2V4dGVuc2lvbnMiXSwidHlwZSI6Im9iamVjdCJ9LCJwcm9maWxlTmFtZSI6eyJtYXhMZW5ndGgiOjI1NiwibWluTGVuZ3RoIjoxLCJwYXR0ZXJuIjoiXlteXFx1MDAwMC1cXHUwMDFmXFx1MDA3Zl0rJCg/IVtcXHNcXFNdKSIsInR5cGUiOiJzdHJpbmcifSwicmF3U25hcHNob3QiOnsiYWRkaXRpb25hbFByb3BlcnRpZXMiOmZhbHNlLCJwcm9wZXJ0aWVzIjp7ImZvcm1hdCI6eyJlbnVtIjpbImpzb24iLCJuZGpzb24iXX0sImluY2x1ZGVfZXhlcmNpc2Vfcm91dGVzIjp7InR5cGUiOiJib29sZWFuIn0sInBhZ2Vfc2l6ZSI6eyJtYXhpbXVtIjo1MDAwLCJtaW5pbXVtIjoxLCJ0eXBlIjoiaW50ZWdlciJ9LCJzY29wZSI6eyJlbnVtIjpbInNlbGVjdGVkX3JlY29yZF90eXBlcyIsImFsbF9hdXRob3JpemVkX3N1cHBvcnRlZF9kYXRhIl19fSwicmVxdWlyZWQiOlsiZm9ybWF0Iiwic2NvcGUiLCJpbmNsdWRlX2V4ZXJjaXNlX3JvdXRlcyIsInBhZ2Vfc2l6ZSJdLCJ0eXBlIjoib2JqZWN0In0sInJlbGF0aXZlUGF0aCI6eyJtYXhMZW5ndGgiOjQwOTYsInBhdHRlcm4iOiJeKD8hLykoPyFbQS1aYS16XTopKD8hLipbXFxcXCVdKSg/IS4qLy8pKD8hLiooPzpefC8pXFwuezEsMn0oPzovfCQpKSg/IS4qOi8vKSg/IS4qW1xcdTAwMDAtXFx1MDAxZl0pLiokKD8hW1xcc1xcU10pIiwidHlwZSI6InN0cmluZyJ9LCJzY2hlZHVsZSI6eyJhZGRpdGlvbmFsUHJvcGVydGllcyI6ZmFsc2UsInByb3BlcnRpZXMiOnsiYWN0aXZhdGlvbl9yZXF1ZXN0ZWQiOnsidHlwZSI6ImJvb2xlYW4ifSwiY2FkZW5jZSI6eyIkcmVmIjoiIy8kZGVmcy9jYWRlbmNlIn0sImRhdGVfd2luZG93Ijp7ImNvbnN0IjoicGFzdF9jb21wbGV0ZV9kYXlzIn0sImxvY2FsX3RpbWUiOnsiJHJlZiI6IiMvJGRlZnMvbG9jYWxUaW1lIn0sImxvb2tiYWNrX2RheXMiOnsibWF4aW11bSI6MzY1LCJtaW5pbXVtIjoxLCJ0eXBlIjoiaW50ZWdlciJ9LCJ3ZWVrZGF5Ijp7Im1heGltdW0iOjcsIm1pbmltdW0iOjEsInR5cGUiOiJpbnRlZ2VyIn19LCJyZXF1aXJlZCI6WyJhY3RpdmF0aW9uX3JlcXVlc3RlZCIsImNhZGVuY2UiLCJsb2NhbF90aW1lIiwid2Vla2RheSIsImxvb2tiYWNrX2RheXMiLCJkYXRlX3dpbmRvdyJdLCJ0eXBlIjoib2JqZWN0In0sInNob3J0U3RyaW5nIjp7Im1heExlbmd0aCI6MjU2LCJ0eXBlIjoic3RyaW5nIn19LCIkaWQiOiJodHRwczovL2hlYWx0aC5tZC9jb250cmFjdHMvcHJvZmlsZS1zeW5jL3YxL3BvcnRhYmxlLWNvbnRlbnQuc2NoZW1hLmpzb24iLCIkc2NoZW1hIjoiaHR0cHM6Ly9qc29uLXNjaGVtYS5vcmcvZHJhZnQvMjAyMC0xMi9zY2hlbWEiLCJhZGRpdGlvbmFsUHJvcGVydGllcyI6ZmFsc2UsInByb3BlcnRpZXMiOnsibWV0cmljX2FsaWFzZXMiOnsiaXRlbXMiOnsiJHJlZiI6IiMvJGRlZnMvbWV0cmljQWxpYXMifSwibWF4SXRlbXMiOjUxMiwidHlwZSI6ImFycmF5IiwidW5pcXVlSXRlbXMiOnRydWV9LCJtZXRyaWNfcmVnaXN0cnkiOnsiJHJlZiI6IiMvJGRlZnMvbWV0cmljUmVnaXN0cnkifSwib3JpZ2luX3BsYXRmb3JtIjp7ImVudW0iOlsiYXBwbGUiLCJhbmRyb2lkIl19LCJwcm9maWxlIjp7IiRyZWYiOiIjLyRkZWZzL3Byb2ZpbGUifSwic2NoZW1hIjp7ImNvbnN0IjoiaGVhbHRobWQucHJvZmlsZV9zeW5jLnBvcnRhYmxlIn0sInNjaGVtYV92ZXJzaW9uIjp7ImNvbnN0IjoxLCJ0eXBlIjoiaW50ZWdlciJ9fSwicmVxdWlyZWQiOlsic2NoZW1hIiwic2NoZW1hX3ZlcnNpb24iLCJvcmlnaW5fcGxhdGZvcm0iLCJtZXRyaWNfcmVnaXN0cnkiLCJtZXRyaWNfYWxpYXNlcyIsInByb2ZpbGUiXSwidGl0bGUiOiJQcm9wb3NlZCBIZWFsdGgubWQgcHJvZmlsZS1zeW5jIHYxIHBvcnRhYmxlIGNvbnRlbnQgKGNsb3NlZCB2MiBmaWVsZCBwcm9qZWN0aW9uKSIsInR5cGUiOiJvYmplY3QifX0="



    // END GENERATED PINNED DATA
    private static let pinnedData = try! JSONSerialization.jsonObject(with: Data(base64Encoded: dataBase64)!) as! [String: Any]
    private static let portableSchema = pinnedData["shape"] as! [String: Any]
    private static let pinnedRegistry = pinnedData["registry"] as! [String: Any]
}
