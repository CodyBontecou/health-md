# Release-status response excerpt provenance

These health-free illustrative projections were reviewed against source at
`b8fd904f4d299f5af4a22111d2fdccf829705ea7`. They are **not device captures**,
complete responses, new response schemas, or release qualification evidence.
The JSON contains only the fields used by the release-status page's examples.

| Projection | Actual producer / existing behavioral test |
| --- | --- |
| `healthmd.local_readiness/1` | `apps/apple/HealthMd/macOS/Managers/HealthMdAgentAPIService.swift`, `readinessResponse()`; `apps/apple/HealthMdTests/macOS/HealthMdAgentAPIServiceTests.swift`, `testReadinessReportsCacheAndIPhoneWithoutIdentityOrGrantChecks` sets revision `revision-1`, two dates, no connected peer, no refresh executor. The full response additionally contains `checks` and `next_actions`. |
| `healthmd.local_capabilities/1` | Same service, `capabilities()`; `testCapabilitiesAdvertiseDirectScopeAndNoCredentials` uses no refresh executor. Full output also contains contracts, limits, and operations. |
| `healthmd.direct_readiness/1` | `apps/cli/crates/healthmd-cli/src/mcp/direct_backend.rs`, Android branch of `status_value()`; `android_readiness_advertises_raw_without_claiming_typed_queries` sets foreground/protected data true, protocol 2, port 17647, no export in progress, and a supported raw product. Full output additionally includes message, products, active job, and wake status. The iPhone branch has different additional fields; this excerpt does not claim an iPhone protocol version. |
| `healthmd.mcp_capabilities/1` | `apps/cli/crates/healthmd-mcp/src/application.rs`, `capabilities_value()`; `DirectIphoneBackend::capabilities()` in `direct_backend.rs`; `SurfaceProfile::wire_name()` in `apps/cli/crates/healthmd-operations/src/model.rs`. Local-direct profile; full output includes caller-scoped operations and pairing/export flags, guidance, limits, and result fallbacks. |

Additional audited boundaries:

- Bundled MCP routes: `apps/apple/HealthMdCLI/Sources/HealthMdMCPCore/HealthMdMCPServer.swift`, `route(for:arguments:)` (`healthmd_doctor` and `healthmd_capabilities`).
- Portable unpaired doctor: `DirectIphoneBackend::doctor()` in `direct_backend.rs`.
- Control status and optional job `committed_bytes`: `apps/apple/HealthMd/macOS/Managers/HealthMdControlServer.swift`, `StatusResponse` / `ActiveExport`. Portable job progress/receipts also use `committed_bytes`; this is transfer progress, not encrypted-store size.
- Mac Settings: `apps/apple/HealthMd/macOS/Views/MacSettingsView.swift`, encrypted context days/range and retention controls, no byte total.
- Helper/package version is MCP initialization metadata (`serverInfo.version`), not a readiness/capabilities qualification field.

`test/release-status.test.mjs` parses real Markdown JSON examples, compares typed
objects with these reviewed projections, and exercises negative mutations for
invented fields (including false/null/zero), changed schemas, and fabricated
Android query parity. It also guards the scope/missingness/qualification prose.
It runs via `npm test` (`node --test`) in Website CI's existing validate job.
No source-grep assertion substitutes for a behavior test. Native runtime tests
above are provenance references, not newly executed evidence for this docs-only
change. If a producer changes, review this projection and the prose against that
producer; do not update both merely to silence CI.
