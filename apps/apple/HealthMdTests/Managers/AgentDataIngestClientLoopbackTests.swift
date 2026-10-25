import Network
import XCTest
@testable import HealthMd

/// Wire-truth tests for `AgentDataIngestClient` against a real loopback
/// HTTP/1.1 gateway double speaking the frozen server contract from
/// `apps/cli/crates/healthmd-cli/src/mcp/ingest_http.rs`:
///
/// - one `POST /v1/ingest` request per artifact;
/// - body framed as one `\n`-terminated manifest line followed immediately
///   by exactly `byte_count` artifact bytes;
/// - `Content-Type: application/x-healthmd-agent-data-ingest` and an exact
///   `Content-Length`;
/// - every validated outcome answered `HTTP 200` with a
///   `healthmd.agent_ingest_response` v1 receipt; rejections are protocol
///   outcomes, never HTTP error statuses;
/// - a connection that closes before the full body arrives produces no
///   receipt (the phone-side retryable class).
/// Scripted per-request behavior.
enum GatewayBehavior {
    /// Answer with an accepted receipt (fixture grammar).
    case accept
    /// Answer with a rejection receipt for one of the four codes.
    case reject(AgentDataIngestRejectionCode)
    /// Answer a non-2xx transport-level rejection.
    case transportStatus(Int)
    /// Accept the connection, read nothing, and close without a receipt.
    case closeWithoutReceipt
    /// Behave per-request from a queue; the last entry repeats.
    case scripted([GatewayBehavior])
}

final class LoopbackGateway: @unchecked Sendable {
    let listener: NWListener
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var behaviors: [GatewayBehavior] = []
    private var repeatingBehavior: GatewayBehavior = .accept
    /// Captured requests for framing assertions (method, path, headers,
    /// manifest line, artifact bytes).
    private(set) var capturedRequests: [CapturedRequest] = []
    private var connectionIDs: Set<ObjectIdentifier> = []
    /// Bound port, captured from the listener's ready state.
    private var boundPort: UInt16?

    struct CapturedRequest {
        let method: String
        let path: String
        let headers: [(String, String)]
        let manifestLine: String
        let artifactBytes: Data
    }

    init(behavior: GatewayBehavior) throws {
        if case .scripted(let list) = behavior {
            self.behaviors = list
        } else {
            self.behaviors = []
        }
        if case .scripted(let list) = behavior, let last = list.last {
            self.repeatingBehavior = last
        } else {
            self.repeatingBehavior = behavior
        }
        // Probe for a free ephemeral port before binding (loopback test
        // listeners prefer ephemeral or probe-before-bind).
        let probedPort = try Self.probeFreeLoopbackPort()
        self.boundPort = probedPort
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        self.listener = try NWListener(
            using: parameters,
            on: NWEndpoint.Port(rawValue: probedPort)!
        )
        self.queue = DispatchQueue(label: "loopback-gateway-\(UUID().uuidString)")
    }

    var port: UInt16 {
        guard let boundPort else {
            preconditionFailure("listener not ready")
        }
        return boundPort
    }

    /// Binds a throwaway loopback socket on port 0, reads the assigned port,
    /// and closes it. The NWListener then binds that port with
    /// allowLocalEndpointReuse.
    private static func probeFreeLoopbackPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw NSError(domain: "LoopbackGateway", code: 2)
        }
        defer { close(descriptor) }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw NSError(domain: "LoopbackGateway", code: 3)
        }
        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(descriptor, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else {
            throw NSError(domain: "LoopbackGateway", code: 4)
        }
        return UInt16(bigEndian: boundAddress.sin_port)
    }

    var url: String {
        "http://127.0.0.1:\(port)"
    }

    func start() throws {
        let semaphore = DispatchSemaphore(value: 0)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                semaphore.signal()
            case .failed:
                semaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 5)
        guard listener.state == .ready else {
            throw NSError(
                domain: "LoopbackGateway", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "listener failed to become ready"]
            )
        }
    }

    func stop() {
        listener.cancel()
        lock.lock()
        connectionIDs.removeAll()
        lock.unlock()
    }

    private func nextBehavior() -> GatewayBehavior {
        lock.lock()
        defer { lock.unlock() }
        if !behaviors.isEmpty {
            return behaviors.removeFirst()
        }
        return repeatingBehavior
    }

    private func handle(_ connection: NWConnection) {
        lock.lock()
        connectionIDs.insert(ObjectIdentifier(connection))
        lock.unlock()
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequestHead(connection: connection)
            case .failed, .cancelled:
                self?.lock.lock()
                _ = self?.connectionIDs.remove(ObjectIdentifier(connection))
                self?.lock.unlock()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequestHead(connection: NWConnection) {
        // Read until the blank line ending the header block.
        var buffer = Data()
        func readMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                if let data { buffer.append(data) }
                if error != nil {
                    connection.cancel()
                    return
                }
                if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let head = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    let remainder = buffer.subdata(in: range.upperBound..<buffer.endIndex)
                    self.dispatch(connection: connection, head: head, alreadyRead: remainder)
                    return
                }
                if isComplete {
                    connection.cancel()
                    return
                }
                readMore()
            }
        }
        readMore()
    }

    private func dispatch(connection: NWConnection, head: Data, alreadyRead: Data) {
        guard let headText = String(data: head, encoding: .utf8) else {
            connection.cancel()
            return
        }
        var lines = headText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            connection.cancel()
            return
        }
        let method = String(parts[0])
        let path = String(parts[1])
        var headers: [(String, String)] = []
        for line in lines where !line.isEmpty {
            if let separator = line.firstIndex(of: ":") {
                headers.append((
                    String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased(),
                    String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                ))
            }
        }

        func header(_ name: String) -> String? {
            headers.first { $0.0 == name }?.1
        }
        guard let contentLengthText = header("content-length"),
              let contentLength = Int(contentLengthText) else {
            connection.cancel()
            return
        }

        func readBody(_ buffer: Data) {
            if buffer.count >= contentLength {
                let body = buffer.prefix(contentLength)
                self.finish(connection, method: method, path: path, headers: headers, body: Data(body))
                return
            }
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: contentLength - buffer.count
            ) { data, _, isComplete, error in
                var next = buffer
                if let data { next.append(data) }
                if error != nil {
                    connection.cancel()
                    return
                }
                if next.count >= contentLength {
                    self.finish(
                        connection,
                        method: method,
                        path: path,
                        headers: headers,
                        body: Data(next.prefix(contentLength))
                    )
                } else if isComplete {
                    connection.cancel()
                } else {
                    readBody(next)
                }
            }
        }
        readBody(alreadyRead)
    }

    private func finish(
        _ connection: NWConnection,
        method: String,
        path: String,
        headers: [(String, String)],
        body: Data
    ) {
        let behavior = nextBehavior()

        // Framing split: manifest line then exact artifact bytes.
        let newline = body.firstIndex(of: 0x0A)
        let manifestLine = newline.map { String(decoding: body[body.startIndex..<$0], as: UTF8.self) } ?? ""
        let artifactBytes = newline.map { body[$0...].dropFirst() } ?? Data()
        lock.lock()
        capturedRequests.append(CapturedRequest(
            method: method,
            path: path,
            headers: headers,
            manifestLine: manifestLine,
            artifactBytes: Data(artifactBytes)
        ))
        lock.unlock()

        // Server-side validation mirroring the reference gateway: only
        // well-framed, checksum-valid, schema-valid uploads produce the
        // accepted fixture grammar; the tests drive other outcomes with
        // explicit scripted behaviors.
        switch behavior {
        case .accept:
            respond(
                connection,
                status: 200,
                body: Self.acceptedReceipt(for: manifestLine, artifactBytes: Data(artifactBytes))
            )
        case .reject(let code):
            respond(
                connection,
                status: 200,
                body: Self.rejectedReceipt(code)
            )
        case .transportStatus(let status):
            respond(connection, status: status, body: Data("{\"code\":\"gateway\",\"message\":\"transport\"}".utf8))
        case .closeWithoutReceipt:
            connection.cancel()
        case .scripted:
            respond(connection, status: 200, body: Self.rejectedReceipt(.transient))
        }
    }

    private func respond(_ connection: NWConnection, status: Int, body: Data) {
        var head = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func acceptedReceipt(for manifestLine: String, artifactBytes: Data) -> Data {
        // Mirror the ingest-accepted-complete.json fixture grammar with
        // the real stored revision identity (SHA-256 of stored bytes).
        let digest = AgentDataIngestManifest.sha256(of: artifactBytes)
        let ownerDate = (try? JSONSerialization.jsonObject(with: Data(manifestLine.utf8)))
            .flatMap { $0 as? [String: Any] }?["owner_date"] as? String ?? "2026-03-15"
        let byteCount = artifactBytes.count
        return Data("""
        {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"accepted",\
        "stored":{"revision_id":"\(digest)","byte_count":\(byteCount),"completeness":{"type":"complete"}},\
        "partition":{"owner_date":"\(ownerDate)","authoritative":{"revision_id":"\(digest)",\
        "completeness":{"type":"complete"}},"complete_revision_present":true,"partial_revision_present":false}}
        """.utf8)
    }

    static func rejectedReceipt(_ code: AgentDataIngestRejectionCode) -> Data {
        Data("""
        {"schema":"healthmd.agent_ingest_response","schema_version":1,"outcome":"rejected",\
        "rejection":{"code":"\(code.rawValue)"}}
        """.utf8)
    }
}

final class AgentDataIngestClientLoopbackTests: XCTestCase {

    // MARK: - Helpers

    private var gateways: [LoopbackGateway] = []

    private func makeGateway(_ behavior: GatewayBehavior) throws -> LoopbackGateway {
        let gateway = try LoopbackGateway(behavior: behavior)
        try gateway.start()
        gateways.append(gateway)
        return gateway
    }

    override func tearDown() {
        for gateway in gateways {
            gateway.stop()
        }
        gateways.removeAll()
        super.tearDown()
    }

    private func noSleep() -> @Sendable (TimeInterval) async throws -> Void {
        { _ in }
    }

    private func makeArtifact() throws -> (URL, Data) {
        let bytes = Data("{\"schema\":\"healthmd.health_data\",\"schema_version\":8}".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("artifact-\(UUID().uuidString).json")
        try bytes.write(to: url)
        return (url, bytes)
    }

    private func makeClient(maximumAttempts: Int = 3) -> AgentDataIngestClient {
        AgentDataIngestClient(
            maximumAttempts: maximumAttempts,
            initialRetryDelay: 0.01,
            sleep: noSleep()
        )
    }

    private func makeManifest(artifactBytes: Data) throws -> AgentDataIngestManifest {
        try AgentDataIngestManifestBuilder.manifest(
            kind: .healthDataDaily,
            platform: "apple",
            artifactSchema: "healthmd.health_data",
            artifactSchemaVersion: 8,
            ownerDate: "2026-03-15",
            physicalFormat: .json,
            mediaType: "application/json",
            artifactBytes: artifactBytes
        )
    }

    private func makeDestination(_ gateway: LoopbackGateway) throws -> AgentDataGatewayDestinationSnapshot {
        try XCTUnwrap(AgentDataGatewayDestinationSnapshot(endpointURLString: gateway.url))
    }


        func testAcceptedUploadSendsExactFrozenFraming() async throws {
            let gateway = try makeGateway(.accept)
            let (artifactURL, artifactBytes) = try makeArtifact()
            let manifest = try makeManifest(artifactBytes: artifactBytes)
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("bodies-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let outcome = await makeClient().upload(
                manifest: manifest,
                artifactFileURL: artifactURL,
                destination: try makeDestination(gateway),
                stagingDirectory: staging
            )

            XCTAssertEqual(outcome.result, .accepted)
            XCTAssertEqual(outcome.attempts, 1)

            let request = try XCTUnwrap(gateway.capturedRequests.first)
            // Method, path, and media type are the frozen surface.
            XCTAssertEqual(request.method, "POST")
            XCTAssertEqual(request.path, "/v1/ingest")
            XCTAssertEqual(
                request.headers.first { $0.0 == "content-type" }?.1,
                "application/x-healthmd-agent-data-ingest"
            )
            // Exact Content-Length: manifest line + newline + byte_count.
            XCTAssertEqual(
                Int(request.headers.first { $0.0 == "content-length" }?.1 ?? ""),
                request.manifestLine.utf8.count + 1 + artifactBytes.count
            )
            XCTAssertEqual(request.manifestLine.utf8.count + 1 + artifactBytes.count, manifest.byteCount + request.manifestLine.utf8.count + 1)
            // The artifact bytes arrive exactly and byte-identically.
            XCTAssertEqual(request.artifactBytes, artifactBytes)
            // The manifest line parses and describes those exact bytes.
            let manifestObject = try XCTUnwrap(JSONSerialization.jsonObject(
                with: Data(request.manifestLine.utf8)
            ) as? [String: Any])
            XCTAssertEqual(manifestObject["byte_count"] as? Int, artifactBytes.count)
            XCTAssertEqual(manifestObject["sha256"] as? String, AgentDataIngestManifest.sha256(of: artifactBytes))
            XCTAssertEqual(manifestObject["schema"] as? String, "healthmd.agent_data_ingest")
            XCTAssertEqual(manifestObject["platform"] as? String, "apple")
            XCTAssertNil(manifestObject["record_count"])
        }

        // MARK: - Fix-and-reupload rejections are never retried

        func testTruncatedRejectionIsSurfacedWithoutRetry() async throws {
            try await assertFixAndReupload(.truncated)
        }

        func testChecksumInvalidRejectionIsSurfacedWithoutRetry() async throws {
            try await assertFixAndReupload(.checksumInvalid)
        }

        func testManifestIncompleteRejectionIsSurfacedWithoutRetry() async throws {
            try await assertFixAndReupload(.manifestIncomplete)
        }

        private func assertFixAndReupload(_ code: AgentDataIngestRejectionCode) async throws {
            let gateway = try makeGateway(.reject(code))
            let (artifactURL, artifactBytes) = try makeArtifact()
            let manifest = try makeManifest(artifactBytes: artifactBytes)
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("bodies-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let outcome = await makeClient().upload(
                manifest: manifest,
                artifactFileURL: artifactURL,
                destination: try makeDestination(gateway),
                stagingDirectory: staging
            )

            XCTAssertEqual(outcome.result, .rejected(code))
            XCTAssertEqual(outcome.attempts, 1)
            XCTAssertEqual(gateway.capturedRequests.count, 1)
        }

        // MARK: - Transient + transport retry

        func testTransientReceiptIsRetriedAndThenSucceeds() async throws {
            let gateway = try makeGateway(.scripted([.reject(.transient), .accept]))
            let (artifactURL, artifactBytes) = try makeArtifact()
            let manifest = try makeManifest(artifactBytes: artifactBytes)
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("bodies-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let outcome = await makeClient().upload(
                manifest: manifest,
                artifactFileURL: artifactURL,
                destination: try makeDestination(gateway),
                stagingDirectory: staging
            )

            XCTAssertEqual(outcome.result, .accepted)
            XCTAssertEqual(outcome.attempts, 2)
            XCTAssertEqual(gateway.capturedRequests.count, 2)
            // Both requests carried identical framing.
            XCTAssertEqual(gateway.capturedRequests.map(\.artifactBytes), [artifactBytes, artifactBytes])
        }

        func testNon2xxTransportRejectionIsRetriedThenSucceeds() async throws {
            let gateway = try makeGateway(.scripted([.transportStatus(503), .accept]))
            let (artifactURL, artifactBytes) = try makeArtifact()
            let manifest = try makeManifest(artifactBytes: artifactBytes)
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("bodies-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let outcome = await makeClient().upload(
                manifest: manifest,
                artifactFileURL: artifactURL,
                destination: try makeDestination(gateway),
                stagingDirectory: staging
            )

            XCTAssertEqual(outcome.result, .accepted)
            XCTAssertEqual(outcome.attempts, 2)
        }

        func testConnectionCloseWithoutReceiptIsRetried() async throws {
            let gateway = try makeGateway(.scripted([.closeWithoutReceipt, .accept]))
            let (artifactURL, artifactBytes) = try makeArtifact()
            let manifest = try makeManifest(artifactBytes: artifactBytes)
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("bodies-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let outcome = await makeClient().upload(
                manifest: manifest,
                artifactFileURL: artifactURL,
                destination: try makeDestination(gateway),
                stagingDirectory: staging
            )

            XCTAssertEqual(outcome.result, .accepted)
            XCTAssertEqual(outcome.attempts, 2)
        }

        func testTransportFailureBoundedRetriesThenFails() async throws {
            // Nothing listens on this loopback port: connection refused on every
            // attempt. Bound to an ephemeral port via a stopped listener, reading
            // the port before the listener is cancelled.
            let stopped = try makeGateway(.accept)
            let port = stopped.port
            stopped.stop()
            gateways.removeAll { $0 === stopped }

            let (artifactURL, artifactBytes) = try makeArtifact()
            let manifest = try makeManifest(artifactBytes: artifactBytes)
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("bodies-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            let destination = try XCTUnwrap(
                AgentDataGatewayDestinationSnapshot(
                    endpointURLString: "http://127.0.0.1:\(port)"
                )
            )

            let outcome = await makeClient(maximumAttempts: 3).upload(
                manifest: manifest,
                artifactFileURL: artifactURL,
                destination: destination,
                stagingDirectory: staging
            )

            guard case .uploadFailed = outcome.result else {
                XCTFail("expected uploadFailed, got \(outcome.result)")
                return
            }
            XCTAssertEqual(outcome.attempts, 3)
        }

        // MARK: - Framing stage

        func testStagedBodyIsManifestLineNewlineThenExactBytes() throws {
            let artifactBytes = Data("exact-bytes-\(UUID().uuidString)".utf8)
            let artifactURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("artifact-\(UUID().uuidString).json")
            try artifactBytes.write(to: artifactURL)
            defer { try? FileManager.default.removeItem(at: artifactURL) }
            let manifest = try makeManifest(artifactBytes: artifactBytes)
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("bodies-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }

            let bodyURL = try AgentDataIngestClient.stageFramedBody(
                manifest: manifest,
                artifactFileURL: artifactURL,
                in: staging
            )
            defer { try? FileManager.default.removeItem(at: bodyURL) }
            let body = try Data(contentsOf: bodyURL)

            let newline = try XCTUnwrap(body.firstIndex(of: 0x0A))
            let line = String(decoding: body[body.startIndex..<newline], as: UTF8.self)
            let bytes = body[body.index(after: newline)...]
            XCTAssertEqual(
                line,
                String(decoding: try manifest.encodedLine(), as: UTF8.self)
            )
            XCTAssertEqual(Data(bytes), artifactBytes)
            XCTAssertEqual(body.count, line.utf8.count + 1 + artifactBytes.count)
        }
    }

