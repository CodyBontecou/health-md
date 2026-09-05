import Foundation

// MARK: - Agent Data ingestion HTTP upload client
//
// One artifact per request: `POST {base}/v1/ingest` with
// `Content-Type: application/x-healthmd-agent-data-ingest`, an exact
// `Content-Length`, and a body of one `\n`-terminated
// `healthmd.agent_data_ingest` v1 manifest line followed immediately by
// exactly `byte_count` artifact bytes. No compression, multipart, or chunked
// upload sessions.
//
// Every validated outcome — accepted or rejected — arrives as HTTP 2xx with
// a `healthmd.agent_ingest_response` v1 receipt. Client retry posture
// (frozen): bounded retries with backoff for transport failures
// (connection refused/reset/timeout, non-2xx transport-level rejections)
// and `transient` receipts; NEVER auto-retry `truncated`,
// `checksum_invalid`, or `manifest_incomplete` — those are
// fix-and-reupload outcomes surfaced to the user.

/// Health-free outcome of one artifact upload attempt (after any retries).
struct AgentDataIngestUploadOutcome: Equatable {
    enum Result: Equatable {
        case accepted
        /// The gateway answered with a fix-and-reupload rejection; never retried.
        case rejected(AgentDataIngestRejectionCode)
        /// No valid receipt could be obtained: transport failures persisted
        /// through every bounded retry, or the response was not a valid
        /// v1 receipt. The error description is health-free.
        case uploadFailed(description: String)
    }

    let result: Result
    let attempts: Int
    /// Byte count of the artifact this outcome describes.
    let byteCount: Int

    var isAccepted: Bool {
        if case .accepted = result { return true }
        return false
    }
}

enum AgentDataIngestClientError: LocalizedError, Equatable {
    /// The staged framed body could not be prepared. Never retried: the
    /// local precondition will fail identically on every attempt.
    case framingFailed
    /// A transport-level network failure (connection refused/reset/timeout,
    /// DNS, TLS). Retryable; the description is health-free.
    case transportFailed(description: String)
    /// A non-2xx transport-level rejection (retryable class).
    case transportRejected(statusCode: Int)
    /// The gateway answered with a `transient` receipt; the bounded-retry class.
    case gatewayTransient
    /// The response was not a valid `healthmd.agent_ingest_response` v1
    /// receipt. Retryable: an identical re-upload is idempotent.
    case invalidReceipt(statusCode: Int?)

    var errorDescription: String? {
        switch self {
        case .framingFailed:
            return "Health.md could not prepare the Agent Data gateway upload."
        case .transportFailed(let description):
            return description
        case .invalidReceipt(let statusCode):
            let status = statusCode.map { " (HTTP \($0))" } ?? ""
            return "The Agent Data gateway returned an invalid response\(status)."
        case .transportRejected(let statusCode):
            return "The Agent Data gateway returned HTTP \(statusCode)."
        case .gatewayTransient:
            return "The Agent Data gateway asked Health.md to retry later."
        }
    }

    /// Transport failures, non-2xx rejections, `transient` receipts, and
    /// invalid receipts are the bounded-retry classes; framing failures are
    /// terminal.
    var isRetryable: Bool {
        switch self {
        case .framingFailed:
            return false
        case .transportFailed, .transportRejected, .gatewayTransient, .invalidReceipt:
            return true
        }
    }
}

/// Retryable classification shared by transport errors and receipts.
private enum AttemptOutcome {
    /// Keep retrying: transport failure or a `transient` receipt.
    case retryable(AgentDataIngestClientError)
    /// Terminal fix-and-reupload rejection; surface, never retry.
    case rejected(AgentDataIngestRejectionCode)
    /// Accepted.
    case accepted(AgentDataIngestReceipt)
}

struct AgentDataIngestClient {
    nonisolated static let defaultMaximumResponseBytes = 64 * 1_024
    /// Bounded attempts for transport failures and `transient` receipts.
    nonisolated static let defaultMaximumAttempts = 3

    private let responseLoader: BoundedURLSessionDataLoader
    private let maximumResponseBytes: Int
    private let maximumAttempts: Int
    private let initialRetryDelay: TimeInterval
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        maximumResponseBytes: Int = AgentDataIngestClient.defaultMaximumResponseBytes,
        maximumAttempts: Int = AgentDataIngestClient.defaultMaximumAttempts,
        initialRetryDelay: TimeInterval = 0.5,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.responseLoader = BoundedURLSessionDataLoader(
            configuration: URLSession.shared.configuration
        )
        self.maximumResponseBytes = max(1, maximumResponseBytes)
        self.maximumAttempts = max(1, maximumAttempts)
        self.initialRetryDelay = max(0, initialRetryDelay)
        self.sleep = sleep
    }

    init(
        session: URLSession,
        maximumResponseBytes: Int = AgentDataIngestClient.defaultMaximumResponseBytes,
        maximumAttempts: Int = AgentDataIngestClient.defaultMaximumAttempts,
        initialRetryDelay: TimeInterval = 0.5,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
    ) {
        self.responseLoader = BoundedURLSessionDataLoader(session: session)
        self.maximumResponseBytes = max(1, maximumResponseBytes)
        self.maximumAttempts = max(1, maximumAttempts)
        self.initialRetryDelay = max(0, initialRetryDelay)
        self.sleep = sleep
    }

    // MARK: - Framing

    /// Stages the exact framed request body for one artifact: the manifest
    /// line, `\n`, then a byte-for-byte copy of the artifact file. The staged
    /// file's size is the exact `Content-Length` URLSession reports.
    ///
    /// The manifest's `byte_count`/`sha256` are computed over the exact
    /// artifact bytes so the framed body and manifest always agree.
    static func stageFramedBody(
        manifest: AgentDataIngestManifest,
        artifactFileURL: URL,
        in directory: URL
    ) throws -> URL {
        let manifestLine = try manifest.encodedLine()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let bodyURL = directory
            .appendingPathComponent("ingest-\(UUID().uuidString).body", isDirectory: false)

        let bodyDescriptor = Darwin.open(
            bodyURL.path,
            O_WRONLY | O_CREAT | O_EXCL,
            0o600
        )
        guard bodyDescriptor >= 0 else {
            throw AgentDataIngestClientError.framingFailed
        }
        var bodyOpen = true
        defer {
            if bodyOpen {
                Darwin.close(bodyDescriptor)
                try? FileManager.default.removeItem(at: bodyURL)
            }
        }

        func writeAll(_ buffer: UnsafeRawBufferPointer, to descriptor: Int32) throws {
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else {
                    throw AgentDataIngestClientError.framingFailed
                }
                offset += written
            }
        }

        try manifestLine.withUnsafeBytes { try writeAll($0, to: bodyDescriptor) }
        try Data([0x0A]).withUnsafeBytes { try writeAll($0, to: bodyDescriptor) }

        let artifactDescriptor = Darwin.open(artifactFileURL.path, O_RDONLY | O_NOFOLLOW)
        guard artifactDescriptor >= 0 else {
            throw AgentDataIngestClientError.framingFailed
        }
        defer { Darwin.close(artifactDescriptor) }

        let chunkSize = 128 * 1_024
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: chunkSize,
            alignment: MemoryLayout<UInt64>.alignment
        )
        defer { buffer.deallocate() }
        var copied: UInt64 = 0
        while true {
            var count: Int
            repeat {
                count = Darwin.read(artifactDescriptor, buffer, chunkSize)
            } while count < 0 && errno == EINTR
            guard count >= 0 else { throw AgentDataIngestClientError.framingFailed }
            if count == 0 { break }
            try writeAll(UnsafeRawBufferPointer(start: buffer, count: count), to: bodyDescriptor)
            copied += UInt64(count)
        }
        guard copied == UInt64(manifest.byteCount) else {
            // The artifact changed size after the manifest was built; never
            // send a mismatched body.
            throw AgentDataIngestClientError.framingFailed
        }

        Darwin.close(bodyDescriptor)
        bodyOpen = false
        return bodyURL
    }

    // MARK: - Upload

    /// Uploads one artifact with the frozen retry posture. Returns the
    /// health-free outcome; never throws for per-artifact protocol results.
    func upload(
        manifest: AgentDataIngestManifest,
        artifactFileURL: URL,
        destination: AgentDataGatewayDestinationSnapshot,
        stagingDirectory: URL
    ) async -> AgentDataIngestUploadOutcome {
        var lastRetryable: AgentDataIngestClientError?
        for attempt in 1...maximumAttempts {
            do {
                let stagedBody = try Self.stageFramedBody(
                    manifest: manifest,
                    artifactFileURL: artifactFileURL,
                    in: stagingDirectory
                )
                defer { try? FileManager.default.removeItem(at: stagedBody) }

                let outcome = try await attemptUpload(
                    manifest: manifest,
                    stagedBodyURL: stagedBody,
                    destination: destination
                )
                switch outcome {
                case .accepted:
                    return AgentDataIngestUploadOutcome(
                        result: .accepted,
                        attempts: attempt,
                        byteCount: manifest.byteCount
                    )
                case .rejected(let code):
                    return AgentDataIngestUploadOutcome(
                        result: .rejected(code),
                        attempts: attempt,
                        byteCount: manifest.byteCount
                    )
                case .retryable(let error):
                    lastRetryable = error
                    if attempt < maximumAttempts {
                        try await sleep(retryDelay(afterAttempt: attempt))
                    }
                }
            } catch is CancellationError {
                return AgentDataIngestUploadOutcome(
                    result: .uploadFailed(description: "Upload cancelled"),
                    attempts: attempt,
                    byteCount: manifest.byteCount
                )
            } catch let error as AgentDataIngestClientError {
                lastRetryable = error
                guard error.isRetryable, attempt < maximumAttempts else { break }
                try? await sleep(retryDelay(afterAttempt: attempt))
            } catch {
                lastRetryable = .transportFailed(description: "The Agent Data gateway upload failed.")
                if attempt < maximumAttempts {
                    try? await sleep(retryDelay(afterAttempt: attempt))
                }
            }
        }
        return AgentDataIngestUploadOutcome(
            result: .uploadFailed(
                description: lastRetryable?.errorDescription
                    ?? "The Agent Data gateway upload failed."
            ),
            attempts: maximumAttempts,
            byteCount: manifest.byteCount
        )
    }

    private func retryDelay(afterAttempt attempt: Int) -> TimeInterval {
        initialRetryDelay * pow(2, Double(attempt - 1))
    }

    /// One request/response exchange: transport, status, receipt parsing.
    private func attemptUpload(
        manifest: AgentDataIngestManifest,
        stagedBodyURL: URL,
        destination: AgentDataGatewayDestinationSnapshot
    ) async throws -> AttemptOutcome {
        var request = URLRequest(url: destination.ingestURL)
        request.httpMethod = "POST"
        request.setValue(
            AgentDataGatewayDestinationSnapshot.ingestMediaType,
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("Health.md iOS Agent Data Gateway Export", forHTTPHeaderField: "User-Agent")
        // An exact Content-Length is derived from the staged body file size;
        // never declared separately from the bytes actually sent.
        request.setValue("close", forHTTPHeaderField: "Connection")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await responseLoader.upload(
                for: request,
                fromFile: stagedBodyURL,
                maximumBytes: maximumResponseBytes
            )
        } catch let error as BoundedURLSessionDataLoaderError {
            switch error {
            case .responseTooLarge(let statusCode, _, _):
                throw AgentDataIngestClientError.invalidReceipt(statusCode: statusCode)
            }
        } catch let urlError as URLError {
            // Transport failure (connection refused/reset/timeout, DNS, TLS):
            // the retryable class. URLError localized descriptions are
            // health-free.
            throw AgentDataIngestClientError.transportFailed(
                description: urlError.localizedDescription
            )
        } catch {
            throw AgentDataIngestClientError.transportFailed(
                description: "The Agent Data gateway upload could not be sent."
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AgentDataIngestClientError.invalidReceipt(statusCode: nil)
        }
        // Rejections are protocol outcomes carried by HTTP success responses.
        // A non-2xx status is a transport-level rejection: health-free and
        // retryable.
        guard (200..<300).contains(httpResponse.statusCode) else {
            return .retryable(.transportRejected(statusCode: httpResponse.statusCode))
        }
        do {
            let receipt = try AgentDataIngestReceipt(decoding: data)
            switch receipt.outcome {
            case .accepted:
                return .accepted(receipt)
            case .rejected(let code) where code.isFixAndReupload:
                return .rejected(code)
            case .rejected:
                return .retryable(.gatewayTransient)
            }
        } catch {
            throw AgentDataIngestClientError.invalidReceipt(statusCode: httpResponse.statusCode)
        }
    }
}
