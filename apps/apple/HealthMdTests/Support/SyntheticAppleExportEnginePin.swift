import Foundation
@testable import HealthMd

/// Pure Codable fixture used by persistence tests. It deliberately does not load the packaged core.
func makeSyntheticAppleExportEnginePin(
    engine: ExportEngineMode = .rust,
    calendarTimeZoneIdentifier: String = "America/Los_Angeles"
) throws -> AppleExportEnginePin {
    let object: [String: Any] = [
        "engine": engine.rawValue,
        "profile": AppleExportEnginePin.profileID,
        "public_schema": HealthMdExportSchema.identifier,
        "public_schema_version": HealthMdExportSchema.version,
        "core_api_version": 4,
        "semantic_input_version": 1,
        "canonical_model_version": 1,
        "render_input_version": 1,
        "artifact_plan_version": 1,
        "registry_version": 1,
        "registry_sha256": String(repeating: "a", count: 64),
        "semantic_profile_revision": 1,
        "render_profile_revision": 2,
        "core_source_revision": "synthetic-persistence-test",
        "calendar_time_zone": calendarTimeZoneIdentifier
    ]
    return try JSONDecoder().decode(
        AppleExportEnginePin.self,
        from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    )
}
