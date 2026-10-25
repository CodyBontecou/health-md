# Claim ledger: What local-first health-data architecture actually means

Verified: 2026-10-22
Verified by: Codex (agent)
Method: mixed

Native/CLI baseline: main `4da74b120e2858c29ee4a77aac0bb46810668974`.
Cloud reference: `7002922d634811b7b3b1c51663814724b4f89e99`.
This is a source-backed architecture review plus bounded public endpoint checks,
not a new Linux/Windows/Android/Tailscale physical release matrix or an audit of
all owner account operations. No private account or health data was accessed.

## Claims

- [x] **Apple and Android perform their platform health reads on the phone.**
  Traced to `apps/apple/HealthMd/Shared/Managers/HealthKitManager.swift` and
  `apps/android/app/src/main/java/com/healthmd/data/health/HealthConnectManager.kt`.
  Selected scope and absent/unsupported records remain explicit.
- [x] **The ordinary file export has no Health.md health-data server hop.**
  Traced to VaultManager/native export plans and Android's folder export path.
  The API target is a separately selected destination. Physical #182 local
  export and paired-Mac results provide executed evidence for the Apple path;
  no provider sync or Android native export was newly executed for this article.
- [x] **A user-selected sync provider controls its own copy.**
  The app writes through the selected folder/provider boundary; the article
  makes no availability, timing or security guarantee about a particular sync
  service. See the scoped provider-destination fact in verified-snippets.md.
- [x] **Direct pairing is authenticated/encrypted and supported operations differ by device.**
  Traced to `apps/cli/README.md`, client pairing/protocol code,
  `IPhoneDirectCLIService.swift`, Android direct services and shared protocol
  contracts. The article now explicitly limits typed MCP health queries to
  iPhone, names Android status/raw/file paths, and records the standalone
  package's alpha/full-release qualification boundary.
- [x] **Trust storage, file validation and spooling are separate from agent transcripts.**
  Traced to `apps/cli/crates/healthmd-client/src/credentials.rs` OsCredentialStore,
  `file_receiver.rs` existing-directory/symlink validation and durable spool,
  `raw_receiver.rs` private spool permissions, and `job.rs` response state.
  The article now allows explicitly queried values to enter an agent's
  transcript/provider systems; it makes no blanket no-data-to-agents claim.
- [x] **Job progress is intended to expose safe operational fields.**
  Traced to client job status and the public direct-protocol status/error
  structures. This is a schema/design boundary, not a claim that arbitrary
  operating-system errors or externally supplied files are safe to publish.
- [x] **The Mac is a destination/automation surface, while the phone remains the HealthKit source.**
  Traced to native export snapshots, Mac receiver and iPhone context/direct
  service. Physical #182 exported frozen phone-off settings to the Mac while
  its live preference was on, and checked the resulting files. This does not
  establish all background-wake/locked-device automation scenarios.
- [x] **Bundled Mac MCP and standalone portable CLI/MCP have separate qualification.**
  Traced to `apps/cli/README.md` and the Mac agent service. The article explicitly
  calls the standalone package alpha and avoids certifying unexecuted host,
  phone or transport combinations from one successful Mac workflow.
- [x] **Explicit API/provider destinations are separate from local export.**
  Traced to Apple's APIExportClient/APIEndpointExportRunner and Android's
  RawSnapshotApiClient/RawSnapshotExportOrchestrator/RawSnapshotValidator.
  Android requires HTTPS, disables redirects and validates/checksums its raw
  artifact. This does not make Android raw snapshots cloud-pilot compatible.
- [x] **The existing cloud pilot is owner-only, intentional-upload, unbacked and distinct from undeployed multi-user source.**
  Traced to the pinned cloud `docs/public-account-dashboard.md`,
  `docs/personal-tailnet-pilot.md`, account-worker route allowlist,
  `src/index.ts` retention configuration and `src/lifecycle.ts` durable account
  disablement/erasure. The wording preserves original envelopes/revisions,
  quota, no age cutoff, loss risks and asynchronous erasure. Public login and
  unauthenticated API boundaries were checked on 2026-10-22. No uploads,
  private MCP queries, credentials or deletion mutations were exercised.
- [x] **Cloud MCP may expose retained results to an explicitly authorized provider.**
  Traced to the pinned cloud read-only MCP deployment contract and token scope
  rules. The article acknowledges provider retention and does not claim live
  phone access, raw snapshot parity or unrestricted cloud signup.
- [x] **Analytics excludes health-bearing fields; F-Droid has separate runtime/dependency behavior.**
  Traced to PricingAnalyticsEvent.swift's allowlist/prohibitions, Android's
  FdroidDistributionRuntime.kt no-op initialization and app/build.gradle.kts
  play-only Billing dependency. Wording now says F-Droid does not initialize
  telemetry or depend on Play Billing, rather than claiming every shared
  telemetry type is absent from its binary. Purchase handling remains with
  the selected platform store.
- [x] **The closing questions are evaluation prompts, not implemented-feature guarantees.**
  Reviewed the scope, empty/unavailable, timeout, storage and deletion questions.
  No sentence claims every health-data tool or every Health.md transport has
  identical supported semantics. Product/privacy links are checked by the
  complete website build.
