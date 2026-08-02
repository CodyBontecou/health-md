import Darwin
import Foundation

nonisolated enum HostedSyncJournalError: LocalizedError, Equatable {
  case unavailable
  case invalidState

  var errorDescription: String? {
    "Health.md could not access the protected hosted synchronization journal."
  }
}

actor HostedSyncJournalStore {
  private static let maximumBytes = 512 * 1_024
  private static let maximumDays = 3_650

  private let directoryURL: URL
  private let directoryDescriptor: Int32
  private let fileManager: FileManager
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(
    baseDirectory: URL? = nil,
    fileManager: FileManager = .default
  ) throws {
    self.fileManager = fileManager
    let base: URL
    if let baseDirectory {
      base = baseDirectory
    } else {
      base = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    }
    directoryURL =
      base
      .appendingPathComponent("Health.md", isDirectory: true)
      .appendingPathComponent("Hosted", isDirectory: true)
      .appendingPathComponent("v1", isDirectory: true)
    encoder = JSONEncoder()
    decoder = JSONDecoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    decoder.dateDecodingStrategy = .iso8601
    directoryDescriptor = try Self.prepareDirectory(
      beneath: base,
      directoryURL: directoryURL,
      fileManager: fileManager
    )
  }

  deinit {
    Darwin.close(directoryDescriptor)
  }

  func snapshot(binding: HostedSyncJournalBinding) throws -> HostedSyncJournal {
    guard binding.isValid else { throw HostedSyncJournalError.invalidState }
    let descriptor = "sync-journal.json".withCString {
      Darwin.openat(
        directoryDescriptor,
        $0,
        O_RDONLY | O_NOFOLLOW | O_CLOEXEC
      )
    }
    if descriptor < 0 {
      if errno == ENOENT { return HostedSyncJournal(binding: binding) }
      throw HostedSyncJournalError.invalidState
    }
    defer { Darwin.close(descriptor) }
    var metadata = stat()
    guard Darwin.fstat(descriptor, &metadata) == 0,
      metadata.st_mode & S_IFMT == S_IFREG,
      metadata.st_nlink == 1,
      metadata.st_size >= 0,
      metadata.st_size <= Self.maximumBytes
    else {
      throw HostedSyncJournalError.invalidState
    }
    let data = try Self.readBounded(descriptor: descriptor)
    var finalMetadata = stat()
    guard Darwin.fstat(descriptor, &finalMetadata) == 0,
      finalMetadata.st_dev == metadata.st_dev,
      finalMetadata.st_ino == metadata.st_ino,
      finalMetadata.st_size == data.count
    else {
      throw HostedSyncJournalError.invalidState
    }
    let journal: HostedSyncJournal
    do {
      journal = try decoder.decode(HostedSyncJournal.self, from: data)
    } catch {
      throw HostedSyncJournalError.invalidState
    }
    guard journal.isValid(maximumDays: Self.maximumDays), journal.binding == binding else {
      throw HostedSyncJournalError.invalidState
    }
    return journal
  }

  func record(
    binding: HostedSyncJournalBinding,
    consentRevision: UInt64,
    days: [String: String],
    synchronizedAt: Date = Date()
  ) throws {
    guard binding.isValid,
      consentRevision > 0,
      days.count <= HostedDataClient.maximumDaysPerRequest,
      days.allSatisfy({ Self.isOwnerDate($0.key) && Self.isDigest($0.value) })
    else {
      throw HostedSyncJournalError.invalidState
    }
    var journal = try snapshot(binding: binding)
    if journal.consentRevision != consentRevision {
      journal = HostedSyncJournal(binding: binding, consentRevision: consentRevision)
    }
    for (ownerDate, digest) in days {
      journal.dayDigests[ownerDate] = digest
    }
    if journal.dayDigests.count > Self.maximumDays {
      for ownerDate in journal.dayDigests.keys.sorted().dropLast(Self.maximumDays) {
        journal.dayDigests.removeValue(forKey: ownerDate)
      }
    }
    journal.lastSynchronizedAt = synchronizedAt
    try save(journal)
  }

  func reset(
    binding: HostedSyncJournalBinding,
    consentRevision: UInt64
  ) throws {
    guard binding.isValid, consentRevision > 0 else {
      throw HostedSyncJournalError.invalidState
    }
    try save(HostedSyncJournal(binding: binding, consentRevision: consentRevision))
  }

  func reset() throws {
    let status = "sync-journal.json".withCString {
      Darwin.unlinkat(directoryDescriptor, $0, 0)
    }
    guard status == 0 || errno == ENOENT,
      Darwin.fsync(directoryDescriptor) == 0
    else {
      throw HostedSyncJournalError.unavailable
    }
  }

  private func save(_ journal: HostedSyncJournal) throws {
    guard journal.isValid(maximumDays: Self.maximumDays) else {
      throw HostedSyncJournalError.invalidState
    }
    let data = try encoder.encode(journal)
    guard data.count <= Self.maximumBytes else {
      throw HostedSyncJournalError.invalidState
    }
    let temporaryName = ".sync-journal-\(UUID().uuidString)"
    let descriptor = temporaryName.withCString {
      Darwin.openat(
        directoryDescriptor,
        $0,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
        mode_t(0o600)
      )
    }
    guard descriptor >= 0 else { throw HostedSyncJournalError.unavailable }
    defer {
      Darwin.close(descriptor)
      temporaryName.withCString { _ = Darwin.unlinkat(directoryDescriptor, $0, 0) }
    }
    do {
      var metadata = stat()
      guard Darwin.fstat(descriptor, &metadata) == 0,
        metadata.st_mode & S_IFMT == S_IFREG,
        metadata.st_nlink == 1,
        Darwin.fchmod(descriptor, mode_t(0o600)) == 0
      else {
        throw HostedSyncJournalError.unavailable
      }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
      try handle.write(contentsOf: data)
      try handle.synchronize()
      #if os(iOS)
        try fileManager.setAttributes(
          [.protectionKey: FileProtectionType.complete],
          ofItemAtPath: directoryURL.appendingPathComponent(temporaryName).path
        )
      #endif
      let renamed = temporaryName.withCString { source in
        "sync-journal.json".withCString { destination in
          Darwin.renameat(
            directoryDescriptor,
            source,
            directoryDescriptor,
            destination
          )
        }
      }
      guard renamed == 0, Darwin.fsync(directoryDescriptor) == 0 else {
        throw HostedSyncJournalError.unavailable
      }
    } catch let error as HostedSyncJournalError {
      throw error
    } catch {
      throw HostedSyncJournalError.unavailable
    }
  }

  private static func prepareDirectory(
    beneath base: URL,
    directoryURL: URL,
    fileManager: FileManager
  ) throws -> Int32 {
    var currentDescriptor = Darwin.open(
      base.path,
      O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    )
    guard currentDescriptor >= 0 else { throw HostedSyncJournalError.invalidState }
    var retained = false
    defer { if !retained { Darwin.close(currentDescriptor) } }
    var currentURL = base
    for component in ["Health.md", "Hosted", "v1"] {
      let mkdirStatus = component.withCString {
        Darwin.mkdirat(currentDescriptor, $0, mode_t(0o700))
      }
      guard mkdirStatus == 0 || errno == EEXIST else {
        throw HostedSyncJournalError.unavailable
      }
      let nextDescriptor = component.withCString {
        Darwin.openat(
          currentDescriptor,
          $0,
          O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
      }
      guard nextDescriptor >= 0 else { throw HostedSyncJournalError.invalidState }
      var metadata = stat()
      guard Darwin.fstat(nextDescriptor, &metadata) == 0,
        metadata.st_mode & S_IFMT == S_IFDIR,
        Darwin.fchmod(nextDescriptor, mode_t(0o700)) == 0,
        Darwin.fsync(currentDescriptor) == 0
      else {
        Darwin.close(nextDescriptor)
        throw HostedSyncJournalError.invalidState
      }
      Darwin.close(currentDescriptor)
      currentDescriptor = nextDescriptor
      currentURL.appendPathComponent(component, isDirectory: true)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var mutableDirectory = currentURL
      try mutableDirectory.setResourceValues(values)
      #if os(iOS)
        try fileManager.setAttributes(
          [.protectionKey: FileProtectionType.complete],
          ofItemAtPath: currentURL.path
        )
      #endif
    }
    guard currentURL.standardizedFileURL == directoryURL.standardizedFileURL else {
      throw HostedSyncJournalError.invalidState
    }
    retained = true
    return currentDescriptor
  }

  private static func readBounded(descriptor: Int32) throws -> Data {
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    var result = Data()
    while result.count <= maximumBytes {
      let remaining = maximumBytes + 1 - result.count
      guard let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)),
        !chunk.isEmpty
      else { break }
      result.append(chunk)
    }
    guard result.count <= maximumBytes else {
      throw HostedSyncJournalError.invalidState
    }
    return result
  }

  private static func isOwnerDate(_ value: String) -> Bool {
    HostedOwnerDate.isValid(value)
  }

  private static func isDigest(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }
}

nonisolated struct HostedSyncJournalBinding: Codable, Equatable, Sendable {
  let resourceURL: URL
  let clientID: String
  let issuer: URL
  let ownerBinding: String

  var isValid: Bool {
    HostedAccountConfiguration(resourceURL: resourceURL, clientID: clientID).isValid
      && HostedOAuthToken.isValidOwnerBinding(ownerBinding)
      && issuer.scheme?.lowercased() == "https"
      && issuer.host?.isEmpty == false
      && issuer.user == nil
      && issuer.password == nil
      && issuer.query == nil
      && issuer.fragment == nil
  }

  enum CodingKeys: String, CodingKey {
    case resourceURL = "resource_url"
    case clientID = "client_id"
    case issuer
    case ownerBinding = "owner_binding"
  }
}

nonisolated struct HostedSyncJournal: Codable, Equatable, Sendable {
  let schema: String
  let schemaVersion: Int
  let binding: HostedSyncJournalBinding
  var consentRevision: UInt64?
  var dayDigests: [String: String]
  var lastSynchronizedAt: Date?

  init(
    binding: HostedSyncJournalBinding,
    consentRevision: UInt64? = nil,
    dayDigests: [String: String] = [:],
    lastSynchronizedAt: Date? = nil
  ) {
    schema = "healthmd.hosted_sync_journal"
    schemaVersion = 2
    self.binding = binding
    self.consentRevision = consentRevision
    self.dayDigests = dayDigests
    self.lastSynchronizedAt = lastSynchronizedAt
  }

  enum CodingKeys: String, CodingKey {
    case schema
    case schemaVersion = "schema_version"
    case binding
    case consentRevision = "consent_revision"
    case dayDigests = "day_digests"
    case lastSynchronizedAt = "last_synchronized_at"
  }

  func isValid(maximumDays: Int) -> Bool {
    schema == "healthmd.hosted_sync_journal"
      && schemaVersion == 2
      && binding.isValid
      && dayDigests.count <= maximumDays
      && dayDigests.allSatisfy {
        HostedOwnerDate.isValid($0.key)
          && $0.value.range(
            of: "^[0-9a-f]{64}$",
            options: .regularExpression
          ) != nil
      }
  }
}
