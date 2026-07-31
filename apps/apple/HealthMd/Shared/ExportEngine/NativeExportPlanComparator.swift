import Foundation

nonisolated struct NativeExportComparisonOptions: Equatable, Sendable {
    let includeFirstDifferingByteOffset: Bool

    /// Passing an explicit value is reserved for internal comparison tooling. With no explicit
    /// value, offsets are available only in debug/test-capable compilations.
    init(includeFirstDifferingByteOffset: Bool? = nil) {
#if DEBUG || HEALTHMD_INTERNAL_TESTING
        self.includeFirstDifferingByteOffset = includeFirstDifferingByteOffset ?? true
#else
        // Release builds cannot opt into byte offsets through a runtime value.
        self.includeFirstDifferingByteOffset = false
#endif
    }
}

/// Health-free evidence for one exact-plan mismatch. This type intentionally has no request ID,
/// session ID, path, media value, write-mode value, payload bytes, date, or field value.
nonisolated struct NativeExportPlanMismatchDiagnostic: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case artifactCount = "artifact_count"
        case artifactID = "artifact_id"
        case relativePath = "relative_path"
        case mediaType = "media_type"
        case writeMode = "write_mode"
        case byteCount = "byte_count"
        case sha256
        case bytes
    }

    let profile: String
    let semanticProfileRevision: UInt32
    let renderProfileRevision: UInt32
    let artifactOrdinal: UInt32?
    let mismatchKind: Kind
    /// For artifact-count mismatches these contain plan item counts. Otherwise they are byte counts.
    let nativeLength: UInt64?
    let rustLength: UInt64?
    /// Content digests only. Artifact IDs and path-derived hashes are never exposed.
    let nativeSHA256: String?
    let rustSHA256: String?
    /// Populated only by debug/test compilation or an explicit internal comparison option.
    let firstDifferingByteOffset: UInt64?
}

/// Byte-exact ordered comparator. It does not parse, normalize, trim, or re-encode any artifact.
nonisolated enum NativeExportPlanComparator {
    static func compare(
        native: NativeExportArtifactPlan,
        rust: NativeExportArtifactPlan,
        pin: AppleExportEnginePin,
        options: NativeExportComparisonOptions = NativeExportComparisonOptions()
    ) -> [NativeExportPlanMismatchDiagnostic] {
        var diagnostics: [NativeExportPlanMismatchDiagnostic] = []
        if native.artifacts.count != rust.artifacts.count {
            diagnostics.append(diagnostic(
                kind: .artifactCount,
                ordinal: nil,
                pin: pin,
                nativeLength: UInt64(native.artifacts.count),
                rustLength: UInt64(rust.artifacts.count),
                nativeSHA256: nil,
                rustSHA256: nil,
                firstDifferingByteOffset: nil
            ))
        }

        for ordinal in 0..<min(native.artifacts.count, rust.artifacts.count) {
            let nativeArtifact = native.artifacts[ordinal]
            let rustArtifact = rust.artifacts[ordinal]
            let context = comparisonContext(native: nativeArtifact, rust: rustArtifact)

            if nativeArtifact.id != rustArtifact.id {
                diagnostics.append(diagnostic(
                    kind: .artifactID,
                    ordinal: ordinal,
                    pin: pin,
                    context: context
                ))
            }
            if nativeArtifact.relativePath != rustArtifact.relativePath {
                diagnostics.append(diagnostic(
                    kind: .relativePath,
                    ordinal: ordinal,
                    pin: pin,
                    context: context
                ))
            }
            if nativeArtifact.mediaType != rustArtifact.mediaType {
                diagnostics.append(diagnostic(
                    kind: .mediaType,
                    ordinal: ordinal,
                    pin: pin,
                    context: context
                ))
            }
            if nativeArtifact.writeMode != rustArtifact.writeMode {
                diagnostics.append(diagnostic(
                    kind: .writeMode,
                    ordinal: ordinal,
                    pin: pin,
                    context: context
                ))
            }
            if nativeArtifact.byteCount != rustArtifact.byteCount {
                diagnostics.append(diagnostic(
                    kind: .byteCount,
                    ordinal: ordinal,
                    pin: pin,
                    context: context
                ))
            }
            if nativeArtifact.sha256 != rustArtifact.sha256 {
                diagnostics.append(diagnostic(
                    kind: .sha256,
                    ordinal: ordinal,
                    pin: pin,
                    context: context
                ))
            }
            let byteComparison = compareBytes(
                nativeArtifact.content,
                rustArtifact.content,
                includeOffset: options.includeFirstDifferingByteOffset
            )
            if !byteComparison.matches {
                diagnostics.append(diagnostic(
                    kind: .bytes,
                    ordinal: ordinal,
                    pin: pin,
                    context: context,
                    firstDifferingByteOffset: byteComparison.offset
                ))
            }
        }
        return diagnostics
    }

    private struct ComparisonContext {
        let nativeLength: UInt64
        let rustLength: UInt64
        let nativeSHA256: String
        let rustSHA256: String
    }

    private static func comparisonContext(
        native: NativeExportArtifact,
        rust: NativeExportArtifact
    ) -> ComparisonContext {
        ComparisonContext(
            nativeLength: native.byteCount,
            rustLength: rust.byteCount,
            nativeSHA256: native.sha256,
            rustSHA256: rust.sha256
        )
    }

    private static func diagnostic(
        kind: NativeExportPlanMismatchDiagnostic.Kind,
        ordinal: Int,
        pin: AppleExportEnginePin,
        context: ComparisonContext,
        firstDifferingByteOffset: UInt64? = nil
    ) -> NativeExportPlanMismatchDiagnostic {
        diagnostic(
            kind: kind,
            ordinal: UInt32(ordinal),
            pin: pin,
            nativeLength: context.nativeLength,
            rustLength: context.rustLength,
            nativeSHA256: context.nativeSHA256,
            rustSHA256: context.rustSHA256,
            firstDifferingByteOffset: firstDifferingByteOffset
        )
    }

    private static func diagnostic(
        kind: NativeExportPlanMismatchDiagnostic.Kind,
        ordinal: UInt32?,
        pin: AppleExportEnginePin,
        nativeLength: UInt64?,
        rustLength: UInt64?,
        nativeSHA256: String?,
        rustSHA256: String?,
        firstDifferingByteOffset: UInt64?
    ) -> NativeExportPlanMismatchDiagnostic {
        NativeExportPlanMismatchDiagnostic(
            profile: AppleExportEnginePin.profileID,
            semanticProfileRevision: pin.semanticProfileRevision,
            renderProfileRevision: pin.renderProfileRevision,
            artifactOrdinal: ordinal,
            mismatchKind: kind,
            nativeLength: nativeLength,
            rustLength: rustLength,
            nativeSHA256: nativeSHA256,
            rustSHA256: rustSHA256,
            firstDifferingByteOffset: firstDifferingByteOffset
        )
    }

    private final class ContentReader {
        private enum Storage {
            case data(Data, Int)
            case file(FileHandle)
        }

        private var storage: Storage

        init(_ content: NativeExportArtifactContent) throws {
            switch content {
            case .inline(let data): storage = .data(data, 0)
            case .file(let file): storage = .file(try FileHandle(forReadingFrom: file.url))
            }
        }

        deinit {
            if case .file(let handle) = storage { try? handle.close() }
        }

        func read(upToCount count: Int) throws -> Data {
            switch storage {
            case .data(let data, let offset):
                guard offset < data.count else { return Data() }
                let upper = min(offset + count, data.count)
                storage = .data(data, upper)
                return Data(data[offset..<upper])
            case .file(let handle):
                return try handle.read(upToCount: count) ?? Data()
            }
        }
    }

    private static func compareBytes(
        _ lhs: NativeExportArtifactContent,
        _ rhs: NativeExportArtifactContent,
        includeOffset: Bool
    ) -> (matches: Bool, offset: UInt64?) {
        do {
            let left = try ContentReader(lhs)
            let right = try ContentReader(rhs)
            var baseOffset: UInt64 = 0
            while true {
                let leftChunk = try left.read(upToCount: 128 * 1_024)
                let rightChunk = try right.read(upToCount: 128 * 1_024)
                if leftChunk != rightChunk {
                    guard includeOffset else { return (false, nil) }
                    let shared = min(leftChunk.count, rightChunk.count)
                    for index in 0..<shared where leftChunk[index] != rightChunk[index] {
                        return (false, baseOffset + UInt64(index))
                    }
                    return (false, baseOffset + UInt64(shared))
                }
                if leftChunk.isEmpty { return (true, nil) }
                baseOffset += UInt64(leftChunk.count)
            }
        } catch {
            return (false, nil)
        }
    }
}
