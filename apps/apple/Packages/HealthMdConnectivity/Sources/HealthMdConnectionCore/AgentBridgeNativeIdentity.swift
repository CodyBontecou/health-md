import Foundation

public enum AgentBridgeIdentityKind: String, Codable, Sendable { case native, derivedChild = "derived_child", external }
public enum AgentBridgeSource: String, Codable, Sendable { case appleHealth = "apple_health", healthConnect = "health_connect", providerNative = "provider_native" }
public enum AgentBridgeMetadataStatus: String, Codable, Sendable { case available, absent, notCaptured = "not_captured", notExposedBySource = "not_exposed_by_source" }
public struct AgentBridgeMetadata: Codable, Equatable, Sendable, BridgeValueCodable {
    public let lastModified: AgentBridgeMetadataStatus
    public let clientRecordID: AgentBridgeMetadataStatus
    public let clientRecordVersion: AgentBridgeMetadataStatus
    public init(lastModified: AgentBridgeMetadataStatus, clientRecordID: AgentBridgeMetadataStatus, clientRecordVersion: AgentBridgeMetadataStatus) { self.lastModified = lastModified; self.clientRecordID = clientRecordID; self.clientRecordVersion = clientRecordVersion }
    init(bridgeJSON: BridgeJSON) throws { let o = try BridgeObject(bridgeJSON, ["last_modified", "client_record_id", "client_record_version"]); lastModified = try o.token("last_modified"); clientRecordID = try o.token("client_record_id"); clientRecordVersion = try o.token("client_record_version"); guard lastModified != .absent, clientRecordVersion != .absent else { throw AgentBridgeValidationError.invalidRequest } }
    var bridgeJSON: BridgeJSON { .object([("last_modified", .string(lastModified.rawValue)), ("client_record_id", .string(clientRecordID.rawValue)), ("client_record_version", .string(clientRecordVersion.rawValue))]) }
}
public enum AgentBridgeRecordIDRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws { guard (1...256).contains(value.unicodeScalars.count) else { throw AgentBridgeValidationError.invalidRequest } }
}
public typealias AgentBridgeRecordID = AgentBridgeText<AgentBridgeRecordIDRule>

/// Source-native identity; not an output/profile schema identifier. Absent-only fields reject null.
public struct AgentBridgeNativeIdentity: Codable, Equatable, Sendable, BridgeValueCodable {
    public let recordType: AgentBridgeNativeType
    public let recordID: AgentBridgeRecordID
    public let kind: AgentBridgeIdentityKind
    public let source: AgentBridgeSource
    public let providerID: AgentBridgeID
    public let metadata: AgentBridgeMetadata
    public let lastModified: AgentBridgeExactTime?
    public let clientRecordID: AgentBridgeRecordID?
    public let clientRecordVersion: Int64?
    public let origin: AgentBridgeRecordID?
    public let parentRecordID: AgentBridgeRecordID?
    public let parentRecordType: AgentBridgeNativeType?
    public init(recordType: AgentBridgeNativeType, recordID: String, kind: AgentBridgeIdentityKind, source: AgentBridgeSource, providerID: AgentBridgeID, metadata: AgentBridgeMetadata, lastModified: AgentBridgeExactTime? = nil, clientRecordID: String? = nil, clientRecordVersion: Int64? = nil, origin: String? = nil, parentRecordID: String? = nil, parentRecordType: AgentBridgeNativeType? = nil) throws {
        self.recordType = recordType; self.recordID = try AgentBridgeRecordID(recordID); self.kind = kind; self.source = source; self.providerID = providerID; self.metadata = metadata; self.lastModified = lastModified; self.clientRecordID = try clientRecordID.map(AgentBridgeRecordID.init); self.clientRecordVersion = clientRecordVersion; self.origin = try origin.map(AgentBridgeRecordID.init); self.parentRecordID = try parentRecordID.map(AgentBridgeRecordID.init); self.parentRecordType = parentRecordType
        try validate()
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["record_type", "record_id", "identity_kind", "source_id", "provider_id", "metadata_status"], optional: ["last_modified", "client_record_id", "client_record_version", "origin", "parent_record_id", "parent_record_type"])
        recordType = try o.value("record_type"); recordID = try o.value("record_id"); kind = try o.token("identity_kind"); source = try o.token("source_id"); providerID = try o.value("provider_id"); metadata = try o.value("metadata_status"); lastModified = try o.optional("last_modified"); clientRecordID = try o.optional("client_record_id"); clientRecordVersion = o.has("client_record_version") ? try o.int("client_record_version") : nil; origin = try o.optional("origin"); parentRecordID = try o.optional("parent_record_id"); parentRecordType = try o.optional("parent_record_type")
        try validate()
    }
    var bridgeJSON: BridgeJSON { .object([("record_type", recordType.bridgeJSON), ("record_id", recordID.bridgeJSON), ("identity_kind", .string(kind.rawValue)), ("source_id", .string(source.rawValue)), ("provider_id", providerID.bridgeJSON), ("metadata_status", metadata.bridgeJSON), ("last_modified", lastModified?.bridgeJSON), ("client_record_id", clientRecordID?.bridgeJSON), ("client_record_version", clientRecordVersion.map(BridgeJSON.int)), ("origin", origin?.bridgeJSON), ("parent_record_id", parentRecordID?.bridgeJSON), ("parent_record_type", parentRecordType?.bridgeJSON)]) }
    private func validate() throws {
        guard (metadata.lastModified == .available) == (lastModified != nil), (metadata.clientRecordID == .available) == (clientRecordID != nil), (metadata.clientRecordVersion == .available) == (clientRecordVersion != nil), metadata.lastModified != .absent, metadata.clientRecordVersion != .absent, clientRecordVersion.map({ $0 >= 0 }) ?? true else { throw AgentBridgeValidationError.invalidRequest }
        if kind == .derivedChild {
            guard parentRecordID != nil, parentRecordType != nil, [metadata.lastModified, metadata.clientRecordID, metadata.clientRecordVersion].allSatisfy({ $0 == .notExposedBySource }) else { throw AgentBridgeValidationError.invalidRequest }
        } else if parentRecordID != nil || parentRecordType != nil { throw AgentBridgeValidationError.invalidRequest }
        switch source {
        case .appleHealth:
            guard providerID.rawValue == "apple_health", [metadata.lastModified, metadata.clientRecordID, metadata.clientRecordVersion].allSatisfy({ $0 == .notExposedBySource }) else { throw AgentBridgeValidationError.invalidRequest }
            if kind == .native { try bridgePattern(recordID.rawValue, "\\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\\z", max: 36) }
        case .healthConnect:
            guard providerID.rawValue == "health_connect" else { throw AgentBridgeValidationError.invalidRequest }
            if kind == .native {
                guard metadata.lastModified != .notExposedBySource, metadata.clientRecordVersion != .notExposedBySource, lastModified.map({ $0.precision == .sourceNanoseconds }) ?? true else { throw AgentBridgeValidationError.invalidRequest }
            }
        case .providerNative: break
        }
    }
}
