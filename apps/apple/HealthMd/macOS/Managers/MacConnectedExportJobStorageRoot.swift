#if os(macOS)
import Foundation

/// Resolves the connected-export journal root once; a live coordinator must not
/// switch roots after a job has been admitted.
final class MacConnectedExportJobStorageRoot {
    private(set) var url: URL?
    private let resolver: () throws -> URL

    init(resolver: @escaping () throws -> URL) {
        self.resolver = resolver
    }

    convenience init(fileManager: FileManager = .default) {
        self.init {
            // Production jobs must survive temporary-directory purge and a
            // restart. Resolution failure is unavailable, not a storage choice.
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return support
                .appendingPathComponent("Health.md", isDirectory: true)
                .appendingPathComponent("ConnectedExportJobs", isDirectory: true)
        }
    }

    func resolve() throws -> URL {
        if let url { return url }
        let resolved = try resolver()
        url = resolved
        return resolved
    }
}
#endif
