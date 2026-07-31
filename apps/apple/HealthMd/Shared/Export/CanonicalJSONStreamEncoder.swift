import Foundation

/// Lazy Foundation array used by the established daily JSON mapper. It retains
/// the source value array but does not build a second array of JSON dictionaries.
nonisolated final class FoundationJSONLazyArray {
    let count: Int
    private let enumerate: (@escaping (Any) throws -> Void) throws -> Void

    init<Element>(
        _ values: [Element],
        transform: @escaping (Element) throws -> Any
    ) {
        self.count = values.count
        self.enumerate = { consume in
            for value in values { try consume(try transform(value)) }
        }
    }

    func forEach(_ consume: @escaping (Any) throws -> Void) throws {
        try enumerate(consume)
    }

    func materialized() throws -> [Any] {
        var result: [Any] = []
        result.reserveCapacity(count)
        try forEach { result.append($0) }
        return result
    }
}

/// Exact, bounded JSON encoder used by the schema-v7 streaming exporters.
/// Keyed containers retain only their direct field emitters so keys can be
/// sorted; arrays are traversed one element at a time.
nonisolated final class CanonicalJSONStreamEncoder {
    struct Formatting: Equatable, Sendable {
        enum FloatingPointStyle: Equatable, Sendable {
            case jsonEncoder
            case foundationFragment
        }

        let prettyPrinted: Bool
        let escapesSlashes: Bool
        let usesFoundationKeyOrdering: Bool
        let floatingPointStyle: FloatingPointStyle

        init(
            prettyPrinted: Bool,
            escapesSlashes: Bool,
            usesFoundationKeyOrdering: Bool,
            floatingPointStyle: FloatingPointStyle = .jsonEncoder
        ) {
            self.prettyPrinted = prettyPrinted
            self.escapesSlashes = escapesSlashes
            self.usesFoundationKeyOrdering = usesFoundationKeyOrdering
            self.floatingPointStyle = floatingPointStyle
        }

        static let compactCanonical = Formatting(
            prettyPrinted: false,
            escapesSlashes: false,
            usesFoundationKeyOrdering: false
        )
        static let compactFoundation = Formatting(
            prettyPrinted: false,
            escapesSlashes: true,
            usesFoundationKeyOrdering: true
        )
        static let prettyFoundation = Formatting(
            prettyPrinted: true,
            escapesSlashes: true,
            usesFoundationKeyOrdering: true
        )
    }

    enum EncodingError: Error, Equatable {
        case missingValue
        case duplicateKey(String)
        case invalidFloatingPoint
        case excessiveDepth
    }

    private static let maximumDepth = 512
    private let output: BufferedExportByteWriter
    private let formatting: Formatting
    private var encodedObjectKeys: [String: Data] = [:]
    private let scalarEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }()

    init(sink: ExportByteSink, formatting: Formatting) throws {
        self.output = try BufferedExportByteWriter(sink: sink)
        self.formatting = formatting
    }

    func encode<T: Encodable>(_ value: T) throws {
        let node = try makeNode(value, codingPath: [], depth: 0)
        try write(node, depth: 0)
        try output.flush()
    }

    /// Streams a Foundation JSON object while lazily inserting one Encodable
    /// value. This keeps established summary construction byte-compatible while
    /// preventing the canonical archive from becoming Data, then a Foundation
    /// graph, then Data again.
    func encodeFoundationJSONObject<T: Encodable>(
        _ object: [String: Any],
        inserting value: T?,
        forKey key: String
    ) throws {
        let storage = ObjectStorage()
        for (field, fieldValue) in object {
            storage.values[field] = try makeFoundationNode(fieldValue, depth: 1)
        }
        if let value {
            storage.values[key] = .deferred {
                try self.makeNode(value, codingPath: [], depth: 1)
            }
        }
        try write(.object(storage), depth: 0)
        try output.flush()
    }

    private indirect enum Node {
        case null
        case bool(Bool)
        case signed(Int64)
        case unsigned(UInt64)
        case double(Double)
        case float(Float)
        case string(String)
        case binary(Data)
        case streamingBase64(CanonicalBase64Value)
        case foundationScalar(Any)
        case object(ObjectStorage)
        case array(ArrayStorage)
        case streamingArray(any StreamingJSONArray)
        case lazyFoundationArray(FoundationJSONLazyArray)
        case reference(NodeBox)
        case deferred(() throws -> Node)
    }

    private final class NodeBox {
        var node: Node?
    }

    private final class ObjectStorage {
        var values: [String: Node] = [:]
    }

    private final class ArrayStorage {
        var values: [Node] = []
    }

    fileprivate protocol StreamingJSONArray {
        var streamingCount: Int { get }
        func forEachStreamingElement(
            _ body: (any Encodable) throws -> Void
        ) rethrows
    }

    private final class NodeEncoder: Encoder {
        let owner: CanonicalJSONStreamEncoder
        let box: NodeBox
        var codingPath: [CodingKey]
        var userInfo: [CodingUserInfoKey: Any] = [:]
        let depth: Int

        init(
            owner: CanonicalJSONStreamEncoder,
            box: NodeBox = NodeBox(),
            codingPath: [CodingKey],
            depth: Int
        ) {
            self.owner = owner
            self.box = box
            self.codingPath = codingPath
            self.depth = depth
        }

        func container<Key>(
            keyedBy _: Key.Type
        ) -> KeyedEncodingContainer<Key> where Key: CodingKey {
            let storage: ObjectStorage
            if case .object(let existing)? = box.node {
                storage = existing
            } else {
                storage = ObjectStorage()
                box.node = .object(storage)
            }
            return KeyedEncodingContainer(KeyedContainer(
                encoder: self,
                storage: storage
            ))
        }

        func unkeyedContainer() -> UnkeyedEncodingContainer {
            let storage: ArrayStorage
            if case .array(let existing)? = box.node {
                storage = existing
            } else {
                storage = ArrayStorage()
                box.node = .array(storage)
            }
            return UnkeyedContainer(encoder: self, storage: storage)
        }

        func singleValueContainer() -> SingleValueEncodingContainer {
            SingleValueContainer(encoder: self)
        }
    }

    private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let encoder: NodeEncoder
        let storage: ObjectStorage
        var codingPath: [CodingKey] { encoder.codingPath }

        mutating func encodeNil(forKey key: Key) throws {
            try put(.null, forKey: key)
        }
        mutating func encode(_ value: Bool, forKey key: Key) throws {
            try put(.bool(value), forKey: key)
        }
        mutating func encode(_ value: String, forKey key: Key) throws {
            try put(.string(value), forKey: key)
        }
        mutating func encode(_ value: Double, forKey key: Key) throws {
            try put(.double(value), forKey: key)
        }
        mutating func encode(_ value: Float, forKey key: Key) throws {
            try put(.float(value), forKey: key)
        }
        mutating func encode(_ value: Int, forKey key: Key) throws {
            try encode(Int64(value), forKey: key)
        }
        mutating func encode(_ value: Int8, forKey key: Key) throws {
            try encode(Int64(value), forKey: key)
        }
        mutating func encode(_ value: Int16, forKey key: Key) throws {
            try encode(Int64(value), forKey: key)
        }
        mutating func encode(_ value: Int32, forKey key: Key) throws {
            try encode(Int64(value), forKey: key)
        }
        mutating func encode(_ value: Int64, forKey key: Key) throws {
            try put(.signed(value), forKey: key)
        }
        mutating func encode(_ value: UInt, forKey key: Key) throws {
            try encode(UInt64(value), forKey: key)
        }
        mutating func encode(_ value: UInt8, forKey key: Key) throws {
            try encode(UInt64(value), forKey: key)
        }
        mutating func encode(_ value: UInt16, forKey key: Key) throws {
            try encode(UInt64(value), forKey: key)
        }
        mutating func encode(_ value: UInt32, forKey key: Key) throws {
            try encode(UInt64(value), forKey: key)
        }
        mutating func encode(_ value: UInt64, forKey key: Key) throws {
            try put(.unsigned(value), forKey: key)
        }

        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            let owner = encoder.owner
            let path = codingPath + [key]
            let depth = encoder.depth + 1
            try put(.deferred {
                try owner.makeNode(value, codingPath: path, depth: depth)
            }, forKey: key)
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy _: NestedKey.Type,
            forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> {
            let child = NodeEncoder(
                owner: encoder.owner,
                codingPath: codingPath + [key],
                depth: encoder.depth + 1
            )
            try? put(.reference(child.box), forKey: key)
            return child.container(keyedBy: NestedKey.self)
        }

        mutating func nestedUnkeyedContainer(
            forKey key: Key
        ) -> UnkeyedEncodingContainer {
            let child = NodeEncoder(
                owner: encoder.owner,
                codingPath: codingPath + [key],
                depth: encoder.depth + 1
            )
            try? put(.reference(child.box), forKey: key)
            return child.unkeyedContainer()
        }

        mutating func superEncoder() -> Encoder {
            let key = Key(stringValue: "super")
            if let key { return superEncoder(forKey: key) }
            return NodeEncoder(
                owner: encoder.owner,
                codingPath: codingPath,
                depth: encoder.depth + 1
            )
        }

        mutating func superEncoder(forKey key: Key) -> Encoder {
            let child = NodeEncoder(
                owner: encoder.owner,
                codingPath: codingPath + [key],
                depth: encoder.depth + 1
            )
            try? put(.reference(child.box), forKey: key)
            return child
        }

        private func put(_ node: Node, forKey key: Key) throws {
            guard storage.values.updateValue(node, forKey: key.stringValue) == nil else {
                throw EncodingError.duplicateKey(key.stringValue)
            }
        }
    }

    private struct UnkeyedContainer: UnkeyedEncodingContainer {
        let encoder: NodeEncoder
        let storage: ArrayStorage
        var codingPath: [CodingKey] { encoder.codingPath }
        var count: Int { storage.values.count }

        mutating func encodeNil() throws { storage.values.append(.null) }
        mutating func encode(_ value: Bool) throws { storage.values.append(.bool(value)) }
        mutating func encode(_ value: String) throws { storage.values.append(.string(value)) }
        mutating func encode(_ value: Double) throws { storage.values.append(.double(value)) }
        mutating func encode(_ value: Float) throws { storage.values.append(.float(value)) }
        mutating func encode(_ value: Int) throws { try encode(Int64(value)) }
        mutating func encode(_ value: Int8) throws { try encode(Int64(value)) }
        mutating func encode(_ value: Int16) throws { try encode(Int64(value)) }
        mutating func encode(_ value: Int32) throws { try encode(Int64(value)) }
        mutating func encode(_ value: Int64) throws { storage.values.append(.signed(value)) }
        mutating func encode(_ value: UInt) throws { try encode(UInt64(value)) }
        mutating func encode(_ value: UInt8) throws { try encode(UInt64(value)) }
        mutating func encode(_ value: UInt16) throws { try encode(UInt64(value)) }
        mutating func encode(_ value: UInt32) throws { try encode(UInt64(value)) }
        mutating func encode(_ value: UInt64) throws { storage.values.append(.unsigned(value)) }

        mutating func encode<T: Encodable>(_ value: T) throws {
            let owner = encoder.owner
            let index = count
            let depth = encoder.depth + 1
            let path = codingPath + [IndexKey(intValue: index)]
            storage.values.append(.deferred {
                try owner.makeNode(value, codingPath: path, depth: depth)
            })
        }

        mutating func nestedContainer<NestedKey: CodingKey>(
            keyedBy _: NestedKey.Type
        ) -> KeyedEncodingContainer<NestedKey> {
            let child = childEncoder()
            storage.values.append(.reference(child.box))
            return child.container(keyedBy: NestedKey.self)
        }

        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            let child = childEncoder()
            storage.values.append(.reference(child.box))
            return child.unkeyedContainer()
        }

        mutating func superEncoder() -> Encoder {
            let child = childEncoder()
            storage.values.append(.reference(child.box))
            return child
        }

        private func childEncoder() -> NodeEncoder {
            NodeEncoder(
                owner: encoder.owner,
                codingPath: codingPath + [IndexKey(intValue: count)],
                depth: encoder.depth + 1
            )
        }
    }

    private struct SingleValueContainer: SingleValueEncodingContainer {
        let encoder: NodeEncoder
        var codingPath: [CodingKey] { encoder.codingPath }

        func encodeNil() throws { encoder.box.node = .null }
        func encode(_ value: Bool) throws { encoder.box.node = .bool(value) }
        func encode(_ value: String) throws { encoder.box.node = .string(value) }
        func encode(_ value: Double) throws { encoder.box.node = .double(value) }
        func encode(_ value: Float) throws { encoder.box.node = .float(value) }
        func encode(_ value: Int) throws { try encode(Int64(value)) }
        func encode(_ value: Int8) throws { try encode(Int64(value)) }
        func encode(_ value: Int16) throws { try encode(Int64(value)) }
        func encode(_ value: Int32) throws { try encode(Int64(value)) }
        func encode(_ value: Int64) throws { encoder.box.node = .signed(value) }
        func encode(_ value: UInt) throws { try encode(UInt64(value)) }
        func encode(_ value: UInt8) throws { try encode(UInt64(value)) }
        func encode(_ value: UInt16) throws { try encode(UInt64(value)) }
        func encode(_ value: UInt32) throws { try encode(UInt64(value)) }
        func encode(_ value: UInt64) throws { encoder.box.node = .unsigned(value) }

        func encode<T: Encodable>(_ value: T) throws {
            encoder.box.node = .deferred {
                try encoder.owner.makeNode(
                    value,
                    codingPath: codingPath,
                    depth: encoder.depth + 1
                )
            }
        }
    }

    private struct IndexKey: CodingKey {
        let intValue: Int?
        let stringValue: String

        init(intValue: Int) {
            self.intValue = intValue
            self.stringValue = String(intValue)
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = Int(stringValue)
        }
    }

    private func makeNode<T: Encodable>(
        _ value: T,
        codingPath: [CodingKey],
        depth: Int
    ) throws -> Node {
        try makeNode(value as any Encodable, codingPath: codingPath, depth: depth)
    }

    private func makeNode(
        _ value: any Encodable,
        codingPath: [CodingKey],
        depth: Int
    ) throws -> Node {
        guard depth <= Self.maximumDepth else { throw EncodingError.excessiveDepth }

        if let value = value as? Bool { return .bool(value) }
        if let value = value as? String { return .string(value) }
        if let value = value as? Double { return .double(value) }
        if let value = value as? Float { return .float(value) }
        if let value = value as? Int { return .signed(Int64(value)) }
        if let value = value as? Int8 { return .signed(Int64(value)) }
        if let value = value as? Int16 { return .signed(Int64(value)) }
        if let value = value as? Int32 { return .signed(Int64(value)) }
        if let value = value as? Int64 { return .signed(value) }
        if let value = value as? UInt { return .unsigned(UInt64(value)) }
        if let value = value as? UInt8 { return .unsigned(UInt64(value)) }
        if let value = value as? UInt16 { return .unsigned(UInt64(value)) }
        if let value = value as? UInt32 { return .unsigned(UInt64(value)) }
        if let value = value as? UInt64 { return .unsigned(value) }
        if let value = value as? Date {
            return .string(CanonicalRFC3339UTC.string(from: value))
        }
        if let value = value as? CanonicalBase64Value {
            return .streamingBase64(value)
        }
        if let value = value as? Data { return .binary(value) }
        if let values = value as? any StreamingJSONArray {
            return .streamingArray(values)
        }

        let encoder = NodeEncoder(
            owner: self,
            codingPath: codingPath,
            depth: depth
        )
        try value.encode(to: encoder)
        guard let node = encoder.box.node else { throw EncodingError.missingValue }
        return node
    }

    private func write(_ node: Node, depth: Int) throws {
        try Task.checkCancellation()
        switch node {
        case .null:
            try output.append("null")
        case .bool(let value):
            try output.append(value ? "true" : "false")
        case .signed(let value):
            try output.append(String(value))
        case .unsigned(let value):
            try output.append(String(value))
        case .double(let value):
            try writeFloatingPoint(value)
        case .float(let value):
            if value.isFinite, formatting.floatingPointStyle == .foundationFragment {
                try writeFoundationFragment(value)
            } else {
                try output.append(scalarEncoder.encode(value))
            }
        case .string(let value):
            try writeString(value)
        case .binary(let value):
            try writeBase64(CanonicalBase64Value(value))
        case .streamingBase64(let value):
            try writeBase64(value)
        case .foundationScalar(let value):
            try writeFoundationFragment(value)
        case .object(let storage):
            try writeObject(storage, depth: depth)
        case .array(let storage):
            try writeArray(storage.values, depth: depth)
        case .streamingArray(let values):
            try writeStreamingArray(values, depth: depth)
        case .lazyFoundationArray(let values):
            try writeLazyFoundationArray(values, depth: depth)
        case .reference(let box):
            guard let value = box.node else { throw EncodingError.missingValue }
            try write(value, depth: depth)
        case .deferred(let build):
            try write(build(), depth: depth)
        }
    }

    private func makeFoundationNode(_ value: Any, depth: Int) throws -> Node {
        guard depth <= Self.maximumDepth else { throw EncodingError.excessiveDepth }
        if value is NSNull { return .null }
        if let array = value as? FoundationJSONLazyArray {
            return .lazyFoundationArray(array)
        }
        if let object = value as? [String: Any] {
            let storage = ObjectStorage()
            for (key, child) in object {
                storage.values[key] = try makeFoundationNode(child, depth: depth + 1)
            }
            return .object(storage)
        }
        if let array = value as? [Any] {
            let storage = ArrayStorage()
            storage.values.reserveCapacity(array.count)
            for child in array {
                storage.values.append(try makeFoundationNode(child, depth: depth + 1))
            }
            return .array(storage)
        }
        if value is String || value is NSNumber || value is Bool ||
            value is Int || value is Int8 || value is Int16 || value is Int32 ||
            value is Int64 || value is UInt || value is UInt8 || value is UInt16 ||
            value is UInt32 || value is UInt64 || value is Float || value is Double {
            return .foundationScalar(value)
        }
        throw EncodingError.missingValue
    }

    private func writeObject(_ storage: ObjectStorage, depth: Int) throws {
        try output.append(byte: 0x7b)
        let keys: [String]
        if formatting.usesFoundationKeyOrdering {
            keys = storage.values.keys.sorted {
                $0.compare($1, options: [.caseInsensitive, .numeric]) == .orderedAscending
            }
        } else {
            keys = storage.values.keys.sorted()
        }
        if formatting.prettyPrinted {
            try output.append("\n")
            if keys.isEmpty { try output.append("\n") }
        }
        for (index, key) in keys.enumerated() {
            if formatting.prettyPrinted { try indent(depth + 1) }
            try writeObjectKey(key)
            try output.append(formatting.prettyPrinted ? " : " : ":")
            if let value = storage.values[key] { try write(value, depth: depth + 1) }
            if index + 1 < keys.count { try output.append(byte: 0x2c) }
            if formatting.prettyPrinted { try output.append("\n") }
        }
        if formatting.prettyPrinted { try indent(depth) }
        try output.append(byte: 0x7d)
    }

    private func writeArray(_ values: [Node], depth: Int) throws {
        try output.append(byte: 0x5b)
        if formatting.prettyPrinted {
            try output.append("\n")
            if values.isEmpty { try output.append("\n") }
        }
        for (index, value) in values.enumerated() {
            if formatting.prettyPrinted { try indent(depth + 1) }
            try write(value, depth: depth + 1)
            if index + 1 < values.count { try output.append(byte: 0x2c) }
            if formatting.prettyPrinted { try output.append("\n") }
        }
        if formatting.prettyPrinted { try indent(depth) }
        try output.append(byte: 0x5d)
    }

    private func writeLazyFoundationArray(
        _ values: FoundationJSONLazyArray,
        depth: Int
    ) throws {
        try output.append(byte: 0x5b)
        if formatting.prettyPrinted {
            try output.append("\n")
            if values.count == 0 { try output.append("\n") }
        }
        var index = 0
        try values.forEach { value in
            try autoreleasepool {
                if self.formatting.prettyPrinted { try self.indent(depth + 1) }
                try self.write(
                    self.makeFoundationNode(value, depth: depth + 1),
                    depth: depth + 1
                )
            }
            index += 1
            if index < values.count { try self.output.append(byte: 0x2c) }
            if self.formatting.prettyPrinted { try self.output.append("\n") }
        }
        if formatting.prettyPrinted { try indent(depth) }
        try output.append(byte: 0x5d)
    }

    private func writeStreamingArray(
        _ values: any StreamingJSONArray,
        depth: Int
    ) throws {
        try output.append(byte: 0x5b)
        if formatting.prettyPrinted {
            try output.append("\n")
            if values.streamingCount == 0 { try output.append("\n") }
        }
        var index = 0
        try values.forEachStreamingElement { value in
            try autoreleasepool {
                if formatting.prettyPrinted { try indent(depth + 1) }
                try write(
                    makeNode(
                        value,
                        codingPath: [IndexKey(intValue: index)],
                        depth: depth + 1
                    ),
                    depth: depth + 1
                )
            }
            index += 1
            if index < values.streamingCount { try output.append(byte: 0x2c) }
            if formatting.prettyPrinted { try output.append("\n") }
        }
        if formatting.prettyPrinted { try indent(depth) }
        try output.append(byte: 0x5d)
    }

    private func writeObjectKey(_ value: String) throws {
        if let cached = encodedObjectKeys[value] {
            try output.append(cached)
            return
        }
        let utf8 = value.utf8
        if utf8.count <= 4 * 1_024,
           !utf8.contains(where: { byte in
               byte <= 0x1f || byte == 0x22 || byte == 0x5c ||
                   (byte == 0x2f && formatting.escapesSlashes)
           }) {
            var encoded = Data(capacity: utf8.count + 2)
            encoded.append(0x22)
            encoded.append(contentsOf: utf8)
            encoded.append(0x22)
            if encodedObjectKeys.count >= 1_024 {
                encodedObjectKeys.removeAll(keepingCapacity: true)
            }
            encodedObjectKeys[value] = encoded
            try output.append(encoded)
            return
        }
        try writeString(value)
    }

    private func writeString(_ value: String) throws {
        try output.append(byte: 0x22)
        let utf8 = value.utf8
        if utf8.count <= 128 * 1_024,
           !utf8.contains(where: { byte in
               byte <= 0x1f || byte == 0x22 || byte == 0x5c ||
                   (byte == 0x2f && formatting.escapesSlashes)
           }) {
            try output.append(Data(utf8))
            try output.append(byte: 0x22)
            return
        }
        var chunk = Data()
        chunk.reserveCapacity(16 * 1_024)

        func flushIfNeeded() throws {
            if chunk.count >= 16 * 1_024 {
                try output.append(chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }

        for byte in value.utf8 {
            switch byte {
            case 0x08: chunk.append(contentsOf: [0x5c, 0x62])
            case 0x09: chunk.append(contentsOf: [0x5c, 0x74])
            case 0x0a: chunk.append(contentsOf: [0x5c, 0x6e])
            case 0x0c: chunk.append(contentsOf: [0x5c, 0x66])
            case 0x0d: chunk.append(contentsOf: [0x5c, 0x72])
            case 0x00...0x1f:
                chunk.append(contentsOf: String(format: "\\u%04x", byte).utf8)
            case 0x22: chunk.append(contentsOf: [0x5c, 0x22])
            case 0x2f where formatting.escapesSlashes:
                chunk.append(contentsOf: [0x5c, 0x2f])
            case 0x5c: chunk.append(contentsOf: [0x5c, 0x5c])
            default: chunk.append(byte)
            }
            try flushIfNeeded()
        }
        try output.append(chunk)
        try output.append(byte: 0x22)
    }

    private func writeFloatingPoint(_ value: Double) throws {
        if value.isFinite, formatting.floatingPointStyle == .foundationFragment {
            try writeFoundationFragment(value)
        } else {
            try output.append(scalarEncoder.encode(value))
        }
    }

    private func writeFoundationFragment(_ value: Any) throws {
        try autoreleasepool {
            let data = try JSONSerialization.data(
                withJSONObject: value,
                options: [.fragmentsAllowed]
            )
            try output.append(data)
        }
    }

    private func writeBase64(_ value: CanonicalBase64Value) throws {
        try output.append(byte: 0x22)
        var carry = Data()
        try value.forEachChunk { chunk in
            try Task.checkCancellation()
            var combined = Data()
            combined.reserveCapacity(carry.count + chunk.count)
            combined.append(carry)
            combined.append(chunk)
            let completeCount = combined.count - (combined.count % 3)
            if completeCount > 0 {
                try appendBase64Encoded(
                    Data(combined[..<completeCount]).base64EncodedData()
                )
            }
            carry = completeCount < combined.count
                ? Data(combined[completeCount...])
                : Data()
        }
        if !carry.isEmpty {
            try appendBase64Encoded(carry.base64EncodedData())
        }
        try output.append(byte: 0x22)
    }

    private func appendBase64Encoded(_ data: Data) throws {
        guard formatting.escapesSlashes, data.contains(0x2f) else {
            try output.append(data)
            return
        }
        var escaped = Data()
        escaped.reserveCapacity(data.count + data.count / 32)
        for byte in data {
            if byte == 0x2f { escaped.append(0x5c) }
            escaped.append(byte)
        }
        try output.append(escaped)
    }

    private func indent(_ depth: Int) throws {
        guard depth > 0 else { return }
        try output.append(String(repeating: " ", count: depth * 2))
    }
}

extension Array: CanonicalJSONStreamEncoder.StreamingJSONArray where Element: Encodable {
    fileprivate var streamingCount: Int { count }

    fileprivate func forEachStreamingElement(
        _ body: (any Encodable) throws -> Void
    ) rethrows {
        for value in self { try body(value) }
    }
}
