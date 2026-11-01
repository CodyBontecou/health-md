import Foundation

/// Inserts native source blocks once, without materializing their contents or copying
/// an already-expanded source document to add another block.
nonisolated enum AppleWakeDateSourceFrontmatter {
    enum ProjectionError: Error { case invalidAggregate }
    static func write(aggregate: Data, keys: [String], to sink: ExportByteSink,
        blocks: (ExportByteSink) throws -> Void) throws {
        guard let text = String(data: aggregate, encoding: .utf8), text.hasPrefix("---\n"),
              let closing = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex),
              !text[..<closing.lowerBound].components(separatedBy: "\n").contains(where: { line in keys.contains { line.hasPrefix("\($0):") } }) else {
            throw ProjectionError.invalidAggregate
        }
        try sink.write(Data(text[..<closing.lowerBound].utf8))
        try blocks(sink)
        try sink.write(Data(text[closing.lowerBound...].utf8))
    }
}
