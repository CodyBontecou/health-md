import Foundation

private nonisolated final class Script: @unchecked Sendable {
    let lock = NSLock()
    var status = 200
    var media: String? = "application/json"
    var bytes = Data()
    var mode = "body"
    var starts = 0
    var stops = 0
    var request: URLRequest?
    var requestBody = Data()
    var emittedBody = false
    func set(_ mode: String = "body", status: Int = 200, media: String? = "application/json", bytes: Data = Data()) {
        lock.lock(); defer { lock.unlock() }
        self.mode = mode; self.status = status; self.media = media; self.bytes = bytes
        starts = 0; stops = 0; request = nil; requestBody = Data(); emittedBody = false
    }
    func counts() -> (Int, Int) { lock.lock(); defer { lock.unlock() }; return (starts, stops) }
    func bodyStarted() -> Bool { lock.lock(); defer { lock.unlock() }; return emittedBody }
}
private nonisolated final class SyntheticProtocol: URLProtocol, @unchecked Sendable {
    static let script = Script()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let s = Self.script
        s.lock.lock()
        s.starts += 1; s.request = request
        if let body = request.httpBody { s.requestBody = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                s.requestBody.append(contentsOf: buffer.prefix(count))
            }
            stream.close()
        }
        let (mode, status, media, bytes) = (s.mode, s.status, s.media, s.bytes)
        s.lock.unlock()
        if mode == "hang" { return }
        if mode == "unavailable" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: media.map { ["Content-Type": $0] })!
        if mode == "redirect" {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: "https://foreign.example/steal")!), redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if mode == "hang_body" {
            client?.urlProtocol(self, didLoad: Data("{".utf8))
            s.lock.lock(); s.emittedBody = true; s.lock.unlock()
            return
        }
        for offset in stride(from: 0, to: bytes.count, by: 1024) {
            client?.urlProtocol(self, didLoad: bytes.subdata(in: offset..<min(offset + 1024, bytes.count)))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {
        let s = Self.script; s.lock.lock(); s.stops += 1; s.lock.unlock()
    }
}

private func hex(_ s: String) -> Data {
    Data(stride(from: 0, to: s.count, by: 2).map { i in
        let start = s.index(s.startIndex, offsetBy: i)
        return UInt8(s[start..<s.index(start, offsetBy: 2)], radix: 16)!
    })
}
private func waitFor(_ predicate: @Sendable () -> Bool) async throws {
    for _ in 0..<1000 {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(1))
    }
    fatalError("Synthetic protocol event did not arrive")
}
private func fallback(_ outcome: ReceiverCoverageOutcome) {
    guard case .fallbackFull = outcome else { fatalError("Untrusted receiver suppressed work") }
}

@main struct TransportTests {
    static func main() async throws {
        let preflight = /*PREPARE*/!
        let request = try preflight.freezeRequest(requestID: "occurrence-1", candidates: ["2026-03-06", "2026-03-07", "2026-03-08"], now: Date(timeIntervalSince1970: 1773043200))
        let client = ReceiverCoverageHTTPClient(protocolClasses: [SyntheticProtocol.self])
        let rows = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).split(separator: "\n")
        for row in rows {
            let columns = row.split(separator: "\t", omittingEmptySubsequences: false)
            let bytes = Data(base64Encoded: String(columns[2]))!
            let accepted = columns[1] == "valid"
            do {
                let evidence = try ReceiverCoverageEvidence.parse(bytes, for: request)
                precondition(accepted, "Invalid parser evidence: \(columns[0])")
                print("\(columns[0])\t\(evidence.normalizedResponse.base64EncodedString())")
            } catch {
                precondition(!accepted, "Rejected valid parser evidence: \(columns[0])")
                print("\(columns[0])\tinvalid")
            }
            SyntheticProtocol.script.set(bytes: bytes)
            let result = try await client.query(request)
            if accepted {
                guard case .valid(let evidence) = result else { fatalError("Valid HTTP coverage rejected") }
                let expected = try ReceiverCoverageEvidence.parse(bytes, for: request)
                precondition(evidence.completedDates == expected.completedDates)
            } else { fallback(result) }
            precondition(SyntheticProtocol.script.counts().0 == 1, "Unexpected retry")
        }
        let valid = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        for status in [204, 301, 302, 307, 308, 401, 429, 500] {
            SyntheticProtocol.script.set(status: status, bytes: valid)
            fallback(try await client.query(request))
            precondition(SyntheticProtocol.script.counts().0 == 1)
        }
        for media in [nil, "text/html", "application/jsonp"] as [String?] {
            SyntheticProtocol.script.set(media: media, bytes: valid)
            fallback(try await client.query(request))
        }
        SyntheticProtocol.script.set("unavailable")
        fallback(try await client.query(request))
        SyntheticProtocol.script.set(bytes: Data(repeating: 32, count: 65537))
        fallback(try await client.query(request))
        // Real URLSession redirect delegate: the foreign URL must never be requested.
        SyntheticProtocol.script.set("redirect", status: 302)
        fallback(try await client.query(request))
        precondition(SyntheticProtocol.script.counts().0 == 1)

        for mode in ["hang", "hang_body"] {
            SyntheticProtocol.script.set(mode)
            let task = Task { try await client.query(request) }
            try await waitFor { SyntheticProtocol.script.counts().0 == 1 }
            if mode == "hang_body" { try await waitFor { SyntheticProtocol.script.bodyStarted() } }
            task.cancel()
            do { _ = try await task.value; fatalError("Cancellation became fallback") }
            catch is CancellationError {}
            try await waitFor { SyntheticProtocol.script.counts().1 >= 1 }
            precondition(SyntheticProtocol.script.counts().0 == 1)
        }
        SyntheticProtocol.script.set("hang")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.query(request)
        }
        do { _ = try await cancelled.value; fatalError("Pre-cancelled query ran") } catch is CancellationError {}
        precondition(SyntheticProtocol.script.counts().0 == 0)
        for mode in ["hang", "hang_body"] {
            SyntheticProtocol.script.set(mode)
            let short = ReceiverCoverageHTTPClient(protocolClasses: [SyntheticProtocol.self], deadline: 0.05)
            fallback(try await short.query(request))
            try await waitFor { SyntheticProtocol.script.counts().1 >= 1 }
        }
        // Verify POST and only the frozen same-origin credential/header configuration.
        SyntheticProtocol.script.set(bytes: valid)
        _ = try await client.query(request)
        let wire = SyntheticProtocol.script.request!
        precondition(wire.url == request.url && wire.httpMethod == "POST")
        precondition(SyntheticProtocol.script.requestBody == request.body)
        precondition(wire.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        precondition(wire.value(forHTTPHeaderField: "X-Tenant") == "synthetic")
        precondition(wire.value(forHTTPHeaderField: "Accept") == "application/json")
        precondition(wire.value(forHTTPHeaderField: "Content-Type") == "application/json")
        print("transport\tok")
    }
}
