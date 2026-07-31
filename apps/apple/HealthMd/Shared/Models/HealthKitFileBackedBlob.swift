import Foundation

extension CodingUserInfoKey {
    nonisolated static let healthKitFileBackedDataDecoding = CodingUserInfoKey(
        rawValue: "healthmd.healthkit-file-backed-data-decoding"
    )!
}

/// Immutable restricted temporary bytes retained by a captured HealthKit model.
/// The lease removes ephemeral files only after every copied model releases them.
nonisolated struct HealthKitFileBackedBlob: Equatable, Sendable, Codable {
    let artifact: ExportArtifactFile

    var url: URL { artifact.url }
    var byteCount: UInt64 { artifact.descriptor.byteCount }
    var sha256: String { artifact.descriptor.sha256 }

    init(artifact: ExportArtifactFile) {
        self.artifact = artifact
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.byteCount == rhs.byteCount && lhs.sha256 == rhs.sha256
    }

    func forEachChunk(
        chunkSize: Int = 128 * 1_024,
        _ consume: (Data) throws -> Void
    ) throws {
        try ExportArtifactIO.forEachFileChunk(
            at: url,
            expectedByteCount: byteCount,
            chunkSize: chunkSize,
            consume
        )
    }

    func materializedData() throws -> Data {
        guard byteCount <= UInt64(Int.max) else { throw CocoaError(.fileReadTooLarge) }
        var result = Data()
        result.reserveCapacity(Int(byteCount))
        try forEachChunk { result.append($0) }
        return result
    }

    init(from decoder: Decoder) throws {
        let data = try decoder.singleValueContainer().decode(Data.self)
        let artifact = try ExportArtifactIO.renderTemporary(
            prefix: "healthkit-decoded-blob",
            mediaType: "application/octet-stream"
        ) { sink in
            try sink.write(data)
        }
        self.init(artifact: artifact)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(materializedData())
    }
}

/// Canonical JSON treats inline and file-backed bytes identically. The custom
/// stream encoder recognizes this wrapper and emits base64 incrementally;
/// JSONEncoder remains a byte-compatible buffered fallback.
nonisolated struct CanonicalBase64Value: Encodable {
    private enum Storage {
        case inline(Data)
        case file(HealthKitFileBackedBlob)
    }

    private let storage: Storage

    init(_ data: Data) {
        storage = .inline(data)
    }

    init(_ blob: HealthKitFileBackedBlob) {
        storage = .file(blob)
    }

    func forEachChunk(_ consume: (Data) throws -> Void) throws {
        switch storage {
        case .inline(let data):
            let chunkSize = 128 * 1_024
            var offset = 0
            while offset < data.count {
                try Task.checkCancellation()
                let upper = min(offset + chunkSize, data.count)
                try consume(Data(data[offset..<upper]))
                offset = upper
            }
        case .file(let blob):
            try blob.forEachChunk(consume)
        }
    }

    func materializedData() throws -> Data {
        switch storage {
        case .inline(let data): return data
        case .file(let blob): return try blob.materializedData()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(materializedData().base64EncodedString())
    }
}
