import Foundation

nonisolated enum BoundedURLSessionDataLoaderError: Error, Equatable {
    case responseTooLarge(
        statusCode: Int?,
        maximumBytes: Int,
        retryAfterSeconds: Int?
    )
}

/// Collects URLSession responses with a hard byte ceiling. Loaders created from
/// a configuration use delegate-sized chunks. Loaders created from an existing
/// session stream `AsyncBytes` through that exact session so injected delegate
/// authentication, certificate pinning, and other task behavior are preserved.
nonisolated final class BoundedURLSessionDataLoader: NSObject, @unchecked Sendable {
    private struct RequestState {
        let maximumBytes: Int
        var response: URLResponse?
        var data = Data()
        let continuation: CheckedContinuation<(Data, URLResponse), Error>
    }

    private final class DelegateProxy: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        weak var owner: BoundedURLSessionDataLoader?

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let owner else {
                completionHandler(.cancel)
                return
            }
            owner.receive(
                dataTask: dataTask,
                response: response,
                completionHandler: completionHandler
            )
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive data: Data
        ) {
            owner?.receive(dataTask: dataTask, data: data)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            owner?.complete(task: task, error: error)
        }
    }

    private final class TaskReference: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var isCancelled = false

        func set(_ task: URLSessionTask) {
            lock.lock()
            self.task = task
            let shouldCancel = isCancelled
            lock.unlock()
            if shouldCancel { task.cancel() }
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let task = task
            lock.unlock()
            task?.cancel()
        }
    }

    private let delegateProxy: DelegateProxy?
    private let session: URLSession
    private let ownsSession: Bool
    private let lock = NSLock()
    private var states: [Int: RequestState] = [:]

    init(configuration: URLSessionConfiguration) {
        let delegateProxy = DelegateProxy()
        self.delegateProxy = delegateProxy
        self.session = URLSession(
            configuration: configuration,
            delegate: delegateProxy,
            delegateQueue: nil
        )
        self.ownsSession = true
        super.init()
        delegateProxy.owner = self
    }

    /// Uses the supplied session itself instead of cloning only its
    /// configuration. This is intentionally a separate path because URLSession
    /// does not expose a safe way to replace its data delegate while forwarding
    /// every custom authentication and task-delegate behavior.
    init(session: URLSession) {
        self.delegateProxy = nil
        self.session = session
        self.ownsSession = false
        super.init()
    }

    deinit {
        if ownsSession {
            session.invalidateAndCancel()
        }
    }

    func data(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, URLResponse) {
        let maximumBytes = max(1, maximumBytes)
        guard delegateProxy != nil else {
            return try await dataUsingInjectedSession(
                for: request,
                maximumBytes: maximumBytes
            )
        }

        let taskReference = TaskReference()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                lock.lock()
                states[task.taskIdentifier] = RequestState(
                    maximumBytes: maximumBytes,
                    continuation: continuation
                )
                lock.unlock()
                taskReference.set(task)
                task.resume()
            }
        } onCancel: {
            taskReference.cancel()
        }
    }

    private func dataUsingInjectedSession(
        for request: URLRequest,
        maximumBytes: Int
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        if response.expectedContentLength > Int64(maximumBytes) {
            bytes.task.cancel()
            throw Self.responseTooLargeError(
                response: response,
                maximumBytes: maximumBytes
            )
        }

        return try await withTaskCancellationHandler {
            var data = Data()
            if response.expectedContentLength > 0 {
                data.reserveCapacity(min(
                    Int(response.expectedContentLength),
                    maximumBytes
                ))
            }

            do {
                for try await byte in bytes {
                    guard data.count < maximumBytes else {
                        bytes.task.cancel()
                        throw Self.responseTooLargeError(
                            response: response,
                            maximumBytes: maximumBytes
                        )
                    }
                    data.append(byte)
                }
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            }
            return (data, response)
        } onCancel: {
            bytes.task.cancel()
        }
    }

    private func receive(
        dataTask: URLSessionDataTask,
        response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        let taskIdentifier = dataTask.taskIdentifier
        var rejected: RequestState?

        lock.lock()
        if var state = states[taskIdentifier] {
            if response.expectedContentLength > Int64(state.maximumBytes) {
                rejected = states.removeValue(forKey: taskIdentifier)
            } else {
                state.response = response
                if response.expectedContentLength > 0 {
                    state.data.reserveCapacity(min(
                        Int(response.expectedContentLength),
                        state.maximumBytes
                    ))
                }
                states[taskIdentifier] = state
            }
        }
        lock.unlock()

        if let rejected {
            completionHandler(.cancel)
            rejected.continuation.resume(throwing: Self.responseTooLargeError(
                response: response,
                maximumBytes: rejected.maximumBytes
            ))
        } else {
            completionHandler(.allow)
        }
    }

    private func receive(
        dataTask: URLSessionDataTask,
        data: Data
    ) {
        let taskIdentifier = dataTask.taskIdentifier
        var rejected: RequestState?

        lock.lock()
        if var state = states[taskIdentifier] {
            if data.count > state.maximumBytes - state.data.count {
                rejected = states.removeValue(forKey: taskIdentifier)
            } else {
                state.data.append(data)
                states[taskIdentifier] = state
            }
        }
        lock.unlock()

        if let rejected {
            dataTask.cancel()
            rejected.continuation.resume(throwing: Self.responseTooLargeError(
                response: dataTask.response,
                maximumBytes: rejected.maximumBytes
            ))
        }
    }

    private static func responseTooLargeError(
        response: URLResponse?,
        maximumBytes: Int
    ) -> BoundedURLSessionDataLoaderError {
        let http = response as? HTTPURLResponse
        let retryAfterValue = http?.value(forHTTPHeaderField: "X-RateLimit-Reset")
            ?? http?.value(forHTTPHeaderField: "Retry-After")
        let retryAfterSeconds = retryAfterValue.flatMap(Int.init).flatMap { value in
            value >= 0 ? value : nil
        }
        return .responseTooLarge(
            statusCode: http?.statusCode,
            maximumBytes: maximumBytes,
            retryAfterSeconds: retryAfterSeconds
        )
    }

    private func complete(
        task: URLSessionTask,
        error: Error?
    ) {
        lock.lock()
        let state = states.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        guard let state else { return }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            state.continuation.resume(throwing: CancellationError())
        } else if let error {
            state.continuation.resume(throwing: error)
        } else if let response = state.response ?? task.response {
            state.continuation.resume(returning: (state.data, response))
        } else {
            state.continuation.resume(throwing: URLError(.badServerResponse))
        }
    }
}
