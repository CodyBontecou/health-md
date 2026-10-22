import Foundation

/// Sanitized review description only. Decoding this value never registers or issues a grant.
/// There is deliberately no v4 enrollment discriminator. Each issuer must load its private record.
public struct AgentBridgeExportDelegation: Codable, Equatable, Sendable, BridgeValueCodable {
    public let authorityID: AgentBridgeUUID
    public let issuer: AgentBridgeAuthorityReferenceIssuer
    public let grantRevision: Int64
    public let peer: AgentBridgePeer
    public let rights: [AgentBridgeDelegationRight]
    public let expiresAt: AgentBridgeUTC
    public let bounds: AgentBridgeDelegationBounds

    public init(authorityID: AgentBridgeUUID, issuer: AgentBridgeAuthorityReferenceIssuer, grantRevision: Int64,
                peer: AgentBridgePeer, rights: [AgentBridgeDelegationRight], expiresAt: AgentBridgeUTC,
                bounds: AgentBridgeDelegationBounds) {
        self.authorityID = authorityID; self.issuer = issuer; self.grantRevision = grantRevision
        self.peer = peer; self.rights = rights; self.expiresAt = expiresAt; self.bounds = bounds
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "authority_id", "issuer", "grant_revision", "peer", "rights", "expires_at", "bounds"])
        try o.schema("healthmd.agent_export_delegation")
        authorityID = try o.value("authority_id"); issuer = try o.token("issuer")
        grantRevision = try o.int("grant_revision", min: 1, max: 2_147_483_647)
        peer = try o.value("peer"); rights = try o.tokens("rights", min: 1, max: 3)
        expiresAt = try o.value("expires_at"); bounds = try o.value("bounds")
        try bridgeSortedUnique(rights.map(\.rawValue))
        switch (issuer, bounds.destinationPolicy) {
        case (.nativeSource, .authenticatedHostBindings), (.authorizedHost, .registeredHostBindings): break
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }
    var bridgeJSON: BridgeJSON {
        .object([("schema", .string("healthmd.agent_export_delegation")), ("schema_version", .int(1)),
                 ("authority_id", authorityID.bridgeJSON), ("issuer", .string(issuer.rawValue)),
                 ("grant_revision", .int(grantRevision)), ("peer", peer.bridgeJSON),
                 ("rights", bridgeTokens(rights)), ("expires_at", expiresAt.bridgeJSON), ("bounds", bounds.bridgeJSON)])
    }
    public func reference() throws -> AgentBridgeAuthorityReference {
        .init(authorityId: authorityID, grantRevision: grantRevision,
              grantSha256: try AgentBridgeDigest(AgentBridgeV4Codec.digest(self)), issuer: issuer)
    }
}

public enum AgentBridgeDelegationRight: String, Codable, Sendable {
    case discover, exportExecute = "export_execute", plan
}
public enum AgentBridgeDelegationProduct: String, Codable, Sendable {
    case generatedFiles = "generated_files", androidSourceProjectionV1 = "android_source_projection_v1"
}
public enum AgentBridgeDelegationProjectionDetail: String, Codable, Sendable {
    case summary, selectedTimeSeries = "selected_time_series", nativeRecords = "native_records"
}
public enum AgentBridgeDelegationProjectionObject: String, Codable, Sendable {
    case dailySummary = "daily_summary", selectedSeries = "selected_series", nativeRecords = "native_records", captureManifest = "capture_manifest"
}

public enum AgentBridgeDelegationDatePolicy: Codable, Equatable, Sendable, BridgeValueCodable {
    case boundedExact(range: AgentBridgeDateRange, maxDays: Int64)
    case authorizedHistory(maxDays: Int64, allowAllAvailable: Bool)
    init(bridgeJSON: BridgeJSON) throws {
        let tag = try BridgeObject(bridgeJSON, ["type", "max_days"], optional: ["range", "allow_all_available"]).text("type")
        switch tag {
        case "bounded_exact":
            let o = try BridgeObject(bridgeJSON, ["type", "max_days", "range"])
            self = .boundedExact(range: try o.value("range"), maxDays: try o.int("max_days", min: 1, max: 366_000))
        case "authorized_history":
            let o = try BridgeObject(bridgeJSON, ["type", "max_days", "allow_all_available"])
            self = .authorizedHistory(maxDays: try o.int("max_days", min: 1, max: 366_000), allowAllAvailable: try o.bool("allow_all_available"))
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }
    var bridgeJSON: BridgeJSON {
        switch self {
        case .boundedExact(let range, let days): return .object([("type", .string("bounded_exact")), ("range", range.bridgeJSON), ("max_days", .int(days))])
        case .authorizedHistory(let days, let all): return .object([("type", .string("authorized_history")), ("max_days", .int(days)), ("allow_all_available", .bool(all))])
        }
    }
}

public enum AgentBridgeDelegationDestinationPolicy: Codable, Equatable, Sendable, BridgeValueCodable {
    case authenticatedHostBindings
    case registeredHostBindings([AgentBridgeUUID])
    init(bridgeJSON: BridgeJSON) throws {
        let tag = try BridgeObject(bridgeJSON, ["type"], optional: ["binding_ids"]).text("type")
        switch tag {
        case "authenticated_host_bindings": _ = try BridgeObject(bridgeJSON, ["type"]); self = .authenticatedHostBindings
        case "registered_host_bindings":
            let ids: [AgentBridgeUUID] = try BridgeObject(bridgeJSON, ["type", "binding_ids"]).list("binding_ids", min: 1, max: 32)
            try bridgeSortedUnique(ids.map(\.rawValue)); self = .registeredHostBindings(ids)
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }
    var bridgeJSON: BridgeJSON {
        switch self {
        case .authenticatedHostBindings: return .object([("type", .string("authenticated_host_bindings"))])
        case .registeredHostBindings(let ids): return .object([("type", .string("registered_host_bindings")), ("binding_ids", .values(ids))])
        }
    }
}

public struct AgentBridgeDelegationBounds: Codable, Equatable, Sendable, BridgeValueCodable {
    public let products: [AgentBridgeDelegationProduct]
    public let projectionDetails: [AgentBridgeDelegationProjectionDetail]
    public let projectionObjectIDs: [AgentBridgeDelegationProjectionObject]
    public let projectionFieldIDs: [AgentBridgeID]
    public let metricIDs: [AgentBridgeID]
    public let calendarTimezones: [AgentBridgeZone]
    public let datePolicy: AgentBridgeDelegationDatePolicy
    public let formats: [AgentBridgeFormat]
    public let outputProfiles: [AgentBridgeOutputProfile]
    public let writeModes: [AgentBridgeWriteMode]
    public let compatibilityDetail: [AgentBridgeDetail]
    public let nativeArchiveProducts: [AgentBridgeOutputSupportNativeArchiveProducts]
    public let destinationPolicy: AgentBridgeDelegationDestinationPolicy

    public init(products: [AgentBridgeDelegationProduct], projectionDetails: [AgentBridgeDelegationProjectionDetail],
                projectionObjectIDs: [AgentBridgeDelegationProjectionObject], projectionFieldIDs: [AgentBridgeID],
                metricIDs: [AgentBridgeID], calendarTimezones: [AgentBridgeZone], datePolicy: AgentBridgeDelegationDatePolicy,
                formats: [AgentBridgeFormat], outputProfiles: [AgentBridgeOutputProfile], writeModes: [AgentBridgeWriteMode],
                compatibilityDetail: [AgentBridgeDetail], nativeArchiveProducts: [AgentBridgeOutputSupportNativeArchiveProducts],
                destinationPolicy: AgentBridgeDelegationDestinationPolicy) {
        self.products = products; self.projectionDetails = projectionDetails; self.projectionObjectIDs = projectionObjectIDs
        self.projectionFieldIDs = projectionFieldIDs; self.metricIDs = metricIDs; self.calendarTimezones = calendarTimezones
        self.datePolicy = datePolicy; self.formats = formats; self.outputProfiles = outputProfiles; self.writeModes = writeModes
        self.compatibilityDetail = compatibilityDetail; self.nativeArchiveProducts = nativeArchiveProducts; self.destinationPolicy = destinationPolicy
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["products", "projection_details", "projection_object_ids", "projection_field_ids", "metric_ids", "calendar_timezones", "date_policy", "formats", "output_profiles", "write_modes", "compatibility_detail", "native_archive_products", "destination_policy"])
        products = try o.tokens("products", min: 1, max: 2)
        projectionDetails = try o.tokens("projection_details", max: 3)
        projectionObjectIDs = try o.tokens("projection_object_ids", max: 4)
        projectionFieldIDs = try o.list("projection_field_ids", max: 256)
        metricIDs = try o.list("metric_ids", min: 1, max: 256)
        calendarTimezones = try o.list("calendar_timezones", min: 1, max: 16)
        datePolicy = try o.value("date_policy"); formats = try o.tokens("formats", min: 1, max: 4)
        outputProfiles = try o.tokens("output_profiles", min: 1, max: 3); writeModes = try o.tokens("write_modes", min: 1, max: 4)
        compatibilityDetail = try o.tokens("compatibility_detail", min: 1, max: 2)
        nativeArchiveProducts = try o.tokens("native_archive_products", min: 1, max: 3)
        destinationPolicy = try o.value("destination_policy")
        for list in [products.map(\.rawValue), projectionDetails.map(\.rawValue), projectionObjectIDs.map(\.rawValue),
                     projectionFieldIDs.map(\.rawValue), metricIDs.map(\.rawValue), calendarTimezones.map(\.rawValue),
                     formats.map(\.rawValue), outputProfiles.map(\.rawValue), writeModes.map(\.rawValue),
                     compatibilityDetail.map(\.rawValue), nativeArchiveProducts.map(\.rawValue)] { try bridgeSortedUnique(list) }
    }
    var bridgeJSON: BridgeJSON {
        .object([("products", bridgeTokens(products)), ("projection_details", bridgeTokens(projectionDetails)),
                 ("projection_object_ids", bridgeTokens(projectionObjectIDs)), ("projection_field_ids", .values(projectionFieldIDs)),
                 ("metric_ids", .values(metricIDs)), ("calendar_timezones", .values(calendarTimezones)), ("date_policy", datePolicy.bridgeJSON),
                 ("formats", bridgeTokens(formats)), ("output_profiles", bridgeTokens(outputProfiles)), ("write_modes", bridgeTokens(writeModes)),
                 ("compatibility_detail", bridgeTokens(compatibilityDetail)), ("native_archive_products", bridgeTokens(nativeArchiveProducts)),
                 ("destination_policy", destinationPolicy.bridgeJSON)])
    }
}

/// Pure bounded-scope comparison only. A caller-supplied delegation is NOT stored authority.
public enum AgentBridgeDelegationSemantics {
    public static func requireGeneratedScope(_ stored: AgentBridgeExportDelegation, intent: AgentBridgeGeneratedIntent,
                                             effective: AgentBridgeOutputSettings, resolvedDates: AgentBridgeDates,
                                             metricIDs: [AgentBridgeID], now: AgentBridgeUTC, right: AgentBridgeDelegationRight) throws {
        _ = try AgentBridgeV4Codec.encode(stored)
        guard stored.peer == intent.peer else { throw AgentBridgeValidationError.bindingChanged }
        let b = stored.bounds
        guard stored.expiresAt.rawValue > now.rawValue, stored.rights.contains(right), b.products.contains(.generatedFiles),
              Set(metricIDs).isSubset(of: Set(b.metricIDs)), b.calendarTimezones.contains(intent.calendarTimezone),
              Set(effective.formats.map(\.rawValue)).isSubset(of: Set(b.formats.map(\.rawValue))),
              b.outputProfiles.contains(effective.outputProfile), b.writeModes.contains(effective.writeMode),
              b.compatibilityDetail.contains(intent.captureScope.compatibilityDetail) else { throw AgentBridgeValidationError.approvalRequired }
        let archive: AgentBridgeOutputSupportNativeArchiveProducts
        switch intent.captureScope.nativeArchive {
        case .none: archive = .none
        case .appleHealthKitCanonical: archive = .appleHealthkitCanonicalV1
        case .androidProviderNativeSnapshot: archive = .androidProviderNativeSnapshotV1
        }
        guard b.nativeArchiveProducts.contains(archive), resolvedDates == (try intent.dates.resolved()) else { throw AgentBridgeValidationError.approvalRequired }
        switch (resolvedDates, b.datePolicy) {
        case (.allAvailable, .authorizedHistory(_, true)): break // Execution must enforce max_days AFTER approved capture resolves history.
        case (.exact(let range), let policy):
            let maxDays: Int64
            switch policy {
            case .authorizedHistory(let days, _): maxDays = days
            case .boundedExact(let permitted, let days):
                guard permitted.startDate.rawValue <= range.startDate.rawValue, range.endDate.rawValue <= permitted.endDate.rawValue else { throw AgentBridgeValidationError.approvalRequired }
                maxDays = days
            }
            guard let start = bridgeDate(range.startDate.rawValue), let end = bridgeDate(range.endDate.rawValue),
                  end >= start, (end.timeIntervalSince(start) / 86_400 + 1) <= Double(maxDays) else { throw AgentBridgeValidationError.approvalRequired }
        default: throw AgentBridgeValidationError.approvalRequired
        }
        if case .registeredHostBindings(let ids) = b.destinationPolicy, !ids.contains(intent.destination.bindingID) {
            throw AgentBridgeValidationError.approvalRequired
        }
    }
}
