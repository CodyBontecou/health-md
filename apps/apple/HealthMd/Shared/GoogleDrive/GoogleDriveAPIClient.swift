import Foundation

nonisolated protocol GoogleDriveAPIClientProtocol: Sendable {
    func about(accessToken: String) async throws -> String
    func metadata(id: String, resourceKey: String?, accessToken: String) async throws -> GoogleDriveFileMetadata
    func validateFolder(_ destination: GoogleDriveDestination, accessToken: String) async throws -> GoogleDriveFileMetadata
    func generateIDs(count: Int, accessToken: String) async throws -> [String]
    func createFolder(id: String, name: String, parentID: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> GoogleDriveFileMetadata
    func findManagedObjects(parentID: String, name: String, pathHash: String, resourceKeys: [String: String], accessToken: String) async throws -> [GoogleDriveFileMetadata]
    func startResumableCreate(id: String, name: String, parentID: String, mediaType: String, byteCount: UInt64, sha256: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> URL
    func startResumableUpdate(id: String, mediaType: String, byteCount: UInt64, sha256: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> URL
    func upload(sessionURL: URL, data: Data, offset: UInt64, totalByteCount: UInt64, accessToken: String) async throws -> GoogleDriveUploadResponse
    func uploadStatus(sessionURL: URL, totalByteCount: UInt64, accessToken: String) async throws -> GoogleDriveUploadResponse
    func download(id: String, resourceKey: String?, accessToken: String) async throws -> Data
}

nonisolated enum GoogleDriveUploadResponse: Equatable, Sendable {
    case incomplete(acknowledgedByteCount: UInt64)
    case completed(GoogleDriveFileMetadata)
}

nonisolated struct GoogleDriveAPIClient: GoogleDriveAPIClientProtocol, Sendable {
    private struct AboutResponse: Decodable { let user: User; struct User: Decodable { let permissionId: String } }
    private struct GenerateResponse: Decodable { let ids: [String] }
    private struct ListResponse: Decodable {
        let files: [MetadataResponse]
        let nextPageToken: String?
    }
    private struct MetadataResponse: Decodable {
        let id: String
        let name: String
        let mimeType: String
        let parents: [String]?
        let driveId: String?
        let resourceKey: String?
        let version: String?
        let size: String?
        let md5Checksum: String?
        let sha1Checksum: String?
        let sha256Checksum: String?
        let trashed: Bool?
        let capabilities: Capabilities?
        let appProperties: [String: String]?
        struct Capabilities: Decodable { let canAddChildren: Bool? }

        var value: GoogleDriveFileMetadata {
            GoogleDriveFileMetadata(
                id: id,
                name: name,
                mimeType: mimeType,
                parents: parents ?? [],
                driveID: driveId,
                resourceKey: resourceKey,
                version: version,
                size: size.flatMap(UInt64.init),
                md5Checksum: md5Checksum,
                sha1Checksum: sha1Checksum,
                sha256Checksum: sha256Checksum,
                trashed: trashed ?? false,
                canAddChildren: capabilities?.canAddChildren,
                appProperties: appProperties
            )
        }
    }

    private static let metadataFields = "id,name,mimeType,parents,driveId,resourceKey,version,size,md5Checksum,sha1Checksum,sha256Checksum,trashed,capabilities(canAddChildren),appProperties"
    private let transport: any GoogleDriveHTTPTransport

    init(transport: any GoogleDriveHTTPTransport = SystemGoogleDriveHTTPTransport()) {
        self.transport = transport
    }

    func about(accessToken: String) async throws -> String {
        let url = Self.url(path: "/drive/v3/about", query: [URLQueryItem(name: "fields", value: "user(permissionId)")])
        let (data, _) = try await send(Self.request(url: url, token: accessToken))
        return try decode(AboutResponse.self, from: data).user.permissionId
    }

    func metadata(id: String, resourceKey: String?, accessToken: String) async throws -> GoogleDriveFileMetadata {
        let url = Self.url(
            path: "/drive/v3/files/\(Self.pathComponent(id))",
            query: [
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "fields", value: Self.metadataFields)
            ]
        )
        var request = Self.request(url: url, token: accessToken)
        Self.attachResourceKeys(resourceKey.map { [id: $0] } ?? [:], to: &request)
        let (data, _) = try await send(request)
        return try decode(MetadataResponse.self, from: data).value
    }

    func validateFolder(_ destination: GoogleDriveDestination, accessToken: String) async throws -> GoogleDriveFileMetadata {
        let permissionID = try await about(accessToken: accessToken)
        guard permissionID == destination.accountPermissionID else {
            throw GoogleDriveError(.accountMismatch)
        }
        let folder = try await metadata(
            id: destination.folderID,
            resourceKey: destination.resourceKey,
            accessToken: accessToken
        )
        guard !folder.trashed,
              folder.mimeType == GoogleDriveFileMetadata.folderMIMEType,
              folder.canAddChildren == true,
              destination.sharedDriveID == nil || folder.driveID == destination.sharedDriveID else {
            throw GoogleDriveError(.folderUnavailable)
        }
        return folder
    }

    func generateIDs(count: Int, accessToken: String) async throws -> [String] {
        let count = min(max(count, 1), 1_000)
        let url = Self.url(path: "/drive/v3/files/generateIds", query: [
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "space", value: "drive"),
            URLQueryItem(name: "type", value: "files")
        ])
        let (data, _) = try await send(Self.request(url: url, token: accessToken))
        let ids = try decode(GenerateResponse.self, from: data).ids
        guard ids.count == count, ids.allSatisfy({ !$0.isEmpty }) else {
            throw GoogleDriveError(.ambiguousCommit, isRetryable: true)
        }
        return ids
    }

    func createFolder(
        id: String,
        name: String,
        parentID: String,
        pathHash: String,
        operationID: UUID,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> GoogleDriveFileMetadata {
        let url = Self.url(path: "/drive/v3/files", query: [
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "fields", value: Self.metadataFields)
        ])
        let body: [String: Any] = [
            "id": id,
            "name": name,
            "mimeType": GoogleDriveFileMetadata.folderMIMEType,
            "parents": [parentID],
            "appProperties": Self.appProperties(pathHash: pathHash, sha256: nil, operationID: operationID)
        ]
        var request = Self.request(url: url, token: accessToken, method: "POST")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        Self.attachResourceKeys(resourceKeys, to: &request)
        let (data, _) = try await send(request)
        return try decode(MetadataResponse.self, from: data).value
    }

    func findManagedObjects(
        parentID: String,
        name: String,
        pathHash: String,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> [GoogleDriveFileMetadata] {
        let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
        let escapedParent = parentID.replacingOccurrences(of: "'", with: "\\'")
        // Search every same-name object visible under drive.file. The runner accepts only exact
        // Health.md ownership/path markers and fails on accessible unowned collisions.
        _ = pathHash
        let query = "'\(escapedParent)' in parents and name = '\(escapedName)' and trashed = false"
        var output: [GoogleDriveFileMetadata] = []
        var pageToken: String?
        repeat {
            var queryItems = [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "spaces", value: "drive"),
                URLQueryItem(name: "corpora", value: "allDrives"),
                URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
                URLQueryItem(name: "supportsAllDrives", value: "true"),
                URLQueryItem(name: "pageSize", value: "100"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(\(Self.metadataFields))")
            ]
            if let pageToken { queryItems.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let url = Self.url(path: "/drive/v3/files", query: queryItems)
            var request = Self.request(url: url, token: accessToken)
            Self.attachResourceKeys(resourceKeys, to: &request)
            let (data, _) = try await send(request)
            let page = try decode(ListResponse.self, from: data)
            output.append(contentsOf: page.files.map(\.value))
            guard output.count <= 1_000 else { throw GoogleDriveError(.remoteConflict) }
            pageToken = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
        } while pageToken != nil
        return output
    }

    func startResumableCreate(
        id: String,
        name: String,
        parentID: String,
        mediaType: String,
        byteCount: UInt64,
        sha256: String,
        pathHash: String,
        operationID: UUID,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> URL {
        let metadata: [String: Any] = [
            "id": id,
            "name": name,
            "parents": [parentID],
            "mimeType": mediaType,
            "appProperties": Self.appProperties(pathHash: pathHash, sha256: sha256, operationID: operationID)
        ]
        return try await startResumable(
            path: "/upload/drive/v3/files",
            method: "POST",
            metadata: metadata,
            mediaType: mediaType,
            byteCount: byteCount,
            resourceKeys: resourceKeys,
            accessToken: accessToken
        )
    }

    func startResumableUpdate(
        id: String,
        mediaType: String,
        byteCount: UInt64,
        sha256: String,
        pathHash: String,
        operationID: UUID,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> URL {
        try await startResumable(
            path: "/upload/drive/v3/files/\(Self.pathComponent(id))",
            method: "PATCH",
            metadata: ["appProperties": Self.appProperties(pathHash: pathHash, sha256: sha256, operationID: operationID)],
            mediaType: mediaType,
            byteCount: byteCount,
            resourceKeys: resourceKeys,
            accessToken: accessToken
        )
    }

    func upload(
        sessionURL: URL,
        data: Data,
        offset: UInt64,
        totalByteCount: UInt64,
        accessToken: String
    ) async throws -> GoogleDriveUploadResponse {
        guard !data.isEmpty,
              UInt64(data.count) <= totalByteCount,
              offset <= totalByteCount - UInt64(data.count) else {
            throw GoogleDriveError(.ambiguousCommit)
        }
        var request = Self.request(url: sessionURL, token: accessToken, method: "PUT")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue(
            "bytes \(offset)-\(offset + UInt64(data.count) - 1)/\(totalByteCount)",
            forHTTPHeaderField: "Content-Range"
        )
        request.httpBody = data
        return try await sendUpload(request)
    }

    func uploadStatus(
        sessionURL: URL,
        totalByteCount: UInt64,
        accessToken: String
    ) async throws -> GoogleDriveUploadResponse {
        var request = Self.request(url: sessionURL, token: accessToken, method: "PUT")
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        request.setValue("bytes */\(totalByteCount)", forHTTPHeaderField: "Content-Range")
        return try await sendUpload(request)
    }

    func download(id: String, resourceKey: String?, accessToken: String) async throws -> Data {
        let url = Self.url(path: "/drive/v3/files/\(Self.pathComponent(id))", query: [
            URLQueryItem(name: "alt", value: "media"),
            URLQueryItem(name: "supportsAllDrives", value: "true")
        ])
        var request = Self.request(url: url, token: accessToken)
        Self.attachResourceKeys(resourceKey.map { [id: $0] } ?? [:], to: &request)
        return try await send(request).0
    }

    private func startResumable(
        path: String,
        method: String,
        metadata: [String: Any],
        mediaType: String,
        byteCount: UInt64,
        resourceKeys: [String: String],
        accessToken: String
    ) async throws -> URL {
        let url = Self.url(path: path, query: [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "fields", value: Self.metadataFields)
        ])
        var request = Self.request(url: url, token: accessToken, method: method)
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue(mediaType, forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue(String(byteCount), forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        Self.attachResourceKeys(resourceKeys, to: &request)
        let (_, response) = try await send(request)
        guard let location = response.value(forHTTPHeaderField: "Location"),
              let sessionURL = URL(string: location),
              sessionURL.scheme?.lowercased() == "https",
              let host = sessionURL.host?.lowercased(),
              host == "googleapis.com" || host.hasSuffix(".googleapis.com") else {
            throw GoogleDriveError(.ambiguousCommit, isRetryable: true)
        }
        return sessionURL
    }

    private func sendUpload(_ request: URLRequest) async throws -> GoogleDriveUploadResponse {
        let (data, response) = try await transport.data(for: request)
        if response.statusCode == 308 {
            let acknowledged = Self.acknowledgedByteCount(response.value(forHTTPHeaderField: "Range"))
            return .incomplete(acknowledgedByteCount: acknowledged)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleDriveHTTPErrorMapper.error(statusCode: response.statusCode, responseData: data)
        }
        return .completed(try decode(MetadataResponse.self, from: data).value)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw GoogleDriveHTTPErrorMapper.error(statusCode: response.statusCode, responseData: data)
        }
        return (data, response)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw GoogleDriveError(.ambiguousCommit, isRetryable: true) }
    }

    private static func url(path: String, query: [URLQueryItem]) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = path
        components.queryItems = query
        return components.url!
    }

    private static func request(url: URL, token: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func attachResourceKeys(_ values: [String: String], to request: inout URLRequest) {
        let header = values.keys.sorted().compactMap { id -> String? in
            guard let key = values[id], !id.isEmpty, !key.isEmpty else { return nil }
            return "\(id)/\(key)"
        }.joined(separator: ",")
        if !header.isEmpty {
            request.setValue(header, forHTTPHeaderField: "X-Goog-Drive-Resource-Keys")
        }
    }

    private static func pathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }

    private static func appProperties(pathHash: String?, sha256: String?, operationID: UUID) -> [String: String] {
        var result = [
            "healthmd_owner": "healthmd",
            "healthmd_version": "1",
            "healthmd_operation_id": operationID.uuidString.lowercased()
        ]
        if let pathHash { result["healthmd_path_hash"] = pathHash }
        if let sha256 { result["healthmd_sha256"] = sha256 }
        return result
    }

    private static func acknowledgedByteCount(_ range: String?) -> UInt64 {
        guard let range,
              let last = range.split(separator: "-").last,
              let lastByte = UInt64(last) else { return 0 }
        return lastByte + 1
    }
}
