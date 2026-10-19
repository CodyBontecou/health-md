import Foundation

/// Private storage identities; these never enter a journal or protocol payload.
nonisolated enum AppleDirectJobNamespace: CaseIterable, Equatable, Sendable {
    case historical
    case wakeDate
}

nonisolated enum AppleDirectJobKind: Equatable, Sendable {
    case raw
    case files
}

@MainActor
struct AppleDirectJobStorage {
    let support: URL
    let fileManager: FileManager

    func namespace(for snapshot: ExportSettingsSnapshot) throws -> AppleDirectJobNamespace {
        let context = snapshot.sleepCaptureContext
        if context?.sleepDayAttribution == .morningEnds
            || context?.exportProfileID == "apple-v11" || snapshot.appleExportEnginePin?.isWakeDate == true {
            let validated = try snapshot.validatedSleepCaptureContext()
            guard validated.sleepDayAttribution == .morningEnds else { throw POSIXError(.EAGAIN) }
            return .wakeDate
        }
        return .historical
    }

    func root(_ namespace: AppleDirectJobNamespace) -> URL {
        support.appendingPathComponent("Health.md", isDirectory: true)
            .appendingPathComponent(namespace == .historical ? "DirectCLIOutbound" : "DirectCLIOutboundSleepAttribution", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
    }

    func lock(_ namespace: AppleDirectJobNamespace) -> URL {
        root(namespace).deletingLastPathComponent().appendingPathComponent(".v1.journal.lock")
    }

    func job(_ jobID: UUID, namespace: AppleDirectJobNamespace, kind: AppleDirectJobKind) -> URL {
        let directory = root(namespace).appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
        return kind == .files ? directory.appendingPathComponent("files", isDirectory: true) : directory
    }

    /// Includes partial/unknown job directories. Ambiguity is never fresh work.
    func existingNamespace(jobID: UUID) throws -> AppleDirectJobNamespace? {
        var result: AppleDirectJobNamespace?
        for namespace in AppleDirectJobNamespace.allCases {
            if try AppleExportJournalRecovery.hasExistingJobDirectory(
                at: job(jobID, namespace: namespace, kind: .raw), fileManager: fileManager) {
                guard result == nil else { throw AppleExportJournalRecovery.RecoveryError.unreadableJournal }
                result = namespace
            }
        }
        return result
    }

    func existingDirectory(jobID: UUID, kind: AppleDirectJobKind) throws -> (AppleDirectJobNamespace, URL)? {
        guard let namespace = try existingNamespace(jobID: jobID) else { return nil }
        let directory = job(jobID, namespace: namespace, kind: kind)
        guard try AppleExportJournalRecovery.hasExistingJobDirectory(at: directory, fileManager: fileManager) else { return nil }
        return (namespace, directory)
    }

    /// Serializes fresh admission across namespaces. It is outside historical purge roots.
    func beginAdmission() throws -> AtomicFileWriter.PublicationLease {
        let directory = support.appendingPathComponent("Health.md", isDirectory: true)
        try createProtectedDirectory(directory)
        return try AtomicFileWriter.beginPublicationTransaction(at: directory.appendingPathComponent(".direct-job-namespaces.lock"))
    }

    func prepareDirectory(jobID: UUID, kind: AppleDirectJobKind, snapshot: ExportSettingsSnapshot) throws -> (AppleDirectJobNamespace, URL) {
        let selected = try namespace(for: snapshot)
        if let existing = try existingNamespace(jobID: jobID), existing != selected { throw POSIXError(.EAGAIN) }
        let directory = job(jobID, namespace: selected, kind: kind)
        try createProtectedDirectory(root(selected).deletingLastPathComponent())
        try createProtectedDirectory(root(selected))
        try createProtectedDirectory(job(jobID, namespace: selected, kind: .raw))
        if kind == .files { try createProtectedDirectory(directory) }
        return (selected, directory)
    }

    /// Continuations retain their accepted location; discovery cannot redirect an old receipt.
    func boundDirectory(jobID: UUID, kind: AppleDirectJobKind, snapshot: ExportSettingsSnapshot,
                        checkpoint: AppleExportJournalCheckpoint) throws -> (AppleDirectJobNamespace, URL) {
        let selected = try namespace(for: snapshot)
        guard try existingNamespace(jobID: jobID) == selected,
              let saved = checkpoint.journalURL, let savedLock = checkpoint.publicationLockURL else { throw POSIXError(.EAGAIN) }
        let directory = job(jobID, namespace: selected, kind: kind)
        guard saved.standardizedFileURL.resolvingSymlinksInPath()
                == directory.appendingPathComponent("journal.json").standardizedFileURL.resolvingSymlinksInPath(),
              savedLock.standardizedFileURL.resolvingSymlinksInPath()
                == lock(selected).standardizedFileURL.resolvingSymlinksInPath() else { throw POSIXError(.EAGAIN) }
        try checkpoint.validateGeneration(fileManager: fileManager)
        return (selected, directory)
    }

    private func createProtectedDirectory(_ directory: URL) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = directory
        try? mutable.setResourceValues(values)
    }
}
