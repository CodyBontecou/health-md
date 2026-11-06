#if os(iOS)
import CoreGraphics
import XCTest
@testable import HealthMd

@MainActor
final class ArchiveDerivationsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }()

    private func date(_ day: Int, month: Int = 10, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    // MARK: - Paths

    func testFilePathFollowsTheProfileOutputSettings() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ArchiveDerivationsTests.\(UUID())"))
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.markdown]
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.organizeFormatsIntoFolders = false
        let snapshot = ExportSettingsSnapshot.from(settings, healthSubfolder: "Health", calendarTimeZoneIdentifier: "UTC")
        let path = ArchiveOutputPath.files(root: "Vault", healthSubfolder: "Health", settings: snapshot)

        XCTAssertEqual(path.display(on: date(19), status: .complete), "Vault/Health/2026-10-19.md")
        XCTAssertEqual(path.display(on: date(19), status: .missing), "Vault/Health/2026-10-19.md")
        // Dates with no file of their own show the root.
        XCTAssertEqual(path.display(on: date(19), status: .notDue), "Vault")
        XCTAssertEqual(path.display(on: date(19), status: .paused), "Vault")
    }

    func testOpenResolvesTheProfilesOwnFileForTheDate() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ArchiveDerivationsTests.\(UUID())"))
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.csv]
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.organizeFormatsIntoFolders = false
        let snapshot = ExportSettingsSnapshot.from(settings, healthSubfolder: "Health", calendarTimeZoneIdentifier: "UTC")
        let path = ArchiveOutputPath.files(root: "Vault", healthSubfolder: "Health", settings: snapshot)
        let root = URL(fileURLWithPath: "/tmp/Vault", isDirectory: true)

        XCTAssertEqual(path.fileURL(on: date(19), rootURL: root)?.path, "/tmp/Vault/Health/2026-10-19.csv")
        XCTAssertNil(ArchiveOutputPath.endpoint(line: "POST api.example.com").fileURL(on: date(19), rootURL: root))
        XCTAssertNil(ArchiveOutputPath.label("Connected Mac").fileURL(on: date(19), rootURL: root))

        // Only an on-device folder offers Open; a Mac's files are not readable here.
        let ledger = CoverageLedger(startedAt: date(1))
        let model = ArchiveModel(profiles: [], ledger: ledger, now: date(31), calendar: calendar)
        var profile = ArchiveProfile(id: UUID(), name: "Daily", destination: "Vault", colorIndex: 0, entry: nil, outputPath: path)
        XCTAssertFalse(model.canOpen(profile, on: date(19)))
        profile.writesFilesOnDevice = true
        XCTAssertTrue(model.canOpen(profile, on: date(19)))
    }

    func testFileLocationFallsBackToTheFolderWhenTheFileIsGone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveOpen-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Health"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Health/2026-10-19.md")
        try Data("x".utf8).write(to: file)

        let found = ArchiveFileLocation.locate(relativePath: "Health/2026-10-19.md", bookmarkData: nil, fallbackRootURL: root)
        guard case .file(let foundFile) = found.location else { return XCTFail("expected the file") }
        XCTAssertEqual(foundFile.standardizedFileURL.path, file.standardizedFileURL.path)
        let missing = ArchiveFileLocation.locate(relativePath: "Health/2026-10-20.md", bookmarkData: nil, fallbackRootURL: root)
        guard case .folder(let folder) = missing.location else { return XCTFail("expected the folder") }
        XCTAssertEqual(folder.standardizedFileURL.path, root.appendingPathComponent("Health").standardizedFileURL.path)
        XCTAssertEqual(
            ArchiveFileLocation.locate(relativePath: "a.md", bookmarkData: nil, fallbackRootURL: nil).location,
            .unavailable
        )
    }

    func testEndpointLineShowsHostAndPathOnly() {
        XCTAssertEqual(
            ArchiveOutputPath.endpointLine(URL(string: "https://user:secret@api.example.com/health?token=1#x")),
            "POST api.example.com/health"
        )
        XCTAssertEqual(ArchiveOutputPath.endpointLine(URL(string: "https://api.example.com/")), "POST api.example.com")
        XCTAssertEqual(ArchiveOutputPath.endpointLine(URL(string: "http://10.0.0.2:8080/v1/ingest")), "POST 10.0.0.2:8080/v1/ingest")
        XCTAssertNil(ArchiveOutputPath.endpointLine(URL(string: "not a url")))
        XCTAssertNil(ArchiveOutputPath.endpointLine(nil))
    }

    // MARK: - Weekly

    func testWeeklyFileCoversTheWeekBeforeItsRun() throws {
        // October 25, 2026 is a Sunday (ISO 7). Its run covers October 18 – 24.
        let range = try XCTUnwrap(ArchiveWeekly.coveredRange(for: date(20), isoWeekday: 7, lookbackDays: 7, calendar: calendar))
        XCTAssertEqual(range.lowerBound, calendar.startOfDay(for: date(18)))
        XCTAssertEqual(range.upperBound, calendar.startOfDay(for: date(24)))
        // The run day itself belongs to the next file.
        XCTAssertEqual(
            ArchiveWeekly.coveringFireDay(for: date(25), isoWeekday: 7, calendar: calendar),
            calendar.startOfDay(for: date(1, month: 11))
        )
        XCTAssertEqual(ArchiveWeekly.weekdayName(isoWeekday: 7, calendar: calendar), "Sunday")
        XCTAssertEqual(ArchiveWeekly.weekdayName(isoWeekday: 1, calendar: calendar), "Monday")
    }

    func testShortLookBackDoesNotClaimTheWholeWeek() throws {
        let range = try XCTUnwrap(ArchiveWeekly.coveredRange(for: date(19), isoWeekday: 7, lookbackDays: 3, calendar: calendar))
        XCTAssertFalse(range.contains(calendar.startOfDay(for: date(19))))
        XCTAssertTrue(range.contains(calendar.startOfDay(for: date(23))))
    }

    // MARK: - Pause

    func testPauseDateComesFromTheRecordedTransition() {
        let started = date(1)
        let paused = CoverageScheduleEvent(date: date(22, hour: 9), isEnabled: false)
        XCTAssertEqual(
            ArchivePause.since(events: [paused], isPaused: true, ledgerStartedAt: started, didSeedFromHistory: true),
            date(22, hour: 9)
        )
        XCTAssertNil(ArchivePause.since(events: [paused], isPaused: false, ledgerStartedAt: started, didSeedFromHistory: true))
        XCTAssertNil(ArchivePause.since(
            events: [paused, CoverageScheduleEvent(date: date(24), isEnabled: true)],
            isPaused: true,
            ledgerStartedAt: started,
            didSeedFromHistory: false
        ))
    }

    func testPauseInferredWhileSeedingHasNoDate() {
        let seededAt = date(5)
        let inferred = CoverageScheduleEvent(date: seededAt.addingTimeInterval(1), isEnabled: false)
        XCTAssertNil(ArchivePause.since(events: [inferred], isPaused: true, ledgerStartedAt: seededAt, didSeedFromHistory: true))
    }

    // MARK: - Attention

    func testEndpointFailureFacts() {
        let detail = "Batch upload failed for Oct 19: API endpoint returned HTTP 503."
        XCTAssertEqual(ArchiveAttention.httpStatus(in: detail), 503)
        XCTAssertNil(ArchiveAttention.httpStatus(in: "Task timed out"))
        XCTAssertEqual(ArchiveAttention.consecutiveFailures([.failed, .failed, .partialSuccess, .failed]), 2)
        XCTAssertEqual(ArchiveAttention.consecutiveFailures([.success, .failed]), 0)
        XCTAssertEqual(ArchiveAttention.repeatedStatus([detail, detail, detail]), 503)
        XCTAssertNil(ArchiveAttention.repeatedStatus([detail, "API endpoint returned HTTP 500."]))
        XCTAssertNil(ArchiveAttention.repeatedStatus([detail, nil]))
    }

    // MARK: - Window

    func testOnlyAnUnfoldedDisplayCountsAsUnfolded() {
        // A large phone in landscape is regular width but short.
        XCTAssertFalse(GlassWindowClass.looksUnfolded(isPad: false, isRegularWidth: true, windowSize: CGSize(width: 956, height: 440)))
        XCTAssertTrue(GlassWindowClass.looksUnfolded(isPad: false, isRegularWidth: true, windowSize: CGSize(width: 890, height: 626)))
        XCTAssertFalse(GlassWindowClass.looksUnfolded(isPad: true, isRegularWidth: true, windowSize: CGSize(width: 1180, height: 820)))
    }

    func testFoldedHintNeedsAnUnfoldedDevice() {
        let phone = CGSize(width: 440, height: 956)
        XCTAssertEqual(
            GlassWindowClass.resolve(isPad: false, isRegularWidth: false, windowSize: phone, screenSize: phone, hasSeenUnfolded: false),
            .phone
        )
        XCTAssertEqual(
            GlassWindowClass.resolve(isPad: false, isRegularWidth: false, windowSize: phone, screenSize: phone, hasSeenUnfolded: true),
            .folded
        )
        XCTAssertEqual(
            GlassWindowClass.resolve(
                isPad: false,
                isRegularWidth: false,
                windowSize: CGSize(width: 433, height: 626),
                screenSize: CGSize(width: 890, height: 626),
                hasSeenUnfolded: true
            ),
            .splitView
        )
        XCTAssertEqual(
            GlassWindowClass.resolve(
                isPad: true,
                isRegularWidth: false,
                windowSize: CGSize(width: 375, height: 820),
                screenSize: CGSize(width: 1180, height: 820),
                hasSeenUnfolded: false
            ),
            .splitView
        )
        XCTAssertEqual(
            GlassWindowClass.resolve(isPad: true, isRegularWidth: true, windowSize: .zero, screenSize: .zero, hasSeenUnfolded: false),
            .pad
        )
    }
}
#endif
