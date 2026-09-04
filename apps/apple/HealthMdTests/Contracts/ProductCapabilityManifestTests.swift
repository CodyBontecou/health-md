import Foundation
import XCTest

/// Keeps Apple product capability decisions aligned with the language-neutral
/// Apple/Android parity inventory. The inventory is product governance rather
/// than a runtime resource and must never contain health data.
final class ProductCapabilityManifestTests: XCTestCase {
    func testAppleAccountsForEveryProductCapability() throws {
        let inventory = try Self.loadInventory()

        XCTAssertEqual(inventory.schema, "healthmd.product_capabilities")
        XCTAssertEqual(inventory.schemaVersion, 1)
        XCTAssertEqual(
            Set(inventory.outputProfiles.map(\.id)),
            ["apple-v8", "android-frozen-v4", "android-analytical-v5"]
        )

        let states = Dictionary(uniqueKeysWithValues: inventory.capabilities.map {
            ($0.id, $0.platforms.apple.state)
        })
        XCTAssertEqual(states.count, inventory.capabilities.count, "Capability IDs must be unique")

        XCTAssertEqual(
            Self.ids(with: .available, in: states),
            Self.sharedCapabilities.union(Self.appleCapabilities)
        )
        XCTAssertEqual(
            Self.ids(with: .unavailable, in: states),
            Self.androidCapabilities.union(["source.private-platform-database"])
        )
        XCTAssertEqual(
            Self.ids(with: .planned, in: states),
            ["core.shared-rust-profile-engine", "setup.share-portable-configuration"]
        )
        XCTAssertEqual(Set(states.keys), Self.allCapabilities)
        XCTAssertEqual(
            inventory.capabilities.first { $0.id == "automation.cancel-active-export" }?.classification,
            "shared"
        )
        XCTAssertEqual(
            inventory.capabilities.first { $0.id == "direct.cli_agent_push_wake" }?.classification,
            "planned"
        )

        for capability in inventory.capabilities {
            let availability = capability.platforms.apple
            if availability.state == .unavailable {
                XCTAssertFalse(
                    availability.reason?.isEmpty ?? true,
                    "Unavailable Apple capability \(capability.id) must include a reason"
                )
            }
            if availability.state == .planned {
                XCTAssertFalse(
                    availability.target?.isEmpty ?? true,
                    "Planned Apple capability \(capability.id) must include a target"
                )
            }
        }
    }

    private static func ids(
        with state: CapabilityInventory.Availability.State,
        in states: [String: CapabilityInventory.Availability.State]
    ) -> Set<String> {
        Set(states.compactMap { $0.value == state ? $0.key : nil })
    }

    private static func loadInventory() throws -> CapabilityInventory {
        let data = try Data(contentsOf: try manifestURL())
        return try JSONDecoder().decode(CapabilityInventory.self, from: data)
    }

    private static func manifestURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("packages/contracts/product-capabilities.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw ManifestError.notFound
    }

    private static let sharedCapabilities: Set<String> = [
        "export.daily-files",
        "export.sleep-summary",
        "export.activity-basics",
        "export.cardiorespiratory-summary",
        "export.vitals-and-body",
        "export.nutrient-totals",
        "export.mindfulness-sessions",
        "export.selected-time-series-detail",
        "export.completed-workouts",
        "export.mobility-and-performance",
        "export.profiles",
        "core.shared-rust-metric-registry",
        "automation.cancel-active-export",
        "direct-cli.shared-qr-pairing",
        "direct.cli_agent_wake",
    ]

    private static let appleCapabilities: Set<String> = [
        "apple.lossless-healthkit-archive",
        "apple.medication-dose-events",
        "apple.state-of-mind",
        "apple.wrist-temperature",
        "apple.hearing-and-symptoms",
        "apple.typed-whoop-provider-section",
        "direct.cli_agent_push_wake",
        "export.range-summary",
    ]

    private static let androidCapabilities: Set<String> = [
        "android.activity-intensity",
        "android.planned-workouts",
        "android.menstruation-periods",
        "android.personal-health-records",
        "android.nutrition-meals",
        "android.contextual-source-fields",
        "android.skin-temperature",
    ]

    private static var allCapabilities: Set<String> {
        sharedCapabilities
            .union(appleCapabilities)
            .union(androidCapabilities)
            .union(["source.private-platform-database", "core.shared-rust-profile-engine", "setup.share-portable-configuration"])
    }

    private enum ManifestError: Error {
        case notFound
    }
}

private struct CapabilityInventory: Decodable {
    let schema: String
    let schemaVersion: Int
    let outputProfiles: [OutputProfile]
    let capabilities: [Capability]

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case outputProfiles = "output_profiles"
        case capabilities
    }

    struct OutputProfile: Decodable {
        let id: String
    }

    struct Capability: Decodable {
        let id: String
        let classification: String
        let platforms: Platforms
    }

    struct Platforms: Decodable {
        let apple: Availability
    }

    struct Availability: Decodable {
        let state: State
        let reason: String?
        let target: String?

        enum State: String, Decodable {
            case available
            case unavailable
            case planned
        }
    }
}
