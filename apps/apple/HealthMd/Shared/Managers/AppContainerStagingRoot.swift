import Foundation

/// Resolves OS path aliases before checking the private roots used for temporary exports.
nonisolated enum AppContainerStagingRoot {
    static func validated(_ candidate: URL, allowedRoots: [URL]) -> URL? {
        guard candidate.isFileURL, let resolved = resolvingExistingAncestor(of: candidate) else { return nil }
        let components = resolved.pathComponents
        let isContained = allowedRoots.filter(\.isFileURL).compactMap(resolvingExistingAncestor).contains { root in
            components.starts(with: root.pathComponents)
        }
        return isContained ? resolved : nil
    }

    private static func resolvingExistingAncestor(of url: URL) -> URL? {
        let fileManager = FileManager.default
        var ancestor = url.standardizedFileURL
        var missingComponents: [String] = []
        while true {
            do {
                _ = try fileManager.attributesOfItem(atPath: ancestor.path)
                // Metadata exists for a dangling symlink too; never treat it as a
                // new directory component whose eventual target is unknown.
                guard fileManager.fileExists(atPath: ancestor.path) else { return nil }
                let resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL
                return missingComponents.reversed().reduce(resolved) {
                    $0.appendingPathComponent($1, isDirectory: true)
                }.standardizedFileURL
            } catch {
                let cocoaError = error as NSError
                guard cocoaError.domain == NSCocoaErrorDomain,
                      cocoaError.code == NSFileNoSuchFileError || cocoaError.code == NSFileReadNoSuchFileError else {
                    return nil
                }
                let parent = ancestor.deletingLastPathComponent()
                guard parent.path != ancestor.path else { return nil }
                missingComponents.append(ancestor.lastPathComponent)
                ancestor = parent
            }
        }
    }
}
