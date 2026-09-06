import XCTest
@testable import HealthMd

/// Gateway destination validation, redaction, persistence, and readiness —
/// mirroring the API-endpoint destination test precedents.
final class AgentDataGatewayDestinationTests: XCTestCase {

    // MARK: - Endpoint validation

    func testNormalizedEndpointStringAcceptsValidHTTPAndHTTPS() {
        for value in [
            "http://127.0.0.1:8791",
            "https://gateway.example.com",
            "https://gateway.example.com/base",
            "HTTPS://Example.COM",
            "http://localhost:8791/",
        ] {
            XCTAssertNotNil(
                AgentDataGatewayEndpoint.normalizedEndpointString(value),
                "expected valid: \(value)"
            )
        }
    }

    func testNormalizedEndpointStringRejectsInvalidValues() {
        for value in [
            "",
            "   ",
            "gateway.example.com",
            "ftp://gateway.example.com",
            "https://",
            "https:///path",
            "https://gateway.example.com\ntoken",
            "https://user:pass@gateway.example.com",
            "https://gateway.example.com#fragment",
            "not a url 💥",
        ] {
            XCTAssertNil(
                AgentDataGatewayEndpoint.normalizedEndpointString(value),
                "expected invalid: \(value)"
            )
        }
    }

    func testIsConfiguredAndDisplayName() {
        XCTAssertFalse(AgentDataGatewayEndpoint.isConfigured(""))
        XCTAssertTrue(AgentDataGatewayEndpoint.isConfigured("https://gateway.example.com"))
        XCTAssertEqual(
            AgentDataGatewayEndpoint.displayName("https://gateway.example.com:8791/base"),
            "gateway.example.com"
        )
        XCTAssertEqual(
            AgentDataGatewayEndpoint.displayName(""),
            "Configure gateway"
        )
    }

    func testRedactedDescriptionStripsQueryAndFailsClosedOnUserInfoAndFragments() {
        XCTAssertEqual(
            AgentDataGatewayEndpoint.redactedDescription(
                "https://gateway.example.com:8791/base?token=hunter2"
            ),
            "https://gateway.example.com:8791/base"
        )
        // Userinfo- and fragment-bearing URLs never validate (twin parity
        // with the Android endpoint helper), so redaction fails closed to
        // the fallback rather than echoing credential-bearing input.
        XCTAssertEqual(
            AgentDataGatewayEndpoint.redactedDescription(
                "https://user:secret@gateway.example.com:8791/base"
            ),
            "No gateway configured"
        )
        XCTAssertEqual(
            AgentDataGatewayEndpoint.redactedDescription(
                "https://gateway.example.com/base#fragment"
            ),
            "No gateway configured"
        )
        XCTAssertEqual(
            AgentDataGatewayEndpoint.redactedDescription("not-a-url"),
            "No gateway configured"
        )
        XCTAssertEqual(
            AgentDataGatewayEndpoint.redactedDescription(
                "not-a-url",
                fallback: "Agent Data gateway"
            ),
            "Agent Data gateway"
        )
    }

    // MARK: - Destination snapshot

    func testDestinationSnapshotAppendsFrozenIngestPath() throws {
        let snapshot = try XCTUnwrap(
            AgentDataGatewayDestinationSnapshot(endpointURLString: "https://gateway.example.com")
        )
        XCTAssertEqual(snapshot.ingestURL.absoluteString, "https://gateway.example.com/v1/ingest")
        XCTAssertEqual(snapshot.displayName, "gateway.example.com")
        XCTAssertEqual(
            snapshot.redactedEndpointDescription,
            "https://gateway.example.com"
        )

        let withBase = try XCTUnwrap(
            AgentDataGatewayDestinationSnapshot(endpointURLString: "https://host.example/base/")
        )
        XCTAssertEqual(withBase.ingestURL.absoluteString, "https://host.example/base/v1/ingest")

        let withPort = try XCTUnwrap(
            AgentDataGatewayDestinationSnapshot(endpointURLString: "http://127.0.0.1:8791")
        )
        XCTAssertEqual(withPort.ingestURL.absoluteString, "http://127.0.0.1:8791/v1/ingest")

        XCTAssertNil(
            AgentDataGatewayDestinationSnapshot(endpointURLString: "ftp://host")
        )
        XCTAssertNil(
            AgentDataGatewayDestinationSnapshot(endpointURLString: "")
        )
    }

    // MARK: - Readiness

    func testReadinessMirrorsAPIEndpointSemantics() {
        // Gateway requires a selected format, no daily-notes-only, and a
        // configured endpoint — mirroring the API destination.
        XCTAssertTrue(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            target: .agentDataGateway,
            hasLocalFolder: false,
            canExportToConnectedMac: false,
            agentDataGatewayConfigured: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            target: .agentDataGateway,
            hasLocalFolder: false,
            canExportToConnectedMac: false,
            agentDataGatewayConfigured: false
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: false,
            target: .agentDataGateway,
            hasLocalFolder: false,
            canExportToConnectedMac: false,
            agentDataGatewayConfigured: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: true,
            hasSelectedFormat: true,
            dailyNotesOnlyModeEnabled: true,
            target: .agentDataGateway,
            hasLocalFolder: false,
            canExportToConnectedMac: false,
            agentDataGatewayConfigured: true
        ))
        XCTAssertFalse(ExportTargetReadiness.canExport(
            isHealthKitAuthorized: false,
            hasSelectedFormat: true,
            target: .agentDataGateway,
            hasLocalFolder: false,
            canExportToConnectedMac: false,
            agentDataGatewayConfigured: true
        ))
    }

    func testTargetMetadata() {
        XCTAssertEqual(
            ExportTargetSelection.agentDataGateway.title,
            "Agent Data gateway"
        )
        XCTAssertTrue(ExportTargetSelection.agentDataGateway.requiresNetworkForScheduledExport)
        XCTAssertEqual(
            ExportTargetSelection.agentDataGateway.rawValue,
            "agentDataGateway"
        )
    }

    // MARK: - Persistence

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "AgentDataGatewayDestinationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testGatewayCRUDPersistsAndReloads() {
        let defaults = makeIsolatedDefaults()
        let store = ProfileDestinationStore(userDefaults: defaults)

        XCTAssertTrue(store.agentDataGateways.isEmpty)

        let first = store.upsertAgentDataGateway(
            name: "Home gateway",
            endpointURLString: "https://gateway.example.com"
        )
        XCTAssertEqual(store.agentDataGateways.count, 1)
        XCTAssertEqual(store.agentDataGateways.first?.name, "Home gateway")

        // Re-entering the same URL (any casing/whitespace form) reuses the row.
        let again = store.upsertAgentDataGateway(
            name: "Renamed",
            endpointURLString: "  https://GATEWAY.example.com  "
        )
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(store.agentDataGateways.count, 1)
        XCTAssertEqual(store.agentDataGateways.first?.name, "Renamed")
        XCTAssertEqual(store.agentDataGateways.first?.endpointURLString, "https://GATEWAY.example.com")

        // A distinct URL creates a second row.
        let second = store.upsertAgentDataGateway(
            name: "LAN gateway",
            endpointURLString: "http://127.0.0.1:8791"
        )
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(store.agentDataGateways.count, 2)

        // A fresh store instance reloads the persisted rows.
        let reloaded = ProfileDestinationStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.agentDataGateways.count, 2)
        XCTAssertEqual(
            reloaded.agentDataGateway(id: second.id)?.endpointURLString,
            "http://127.0.0.1:8791"
        )
        XCTAssertNil(reloaded.agentDataGateway(id: UUID()))

        // Deletion removes the row; bindings resolve to nil.
        reloaded.deleteAgentDataGateway(id: first.id)
        XCTAssertNil(reloaded.agentDataGateway(id: first.id))
        XCTAssertEqual(reloaded.agentDataGateways.count, 1)
    }

    func testProfileGatewayBindingRoundTripsInDestinationStore() throws {
        let defaults = makeIsolatedDefaults()
        let profileStore = ExportProfileStore(
            userDefaults: defaults,
            now: { Date(timeIntervalSince1970: 0) }
        )
        let destinationStore = ProfileDestinationStore(userDefaults: defaults)

        let gateway = destinationStore.upsertAgentDataGateway(
            name: "Home",
            endpointURLString: "https://gateway.example.com"
        )
        let other = destinationStore.upsertAgentDataGateway(
            name: "LAN",
            endpointURLString: "http://127.0.0.1:8791"
        )
        let profile = profileStore.add(
            name: "Gateway profile",
            settings: ExportSettingsSnapshot.from(AdvancedExportSettings(userDefaults: makeIsolatedDefaults())),
            target: .agentDataGateway
        )

        // The binding is native destination-store state; the ExportProfile
        // payload is unchanged.
        XCTAssertNil(destinationStore.agentDataGatewayBinding(profileID: profile.id))
        destinationStore.setAgentDataGatewayBinding(profileID: profile.id, gatewayID: gateway.id)
        XCTAssertEqual(destinationStore.agentDataGatewayBinding(profileID: profile.id), gateway.id)
        XCTAssertEqual(
            destinationStore.agentDataGateway(id: destinationStore.agentDataGatewayBinding(profileID: profile.id))?.name,
            "Home"
        )

        // Rebinding swaps the referenced row; unbinding removes the entry.
        destinationStore.setAgentDataGatewayBinding(profileID: profile.id, gatewayID: other.id)
        XCTAssertEqual(destinationStore.agentDataGatewayBinding(profileID: profile.id), other.id)
        destinationStore.setAgentDataGatewayBinding(profileID: profile.id, gatewayID: nil)
        XCTAssertNil(destinationStore.agentDataGatewayBinding(profileID: profile.id))
        destinationStore.setAgentDataGatewayBinding(profileID: profile.id, gatewayID: gateway.id)

        // A fresh store instance reloads the persisted binding.
        let reloaded = ProfileDestinationStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.agentDataGatewayBinding(profileID: profile.id), gateway.id)

        // Deleting a gateway removes its bindings.
        reloaded.deleteAgentDataGateway(id: gateway.id)
        XCTAssertNil(reloaded.agentDataGatewayBinding(profileID: profile.id))
    }

    // MARK: - Shared setup exclusion

    #if os(iOS)
    @MainActor
    func testSharedSetupExportContextExcludesGatewayProfiles() {
        let settings = ExportSettingsSnapshot.from(
            AdvancedExportSettings(userDefaults: makeIsolatedDefaults())
        )
        let folderProfile = ExportProfile(
            name: "Folder",
            settings: settings,
            target: .localIPhoneFolder
        )
        let gatewayProfile = ExportProfile(
            name: "Gateway",
            settings: settings,
            target: .agentDataGateway
        )
        let gatewayEntry = ScheduledExportEntry(
            profileID: gatewayProfile.id,
            isEnabled: true
        )

        let context = SharedSetupV2ExportContext(
            profiles: [folderProfile, gatewayProfile],
            activeProfileID: gatewayProfile.id,
            destinationVaults: [],
            destinationAPIEndpoints: [],
            scheduledEntries: [gatewayEntry],
            preservedAndroidExtensions: [:]
        )

        // The v2 document has no gateway destination kind; gateway profiles
        // never participate in shared setup bundles and nothing is
        // approximated as another destination.
        XCTAssertEqual(context.profiles.map(\.name), ["Folder"])
        XCTAssertEqual(context.excludedAgentDataGatewayProfileCount, 1)
        XCTAssertNil(context.activeProfileID)
        XCTAssertTrue(context.scheduledEntries.isEmpty)
        XCTAssertTrue(context.preservedAndroidExtensions.isEmpty)
    }
    #endif

    // MARK: - Live settings

    @MainActor
    func testLiveSettingsPersistAndValidate() {
        let defaults = makeIsolatedDefaults()
        let settings = AgentDataGatewaySettings(userDefaults: defaults)

        XCTAssertFalse(settings.isConfigured)
        XCTAssertNil(settings.destinationSnapshot)

        settings.endpointURLString = "https://gateway.example.com/base"
        XCTAssertTrue(settings.isConfigured)
        let snapshot = settings.destinationSnapshot
        XCTAssertEqual(snapshot?.ingestURL.absoluteString, "https://gateway.example.com/base/v1/ingest")
        XCTAssertEqual(settings.displayName, "gateway.example.com")

        // A fresh instance reads the persisted value.
        let reread = AgentDataGatewaySettings(userDefaults: defaults)
        XCTAssertEqual(reread.endpointURLString, "https://gateway.example.com/base")

        // Invalid URLs never produce a destination snapshot.
        reread.endpointURLString = "not-a-url"
        XCTAssertFalse(reread.isConfigured)
        XCTAssertNil(reread.destinationSnapshot)
    }
}
