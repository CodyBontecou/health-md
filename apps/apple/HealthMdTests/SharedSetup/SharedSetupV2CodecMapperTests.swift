import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class SharedSetupV2CodecMapperTests: XCTestCase {
    func testFourAppleDetailPoliciesRemainOrthogonalAndRangeSummaryUsesCurrentPreference() throws {
        let policies: [(String, AppleExportDetailPolicy)] = [
            ("Summary", .summary),
            ("Detailed", .detailedTimeSeries),
            ("Archive", .archiveOnly),
            ("Lossless", .lossless)
        ]
        let profiles = policies.enumerated().map { offset, value in
            makeProfile(
                id: profileID(offset + 1),
                name: value.0,
                policy: value.1,
                enabledNativeIDs: ["steps"],
                generateRangeSummary: offset == 1
            )
        }

        let document = try map(
            profiles: profiles,
            activeProfileID: profiles[2].id
        )

        XCTAssertEqual(
            document.profiles.map(\.export.compatibilityDetail),
            [.summary, .selectedTimeSeries, .summary, .selectedTimeSeries]
        )
        XCTAssertEqual(
            document.profiles.map { $0.platformExtensions.apple?.export.healthKitSourceArchive },
            [
                SharedSetupV2.HealthKitSourceArchive.none,
                SharedSetupV2.HealthKitSourceArchive.none,
                .canonicalV1,
                .canonicalV1
            ].map(Optional.some)
        )
        XCTAssertEqual(
            document.profiles.map { $0.platformExtensions.apple?.export.generateRangeSummary },
            [false, true, false, false]
        )
        XCTAssertEqual(document.activeProfile, "profile-003")

        let text = String(decoding: try SharedSetupV2Codec.encode(document), as: UTF8.self)
        XCTAssertTrue(text.contains("\"generate_range_summary\":true"))
        XCTAssertFalse(text.contains("generate_weekly_rollups"))
        XCTAssertFalse(text.contains("generate_monthly_rollups"))
        XCTAssertFalse(text.contains("generate_yearly_rollups"))
        XCTAssertFalse(text.contains("\"rollups\""))
    }

    func testAllProfileOrderActiveMappingAndAliasUnionIncludesDisabledIndividualRows() throws {
        var first = makeProfile(
            id: profileID(1),
            name: " First ",
            enabledNativeIDs: ["steps"],
            individualNative: [
                "heart_rate_avg": .init(
                    trackIndividually: false,
                    customFolder: "entries/heart"
                )
            ]
        )
        first.settings.exportFormats = [.markdown, .csv, .json, .obsidianBases]
        first.settings.formatCustomization.frontmatterConfig.placeholderFields = ["zeta", "alpha"]
        first.settings.formatCustomization.frontmatterConfig.fields = [
            .init(originalKey: "steps", customKey: "daily_steps", isEnabled: true),
            .init(originalKey: "heart_rate", customKey: "heart_rate", isEnabled: false)
        ]
        let second = makeProfile(
            id: profileID(2),
            name: "Second",
            enabledNativeIDs: ["active_energy"]
        )

        let document = try map(
            profiles: [first, second],
            activeProfileID: second.id
        )

        XCTAssertEqual(document.profiles.map(\.bundleID), ["profile-001", "profile-002"])
        XCTAssertEqual(document.profiles.map(\.name), ["First", "Second"])
        XCTAssertEqual(document.activeProfile, "profile-002")
        XCTAssertEqual(document.profiles[0].metrics.enabledIDs, ["steps"])
        XCTAssertEqual(document.profiles[0].export.formats, [.csv, .json, .markdown, .obsidianBases])
        XCTAssertEqual(
            document.profiles[0].presentation.frontmatter.placeholders,
            ["zeta", "alpha"]
        )
        XCTAssertEqual(
            document.profiles[0].presentation.frontmatter.fields.map(\.sourceKey),
            ["steps", "heart_rate"]
        )
        XCTAssertEqual(
            document.profiles[0].individualEntries.metrics["heart_rate_avg"]?.enabled,
            false
        )
        XCTAssertEqual(
            document.metricAliases.map(\.semanticID),
            ["active_energy", "heart_rate_avg", "steps"]
        )
        XCTAssertEqual(
            Set(document.metricAliases.map(\.semanticID)),
            Set(document.profiles.flatMap {
                $0.metrics.enabledIDs + Array($0.individualEntries.metrics.keys)
            })
        )
    }

    func testCanonicalEncodingHasExplicitNullsAndOmitsNativeIDsSecretsPathsPinsAndTimestamps() throws {
        let nativeProfileID = profileID(1)
        let vaultID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        var profile = makeProfile(
            id: nativeProfileID,
            name: "Private local profile",
            enabledNativeIDs: ["hrv"],
            target: .localIPhoneFolder,
            folderVaultID: vaultID
        )
        profile.settings.healthSubfolder = "private-file-provider-subfolder"
        profile.settings.calendarTimeZoneIdentifier = "America/Los_Angeles"
        profile.settings.metricSelection.enabledCategoryIDs = ["private_category"]
        let vault = SavedVaultDestination(
            id: vaultID,
            name: "Personal iCloud Vault",
            standardizedPath: "/private/mobile/Library/Mobile Documents/private-vault",
            bookmarkData: Data("private-bookmark".utf8),
            createdAt: fixedDate(year: 2031, month: 1, day: 2)
        )

        let document = try map(
            profiles: [profile],
            activeProfileID: nativeProfileID,
            destinations: .init(vaults: [vault])
        )
        let first = try SharedSetupV2Codec.encode(document)
        let second = try SharedSetupV2Codec.encode(document)
        let root = try jsonObject(first)
        let encodedText = String(decoding: first, as: UTF8.self)
        let encodedLower = encodedText.lowercased()

        XCTAssertEqual(first, second)
        XCTAssertEqual(document.profiles[0].destination.kind, .deviceFolder)
        XCTAssertNil(document.profiles[0].destination.apiEndpoint)
        XCTAssertNil(document.profiles[0].schedule)
        XCTAssertNil(document.profiles[0].platformExtensions.android)

        let encodedProfiles = try XCTUnwrap(root["profiles"] as? [[String: Any]])
        let encodedProfile = try XCTUnwrap(encodedProfiles.first)
        let destination = try XCTUnwrap(encodedProfile["destination"] as? [String: Any])
        let extensions = try XCTUnwrap(encodedProfile["platform_extensions"] as? [String: Any])
        XCTAssertTrue(destination["api_endpoint"] is NSNull)
        XCTAssertTrue(encodedProfile["schedule"] is NSNull)
        XCTAssertTrue(extensions["android"] is NSNull)
        let aliases = try XCTUnwrap(root["metric_aliases"] as? [[String: Any]])
        XCTAssertTrue(try XCTUnwrap(aliases.first)["android_selection_id"] is NSNull)

        for prohibited in [
            nativeProfileID.uuidString.lowercased(),
            vaultID.uuidString.lowercased(),
            "private/mobile",
            "private-bookmark",
            "personal icloud vault",
            "private-file-provider-subfolder",
            "america/los_angeles",
            "appleexportenginepin",
            "createdat",
            "updatedat",
            "bookmark",
            "folder_vault_id",
            "folder_grant",
            "content_uri",
            "permission",
            "pairing",
            "destination_fingerprint",
            "engine_pin",
            "timezone",
            "timestamp",
            "include_granular_data",
            "private_category",
            "enabled_categories"
        ] {
            XCTAssertFalse(encodedLower.contains(prohibited), "Unexpected output: \(prohibited)")
        }
    }

    func testEndpointHintAndScheduleAreInertAndContainNoRuntimeState() throws {
        let nativeProfileID = profileID(1)
        let endpointID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!
        let profile = makeProfile(
            id: nativeProfileID,
            name: "Scheduled API",
            enabledNativeIDs: ["steps"],
            target: .apiEndpoint,
            apiEndpointID: endpointID
        )
        let endpoint = SavedAPIEndpoint(
            id: endpointID,
            name: "Tenant secret display name",
            endpointURLString: "https://synthetic-user:synthetic-pass@API.Example.invalid:9443/v2/health?tenant=private#secret",
            createdAt: fixedDate(year: 2032, month: 2, day: 3)
        )
        let entry = ScheduledExportEntry(
            id: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!,
            profileID: nativeProfileID,
            isEnabled: true,
            frequency: .custom,
            customInterval: 2,
            customUnit: .week,
            customAnchorDate: fixedDate(year: 2026, month: 5, day: 17),
            preferredHour: 8,
            preferredMinute: 45,
            weekday: 4,
            lookbackDays: 9,
            todayRefreshEnabled: true,
            todayRefreshIntervalHours: 12,
            lastExportDate: fixedDate(year: 2033, month: 3, day: 4),
            lastTodayRefreshDate: fixedDate(year: 2034, month: 4, day: 5),
            enabledAt: fixedDate(year: 2035, month: 5, day: 6)
        )

        let document = try map(
            profiles: [profile],
            activeProfileID: nativeProfileID,
            destinations: .init(apiEndpoints: [endpoint]),
            schedules: [entry]
        )
        let mapped = document.profiles[0]
        let schedule = try XCTUnwrap(mapped.schedule)
        let hint = try XCTUnwrap(mapped.destination.apiEndpoint)
        let appleSchedule = try XCTUnwrap(mapped.platformExtensions.apple?.schedule)

        XCTAssertEqual(mapped.destination.kind, .apiEndpoint)
        XCTAssertEqual(hint.host, "api.example.invalid")
        XCTAssertEqual(hint.port, 9443)
        XCTAssertEqual(hint.path, "/v2/health")
        XCTAssertTrue(hint.queryOmitted)
        XCTAssertTrue(hint.credentialsRequired)
        XCTAssertEqual(hint.validatedURLString, "https://api.example.invalid:9443/v2/health")
        XCTAssertTrue(schedule.activationRequested)
        XCTAssertEqual(schedule.cadence, .init(value: 2, unit: .weeks, anchorDate: "2026-05-17"))
        XCTAssertEqual(schedule.localTime, .init(hour: 8, minute: 45))
        XCTAssertEqual(schedule.weekday, 4)
        XCTAssertEqual(schedule.lookbackDays, 9)
        XCTAssertEqual(schedule.dateWindow, .pastCompleteDays)
        XCTAssertEqual(appleSchedule.frequency, .custom)
        XCTAssertEqual(appleSchedule.customUnit, .weeks)
        XCTAssertTrue(appleSchedule.todayRefreshRequested)
        XCTAssertEqual(appleSchedule.todayRefreshIntervalHours, 12)

        let text = String(decoding: try SharedSetupV2Codec.encode(document), as: UTF8.self).lowercased()
        for prohibited in [
            "synthetic-user", "synthetic-pass", "tenant=private", "#secret",
            "tenant secret display name", entry.id.uuidString.lowercased(),
            nativeProfileID.uuidString.lowercased(), "last_export", "last_refresh",
            "enabled_at", "2033-", "2034-", "2035-", "timezone", "progress"
        ] {
            XCTAssertFalse(text.contains(prohibited), "Unexpected output: \(prohibited)")
        }
        XCTAssertTrue(text.contains("\"activation_requested\":true"))
        XCTAssertFalse(text.contains("\"isenabled\""))
    }

    func testUnsafeOrUnconfiguredAPIStillProducesOnlyInertAPIIntent() throws {
        let endpointID = UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!
        let profile = makeProfile(
            id: profileID(1),
            name: "Unsafe endpoint",
            target: .apiEndpoint,
            apiEndpointID: endpointID
        )
        let endpoint = SavedAPIEndpoint(
            id: endpointID,
            name: "Unsafe",
            endpointURLString: "http://private.invalid/upload"
        )

        let document = try map(
            profiles: [profile],
            activeProfileID: profile.id,
            destinations: .init(apiEndpoints: [endpoint])
        )

        XCTAssertEqual(document.profiles[0].destination.kind, .apiEndpoint)
        XCTAssertNil(document.profiles[0].destination.apiEndpoint)
        XCTAssertNoThrow(try SharedSetupV2Codec.encode(document))
    }

    func testStrictVersionDispatchUnknownFieldsAndVersionSpecificBounds() throws {
        let profile = makeProfile(
            id: profileID(1),
            name: "Dispatch",
            enabledNativeIDs: ["steps"]
        )
        let encoded = try SharedSetupV2Codec.encode(try map(
            profiles: [profile],
            activeProfileID: profile.id
        ))

        guard case .v2(let dispatched) = try SharedSetupVersionedCodec.decode(encoded) else {
            return XCTFail("Expected v2 dispatch")
        }
        XCTAssertEqual(dispatched.profiles.first?.name, "Dispatch")

        var unknownRoot = try jsonObject(encoded)
        unknownRoot["future_optional"] = ["bounded": [1, 2, 3]]
        let withUnknown = try jsonData(unknownRoot)
        let decodedUnknown = try SharedSetupV2Codec.decode(withUnknown)
        let reencoded = try SharedSetupV2Codec.encode(decodedUnknown)
        XCTAssertNil(try jsonObject(reencoded)["future_optional"])

        for versionToken in ["true", "\"2\"", "2.0", "3"] {
            let text = String(decoding: encoded, as: UTF8.self)
                .replacingOccurrences(
                    of: "\"schema_version\":2",
                    with: "\"schema_version\":\(versionToken)"
                )
            XCTAssertThrowsError(try SharedSetupVersionedCodec.decode(Data(text.utf8)))
        }

        var tooWide = try jsonObject(encoded)
        tooWide["future_optional"] = Array(repeating: true, count: 513)
        XCTAssertThrowsError(try SharedSetupV2Codec.decode(try jsonData(tooWide)))

        var tooDeep = try jsonObject(encoded)
        var nested: Any = true
        for index in 0..<20 {
            nested = ["level_\(index)": nested]
        }
        tooDeep["future_optional"] = nested
        XCTAssertThrowsError(try SharedSetupV2Codec.decode(try jsonData(tooDeep)))

        var tooManyNodes = try jsonObject(encoded)
        tooManyNodes["future_optional"] = Array(
            repeating: Array(repeating: true, count: 512),
            count: 512
        )
        XCTAssertThrowsError(try SharedSetupV2Codec.decode(try jsonData(tooManyNodes)))

        var oversizedScalar = try jsonObject(encoded)
        oversizedScalar["future_optional"] = String(repeating: "x", count: 65_537)
        XCTAssertThrowsError(try SharedSetupV2Codec.decode(try jsonData(oversizedScalar)))

        var prohibited = try jsonObject(encoded)
        prohibited["future_token"] = "synthetic"
        XCTAssertThrowsError(try SharedSetupV2Codec.decode(try jsonData(prohibited)))
        prohibited = try jsonObject(encoded)
        prohibited["nativeProfileId"] = "00000000-0000-4000-8000-000000000001"
        XCTAssertThrowsError(try SharedSetupV2Codec.decode(try jsonData(prohibited)))

        let oversizedV2 = Data(repeating: 0, count: SharedSetupV2.maximumEncodedBytes + 1)
        XCTAssertThrowsError(try SharedSetupVersionedCodec.decode(oversizedV2))

        let v1 = try Data(contentsOf: v1FixtureURL())
        guard case .v1(let v1Document) = try SharedSetupVersionedCodec.decode(v1) else {
            return XCTFail("Expected v1 dispatch")
        }
        XCTAssertEqual(v1Document.schemaVersion, 1)

        var oversizedV1Root = try jsonObject(v1)
        oversizedV1Root["future_optional"] = Array(
            repeating: String(repeating: "x", count: 60_000),
            count: 5
        )
        let oversizedV1 = try jsonData(oversizedV1Root)
        XCTAssertGreaterThan(oversizedV1.count, SharedSetupV1.maximumEncodedBytes)
        XCTAssertLessThan(oversizedV1.count, SharedSetupV2.maximumEncodedBytes)
        XCTAssertThrowsError(try SharedSetupVersionedCodec.decode(oversizedV1)) { error in
            XCTAssertEqual(error as? SharedSetupError, .oversized)
        }
    }

    func testValidationRejectsBundleNameAliasDestinationScheduleAndExtensionContradictions() throws {
        let profile = makeProfile(
            id: profileID(1),
            name: "Valid",
            enabledNativeIDs: ["steps"]
        )
        let entry = ScheduledExportEntry(
            profileID: profile.id,
            frequency: .daily,
            customAnchorDate: fixedDate(year: 2026, month: 1, day: 2)
        )
        let valid = try map(
            profiles: [profile],
            activeProfileID: profile.id,
            schedules: [entry]
        )

        var badBundle = valid
        badBundle.profiles[0].bundleID = "profile-002"
        assertInvalid(badBundle)

        var badName = valid
        badName.profiles[0].name = " Valid "
        assertInvalid(badName)

        var duplicateName = valid
        var duplicateProfile = duplicateName.profiles[0]
        duplicateProfile.bundleID = "profile-002"
        duplicateProfile.name = "vALID"
        duplicateName.profiles.append(duplicateProfile)
        assertInvalid(duplicateName)

        var tooManyProfiles = valid
        tooManyProfiles.profiles = (1...101).map { index in
            var copy = valid.profiles[0]
            copy.bundleID = String(format: "profile-%03d", index)
            copy.name = "Profile \(index)"
            return copy
        }
        assertInvalid(tooManyProfiles)

        var badActive = valid
        badActive.activeProfile = "profile-999"
        assertInvalid(badActive)

        var badAliases = valid
        badAliases.metricAliases = []
        assertInvalid(badAliases)

        var badDestination = valid
        badDestination.profiles[0].destination.apiEndpoint = .init(
            scheme: "https",
            host: "safe.invalid",
            port: nil,
            path: "/upload",
            queryOmitted: false,
            credentialsRequired: true
        )
        assertInvalid(badDestination)

        var badSchedule = valid
        badSchedule.profiles[0].platformExtensions.apple?.schedule = nil
        assertInvalid(badSchedule)

        var badExtension = valid
        badExtension.profiles[0].platformExtensions.apple = nil
        assertInvalid(badExtension)

        var badAnchor = valid
        badAnchor.profiles[0].schedule?.cadence.anchorDate = "2026-02-30"
        assertInvalid(badAnchor)

        let validData = try SharedSetupV2Codec.encode(valid)
        var raw = try jsonObject(validData)
        var profiles = try XCTUnwrap(raw["profiles"] as? [[String: Any]])
        profiles[0].removeValue(forKey: "schedule")
        raw["profiles"] = profiles
        XCTAssertThrowsError(try SharedSetupV2Codec.decode(try jsonData(raw)))
    }

    func testTypedAndroidExtensionAndUnavailableMeaningArePreservedAndReportedWithoutApproximation() throws {
        let defaults = isolatedDefaults()
        let profile = makeProfile(
            id: profileID(1),
            name: "Android source",
            enabledNativeIDs: ["steps"]
        )
        var document = try map(profiles: [profile], activeProfileID: profile.id)
        let androidExtension = syntheticAndroidExtension()
        document.createdBy.platform = .android
        document.profiles[0].platformExtensions.android = androidExtension
        document.profiles[0].destination = .init(kind: .cloud, apiEndpoint: nil)
        document.profiles[0].presentation.markdown.style = .custom
        document.profiles[0].presentation.markdown.originDialect = .android
        document.profiles[0].presentation.markdown.customText = "{{android_only}}"
        document.profiles[0].schedule = .init(
            activationRequested: true,
            cadence: .init(value: 1, unit: .days, anchorDate: "2026-05-17"),
            localTime: .init(hour: 6, minute: 0),
            weekday: 1,
            lookbackDays: ExportSchedule.maximumLookbackDays + 1,
            dateWindow: .pastCompleteDays
        )
        document.profiles[0].metrics.enabledIDs.append("android.hrv_rmssd")
        document.profiles[0].metrics.enabledIDs.sort()
        document.metricAliases.append(.init(
            semanticID: "android.hrv_rmssd",
            equivalence: .platformDistinct,
            appleSelectionID: nil,
            androidSelectionID: "hrv"
        ))
        document.metricAliases.sort { $0.semanticID < $1.semanticID }
        let canonical = try SharedSetupV2Codec.decode(SharedSetupV2Codec.encode(document))
        let before = defaults.dictionaryRepresentation() as NSDictionary

        let plan = SharedSetupV2Mapper.preview(canonical, registry: fixtureRegistry())

        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before)
        XCTAssertFalse(plan.hasInvalidItems)
        XCTAssertEqual(plan.defaultSelectedBundleIDs, ["profile-001"])
        XCTAssertEqual(plan.profiles[0].supportedMetricSelectionIDs, ["steps"])
        XCTAssertEqual(
            plan.profiles[0].unsupportedPreservedSemanticIDs,
            ["android.hrv_rmssd"]
        )
        XCTAssertEqual(plan.profiles[0].preservedAndroidExtension, androidExtension)
        XCTAssertFalse(plan.profiles[0].installCustomTemplate)
        XCTAssertFalse(plan.profiles[0].importsScheduleEnabled)
        XCTAssertFalse(plan.profiles[0].destinationIsLocallyBound)
        XCTAssertFalse(plan.profiles[0].destinationKindIsSupported)
        XCTAssertFalse(plan.profiles[0].scheduleCanApplyExactly)
        XCTAssertTrue(plan.profiles[0].items.contains {
            $0.id.hasSuffix("schedule") &&
                $0.status == .requiresAction &&
                $0.detail.contains("do not clamp or approximate")
        })
        XCTAssertTrue(plan.profiles[0].items.contains {
            $0.id.hasSuffix("template") && $0.status == .requiresAction
        })
        XCTAssertTrue(plan.profiles[0].items.contains {
            $0.id.hasSuffix("metric.android.hrv_rmssd") &&
                $0.status == .requiresAction &&
                $0.detail.contains("will not be approximated")
        })
        XCTAssertTrue(plan.profiles[0].items.contains {
            $0.id.hasSuffix("android-extension") && $0.status == .unsupported
        })
        XCTAssertTrue(plan.profiles[0].items.contains {
            $0.id.hasSuffix("destination") && $0.status == .unsupported
        })
    }

    func testMapperPreservesPerProfileAndroidExtensionsAndRejectsOrphanState() throws {
        let first = makeProfile(id: profileID(1), name: "One")
        let second = makeProfile(id: profileID(2), name: "Two")
        let extensionValue = syntheticAndroidExtension()

        let mapped = try map(
            profiles: [first, second],
            activeProfileID: first.id,
            preservedAndroid: [second.id: extensionValue]
        )

        XCTAssertNil(mapped.profiles[0].platformExtensions.android)
        XCTAssertEqual(mapped.profiles[1].platformExtensions.android, extensionValue)

        let orphan = ScheduledExportEntry(profileID: profileID(99))
        XCTAssertThrowsError(try map(
            profiles: [first, second],
            activeProfileID: first.id,
            schedules: [orphan]
        ))
        XCTAssertThrowsError(try map(
            profiles: [first, second],
            activeProfileID: first.id,
            preservedAndroid: [profileID(99): extensionValue]
        ))
    }

    func testWriterRejectsProhibitedMaterialAndNeverInfersCloudFromFileProviderPaths() throws {
        var profile = makeProfile(
            id: profileID(1),
            name: "File Provider",
            enabledNativeIDs: ["steps"],
            target: .localIPhoneFolder,
            folderVaultID: UUID(uuidString: "EEEEEEEE-EEEE-4EEE-8EEE-EEEEEEEEEEEE")!
        )
        profile.settings.formatCustomization.frontmatterConfig.customFields = [
            "unsafe": "Bearer synthetic-secret"
        ]
        let vault = SavedVaultDestination(
            id: try XCTUnwrap(profile.folderVaultID),
            name: "iCloud Drive",
            standardizedPath: "/private/File Provider Storage/Health",
            bookmarkData: Data("bookmark".utf8)
        )
        let document = try map(
            profiles: [profile],
            activeProfileID: profile.id,
            destinations: .init(vaults: [vault])
        )

        XCTAssertEqual(document.profiles[0].destination.kind, .deviceFolder)
        XCTAssertThrowsError(try SharedSetupV2Codec.encode(document))
    }

    func testCanonicalV2FixturesDecodeWhenContractLaneIsIntegrated() throws {
        // Only the canonical public `healthmd.shared_setup` artifacts live here.
        // The cycle-2 transaction scenario fixture is deliberately excluded: it is
        // local test infrastructure with its own schema identity whose envelope
        // must be rejected by the public v2 security validation.
        let canonicalFixtureNames = [
            "android-shared-setup-v2.json",
            "apple-shared-setup-v2.json",
        ]
        guard let directory = sharedSetupV2FixtureDirectory(),
              let fixtureURLs = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ).filter({ canonicalFixtureNames.contains($0.lastPathComponent) })
              .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }),
              !fixtureURLs.isEmpty else {
            throw XCTSkip(
                "Cycle-1 contract lane fixture is not in this isolated worktree; reconcile this test against packages/contracts/shared-setup/v2/fixtures after integration."
            )
        }

        for url in fixtureURLs {
            let document = try SharedSetupV2Codec.decode(Data(contentsOf: url))
            XCTAssertEqual(document.schemaVersion, 2, url.lastPathComponent)
            XCTAssertEqual(
                try SharedSetupV2Codec.encode(document),
                try SharedSetupV2Codec.encode(document),
                url.lastPathComponent
            )
        }
    }

    // MARK: - Helpers

    private func map(
        profiles: [ExportProfile],
        activeProfileID: UUID?,
        destinations: SharedSetupV2DestinationSnapshots? = nil,
        schedules: [ScheduledExportEntry] = [],
        preservedAndroid: [UUID: SharedSetupV2.AndroidExtension] = [:]
    ) throws -> SharedSetupV2 {
        let resolvedDestinations = destinations ?? SharedSetupV2DestinationSnapshots()
        return try SharedSetupV2Mapper.exportDocument(
            profiles: profiles,
            activeProfileID: activeProfileID,
            destinations: resolvedDestinations,
            scheduledEntries: schedules,
            registry: fixtureRegistry(),
            appVersion: "2.0-synthetic",
            preservedAndroidExtensions: preservedAndroid,
            calendar: utcCalendar()
        )
    }

    private func makeProfile(
        id: UUID,
        name: String,
        policy: AppleExportDetailPolicy = .summary,
        enabledNativeIDs: Set<String> = [],
        individualNative: [String: MetricTrackingConfig] = [:],
        generateRangeSummary: Bool = false,
        target: ExportTargetSelection = .localIPhoneFolder,
        folderVaultID: UUID? = nil,
        apiEndpointID: UUID? = nil
    ) -> ExportProfile {
        let settings = AdvancedExportSettings(userDefaults: isolatedDefaults())
        settings.detailPolicy = policy
        settings.metricSelection.enabledMetrics = enabledNativeIDs
        settings.individualTracking.metricConfigs = individualNative
        settings.generateRangeSummary = generateRangeSummary
        var snapshot = ExportSettingsSnapshot.from(settings)
        snapshot.healthSubfolder = "must-not-be-shared"
        return ExportProfile(
            id: id,
            name: name,
            settings: snapshot,
            target: target,
            folderVaultID: folderVaultID,
            apiEndpointID: apiEndpointID,
            createdAt: fixedDate(year: 2036, month: 6, day: 7),
            updatedAt: fixedDate(year: 2037, month: 7, day: 8),
            isMigrationDefault: true
        )
    }

    private func fixtureRegistry() -> SharedSetupMetricRegistry {
        SharedSetupMetricRegistry(
            version: 1,
            sha256: String(repeating: "a", count: 64),
            semanticToApple: [
                "active_energy": "active_energy",
                "heart_rate_avg": "heart_rate_avg",
                "hrv": "hrv",
                "steps": "steps"
            ],
            semanticToAndroid: [
                "active_energy": "active_calories",
                "heart_rate_avg": "avg_hr",
                "steps": "steps",
                "android.hrv_rmssd": "hrv"
            ],
            equivalence: [
                "active_energy": .mappedAlias,
                "heart_rate_avg": .mappedAlias,
                "hrv": .platformExactOrUnavailable,
                "steps": .platformExactOrUnavailable,
                "android.hrv_rmssd": .platformDistinct
            ]
        )
    }

    private func syntheticAndroidExtension() -> SharedSetupV2.AndroidExtension {
        .init(
            extensionVersion: 2,
            export: .init(
                mode: .rawSnapshot,
                legacyPrimaryFormat: .markdown,
                compatibilityProfile: .analyticalV5,
                includeLegacyAliases: true,
                includeAndroidNativeFields: true,
                legacyDataTypes: .init(
                    sleep: true,
                    activity: true,
                    heart: true,
                    vitals: true,
                    body: true,
                    nutrition: true,
                    mobility: true,
                    reproductiveHealth: true,
                    mindfulness: true,
                    workouts: true,
                    plannedWorkouts: true,
                    medicalResources: true
                ),
                subfolder: "health",
                folderOrganization: .byYearMonth,
                rawSnapshot: .init(
                    format: .ndjson,
                    scope: .allAuthorizedSupportedData,
                    includeExerciseRoutes: true,
                    pageSize: 500
                )
            )
        )
    }

    private func assertInvalid(
        _ document: SharedSetupV2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try SharedSetupV2Codec.encode(document),
            file: file,
            line: line
        )
    }

    private func profileID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!
    }

    private func fixedDate(year: Int, month: Int, day: Int) -> Date {
        utcCalendar().date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func jsonData(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "SharedSetupV2CodecMapperTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func v1FixtureURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(
                "packages/contracts/shared-setup/v1/fixtures/shared-setup-v1.json"
            )
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw XCTSkip("Could not locate the canonical Shared Setup v1 fixture")
    }

    private func sharedSetupV2FixtureDirectory() -> URL? {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(
                "packages/contracts/shared-setup/v2/fixtures",
                isDirectory: true
            )
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(
                atPath: candidate.path,
                isDirectory: &isDirectory
            ), isDirectory.boolValue {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }
}
