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
        var object: [String: Any] = [
            "schema": whoop.schema, "schema_version": whoop.schemaVersion,
            "capture_status": whoop.captureStatus.rawValue,
            "resources": array(whoop.resources), "cycles": array(whoop.cycles),
            "recoveries": array(whoop.recoveries), "sleep": array(whoop.sleep),
            "workouts": array(whoop.workouts), "warnings": array(whoop.warnings)
        ]
        if let fetchedAt = whoop.fetchedAt { object["fetched_at"] = fetchedAt }
        if let body = whoop.body { object["body"] = try jsonObject(body) }
        return ["whoop": object]
    }

    private static func array<Value: Encodable>(_ values: [Value]) -> FoundationJSONLazyArray {
        FoundationJSONLazyArray(values) { try jsonObject($0) }
    }

    private static func jsonObject<Value: Encodable>(_ value: Value) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try JSONSerialization.jsonObject(with: encoder.encode(value))
    }
}
