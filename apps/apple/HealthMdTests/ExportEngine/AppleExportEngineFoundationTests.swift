import Foundation
import HealthMdCoreRust
import XCTest
@testable import HealthMd

@MainActor
final class AppleExportEngineFoundationTests: XCTestCase {
    func testUnknownModesAndMissingPersistedPinsFailClosedToLegacy() throws {
        XCTAssertEqual(try JSONDecoder().decode(ExportEngineMode.self, from: Data(#""rust""#.utf8)), .rust)
        XCTAssertThrowsError(
            try JSONDecoder().decode(ExportEngineMode.self, from: Data(#""future""#.utf8))
        )
        XCTAssertEqual(ExportEngineMode(persistedValue: "future"), .legacy)
        XCTAssertEqual(ExportEngineMode(persistedValue: nil), .legacy)

        let context = try coreContext(engine: .shadow)
        let encodedPin = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(context.pin)) as? [String: Any]
        )
        for invalidEngine in ["future-engine", "legacy"] {
            var invalidPin = encodedPin
            invalidPin["engine"] = invalidEngine
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    AppleExportEnginePin.self,
                    from: try JSONSerialization.data(withJSONObject: invalidPin)
                )
            )
        }
        for (key, value) in [
            ("registry_sha256", "ABC" as Any),
            ("calendar_time_zone", "+05:00" as Any),
            ("core_api_version", 0 as Any),
            ("core_source_revision", "revision\u{0000}with-control" as Any),
        ] {
            var invalidPin = encodedPin
            invalidPin[key] = value
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    AppleExportEnginePin.self,
                    from: try JSONSerialization.data(withJSONObject: invalidPin)
                )
            )
        }

        let resolver = AppleExportEnginePolicyResolver(
            injectedOverride: "rust",
            userDefaults: nil,
            environment: [:]
        )
        XCTAssertEqual(
            resolver.modeForPersistedOperation(
                pin: nil,
                profile: .appleHealthDataV8,
                buildInfo: context.buildInfo,
                registrySnapshot: context.registry
            ),
            .legacy
        )
        XCTAssertEqual(
            resolver.modeForNewOperation(
                profile: .appleHealthDataV8,
                buildInfo: context.buildInfo,
                registrySnapshot: context.registry
            ),
            .rust
        )
        var incompatibleBuild = context.buildInfo
        incompatibleBuild.coreApiVersion += 1
        XCTAssertEqual(
            resolver.modeForNewOperation(
                profile: .appleHealthDataV8,
                buildInfo: incompatibleBuild,
                registrySnapshot: context.registry
            ),
            .legacy
        )
        XCTAssertEqual(
            resolver.modeForPersistedOperation(
                pin: context.pin,
                profile: .appleHealthDataV8,
                buildInfo: incompatibleBuild,
                registrySnapshot: context.registry
            ),
            .legacy
        )

        let unknownResolver = AppleExportEnginePolicyResolver(
            injectedOverride: "unknown",
            userDefaults: nil,
            environment: [:]
        )
        XCTAssertEqual(
            unknownResolver.modeForNewOperation(
                profile: .appleHealthDataV8,
                buildInfo: context.buildInfo,
                registrySnapshot: context.registry
            ),
            .legacy
        )

        let suiteName = "healthmd.tests.export-engine.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("shadow", forKey: AppleExportEnginePolicyResolver.userDefaultsKey)
        let defaultsResolver = AppleExportEnginePolicyResolver(
            userDefaults: defaults,
            environment: [AppleExportEnginePolicyResolver.environmentKey: "rust"]
        )
        XCTAssertEqual(
            defaultsResolver.modeForNewOperation(
                profile: .appleHealthDataV8,
                buildInfo: context.buildInfo,
                registrySnapshot: context.registry
            ),
            .shadow
        )
        defaults.removeObject(forKey: AppleExportEnginePolicyResolver.userDefaultsKey)
        let environmentResolver = AppleExportEnginePolicyResolver(
            userDefaults: defaults,
            environment: [AppleExportEnginePolicyResolver.environmentKey: "rust"]
        )
        XCTAssertEqual(
            environmentResolver.modeForNewOperation(
                profile: .appleHealthDataV8,
                buildInfo: context.buildInfo,
                registrySnapshot: context.registry
            ),
            .rust
        )
        XCTAssertEqual(
            resolver.modeForNewOperation(
                profile: .androidFrozenV4,
                buildInfo: context.buildInfo,
                registrySnapshot: context.registry
            ),
            .legacy
        )
    }

    func testEnginePinRoundTripsAndRejectsIncompatiblePackagedContract() throws {
        let context = try coreContext(engine: .rust, timeZone: "America/Los_Angeles")
        let data = try JSONEncoder().encode(context.pin)
        let decoded = try JSONDecoder().decode(AppleExportEnginePin.self, from: data)

        XCTAssertEqual(decoded, context.pin)
        XCTAssertNoThrow(try decoded.validateCompatibility(
            buildInfo: context.buildInfo,
            registrySnapshot: context.registry
        ))
        XCTAssertTrue(decoded.isCompatible(
            buildInfo: context.buildInfo,
            registrySnapshot: context.registry
        ))

        XCTAssertTrue(decoded.isRangeCompatible(buildInfo: context.buildInfo))
        var oldRangeCore = context.buildInfo
        oldRangeCore.coreApiVersion = 3
        XCTAssertFalse(decoded.isRangeCompatible(buildInfo: oldRangeCore))
        XCTAssertThrowsError(try decoded.validateRangeCompatibility(buildInfo: oldRangeCore)) { error in
            XCTAssertEqual(
                error as? AppleExportEnginePin.CompatibilityError,
                .incompatibleSemanticProfile
            )
        }

        var incompatibleBuild = context.buildInfo
        incompatibleBuild.renderProfileRevision += 1
        XCTAssertFalse(decoded.isCompatible(
            buildInfo: incompatibleBuild,
            registrySnapshot: context.registry
        ))
        XCTAssertThrowsError(try decoded.validateCompatibility(
            buildInfo: incompatibleBuild,
            registrySnapshot: context.registry
        )) { error in
            XCTAssertEqual(
                error as? AppleExportEnginePin.CompatibilityError,
                .incompatibleRenderProfile
            )
        }

        var compatibleRollbackSource = context.buildInfo
        compatibleRollbackSource.coreSourceRevision += "-other"
        XCTAssertTrue(decoded.isCompatible(
            buildInfo: compatibleRollbackSource,
            registrySnapshot: context.registry
        ), "Source revision is provenance; version/profile pins govern resume compatibility.")
        var incompatibleRegistry = context.registry
        incompatibleRegistry.registrySha256 = String(repeating: "0", count: 64)
        XCTAssertFalse(decoded.isCompatible(
            buildInfo: context.buildInfo,
            registrySnapshot: incompatibleRegistry
        ))

        XCTAssertThrowsError(try AppleExportEnginePin(
            engine: .shadow,
            calendarTimeZoneIdentifier: "+05:00",
            buildInfo: context.buildInfo,
            registrySnapshot: context.registry
        )) { error in
            XCTAssertEqual(
                error as? AppleExportEnginePin.CompatibilityError,
                .invalidCalendarTimeZone
            )
        }
    }

    func testCorePlanConversionPreservesOrderAndRejectsInvalidIntegrityOrPlanMetadata() throws {
        let context = try coreContext(engine: .shadow)
        let firstData = Data("first\n".utf8)
        let secondData = Data([0, 1, 2, 3])
        let first = coreArtifact(
            path: "Health/first.md",
            mediaType: "text/markdown",
            writeMode: .markdownMerge,
            data: firstData
        )
        let second = coreArtifact(
            path: "api/batch.json",
            mediaType: "application/json",
            writeMode: .apiPost,
            data: secondData
        )
        let corePlan = CoreArtifactPlan(
            schema: NativeExportArtifactPlan.schema,
            artifactPlanVersion: context.pin.artifactPlanVersion,
            requestId: "request",
            sessionId: "session",
            profile: .appleHealthDataV8,
            items: [first, second],
            totalByteCount: UInt64(firstData.count + secondData.count)
        )

        let converted = try CoreArtifactPlanConverter.convert(corePlan, pin: context.pin)
        XCTAssertEqual(converted.artifacts.map(\.relativePath), ["Health/first.md", "api/batch.json"])
        XCTAssertEqual(converted.artifacts.map(\.role), [.file, .apiRequest])
        XCTAssertEqual(converted.artifacts.map(\.inlineData), [firstData, secondData])
        XCTAssertEqual(converted.totalByteCount, UInt64(firstData.count + secondData.count))

        let service = HealthMdCoreService()
        let stream = try service.plannedLosslessArtifactStream(
            mode: .rawBytes,
            artifact: CoreStreamArtifactConfig(
                requestId: "stream-request",
                sessionId: "stream-session",
                profile: .appleHealthDataV8,
                relativePath: "Health/stream.bin",
                mediaType: "application/octet-stream",
                writeMode: .overwrite
            )
        )
        let streamedPrefix = try stream.push(raw: Data([9, 8, 7]))
        let streamedFinish = try stream.finish()
        let streamedDescriptor = try XCTUnwrap(streamedFinish.descriptor.artifact)
        let streamedData = Data(streamedPrefix + streamedFinish.chunk)
        let rustGeneratedPlan = CoreArtifactPlan(
            schema: NativeExportArtifactPlan.schema,
            artifactPlanVersion: context.pin.artifactPlanVersion,
            requestId: "stream-request",
            sessionId: "stream-session",
            profile: .appleHealthDataV8,
            items: [CoreArtifactPlanItem(
                artifactId: streamedDescriptor.artifactId,
                relativePath: streamedDescriptor.relativePath,
                mediaType: streamedDescriptor.mediaType,
                writeMode: streamedDescriptor.writeMode,
                content: streamedData,
                byteCount: streamedDescriptor.byteCount,
                sha256: streamedDescriptor.sha256
            )],
            totalByteCount: streamedDescriptor.byteCount
        )
        let rustGeneratedConversion = try CoreArtifactPlanConverter.convert(
            rustGeneratedPlan,
            pin: context.pin
        )
        XCTAssertEqual(rustGeneratedConversion.artifacts.first?.inlineData, Data([9, 8, 7]))

        var invalidDigest = first
        invalidDigest.sha256 = String(repeating: "0", count: 64)
        let invalidDigestPlan = CoreArtifactPlan(
            schema: NativeExportArtifactPlan.schema,
            artifactPlanVersion: context.pin.artifactPlanVersion,
            requestId: "request",
            sessionId: "session",
            profile: .appleHealthDataV8,
            items: [invalidDigest],
            totalByteCount: invalidDigest.byteCount
        )
        XCTAssertThrowsError(try CoreArtifactPlanConverter.convert(invalidDigestPlan, pin: context.pin)) {
            XCTAssertEqual(
                $0 as? NativeExportArtifact.ValidationError,
                .contentDigestMismatch
            )
        }

        var invalidPath = first
        invalidPath.relativePath = "../private.md"
        let invalidPathPlan = CoreArtifactPlan(
            schema: NativeExportArtifactPlan.schema,
            artifactPlanVersion: context.pin.artifactPlanVersion,
            requestId: "request",
            sessionId: "session",
            profile: .appleHealthDataV8,
            items: [invalidPath],
            totalByteCount: invalidPath.byteCount
        )
        XCTAssertThrowsError(try CoreArtifactPlanConverter.convert(invalidPathPlan, pin: context.pin)) {
            XCTAssertEqual($0 as? NativeExportArtifact.ValidationError, .invalidRelativePath)
        }

        var invalidID = first
        invalidID.artifactId = String(repeating: "0", count: 64)
        let invalidIDPlan = CoreArtifactPlan(
            schema: NativeExportArtifactPlan.schema,
            artifactPlanVersion: context.pin.artifactPlanVersion,
            requestId: "request",
            sessionId: "session",
            profile: .appleHealthDataV8,
            items: [invalidID],
            totalByteCount: invalidID.byteCount
        )
        XCTAssertThrowsError(try CoreArtifactPlanConverter.convert(invalidIDPlan, pin: context.pin)) {
            XCTAssertEqual(
                $0 as? NativeExportArtifactPlan.ValidationError,
                .artifactIDMismatch
            )
        }

        var invalidVersion = corePlan
        invalidVersion.artifactPlanVersion += 1
        XCTAssertThrowsError(try CoreArtifactPlanConverter.convert(invalidVersion, pin: context.pin)) {
            XCTAssertEqual(
                $0 as? NativeExportArtifactPlan.ValidationError,
                .incompatibleArtifactPlanVersion
            )
        }
    }

    func testComparatorReportsEveryOrderedMismatchWithoutSensitiveValues() throws {
        let context = try coreContext(engine: .shadow)
        let nativeArtifact = try artifact(
            path: "Health/private-2026-07-25.md",
            mediaType: "text/markdown",
            writeMode: .overwrite,
            data: Data([1, 2, 3])
        )
        let native = try plan([nativeArtifact], pin: context.pin)

        let extra = try artifact(
            path: "Health/extra.md",
            mediaType: "text/markdown",
            writeMode: .overwrite,
            data: Data([4])
        )
        let countPlan = try plan([nativeArtifact, extra], pin: context.pin)
        XCTAssertEqual(
            Set(NativeExportPlanComparator.compare(
                native: native,
                rust: countPlan,
                pin: context.pin
            ).map(\.mismatchKind)),
            [.artifactCount]
        )

        let alternateRequestID = "alternate-request"
        let idArtifact = try artifact(
            requestID: alternateRequestID,
            path: nativeArtifact.relativePath,
            mediaType: nativeArtifact.mediaType,
            writeMode: nativeArtifact.writeMode,
            data: nativeArtifact.inlineData
        )
        let idPlan = try plan(
            [idArtifact],
            pin: context.pin,
            requestID: alternateRequestID
        )
        let pathPlan = try plan([try artifact(
            path: "Health/other.md",
            mediaType: nativeArtifact.mediaType,
            writeMode: nativeArtifact.writeMode,
            data: nativeArtifact.inlineData
        )], pin: context.pin)
        let mediaPlan = try plan([try artifact(
            path: nativeArtifact.relativePath,
            mediaType: "application/octet-stream",
            writeMode: nativeArtifact.writeMode,
            data: nativeArtifact.inlineData
        )], pin: context.pin)
        let writePlan = try plan([try artifact(
            path: nativeArtifact.relativePath,
            mediaType: nativeArtifact.mediaType,
            writeMode: .append,
            data: nativeArtifact.inlineData
        )], pin: context.pin)
        let lengthPlan = try plan([try artifact(
            path: nativeArtifact.relativePath,
            mediaType: nativeArtifact.mediaType,
            writeMode: nativeArtifact.writeMode,
            data: Data([1, 2, 3, 4])
        )], pin: context.pin)
        let bytePlan = try plan([try artifact(
            path: nativeArtifact.relativePath,
            mediaType: nativeArtifact.mediaType,
            writeMode: nativeArtifact.writeMode,
            data: Data([1, 2, 4])
        )], pin: context.pin)

        XCTAssertEqual(kinds(native: native, rust: idPlan, pin: context.pin), [.artifactID])
        XCTAssertEqual(
            kinds(native: native, rust: pathPlan, pin: context.pin),
            [.artifactID, .relativePath]
        )
        XCTAssertEqual(
            kinds(native: native, rust: mediaPlan, pin: context.pin),
            [.artifactID, .mediaType]
        )
        XCTAssertEqual(
            kinds(native: native, rust: writePlan, pin: context.pin),
            [.artifactID, .writeMode]
        )
        XCTAssertEqual(
            kinds(native: native, rust: lengthPlan, pin: context.pin),
            [.artifactID, .byteCount, .sha256, .bytes]
        )
        XCTAssertEqual(
            kinds(native: native, rust: bytePlan, pin: context.pin),
            [.artifactID, .sha256, .bytes]
        )

        let byteDiagnostic = try XCTUnwrap(NativeExportPlanComparator.compare(
            native: native,
            rust: bytePlan,
            pin: context.pin,
            options: NativeExportComparisonOptions(includeFirstDifferingByteOffset: true)
        ).first { $0.mismatchKind == .bytes })
        XCTAssertEqual(byteDiagnostic.firstDifferingByteOffset, 2)
        XCTAssertEqual(byteDiagnostic.artifactOrdinal, 0)
        XCTAssertEqual(byteDiagnostic.profile, AppleExportEnginePin.profileID)

        let diagnosticJSON = try XCTUnwrap(String(
            data: JSONEncoder().encode(byteDiagnostic),
            encoding: .utf8
        ))
        XCTAssertFalse(diagnosticJSON.contains(nativeArtifact.relativePath))
        XCTAssertFalse(diagnosticJSON.contains(nativeArtifact.mediaType))
        XCTAssertFalse(diagnosticJSON.contains("2026-07-25"))
        XCTAssertFalse(diagnosticJSON.contains("request"))
        XCTAssertFalse(diagnosticJSON.contains("AQID"))
    }

    func testShadowReturnsNativePlanEmitsHealthFreeMismatchAndNeverCommits() async throws {
        let context = try coreContext(engine: .shadow)
        let nativePlan = try plan([try artifact(
            path: "Health/day.md",
            mediaType: "text/markdown",
            writeMode: .overwrite,
            data: Data("native".utf8)
        )], pin: context.pin)
        let rustPlan = try plan([try artifact(
            path: "Health/day.md",
            mediaType: "text/markdown",
            writeMode: .overwrite,
            data: Data("rust".utf8)
        )], pin: context.pin)
        let native = NativeExportEngineSpy(plan: nativePlan)
        let rust = RustExportEngineSpy(plan: rustPlan)
        let recorder = ShadowDiagnosticRecorder()
        let shadow = ShadowExportEngine(
            native: native,
            rust: rust,
            diagnosticSink: { diagnostic in
                await recorder.record(diagnostic)
            }
        )
        let input = ExportEngineOperationInput(pin: context.pin, payload: ShadowTestPayload(value: 42))

        let returned = try await shadow.render(input)
        XCTAssertEqual(returned, nativePlan)
        let nativeValues = await native.renderedValues()
        let rustValues = await rust.renderedValues()
        let nativeCommitCount = await native.commitCount()
        let rustCommitCount = await rust.commitCount()
        let diagnostics = await recorder.values()
        XCTAssertEqual(nativeValues, [42])
        XCTAssertEqual(rustValues, [42])
        XCTAssertEqual(nativeCommitCount, 0)
        XCTAssertEqual(rustCommitCount, 0)
        XCTAssertFalse(diagnostics.isEmpty)
        guard case .comparisonCompleted(let completed) = diagnostics.first else {
            return XCTFail("Expected one comparison denominator event before mismatch details")
        }
        XCTAssertFalse(completed.matches)
        XCTAssertEqual(completed.mismatchCount, UInt32(diagnostics.count - 1))
        XCTAssertTrue(diagnostics.dropFirst().allSatisfy {
            if case .planMismatch = $0 { return true }
            return false
        })

        let failureRecorder = ShadowDiagnosticRecorder()
        let failingRust = RustExportEngineSpy(plan: rustPlan, shouldFail: true)
        let failureShadow = ShadowExportEngine(
            native: native,
            rust: failingRust,
            diagnosticSink: { diagnostic in
                await failureRecorder.record(diagnostic)
            }
        )
        let failureReturned = try await failureShadow.render(input)
        let failureDiagnostics = await failureRecorder.values()
        let failingRustCommitCount = await failingRust.commitCount()
        XCTAssertEqual(failureReturned, nativePlan)
        XCTAssertEqual(failingRustCommitCount, 0)
        XCTAssertEqual(failureDiagnostics.count, 1)
        XCTAssertTrue(failureDiagnostics.allSatisfy {
            if case .rustRenderFailed = $0 { return true }
            return false
        })
    }

    func testShadowEvidenceRecorderPersistsOnlyBoundedHealthFreeCounters() async throws {
        let suiteName = "ShadowExportEvidenceRecorderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let storageKey = "evidence"
        let recorder = ShadowExportEvidenceRecorder(
            userDefaults: defaults,
            storageKey: storageKey
        )
        let completed = ShadowExportComparisonCompletedDiagnostic(
            profile: AppleExportEnginePin.profileID,
            semanticProfileRevision: 1,
            renderProfileRevision: 2,
            matches: false,
            mismatchCount: 1
        )
        let mismatch = NativeExportPlanMismatchDiagnostic(
            profile: AppleExportEnginePin.profileID,
            semanticProfileRevision: 1,
            renderProfileRevision: 2,
            artifactOrdinal: 0,
            mismatchKind: .bytes,
            nativeLength: 10,
            rustLength: 11,
            nativeSHA256: String(repeating: "a", count: 64),
            rustSHA256: String(repeating: "b", count: 64),
            firstDifferingByteOffset: 3
        )
        let failure = ShadowExportFailureDiagnostic(
            profile: AppleExportEnginePin.profileID,
            semanticProfileRevision: 1,
            renderProfileRevision: 2,
            kind: .rustRenderFailed
        )

        await recorder.record(.comparisonCompleted(completed))
        await recorder.record(.planMismatch(mismatch))
        await recorder.record(.rustRenderFailed(failure))

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.profiles.count, 1)
        let profile = try XCTUnwrap(snapshot.profiles.first)
        XCTAssertEqual(profile.comparisonCount, 1)
        XCTAssertEqual(profile.exactMatchCount, 0)
        XCTAssertEqual(profile.mismatchOperationCount, 1)
        XCTAssertEqual(profile.reportedMismatchCount, 1)
        XCTAssertEqual(profile.rustFailureCount, 1)
        XCTAssertEqual(profile.mismatchDimensions, ["bytes": 1])
        XCTAssertEqual(profile.rustFailureCodes, ["rust_render_failed": 1])
        let persisted = try XCTUnwrap(defaults.data(forKey: storageKey))
        let text = String(decoding: persisted, as: UTF8.self)
        XCTAssertFalse(text.contains(String(repeating: "a", count: 64)))
        XCTAssertFalse(text.contains(String(repeating: "b", count: 64)))
        XCTAssertFalse(text.contains("artifactOrdinal"))
        XCTAssertFalse(text.contains("firstDifferingByteOffset"))

        defaults.set(Data("corrupt-private-state".utf8), forKey: storageKey)
        let corruptSnapshot = await recorder.snapshot()
        XCTAssertEqual(corruptSnapshot, .empty)
        await recorder.record(.comparisonCompleted(ShadowExportComparisonCompletedDiagnostic(
            profile: AppleExportEnginePin.profileID,
            semanticProfileRevision: 1,
            renderProfileRevision: 2,
            matches: true,
            mismatchCount: 0
        )))
        let recoveredSnapshot = await recorder.snapshot()
        XCTAssertEqual(recoveredSnapshot.profiles.first?.exactMatchCount, 1)
        await recorder.reset()
        let resetSnapshot = await recorder.snapshot()
        XCTAssertEqual(resetSnapshot, .empty)
    }

    func testShadowEvidenceRecorderCountersSaturateWithoutOverflow() async throws {
        let suiteName = "ShadowExportEvidenceRecorderSaturation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let storageKey = "evidence"
        let saturated = ShadowExportEvidenceSnapshot(profiles: [
            ShadowExportProfileEvidence(
                profile: AppleExportEnginePin.profileID,
                semanticProfileRevision: 1,
                renderProfileRevision: 2,
                comparisonCount: .max,
                exactMatchCount: .max
            )
        ])
        let encoder = JSONEncoder()
        defaults.set(try encoder.encode(saturated), forKey: storageKey)
        let recorder = ShadowExportEvidenceRecorder(userDefaults: defaults, storageKey: storageKey)

        await recorder.record(.comparisonCompleted(ShadowExportComparisonCompletedDiagnostic(
            profile: AppleExportEnginePin.profileID,
            semanticProfileRevision: 1,
            renderProfileRevision: 2,
            matches: true,
            mismatchCount: 0
        )))

        let snapshot = await recorder.snapshot()
        XCTAssertEqual(snapshot.profiles.count, 1)
        let profile = try XCTUnwrap(snapshot.profiles.first)
        XCTAssertEqual(profile.comparisonCount, .max)
        XCTAssertEqual(profile.exactMatchCount, .max)
    }

    func testCommitBarrierAllowsOnlyOneWayTransitionsAndLocksAuthorityAtCommit() async throws {
        let barrier = ExportCommitBarrier()
        var barrierState = await barrier.state
        XCTAssertEqual(barrierState, .planned)
        try await barrier.authorizeAuthorityFallback()
        try await barrier.authorizeRerender()

        try await barrier.transition(to: .materialized)
        barrierState = await barrier.state
        XCTAssertEqual(barrierState, .materialized)
        try await barrier.authorizeAuthorityFallback()
        try await barrier.authorizeRerender()

        try await barrier.transition(to: .committing)
        barrierState = await barrier.state
        XCTAssertEqual(barrierState, .committing)
        await assertBarrierError(.authorityLocked) {
            try await barrier.authorizeAuthorityFallback()
        }
        await assertBarrierError(.authorityLocked) {
            try await barrier.authorizeRerender()
        }
        await assertBarrierError(.invalidTransition) {
            try await barrier.transition(to: .materialized)
        }

        try await barrier.transition(to: .completed)
        barrierState = await barrier.state
        XCTAssertEqual(barrierState, .completed)
        await assertBarrierError(.authorityLocked) {
            try await barrier.authorizeAuthorityFallback()
        }
        await assertBarrierError(.invalidTransition) {
            try await barrier.transition(to: .failed)
        }

        let failingBarrier = ExportCommitBarrier()
        try await failingBarrier.transition(to: .failed)
        let failingBarrierState = await failingBarrier.state
        XCTAssertEqual(failingBarrierState, .failed)
        await assertBarrierError(.authorityLocked) {
            try await failingBarrier.authorizeRerender()
        }
    }

    private struct CoreContext {
        let buildInfo: CoreBuildInfo
        let registry: CoreMetricRegistrySnapshot
        let pin: AppleExportEnginePin
    }

    private func coreContext(
        engine: ExportEngineMode,
        timeZone: String = "UTC"
    ) throws -> CoreContext {
        let service = HealthMdCoreService()
        let buildInfo = try service.buildInfo()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let pin = try AppleExportEnginePin(
            engine: engine,
            calendarTimeZoneIdentifier: timeZone,
            buildInfo: buildInfo,
            registrySnapshot: registry
        )
        return CoreContext(buildInfo: buildInfo, registry: registry, pin: pin)
    }

    private func coreArtifact(
        requestID: String = "request",
        sessionID: String = "session",
        path: String,
        mediaType: String,
        writeMode: CoreArtifactWriteMode,
        data: Data
    ) -> CoreArtifactPlanItem {
        let sha256 = NativeExportArtifact.sha256(of: data)
        return CoreArtifactPlanItem(
            artifactId: NativeExportArtifactPlan.artifactID(
                requestID: requestID,
                sessionID: sessionID,
                profile: .appleHealthDataV8,
                relativePath: path,
                mediaType: mediaType,
                writeMode: writeMode,
                contentSHA256: sha256
            ),
            relativePath: path,
            mediaType: mediaType,
            writeMode: writeMode,
            content: data,
            byteCount: UInt64(data.count),
            sha256: sha256
        )
    }

    private func artifact(
        requestID: String = "request",
        sessionID: String = "session",
        path: String,
        mediaType: String,
        writeMode: CoreArtifactWriteMode,
        data: Data
    ) throws -> NativeExportArtifact {
        let sha256 = NativeExportArtifact.sha256(of: data)
        return try NativeExportArtifact(
            role: NativeExportArtifactRole(writeMode: writeMode),
            id: NativeExportArtifactPlan.artifactID(
                requestID: requestID,
                sessionID: sessionID,
                profile: .appleHealthDataV8,
                relativePath: path,
                mediaType: mediaType,
                writeMode: writeMode,
                contentSHA256: sha256
            ),
            relativePath: path,
            mediaType: mediaType,
            writeMode: writeMode,
            inlineData: data,
            byteCount: UInt64(data.count),
            sha256: sha256
        )
    }

    private func plan(
        _ artifacts: [NativeExportArtifact],
        pin: AppleExportEnginePin,
        requestID: String = "request",
        sessionID: String = "session"
    ) throws -> NativeExportArtifactPlan {
        try NativeExportArtifactPlan(
            artifactPlanVersion: pin.artifactPlanVersion,
            requestID: requestID,
            sessionID: sessionID,
            profile: .appleHealthDataV8,
            artifacts: artifacts,
            totalByteCount: artifacts.reduce(0) { $0 + $1.byteCount },
            pin: pin
        )
    }

    private func kinds(
        native: NativeExportArtifactPlan,
        rust: NativeExportArtifactPlan,
        pin: AppleExportEnginePin
    ) -> Set<NativeExportPlanMismatchDiagnostic.Kind> {
        Set(NativeExportPlanComparator.compare(
            native: native,
            rust: rust,
            pin: pin
        ).map(\.mismatchKind))
    }

    private func assertBarrierError(
        _ expected: ExportCommitBarrier.BarrierError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected barrier error \(expected.rawValue)")
        } catch {
            XCTAssertEqual(error as? ExportCommitBarrier.BarrierError, expected)
        }
    }
}

private nonisolated struct ShadowTestPayload: Sendable {
    let value: Int
}

private actor NativeExportEngineSpy: NativeExportEngine {
    typealias Payload = ShadowTestPayload

    private let plan: NativeExportArtifactPlan
    private var values: [Int] = []
    private var commits = 0

    init(plan: NativeExportArtifactPlan) {
        self.plan = plan
    }

    func render(_ input: ExportEngineOperationInput<Payload>) async throws -> NativeExportArtifactPlan {
        values.append(input.payload.value)
        return plan
    }

    func commit() {
        commits += 1
    }

    func renderedValues() -> [Int] { values }
    func commitCount() -> Int { commits }
}

private actor RustExportEngineSpy: RustExportEngine {
    typealias Payload = ShadowTestPayload

    private enum TestError: Error {
        case expectedFailure
    }

    private let plan: NativeExportArtifactPlan
    private let shouldFail: Bool
    private var values: [Int] = []
    private var commits = 0

    init(plan: NativeExportArtifactPlan, shouldFail: Bool = false) {
        self.plan = plan
        self.shouldFail = shouldFail
    }

    func render(_ input: ExportEngineOperationInput<Payload>) async throws -> NativeExportArtifactPlan {
        values.append(input.payload.value)
        if shouldFail { throw TestError.expectedFailure }
        return plan
    }

    func commit() {
        commits += 1
    }

    func renderedValues() -> [Int] { values }
    func commitCount() -> Int { commits }
}

private actor ShadowDiagnosticRecorder {
    private var diagnostics: [ShadowExportDiagnostic] = []

    func record(_ diagnostic: ShadowExportDiagnostic) {
        diagnostics.append(diagnostic)
    }

    func values() -> [ShadowExportDiagnostic] { diagnostics }
}
