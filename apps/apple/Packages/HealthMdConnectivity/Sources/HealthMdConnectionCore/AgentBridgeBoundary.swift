import Foundation

/// Supported closed export/discovery documents. Delegation descriptions have no wire enrollment
/// discriminator. Queries, projections and controls are not generically forwarded.
public enum AgentBridgeDocument: Codable, Equatable, Sendable, BridgeValueCodable {
    case discoveryRequest(AgentBridgeDiscoveryRequest), discovery(AgentBridgeDiscovery)
    case intent(AgentBridgeGeneratedIntent), planRequest(AgentBridgePlanRequest), plan(AgentBridgePlan)
    case authority(AgentBridgeAuthority), delegation(AgentBridgeExportDelegation)
    case approvalRequest(AgentBridgeApprovalRequest), approval(AgentBridgeApproval)
    case execute(AgentBridgeExecute), receipt(AgentBridgeExecutionReceipt), cancel(AgentBridgeCancel), resume(AgentBridgeResume)
    case manifest(AgentBridgeArtifactManifest), commit(AgentBridgeCommitReceipt), error(AgentBridgeError)

    init(bridgeJSON: BridgeJSON) throws {
        guard case .object(let members) = bridgeJSON,
              case .string(let schema)? = members.first(where: { $0.key.utf8.elementsEqual("schema".utf8) })?.value else { throw AgentBridgeValidationError.invalidRequest }
        switch schema {
        case "healthmd.agent_discovery_request": self = .discoveryRequest(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_discovery": self = .discovery(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_export_intent": self = .intent(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_plan_request": self = .planRequest(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_export_plan": self = .plan(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_authority": self = .authority(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_export_delegation": self = .delegation(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_approval_request": self = .approvalRequest(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_approval": self = .approval(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_execute_request": self = .execute(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_execution_receipt": self = .receipt(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_cancel_request": self = .cancel(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_resume_request": self = .resume(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_artifact_manifest": self = .manifest(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_commit_receipt": self = .commit(try .init(bridgeJSON: bridgeJSON))
        case "healthmd.agent_error": self = .error(try .init(bridgeJSON: bridgeJSON))
        default: throw AgentBridgeValidationError.unsupportedCapability
        }
    }
    var bridgeJSON: BridgeJSON {
        switch self {
        case .discoveryRequest(let v): return v.bridgeJSON
        case .discovery(let v): return v.bridgeJSON
        case .intent(let v): return v.bridgeJSON
        case .planRequest(let v): return v.bridgeJSON
        case .plan(let v): return v.bridgeJSON
        case .authority(let v): return v.bridgeJSON
        case .delegation(let v): return v.bridgeJSON
        case .approvalRequest(let v): return v.bridgeJSON
        case .approval(let v): return v.bridgeJSON
        case .execute(let v): return v.bridgeJSON
        case .receipt(let v): return v.bridgeJSON
        case .cancel(let v): return v.bridgeJSON
        case .resume(let v): return v.bridgeJSON
        case .manifest(let v): return v.bridgeJSON
        case .commit(let v): return v.bridgeJSON
        case .error(let v): return v.bridgeJSON
        }
    }
    var wireType: String? {
        switch self {
        case .discoveryRequest: return "discovery_request"
        case .discovery: return "discovery_response"
        case .planRequest: return "plan_request"
        case .plan: return "plan_response"
        case .approvalRequest: return "approval_request"
        case .approval: return "approval_response"
        case .execute: return "execute_request"
        case .receipt: return "execution_receipt"
        case .cancel: return "cancel_request"
        case .resume: return "resume_request"
        case .manifest: return "artifact_manifest"
        case .commit: return "commit_receipt"
        case .error: return "rejected"
        case .intent, .authority, .delegation: return nil // Not standalone v4 discriminators.
        }
    }
}

/// The wire discriminator is derived from a supported typed payload, never caller-selected.
public struct AgentBridgeEnvelope: Codable, Equatable, Sendable, BridgeValueCodable {
    public let payload: AgentBridgeDocument
    public init(payload: AgentBridgeDocument) throws {
        guard payload.wireType != nil else { throw AgentBridgeValidationError.unsupportedCapability }
        self.payload = payload
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["protocol_version", "type", "payload"])
        try o.constant("protocol_version", .int(4))
        payload = try o.value("payload")
        guard let type = payload.wireType, type == (try o.text("type")) else { throw AgentBridgeValidationError.invalidRequest }
    }
    var bridgeJSON: BridgeJSON { .object([("protocol_version", .int(4)), ("type", .string(payload.wireType ?? "")), ("payload", payload.bridgeJSON)]) }
}

/// No edits to deployed hello fields or base-version constants. Call only after authenticating hello.
public struct AgentBridgeNegotiation: Equatable, Sendable {
    public let baseVersion: Int
    public let queryV3: Bool
    public let agentBridgeV4: Bool
    public init(localVersions: [Int], remoteVersions: [Int], deployedBaseVersion: Int) throws {
        guard [1, 2].contains(deployedBaseVersion), localVersions.contains(deployedBaseVersion), remoteVersions.contains(deployedBaseVersion),
              localVersions.count <= 16, remoteVersions.count <= 16,
              localVersions.allSatisfy({ $0 > 0 }), remoteVersions.allSatisfy({ $0 > 0 }),
              Set(localVersions).count == localVersions.count, Set(remoteVersions).count == remoteVersions.count else { throw AgentBridgeValidationError.unsupportedCapability }
        baseVersion = deployedBaseVersion
        queryV3 = localVersions.contains(3) && remoteVersions.contains(3)
        agentBridgeV4 = localVersions.contains(4) && remoteVersions.contains(4)
    }
    public func encode(_ envelope: AgentBridgeEnvelope) throws -> Data {
        guard agentBridgeV4 else { throw AgentBridgeValidationError.unsupportedCapability }
        return try AgentBridgeV4Codec.encode(envelope)
    }
    public func decode(_ bytes: Data) throws -> AgentBridgeEnvelope {
        guard agentBridgeV4 else { throw AgentBridgeValidationError.unsupportedCapability }
        return try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes)
    }
}
