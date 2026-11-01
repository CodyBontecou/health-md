import Combine
import Foundation
import os

/// Owns the persisted ledger. Coverage is presentation data, so every failure here is
/// logged and contained. Recording must never affect the export that triggered it.
final class CoverageLedgerStore: ObservableObject {
    /// `nonisolated deinit`: see `ExportProfileStore` for the iOS 26.2 runtime reason.
    nonisolated deinit {}

    static let appGroupIdentifier = "group.com.codybontecou.obsidianhealth"
    static let maximumFileBytes = 32 * 1_024 * 1_024

    /// App-hosted tests and UI tests stay in memory, so they cannot touch a real ledger.
    static let shared = CoverageLedgerStore(
        fileURL: TestMode.suppressesRuntimeServices ? nil : defaultFileURL()
    )

    @Published private(set) var ledger: CoverageLedger

    private let fileURL: URL?
    private let now: () -> Date
    private let calendar: () -> Calendar
    /// True when the file came from a newer build. Its data is left in place, unmodified.
    private let isReadOnly: Bool
    private let writeQueue = DispatchQueue(label: "md.health.coverage-ledger", qos: .utility)
    private let logger = Logger(subsystem: "com.codybontecou.healthmd", category: "CoverageLedger")

    init(
        fileURL: URL?,
        now: @escaping () -> Date = { Date() },
        calendar: @escaping () -> Calendar = { Calendar.current }
    ) {
        self.fileURL = fileURL
        self.now = now
        self.calendar = calendar

        let loaded = fileURL.flatMap(Self.load)
        if let loaded, loaded.version > CoverageLedger.currentVersion {
            ledger = CoverageLedger(startedAt: now())
            isReadOnly = true
        } else {
            ledger = loaded ?? CoverageLedger(startedAt: now())
            isReadOnly = false
        }
    }

    // MARK: - Recording

    func record(
        entry: ExportHistoryEntry,
        explicitProfileID: UUID?,
        completedDates: [Date]?,
        priorHistory: [ExportHistoryEntry]
    ) {
        guard !isReadOnly else { return }
        let previous = ledger
        let profileStore = ExportProfileStore()
        let currentCalendar = calendar()
        ledger.seedIfNeeded(
            history: priorHistory,
            profiles: profileStore.profiles,
            scheduleEntries: ScheduledExportEntryStore().allEntries(),
            now: now(),
            calendar: currentCalendar
        )
        if let profileID = CoverageAttribution.profileID(
            explicitID: explicitProfileID,
            entry: entry,
            profiles: profileStore.profiles,
            activeProfileID: profileStore.activeProfileID
        ) {
            ledger.apply(
                CoverageRun(entry: entry, completedDates: completedDates),
                profileID: profileID,
                now: now(),
                calendar: currentCalendar
            )
        }
        if ledger != previous { persist() }
    }

    func recordScheduleTransition(profileID: UUID, isEnabled: Bool) {
        guard !isReadOnly else { return }
        ledger.recordScheduleTransition(profileID: profileID, isEnabled: isEnabled, at: now())
        persist()
    }

    /// Clearing export history also clears what it recorded here. Recording restarts
    /// now, so the cleared dates show as no history rather than as gaps.
    func clear() {
        guard !isReadOnly else { return }
        ledger = CoverageLedger(startedAt: now())
        ledger.didSeedFromHistory = true
        persist()
    }

    #if DEBUG
    /// UI-test screenshots only. The store is in memory under UI testing, so nothing persists.
    func seedScreenshotCoverage(profileIDs: [UUID]) {
        guard TestMode.isUITesting else { return }
        let profileIDs = profileIDs.isEmpty ? ExportProfileStore().profiles.map(\.id) : profileIDs
        guard !profileIDs.isEmpty else { return }
        let calendar = calendar()
        let today = calendar.startOfDay(for: now())
        guard let start = calendar.date(byAdding: .day, value: -40, to: today) else { return }
        var seeded = CoverageLedger(startedAt: start)
        seeded.didSeedFromHistory = true
        for offset in 1...40 where offset != 6 && offset != 7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            var record = CoverageDateRecord(updatedAt: date)
            record.settledOutcome = offset == 3 ? .partial : .complete
            record.filesWritten = 1
            record.lastWriter = .schedule
            for profileID in profileIDs {
                seeded.profiles[profileID, default: [:]][CoverageDateKey.key(for: date, calendar: calendar)] = record
            }
        }
        ledger = seeded
    }
    #endif

    /// Waits for queued writes.
    func flush() {
        writeQueue.sync {}
    }

    // MARK: - Persistence

    private func persist() {
        guard let fileURL else { return }
        let data: Data
        do {
            data = try JSONEncoder().encode(ledger)
        } catch {
            logger.error("Coverage ledger encode failed")
            return
        }
        guard data.count <= Self.maximumFileBytes else {
            logger.error("Coverage ledger exceeded its size bound")
            return
        }
        // A local copy keeps the closure free of main-actor state.
        let log = logger
        writeQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                #if os(iOS)
                // Background exports run after first unlock, while the device is locked.
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: fileURL.path
                )
                #endif
            } catch {
                log.error("Coverage ledger write failed")
            }
        }
    }

    private static func load(from url: URL) -> CoverageLedger? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              size <= maximumFileBytes,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(CoverageLedger.self, from: data)
    }

    private static func defaultFileURL() -> URL? {
        // The macOS app has no app-group entitlement, and asking for one can show a
        // system prompt. Only iOS widgets need the shared container.
        #if os(iOS)
        let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
        #else
        let groupURL: URL? = nil
        #endif
        let base = groupURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?
            .appendingPathComponent("Coverage", isDirectory: true)
            .appendingPathComponent("coverage-ledger.json")
    }
}
