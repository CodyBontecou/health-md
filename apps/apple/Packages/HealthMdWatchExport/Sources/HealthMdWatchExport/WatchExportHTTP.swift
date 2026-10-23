import Foundation

final class WatchExportHTTP: NSObject, WatchExportTransport, URLSessionTaskDelegate, @unchecked Sendable {
    static let acknowledgementLimit = 8192
    private let protocolClasses: [AnyClass]?

    init(protocolClasses: [AnyClass]? = nil) {
        self.protocolClasses = protocolClasses
        super.init()
    }

    static func request(_ pending: WatchPendingUpload, destination: WatchExportDestination) throws -> URLRequest {
        let destination = try destination.validated()
        var request = URLRequest(url: destination.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = pending.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(destination.bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(pending.id.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return request
    }

    func upload(_ pending: WatchPendingUpload, to destination: WatchExportDestination) async throws {
        let request = try Self.request(pending, destination: destination)
        let configuration = URLSessionConfiguration.ephemeral
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.url == destination.endpoint,
                  http.statusCode == 200 || http.statusCode == 201 else { throw WatchExportError.rejected }
            guard http.mimeType?.lowercased() == "application/json" else { throw WatchExportError.invalidAcknowledgement }
            var body = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard body.count < Self.acknowledgementLimit else { throw WatchExportError.invalidAcknowledgement }
                body.append(byte)
            }
            try Self.validateAcknowledgement(body, statusCode: http.statusCode, uploadID: pending.id)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as WatchExportError {
            throw error
        } catch {
            // Never propagate URLs, credentials, response bodies, or raw system errors to UI/logs.
            try Task.checkCancellation()
            throw WatchExportError.transport
        }
    }

    static func validateAcknowledgement(_ body: Data, statusCode: Int, uploadID: UUID) throws {
        guard statusCode == 200 || statusCode == 201 else { throw WatchExportError.rejected }
        struct Acknowledgement: Decodable {
            let schema: String
            let schemaVersion: Int
            let uploadID: UUID
            let accepted: Bool
            enum CodingKeys: String, CodingKey {
                case schema, schemaVersion = "schema_version", uploadID = "upload_id", accepted
            }
        }
        guard body.count <= acknowledgementLimit,
              let ack = try? JSONDecoder().decode(Acknowledgement.self, from: body),
              ack.schema == "healthmd.watch_ack", ack.schemaVersion == 1,
              ack.uploadID == uploadID, ack.accepted else { throw WatchExportError.invalidAcknowledgement }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Refuse even same-origin redirects: health data and credentials have exactly one destination.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
