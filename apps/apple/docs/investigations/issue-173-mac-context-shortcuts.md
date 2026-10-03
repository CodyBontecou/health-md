# Issue #173: phone-initiated Mac context Shortcut investigation

Refs https://github.com/CodyBontecou/health-md/issues/173

## Outcome and limits

A mobile automation should explicitly refresh an authenticated computer's encrypted query context for a frozen profile/date scope and retrieve a durable status without producing export files. This is not ordinary file export and must not change existing Shortcut destinations, saved profiles, or local data.

**Partial investigation, not an implementation of the two requested actions.** Source inspection at base `b8fd904f4d299f5af4a22111d2fdccf829705ea7` confirms the documentation advertised a path that does not exist. This change corrects that availability claim and adds behavioral regression coverage for existing safety boundaries. No local builds/tests, physical-device automation, HealthKit capture, or sleep/wake reproduction were performed in the source-only Linux lane. Cloud check receipts belong in the PR/lane report; test source alone is not a passing receipt.

## Reachable implementation

| Surface | Actual source evidence | Limit |
| --- | --- | --- |
| Shortcut registration | `HealthMd/iOS/AppIntents/HealthMdAppShortcuts.swift` registers seven actions | Neither Mac context action is present |
| Ordinary export | `ExportIntentRunner.run` invokes `withVaultAccess` / `exportDatesBackground`, records an iPhone target and file-export use | A remote profile does not turn this pipeline into context acquisition |
| Context request direction | `HealthMd/Shared/Sync/SyncPayload.swift`: `.iphoneExportRequest(IPhoneExportRequest)` is Mac → phone; `.contextStore` is a response mode | No phone → Mac refresh request or status-query message exists |
| Existing context capability | `SyncPeerCapabilities.supportsRequestScopedContextAcquisition` | Negotiates Mac-initiated acquisition, not phone-initiated automation support |
| Mac backend | `HealthMd/macOS/HealthMdApp+macOS.swift`, `setupControlServer` refresh executor; `MacIPhoneExportRequestCoordinator.requestExport` | Creates a durable job from local computer-side requests; not an iOS App Intent |
| Context scope validation | `MacIPhoneExportRequestCoordinator.requestExport` / `preflight`; `IPhoneExportRequestHandler.handle` | Enforces canonical selection and context capability; no profile-to-reverse-request adapter |
| Quota boundary | `IPhoneExportRequestHandler.handle`: `.contextStore` bypasses file purchase/quota checks; context corpus uses `.encryptedContext` | Not proof that an unimplemented Shortcut is quota-exempt |
| Phone receipt | No `IPhoneContextRefreshStatus` or associated App Intent/store in source | Mac's local durable record does not supply a phone-side recoverable receipt |

The premature identifiers `RefreshMacContextIntent`, `IPhoneContextRefreshRequest`, `GetMacContextRefreshStatusIntent`, and `IPhoneContextRefreshStatus` appeared only in documentation. Opening the two apps or upgrading the OS cannot make nonexistent actions available.

## Acceptance mapping

| Issue criterion | Evidence in this partial change | Still required |
| --- | --- | --- |
| Register refresh/status with explicit profile/date scope | Corrected action lists document absence; no placeholder registrations added | Both intents, profile/date validation, frozen scope and durable identity |
| Reuse authenticated capability-negotiated durable acquisition | New `CLIRawControlSafetyTests.testContextAcquisitionRejectsPeerMissingCapabilityWithoutSendingRequest`; existing Mac `.contextStore` coordinator identified | Reverse request/status capability, authenticated ingress and end-to-end adapter |
| No arbitrary peer/path, export files or file quota | New `testContextAcquisitionRejectsProjectionPointersBeforeJobCreation`; `testContextAcquisitionWithoutFolderRetainsExactPendingJobAcrossRestart`; iOS `testRemoteProfileShortcutStillUsesLocalPipelineAndFileQuota` / `testRemoteProfileShortcutDoesNotBypassFileQuota` preserve ordinary exports | Context-only Shortcut behavioral tests for no file writes/quota consumption, selected-peer binding, and hostile requests. Existing backend tests are not end-to-end proof |
| Truthful unavailable/locked/incompatible/pending with recoverable ID | Backend tests cover absent context capability, waiter timeout, disconnect/restart status and rejection of changed selection under one job ID | Phone receipt persistence/status action, locked/unavailable Mac handling, lost acknowledgement recovery and peer replacement tests |
| Physical iPhone automation after wake, supported availability, no wake/protected-data promises | Docs explicitly withhold wake/bypass guarantees | Real iPhone + Mac test with exact versions, foreground/authenticated session, locked denial, disconnect, pending recovery, asleep Mac and after-wake cases |
| Correct availability until an exact release | Apple feature guide and website describe proposed/not implemented actions, remove fictional parameters/implementation notes | Keep unavailable until implementation + qualification + an exact released version names both actions |

## Regression execution surface

The tests are added to existing XCTest classes, not source-text assertions. `HealthMdTests` is a `PBXFileSystemSynchronizedRootGroup` attached to the test targets; no manual project registration is needed. The iOS suite is guarded by `#if os(iOS)` and the Mac coordinator tests by `#if os(macOS)`.

`.github/workflows/apple-ci.yml` runs the iOS test scheme through `make test-ios` and the macOS scheme through `make coverage`, including these classes. `.github/workflows/website-ci.yml` validates and builds the changed docs. No release/deploy workflow is needed. Neither simulator tests nor successful docs builds qualify physical Shortcuts execution.

## Implementation handoff (not a supported contract)

1. Define a separately negotiated phone-initiated context capability. Legacy peers must default it to false; do not send new enum cases to an unnegotiated peer. The existing acquisition capability is insufficient.
2. Resolve an explicit/active profile without fallback on an unknown name or unbound destination. Freeze canonical metric/source/detail selection and owner-date scope before network work; no arbitrary host, URL, destination path, shell, or file mode parameter.
3. Use the existing authenticated Apple sync transport and installation identity binding. A capability announcement alone is not authentication. Persist an idempotent immutable request identity on phone before sending and map it to one Mac durable `.contextStore` job. Retries after lost acknowledgements must not create another job or change the peer/scope.
4. Admit the request on Mac only with the negotiated capability and correct live peer/role. Reuse the coordinator's scope and corpus validation, encrypted store commit and recovery path; never route through file export or expose raw health payloads in diagnostics.
5. Persist phone receipts bound to request, peer and scope; stale/foreign status must not overwrite them. Status must distinguish pending, unavailable and terminal completion. Waiter expiry/disconnect is not success or cancellation. Return recoverable identity even when the acknowledgement is lost.
6. Add behavioral tests for replay/deduplication, changed profile/date/peer, failed persistence, legacy peers, malformed requests, late receipts, locked data, no file/quota side effects and ordinary-export compatibility. Wire tests must include both producers and consumers.
7. Verify App Intents APIs against the public Apple documentation/toolchain used for qualification, then register the actions and perform physical-iPhone automation QA. Do not publish promises based on unverified SDK availability.

## Platform and version impact

This partial change adds no mobile feature or new platform staging: only documentation and tests. The parity inventory is not changed to claim availability. Android's direct sources (`apps/android/app/src/main/java/com/healthmd/direct/DirectCliCoordinator.kt` and `DirectCliForegroundService.kt`) implement computer-initiated direct operations; source inspection found no equivalent phone-initiated Mac encrypted-context automation path. This is an implementation gap, not evidence that Health Connect makes the neutral outcome impossible. A future implementation must explicitly stage Android as `planned` with a concrete desktop-context protocol/automation target in `packages/contracts/product-capabilities.json`, or provide a documented platform reason for unavailability.

No export schema, direct Rust protocol, archive, fixture, profile storage, version or release metadata changes in this PR. Existing Apple/Android exports, Rust CLI/core and external Obsidian consumer bytes remain untouched. The eventual Apple sync request/status additions need a capability-gated compatibility decision; they do not inherently require a daily export schema bump. Keep issue #173 open until the missing implementation and device evidence exist.
