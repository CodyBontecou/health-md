import Foundation

/// Dedicated ephemeral transport: no upload-client redirects, shared credentials, cookies, cache,
/// response previews or logging. Only new opted-in occurrences may call it; no automatic retries.
nonisolated struct ReceiverCoverageHTTPClient: Sendable {
    private let protocolClasses: [AnyClass]?
    private let deadline: TimeInterval

    init(protocolClasses: [AnyClass]? = nil, deadline: TimeInterval = 10) {
        precondition(deadline > 0 && deadline <= Double(ReceiverCoveragePreflight.deadlineSeconds))
        self.protocolClasses = protocolClasses
        self.deadline = deadline
    }

    func query(_ request: ReceiverCoverageRequest) async throws -> ReceiverCoverageOutcome {
        try Task.checkCancellation()
        let expires = ProcessInfo.processInfo.systemUptime + deadline
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = deadline
        configuration.timeoutIntervalForResource = deadline
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        var wire = URLRequest(url: request.url)
        wire.httpMethod = "POST"
        wire.httpBody = request.body
        wire.allHTTPHeaderFields = request.headers
        let exchange = CoverageHTTPExchange()
        do {
            let remaining = expires - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else {
                try Task.checkCancellation()
                return .fallbackFull
            }
            let bytes = try await exchange.run(wire, configuration: configuration, deadline: remaining)
            try Task.checkCancellation()
            let evidence = try ReceiverCoverageEvidence.parse(bytes, for: request)
            try Task.checkCancellation()
            guard ProcessInfo.processInfo.systemUptime < expires else { return .fallbackFull }
            return .valid(evidence)
        } catch {
            // Cancellation never becomes fallback, including races with EOF/parse/deadline errors.
            try Task.checkCancellation()
            if error is CancellationError { throw CancellationError() }
            return .fallbackFull
        }
    }
}

/// URLSession delegates run off actor. Every mutable field and continuation transition is guarded
/// by lock; callbacks/cancellation/deadline may race, but exactly one completion wins. Session/task
/// cancellation and continuation resumption happen outside the lock. No health/private error escapes.
private nonisolated final class CoverageHTTPExchange: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var timer: DispatchWorkItem?
    private var buffer: ReceiverCoverageResponseBuffer?
    private var finished = false

    func run(_ request: URLRequest, configuration: URLSessionConfiguration, deadline: TimeInterval) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if finished {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
                let task = session.dataTask(with: request)
                let timer = DispatchWorkItem { [weak self] in self?.reject() }
                self.session = session
                self.task = task
                self.timer = timer
                DispatchQueue.global().asyncAfter(deadline: .now() + deadline, execute: timer)
                task.resume()
                lock.unlock()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func reject() { finish(.failure(ReceiverCoveragePreflight.BoundaryError.invalidResponse)) }

    private func finish(_ result: Result<Data, any Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        let session = self.session
        let task = self.task
        let timer = self.timer
        self.continuation = nil
        self.session = nil
        self.task = nil
        self.timer = nil
        buffer = nil
        lock.unlock()
        timer?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse,
              response.url == dataTask.originalRequest?.url,
              response.expectedContentLength <= Int64(ReceiverCoveragePreflight.maximumResponseBytes),
              let buffer = try? ReceiverCoverageResponseBuffer(statusCode: response.statusCode,
                  contentType: response.value(forHTTPHeaderField: "Content-Type")) else {
            completionHandler(.cancel)
            reject()
            return
        }
        lock.lock()
        let active = !finished
        if active { self.buffer = buffer }
        lock.unlock()
        completionHandler(active ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        do {
            guard buffer != nil else { throw ReceiverCoveragePreflight.BoundaryError.invalidResponse }
            try buffer?.append(data)
            lock.unlock()
        } catch {
            lock.unlock()
            reject()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let data = error == nil ? try? buffer?.finish() : nil
        lock.unlock()
        if let data { finish(.success(data)) } else { reject() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
        reject()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(_ challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Cover BOTH session-level (e.g. client certificate) and task-level challenges. Preserve
        // platform TLS trust validation; never acquire/retry account/proxy/client credentials.
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            reject()
        }
    }
}
