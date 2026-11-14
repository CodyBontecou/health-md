import Foundation
import XCTest
@testable import HealthMdConnectionCore

final class AgentBridgeDelegationTests: XCTestCase {
    func testClosedNativeDelegationIsDescriptionNotWireEnrollment() throws {
        let bytes = Data(Self.native.utf8)
        let grant = try AgentBridgeV4Codec.decode(AgentBridgeExportDelegation.self, from: bytes)
        XCTAssertEqual(try AgentBridgeV4Codec.encode(grant), bytes)
        XCTAssertEqual(grant.rights.map(\.rawValue), ["discover", "export_execute", "plan"])
        XCTAssertEqual(grant.bounds.metricIDs.map(\.rawValue), ["hrv", "steps"])
        XCTAssertEqual(try grant.reference().grantSha256.rawValue, "c7049dd0ca1c746a993cde5a78b35df783ac50351240ff261155b8e8133b5f76")
        XCTAssertThrowsError(try AgentBridgeEnvelope(payload: .delegation(grant))) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .unsupportedCapability)
        }
        XCTAssertThrowsError(try AgentBridgeV4Codec.decode(AgentBridgeExportDelegation.self, from:
            Data(Self.native.replacingOccurrences(of: "authenticated_host_bindings", with: "registered_host_bindings").utf8)))
        for altered in [
            Self.native.replacingOccurrences(of: "\"grant_revision\":1", with: "\"grant_revision\":true"),
            Self.native.replacingOccurrences(of: "\"grant_revision\":1", with: "\"grant_revision\":1,\"grant_\\u0072evision\":1"),
            Self.native.replacingOccurrences(of: "\"plan\"", with: "\"native_configuration_mutate\""),
            Self.native.replacingOccurrences(of: "\"hrv\",\"steps\"", with: "\"steps\",\"hrv\""),
            Self.native.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":1,\"secret\":\"x\"")
        ] {
            XCTAssertThrowsError(try AgentBridgeV4Codec.decode(AgentBridgeExportDelegation.self, from: Data(altered.utf8)))
        }
    }

    private static let native = #"{"authority_id":"00000000-0000-4000-8000-000000000007","bounds":{"calendar_timezones":["UTC"],"compatibility_detail":["summary"],"date_policy":{"allow_all_available":true,"max_days":366,"type":"authorized_history"},"destination_policy":{"type":"authenticated_host_bindings"},"formats":["json"],"metric_ids":["hrv","steps"],"native_archive_products":["none"],"output_profiles":["apple-v8"],"products":["generated_files"],"projection_details":[],"projection_field_ids":[],"projection_object_ids":[],"write_modes":["overwrite"]},"expires_at":"2000-01-03T01:00:00Z","grant_revision":1,"issuer":"native_source","peer":{"host_installation_id":"00000000-0000-4000-8000-000000000002","platform":"apple","source_installation_id":"00000000-0000-4000-8000-000000000001"},"rights":["discover","export_execute","plan"],"schema":"healthmd.agent_export_delegation","schema_version":1}"#
}
