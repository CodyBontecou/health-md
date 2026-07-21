import CryptoKit
import Foundation

/// Stable JSON used for query fingerprints, cursor binding, source digests, and evidence packet IDs.
/// It is independent from the daily export serializer and does not change daily export bytes.
nonisolated enum HealthMdQueryCanonicalSerializer {
    static func data<Value: Encodable>(for value: Value) throws -> Data {
        try encoder().encode(value)
    }

    static func string<Value: Encodable>(for value: Value) throws -> String {
        String(decoding: try data(for: value), as: UTF8.self)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try decoder().decode(type, from: data)
    }

    static func sha256<Value: Encodable>(of value: Value) throws -> String {
        sha256(data: try data(for: value))
    }

    static func sha256(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func packetID(
        kind: HealthMdPacketKind,
        range: HealthMdDateRange?,
        facts: [HealthMdPacketFact],
        coverage: HealthMdCoverage,
        sources: [HealthMdSourceDescriptor],
        limitations: [HealthMdLimitation]
    ) throws -> String {
        let semantic = SemanticPacket(
            schema: HealthMdQuerySchemas.evidencePacket,
            schemaVersion: 1,
            kind: kind,
            range: range,
            facts: normalizeFacts(facts),
            coverage: coverage,
            sources: Array(Set(sources)).sorted(by: sourceOrder),
            limitations: Array(Set(limitations)).sorted(by: limitationOrder)
        )
        return try sha256(of: semantic)
    }

    static func makePacket(
        kind: HealthMdPacketKind,
        range: HealthMdDateRange?,
        facts: [HealthMdPacketFact],
        coverage: HealthMdCoverage,
        sources: [HealthMdSourceDescriptor],
        limitations: [HealthMdLimitation],
        metadata: HealthMdEvidencePacketMetadata = .init()
    ) throws -> HealthMdEvidencePacket {
        let normalizedFacts = normalizeFacts(facts)
        let normalizedSources = Array(Set(sources)).sorted(by: sourceOrder)
        let normalizedLimitations = Array(Set(limitations)).sorted(by: limitationOrder)
        let id = try packetID(
            kind: kind,
            range: range,
            facts: normalizedFacts,
            coverage: coverage,
            sources: normalizedSources,
            limitations: normalizedLimitations
        )
        return HealthMdEvidencePacket(
            schema: HealthMdQuerySchemas.evidencePacket,
            schemaVersion: 1,
            packetID: id,
            kind: kind,
            range: range,
            facts: normalizedFacts,
            coverage: coverage,
            sources: normalizedSources,
            limitations: normalizedLimitations,
            metadata: metadata
        )
    }

    private static func normalizeFacts(_ facts: [HealthMdPacketFact]) -> [HealthMdPacketFact] {
        facts.map { fact in
            HealthMdPacketFact(
                factID: fact.factID,
                label: fact.label,
                ownerDate: fact.ownerDate,
                value: fact.value,
                evidence: Array(Set(fact.evidence)).sorted { $0.evidenceID < $1.evidenceID }
            )
        }.sorted {
            if $0.factID != $1.factID { return $0.factID < $1.factID }
            return ($0.ownerDate ?? "") < ($1.ownerDate ?? "")
        }
    }

    private static func sourceOrder(_ lhs: HealthMdSourceDescriptor, _ rhs: HealthMdSourceDescriptor) -> Bool {
        if lhs.schema != rhs.schema { return lhs.schema < rhs.schema }
        if lhs.schemaVersion != rhs.schemaVersion { return lhs.schemaVersion < rhs.schemaVersion }
        return lhs.digest < rhs.digest
    }

    private static func limitationOrder(_ lhs: HealthMdLimitation, _ rhs: HealthMdLimitation) -> Bool {
        lhs.code != rhs.code ? lhs.code < rhs.code : lhs.message < rhs.message
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(CanonicalRFC3339UTC.string(from: date))
        }
        // `.throw` is intentional: NaN and infinities are never valid query values.
        encoder.nonConformingFloatEncodingStrategy = .throw
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Invalid canonical RFC 3339 timestamp")
                )
            }
            return date
        }
        decoder.nonConformingFloatDecodingStrategy = .throw
        return decoder
    }

    private struct SemanticPacket: Encodable {
        let schema: String
        let schemaVersion: Int
        let kind: HealthMdPacketKind
        let range: HealthMdDateRange?
        let facts: [HealthMdPacketFact]
        let coverage: HealthMdCoverage
        let sources: [HealthMdSourceDescriptor]
        let limitations: [HealthMdLimitation]
        enum CodingKeys: String, CodingKey {
            case schema, schemaVersion = "schema_version", kind, range, facts, coverage, sources, limitations
        }
    }
}

nonisolated enum HealthMdEvidenceResolver {
    /// Resolves references only when ID, locator, and source descriptor all match.
    /// An ID collision cannot redirect a packet fact to different source evidence.
    static func resolve(
        _ references: [HealthMdEvidenceReference],
        in days: [HealthMdCompactContextDay]
    ) -> [HealthMdContextEvidence] {
        var index: [String: HealthMdContextEvidence] = [:]
        for evidence in days.flatMap(\.evidence) {
            let reference = evidence.reference
            let key = resolutionKey(reference)
            index[key] = evidence
        }
        return references.compactMap { index[resolutionKey($0)] }
    }

    static func allResolve(
        _ references: [HealthMdEvidenceReference],
        in days: [HealthMdCompactContextDay]
    ) -> Bool {
        resolve(references, in: days).count == references.count
    }

    private static func resolutionKey(_ reference: HealthMdEvidenceReference) -> String {
        let locator = (try? HealthMdQueryCanonicalSerializer.string(for: reference.locator)) ?? ""
        return "\(reference.evidenceID)|\(reference.source.schema)|\(reference.source.schemaVersion)|\(reference.source.digest)|\(locator)"
    }
}
