import Foundation

public enum AgentBridgePlatform: String, Codable, Sendable { case apple, android }
public enum AgentBridgeFormat: String, Codable, Sendable { case csv, json, markdown, obsidianBases = "obsidian_bases" }
public enum AgentBridgeOutputProfile: String, Codable, Sendable { case appleV8 = "apple-v8", androidFrozenV4 = "android-frozen-v4", androidAnalyticalV5 = "android-analytical-v5" }
public enum AgentBridgeWriteMode: String, Codable, Sendable { case overwrite, append, mergeMarkdown = "merge_markdown", mergeMarkdownPreservingPreamble = "merge_markdown_preserving_preamble" }
public enum AgentBridgeDetail: String, Codable, Sendable { case summary, selectedTimeSeries = "selected_time_series" }

public struct AgentBridgePeer: Codable, Equatable, Sendable, BridgeValueCodable {
    public let sourceInstallationID: AgentBridgeUUID
    public let hostInstallationID: AgentBridgeUUID
    public let platform: AgentBridgePlatform
    public init(sourceInstallationID: AgentBridgeUUID, hostInstallationID: AgentBridgeUUID, platform: AgentBridgePlatform) {
        self.sourceInstallationID = sourceInstallationID; self.hostInstallationID = hostInstallationID; self.platform = platform
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["source_installation_id", "host_installation_id", "platform"])
        sourceInstallationID = try o.value("source_installation_id"); hostInstallationID = try o.value("host_installation_id"); platform = try o.token("platform")
    }
    var bridgeJSON: BridgeJSON { .object([("source_installation_id", sourceInstallationID.bridgeJSON), ("host_installation_id", hostInstallationID.bridgeJSON), ("platform", .string(platform.rawValue))]) }
}

public struct AgentBridgeDiscoveryRequest: Codable, Equatable, Sendable, BridgeValueCodable {
    public let requestID: AgentBridgeUUID
    public let peer: AgentBridgePeer
    public init(requestID: AgentBridgeUUID, peer: AgentBridgePeer) { self.requestID = requestID; self.peer = peer }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "request_id", "peer"])
        try o.schema("healthmd.agent_discovery_request"); requestID = try o.value("request_id"); peer = try o.value("peer")
    }
    var bridgeJSON: BridgeJSON { .object([("schema", .string("healthmd.agent_discovery_request")), ("schema_version", .int(1)), ("request_id", requestID.bridgeJSON), ("peer", peer.bridgeJSON)]) }
}
