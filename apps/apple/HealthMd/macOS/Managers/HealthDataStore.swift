#if os(macOS)
import Foundation
import Combine
import os.log

/// Local JSON-based storage for health data received from iPhone via sync.
/// Replaces HealthKit queries on macOS where HKHealthStore is unavailable.
@MainActor
final class HealthDataStore: ObservableObject {

    // MARK: - Published State

    @Published var lastSyncDate: Date?
    @Published var lastSyncDevice: String?
    @Published var availableDates: [Date] = []
    @Published var recordCount: Int = 0

    // Sync progress tracking (for all-time syncs)
    @Published var syncProgress: SyncProgressInfo?
    @Published var isSyncingAllData: Bool = false

    // MARK: - Private

    private let logger = Logger(subsystem: "com.codybontecou.obsidianhealth", category: "HealthDataStore")
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dateFormatter: DateFormatter

    /// Root directory: ~/Library/Application Support/Health.md/
    private let storeDirectory: URL

    /// Metadata file path
    private var metadataURL: URL {
        storeDirectory.appendingPathComponent("sync-metadata.json")
    }

    // MARK: - Init

    init(storeDirectory: URL? = nil) {
        if let storeDirectory {
            self.storeDirectory = storeDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storeDirectory = appSupport.appendingPathComponent("Health.md", isDirectory: true)
        }

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        self.dateFormatter = df

        createStoreDirectoryIfNeeded()
        loadMetadata()
        refreshAvailableDates()
    }

    // MARK: - Public API

    /// Store one or more health data records (one per date).
    func store(_ records: [HealthData], fromDevice deviceName: String? = nil) {
        for record in records {
            let dateString = dateFormatter.string(from: record.date)
            let fileURL = storeDirectory.appendingPathComponent("\(dateString).json")

            do {
                let data = try encoder.encode(record)
                try data.write(to: fileURL, options: .atomic)
                logger.info("Stored health data for \(dateString)")
            } catch {
                logger.error("Failed to store health data for \(dateString): \(error.localizedDescription)")
            }
        }

        // Update metadata
        var metadata = loadMetadataFromDisk()
        metadata.lastSyncDate = Date()
        metadata.sourceDeviceName = deviceName ?? metadata.sourceDeviceName
        metadata.recordCount = countStoredFiles()
        metadata.syncedDates = listStoredDates()
        saveMetadata(metadata)

        // Refresh published state
        loadMetadata()
        refreshAvailableDates()
    }

    /// Fetch stored health data for a specific date.
    func fetchHealthData(for date: Date) -> HealthData? {
        let dateString = dateFormatter.string(from: date)
        let fileURL = storeDirectory.appendingPathComponent("\(dateString).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let healthData = try decoder.decode(HealthData.self, from: data)
            return healthData
        } catch {
            logger.error("Failed to read health data for \(dateString): \(error.localizedDescription)")
            return nil
        }
    }

    /// Check if data exists for a specific date.
    func hasData(for date: Date) -> Bool {
        let dateString = dateFormatter.string(from: date)
        let fileURL = storeDirectory.appendingPathComponent("\(dateString).json")
        return fileManager.fileExists(atPath: fileURL.path)
    }

    /// Returns the earliest and latest stored dates, or nil if no data.
    func dateRange() -> (earliest: Date, latest: Date)? {
        let dates = listStoredDates()
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        return (earliest, latest)
    }

    /// Delete all stored health data and metadata.
    func deleteAll() {
        do {
            let files = try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
            for file in files {
                try fileManager.removeItem(at: file)
            }
            logger.info("Deleted all stored health data")
        } catch {
            logger.error("Failed to delete stored data: \(error.localizedDescription)")
        }

        lastSyncDate = nil
        lastSyncDevice = nil
        availableDates = []
        recordCount = 0
    }

    /// Update sync progress from an incoming progress message.
    func updateSyncProgress(_ progress: SyncProgressInfo) {
        self.syncProgress = progress
        if progress.isComplete {
            self.isSyncingAllData = false
            // Clear progress after a short delay so the UI can show the completion state
            Task {
                try? await Task.sleep(for: .seconds(3))
                self.syncProgress = nil
            }
        } else {
            self.isSyncingAllData = true
        }
    }

    // MARK: - Private Helpers

    private func createStoreDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: storeDirectory.path) {
            do {
                try fileManager.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
                logger.info("Created store directory: \(self.storeDirectory.path)")
            } catch {
                logger.error("Failed to create store directory: \(error.localizedDescription)")
            }
        }
    }

    private func loadMetadata() {
        let metadata = loadMetadataFromDisk()
        self.lastSyncDate = metadata.lastSyncDate
        self.lastSyncDevice = metadata.sourceDeviceName
        self.recordCount = metadata.recordCount
    }

    private func loadMetadataFromDisk() -> SyncMetadata {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return SyncMetadata()
        }

        do {
            let data = try Data(contentsOf: metadataURL)
            return try decoder.decode(SyncMetadata.self, from: data)
        } catch {
            logger.error("Failed to load sync metadata: \(error.localizedDescription)")
            return SyncMetadata()
        }
    }

    private func saveMetadata(_ metadata: SyncMetadata) {
        do {
            let data = try encoder.encode(metadata)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            logger.error("Failed to save sync metadata: \(error.localizedDescription)")
        }
    }

    private func countStoredFiles() -> Int {
        return listStoredDates().count
    }

    private func listStoredDates() -> [Date] {
        do {
            let files = try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
            return files.compactMap { url -> Date? in
                let name = url.deletingPathExtension().lastPathComponent
                guard url.pathExtension == "json", name != "sync-metadata" else { return nil }
                return dateFormatter.date(from: name)
            }.sorted()
        } catch {
            logger.error("Failed to list stored dates: \(error.localizedDescription)")
            return []
        }
    }

    private func refreshAvailableDates() {
        availableDates = listStoredDates()
        recordCount = availableDates.count
    }
}

#endif
