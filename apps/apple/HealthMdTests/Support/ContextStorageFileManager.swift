#if os(macOS)
import Foundation

/// Synthetic system-directory resolution, with separate stable and purgeable
/// locations. All actual coordinator journal I/O still uses the real filesystem.
final class ContextStorageFileManager: FileManager, @unchecked Sendable {
    var supportURL: URL?
    let temporaryURL: URL
    private(set) var resolutionAttempts = 0

    init(temporaryURL: URL, supportURL: URL? = nil) {
        self.temporaryURL = temporaryURL
        self.supportURL = supportURL
        super.init()
    }

    override var temporaryDirectory: URL { temporaryURL }

    override func url(for directory: FileManager.SearchPathDirectory,
                      in domain: FileManager.SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        precondition(directory == .applicationSupportDirectory && domain == .userDomainMask)
        resolutionAttempts += 1
        guard let supportURL else { throw CocoaError(.fileReadNoPermission) }
        return supportURL
    }
}
#endif
