import Foundation

/// Native provider facts are independent of the bounded Apple aggregate semantics.
/// Collections are projected one record at a time after successor attestation.
nonisolated enum AppleWakeDateProviderProjection {
    enum ProjectionError: Error { case invalidProvider }

    static func lazyJSONObject(_ providers: HealthProviderSections) throws -> [String: Any] {
        guard let whoop = providers.whoop else { return [:] }
        guard whoop.schema == WHOOPDailyProviderSection.schemaIdentifier,
              whoop.schemaVersion == WHOOPDailyProviderSection.currentSchemaVersion,
              whoop.recordCountsAreValid else { throw ProjectionError.invalidProvider }
        let counts: [WHOOPResourceName: Int] = [.cycles: whoop.cycles.count, .recovery: whoop.recoveries.count,
            .sleep: whoop.sleep.count, .workouts: whoop.workouts.count, .body: whoop.body == nil ? 0 : 1]
        let resources = Set(whoop.resources.map(\.resource))
        guard counts.allSatisfy({ $0.value == 0 || resources.contains($0.key) }) else { throw ProjectionError.invalidProvider }
        if whoop.captureStatus == .notRequested {
            guard whoop.fetchedAt == nil, whoop.resources.isEmpty, counts.values.allSatisfy({ $0 == 0 }) else {
                throw ProjectionError.invalidProvider
            }
        } else {
            guard whoop.fetchedAt != nil, !whoop.resources.isEmpty else { throw ProjectionError.invalidProvider }
        }
        var object: [String: Any] = [
            "schema": whoop.schema, "schema_version": whoop.schemaVersion,
            "capture_status": whoop.captureStatus.rawValue,
            "resources": array(whoop.resources), "cycles": array(whoop.cycles),
            "recoveries": array(whoop.recoveries), "sleep": array(whoop.sleep),
            "workouts": array(whoop.workouts), "warnings": array(whoop.warnings)
        ]
        object["fetched_at"] = whoop.fetchedAt.map { $0 as Any } ?? NSNull()
        if let body = whoop.body { object["body"] = try jsonObject(body) }
        return ["whoop": object]
    }

    private static func array<Value: Encodable>(_ values: [Value]) -> FoundationJSONLazyArray {
        FoundationJSONLazyArray(values) { try jsonObject($0) }
    }

    static func writeMarkdownSection(_ providers: HealthProviderSections, headerPrefix: String,
        to sink: ExportByteSink) throws {
        guard !providers.isEmpty else { return }
        try sink.write(Data("\n\(headerPrefix) WHOOP Source Facts\n\n| Native Provider (JSON) |\n|---|\n| `".utf8))
        let escaped = MarkdownJSONCodeCellSink(output: sink)
        try HealthKitRecordArchiveSerializer.writeDailyJSONObject(lazyJSONObject(providers), archive: nil,
            to: escaped, outputFormatting: [.sortedKeys])
        _ = try escaped.finish()
        try sink.write(Data("` |\n".utf8))
    }

    /// Adds the established flat namespace without changing Apple metric values or units.
    static func addingFrontmatter(to aggregate: Data, providers: HealthProviderSections,
        includeMetadata: Bool) throws -> Data {
        guard includeMetadata, let whoop = providers.whoop else { return aggregate }
        guard let text = String(data: aggregate, encoding: .utf8) else { throw ProjectionError.invalidProvider }
        var lines = text.components(separatedBy: "\n")
        guard lines.first == "---", let closing = lines.indices.dropFirst().first(where: { lines[$0] == "---" }),
              !lines[1..<closing].contains(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("whoop_") }) else {
            throw ProjectionError.invalidProvider
        }
        let scalars = whoop.flatScalars
        let fields = try scalars.map { scalar in
            // Numeric fields retain their existing machine values. Text is quoted to
            // keep provider labels from introducing YAML keys or delimiters.
            let value: String
            if scalar.definition.key == "whoop_capture_status" || scalar.definition.key == "whoop_workout_sport_name" {
                value = String(decoding: try JSONSerialization.data(withJSONObject: scalar.value,
                    options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
            } else { value = scalar.value }
            return "\(scalar.definition.key): \(value)"
        }
        let units = scalars.filter { !$0.definition.unit.isEmpty }.map {
            "  \($0.definition.key): \($0.definition.unit)"
        }
        if let index = lines[1..<closing].firstIndex(of: "units:") {
            let end = ((index + 1)..<closing).first { !lines[$0].hasPrefix(" ") } ?? closing
            lines.insert(contentsOf: units, at: end)
            lines.insert(contentsOf: fields, at: index)
        } else {
            lines.insert(contentsOf: fields + (units.isEmpty ? [] : ["units:"] + units), at: closing)
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func jsonObject<Value: Encodable>(_ value: Value) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }
}
