# Share My Setup v1 QA record

Date: 2026-08-14  
Branch: `feature/shared-setup-v1`  
Worktree: `/Users/codybontecou/dev/health-md-shared-setup`

## Automated gates

| Gate | Result |
|---|---|
| `python3 -m unittest test_validate_shared_setup.py` from `packages/contracts` | 11 passed |
| `python3 packages/contracts/validate.py` | 13 contracts, 23 fixtures, 7 packaging mirrors, 2 inventories, 3 output profiles, 26 capabilities, and 41 documentation links validated |
| `xcodebuild test ... -scheme HealthMd-Tests-macOS` | 1,926 passed, 8 skipped, 0 failed after final credential-Undo, DNS, and registry-identity hardening |
| `xcodebuild test ... -scheme HealthMd-Tests-iOS` on iPhone 17 Pro simulator | 1,853 passed, 13 skipped, 0 failed after final credential-Undo, DNS, registry-identity, cancellation, and native-picker coverage |
| Signed `xcodebuild build ... -destination platform=iOS,id=00008150-001405DA2188401C` | Passed for the paired physical iPhone 17 Pro |
| Focused `HealthMdTests/SharedSetupV1Tests` after final hardening | 23 passed on the iPhone 17 Pro simulator, including endpoint-safe Undo and retryable cleanup-failure coverage |
| Focused `HealthMdUITests/OnboardingJourneyUITests/testUseSharedSetupSecondaryActionPresentsNativeDocumentPicker` | Passed in Debug on iPhone and iPad simulators; verified presentation, Cancel, and reuse |
| Focused Shared Setup Settings UI tests | Passed in Debug on iPhone and iPad simulators; verified card controls, native picker, `Save to Files` exporter, and system activity sheet presentation |
| Release iOS simulator build | Passed, including the non-`DEBUG` importer branch |
| Focused onboarding importer UI test with `-configuration Release` | Passed on iOS 26.5; verified production picker presentation, Cancel, and reuse |
| `./gradlew :app:testDebugUnitTest` | 937 passed, 1 skipped, 0 failed after the device-, interoperability-, lifecycle-, and credential-verification fixes |
| API 35 instrumentation: `SharedSetupAndroidRuntimeTest` plus `SharedSetupActivityLifecycleTest` | 8 passed on the phone AVD, covering Android ICU, provider publication, large-font layout, RTL layout, status semantics, success announcements, the full pinned Apple/Android registry union, and real external Apply → Success → Activity recreation → Undo → recreation without retained-intent replay |
| `./gradlew :app:lintDebug` | Passed after the device-discovered fixes |
| `git diff --check` plus plist/JSON/XML syntax and no-staged-files checks | Passed after the device-discovered fixes |

## Manual Apple simulator checks

Device: iPhone 17 Pro simulator, iOS 26.5.

| Scenario | Result | Evidence |
|---|---|---|
| Cold external open of canonical Apple fixture | Passed | `.healthmdconfig` opened directly into **Review Shared Setup** |
| Warm external open of canonical Apple fixture | Passed | Existing process opened the same review flow |
| Updated canonical Apple fixture with Apple-only HRV | Passed | Apple showed all six semantic selections as exact; Android showed six requested with one unavailable and five supported, proving unavailable is not misclassified as invalid |
| Android-generated export opened on Apple | Passed | 106 Android-selected metrics decoded; unsupported Android-only metrics were shown as **Requires action** |
| Schedule/endpoint disclosure | Passed | Review stated schedule remains off and endpoint authentication is not included |
| Maximum Dynamic Type launch | Passed for the visible review viewport | Accessibility XXXL kept the title and overview values readable; full physical-device navigation remains required |
| Forced right-to-left launch | Passed for the visible review viewport | Close control, section headers, labels, and values mirrored without overlap |
| iPad cold external open of canonical fixture | Passed | iPad (A16), iOS 26.5, opened directly into **Review Shared Setup** over onboarding |
| iPhone/iPad Settings entry | Passed in XCUITest | Configuration card, Use, and Share controls were exposed; Use presented the native picker on both idioms |
| Save to Files and system share presentation | Passed in XCUITest | iPhone and iPad opened the native file exporter with an enabled **Save** action and presented the system `ActivityListView` for the generated `.healthmdconfig` artifact |
| Saved Apple artifact validity | Passed on iPhone simulator | Native **Save to Files** produced a 48,968-byte `Health-md-Setup.healthmdconfig`; bytes were canonical sorted compact JSON, and the payload passed the v1 contract/schema/security validator after adding the validator's fixture-only trailing newline. It identified Apple 3.0.5, contained 217 semantic metrics, a typed Apple extension, and no fabricated Android extension |
| iPhone/iPad onboarding entry | Passed in Debug and Release XCUITest | Secondary action presented the native picker; Cancel restored the action and a second presentation succeeded |
| Native Files picker selection | Passed on iPhone simulator | A host-seeded synthetic `Family-Setup.healthmdconfig` was selected from **On My iPhone** through the real picker and reached **Review Shared Setup**; this host-dependent test was removed after recording the passing result |
| Apply, success, Undo, and Finish from picker import | Passed on iPhone simulator | A host-dependent XCUITest selected the fixture, tapped **Apply Shared Setup**, observed **Setup Applied**, reached **Undo** and **Finish Setup**, verified Undo became unavailable after restoration, and returned to onboarding; the test was removed after recording the passing result |
| Endpoint confirmation and credential-safe Undo | Passed on iPhone simulator | A host-dependent XCUITest selected/applied the fixture, entered a new local Authorization value, confirmed the endpoint, observed the credential field disappear, then completed Undo; the test was removed after recording the passing result. The current source-level guarantee is asserted by `testEndpointConfirmationAndUndoClearNewCredentialBeforeRestoringOldEndpoint` (endpoint restored, persisted credential cleared, one-shot Undo) and `testUndoCredentialCleanupFailureLeavesConfirmedEndpointAndUndoRetryable` |

## Manual Android emulator checks

Device: Pixel 7 AVD, Android 15 / API 35, Google APIs ARM64 image.

| Scenario | Result | Evidence |
|---|---|---|
| Onboarding secondary action | Passed | **Use a Shared Setup** opened the shared importer without adding an onboarding milestone |
| `OpenDocument` from Downloads | Passed after final IO fix | Canonical fixture reached **Review Shared Setup** with provider reads dispatched off the main thread |
| Review compatibility UI | Passed | Formats, metric count, naming, units, Daily Notes, individual entries, schedule, endpoint, applied/action/unsupported states shown |
| Apply | Passed | **Shared Setup Applied** showed applied/action/unsupported counts, endpoint completion, Undo, and Finish Setup |
| Undo | Passed | Returned to the pre-import Shared Setup start state |
| `CreateDocument` | Passed | Wrote `HealthMd-Shared-Setup.healthmdconfig`; decoded as schema v1, Android origin, schedule disabled, Apple extension `null` |
| Android Sharesheet | Passed after fix | Sharesheet displayed one `.healthmdconfig` file through the narrow provider; unique artifacts now receive a 60-second recipient-read grace period, then are removed or pruned before a later share |
| Cold Files-app `ACTION_VIEW` | Passed after final security/threading fixes | Generic provider octet-stream URI opened directly into review |
| Warm Files-app `ACTION_VIEW` / `onNewIntent` | Passed after final security/threading fixes | Process ID stayed unchanged while an Android-generated setup opened in review |
| Activity recreation during Success | Passed after final lifecycle fix | Rotating the AVD recreated the Activity without replaying the retained external intent; **Shared Setup Applied** and the original bounded Undo remained available in the same process |
| Recreation after Finish Setup | Passed after final lifecycle fix | After Finish Setup, a later rotation stayed outside Review/Success and did not reopen the consumed document |
| Real OS process death during Success | Passed on API 35 AVD | After external import and Apply, the app was backgrounded and killed with `am kill`; reopening its retained Recents task created a new PID and restored **Shared Setup Applied** with Undo instead of replaying Review |
| Real OS process death after Undo | Passed on API 35 AVD | Undo returned to the Shared Setup start state; a second background kill and Recents-task restoration created another PID and retained the finished/idle state without reopening Review or Success |
| Full Apple writer output opened on Android | Passed after registry-union fix | A native Apple `Save to Files` artifact with 217 selected metrics opened through Android MediaStore octet-stream routing; Android reported 129 Apple-only metrics unavailable and retained 88 exact supported selections |
| Full Apple artifact Apply and Undo | Passed | The 88 supported selections applied transactionally; success reported one applied group, four attention groups, one unsupported group, endpoint confirmation with no inherited authentication, and Undo returned to the Shared Setup start state |
| Apple → Android → Apple native re-export | Passed | After applying the Apple artifact, Android `CreateDocument` emitted a valid 26,147-byte Android-origin v1 document with 88 metrics, schedule disabled, a typed Android extension, and the exact imported Apple extension; Apple opened the result in review with 88 exact selections |
| Unrelated octet stream | Covered by unit test | Display-name validation fails closed before reading |
| 2.0× large-font review and success traversal | Passed after fix | Review values stack beneath labels; Apply remained reachable; success counts no longer collided; Apply completed successfully |
| Arabic-app-locale RTL traversal | Passed | Navigation, labels, values, cards, and primary action mirrored; primary action remained reachable |
| TalkBack semantics | Instrumented; physical traversal pending | Compatibility cards expose one merged status description; success heading is a polite live region |

### Device-discovered defects fixed

1. Android ICU rejected an incompletely escaped template-token regular expression even though host-JVM tests accepted it. Both codec and mapper patterns now escape the closing braces.
2. Publishing two providers with the same `androidx.core.content.FileProvider` class caused the shared authority to bind to the clinician-report provider. Shared Setup now uses a distinct `SharedSetupFileProvider` subclass.
3. Generic document-provider content URIs do not preserve the filename in the URI path. The octet-stream intent filter now accepts the provider URI, then coordinator-side content-scheme, MIME, and queried display-name validation rejects unrelated files before reading.
4. Document-provider reads previously ran on the activity main thread. Cold and warm imports now serialize external reads on the IO dispatcher while the transient activity grant is valid.
5. Reusing one share URI could let an old grant observe a later export. Each share now uses a unique cache directory and URI, and cleanup recursively removes the bounded share root.
6. At 2.0× Android font scale, two-column review and success rows collided (`Unsupported items1`) and split short values awkwardly. Review rows now stack above 1.3× font scale, while ordinary-size rows retain spaced, RTL-aware columns.
7. Android native picker reads/writes and share-file creation still ran on the main dispatcher, and immediate chooser-result cleanup could race a recipient's first URI read. ViewModel document I/O now switches to `Dispatchers.IO`; at most four unique artifacts survive a 60-second grace period, and only expired artifacts are pruned so an older cleanup cannot delete a newer share.
8. Apple security-scoped Files reads still used the main actor. The coordinator now acquires scope immediately, performs the bounded file read in a detached user-initiated task, serializes latest-document ownership, returns to the main actor for decode/preview state, and releases scope exactly once.
9. Android share cleanup initially measured from creation and used recreation-fragile UI state. Each share now reserves a UUID in `SavedStateHandle` before IO, serializes launch/handoff through one mutex, records handoff on `Dispatchers.IO`, preserves every recipient for a full 60 seconds after chooser return, rejects a fifth outstanding share, and performs exact-ID cleanup that survives screen recreation.
10. SwiftUI `fileImporter` silently failed to present on the current iOS 26.5 simulator/development host. Shared Setup now keeps `fileImporter` for iOS 17–25 Release, while Debug and iOS 26 use the same native `UIDocumentPickerViewController` through a SwiftUI sheet. Debug iPhone/iPad and Release iPhone UI tests verify presentation, cancellation, and reuse.
11. Cancelling or superseding an Apple import cancelled only the parent task while an unstructured detached file read could continue holding security scope. The parent now propagates cancellation to an injected detached reader, the bounded reader uses cancellation-aware async bytes, and a focused test attests cancellation delivery before the coordinator releases ownership.
12. A full native Apple export was initially rejected by Android as a pinned alias mismatch because Android validated against only the Android analytical profile even though the shared registry SHA covers the cross-platform union. Android now builds one union from the Apple v8 and Android v5 snapshots, validates Apple-only rows with `android_selection_id: null`, never treats those rows as supported Android selections, and retains the distinct Android RMSSD identity. The canonical Apple fixture now includes an Apple-only HRV row, host tests cover its `requires_action` behavior, and API 35 instrumentation attests the runtime union.
13. Android Activity recreation replayed the retained `ACTION_VIEW` after Apply, replacing Success with Review and risking replacement of the original Undo snapshot. External IO is now process-owned and latest-request guarded; Activity state distinguishes same-process recreation, completed-byte restoration, interrupted new-process retry, and finished flows; ViewModel stores bounded Review/Success bytes and suppresses restored-byte replay. Unit tests cover each restoration decision and retained-byte lifecycle. A permanent ActivityScenario/Compose instrumentation test now performs a real external import, Apply, Success recreation, Undo, and second recreation. It also exposed that mutating the Activity's retained launch intent breaks lifecycle ownership, so the original intent now stays intact for an interrupted new-process retry while saved state prevents duplicate handling. Separate ADB testing killed the background app process twice and restored the original Recents task: Success/Undo survived the first new PID, and the finished state survived the second without reopening the document.
14. Apple endpoint confirmation could report success after a suppressed Keychain delete/write failure, allowing a stale credential to reappear after relaunch. Confirmation now uses throwing Keychain reads/deletes/writes, verifies persisted credential and endpoint state, restores the prior destination on failure, retains the unconfirmed hint, and has injected-failure coverage.
15. Apple endpoint host validation admitted Unicode letters even though the public schema permits only ASCII DNS labels. Apple now enforces ASCII host bytes and label bounds, with a Unicode-homograph rejection test.
16. Apple combined the v8 Apple and v5 Android registry projections without first proving one version/SHA identity. The adapter now fails closed unless both projections are registry version 1 with identical SHA-256 identity, retains that checked version, and emits it rather than a separate hardcoded value.
17. A prompt-to-artifact re-audit found that Apple Undo restored portable settings, schedule, pending hint, and extensions but never touched the API endpoint/credential mutated by endpoint confirmation. The Undo snapshot now records the prior non-secret endpoint URL; Undo clears and verifies the Keychain credential before restoring that URL, verifies the cleared persisted state, restores the credential during a failed rollback only when restoration can be attested (failing closed otherwise), and reports explicit attention that credentials were cleared. Coverage now asserts post-Undo endpoint, in-memory and persisted credential, pending hint, settings, one-shot Undo state, and the retryable failure when cleanup itself fails.
18. The same audit found that Android endpoint confirmation suppressed prior secure-store read failures, never read back the saved authorization, and discarded credential-rollback failures. Confirmation now fails closed before any mutation when prior credentials cannot be read, verifies the exact normalized persisted authorization and empty headers before committing the endpoint, verifies restored credentials after rollback, fails closed with an attested clear when restoration cannot be verified, and reports an explicit verification failure. Injected-failure tests cover prior-read failure, no-op write, silently retained wrong credentials, and dying-store restoration failure.

A final independent source re-review found no remaining blocker, high, or medium issues in these fixes. Physical-provider and OS process-death behavior remain manual gates rather than source-attested interoperability evidence.

## Physical-device execution matrix

A row passes only when the named physical devices, system channel/provider, UI outcome, and resulting artifact or persisted-state check are all recorded. A launch attempt, screenshot alone, simulator/AVD result, or background install does not satisfy a row.

| ID | Required physical check | Required evidence | Status |
|---|---|---|---|
| A1 | Apple Files local save, cold open, and warm open | Saved artifact bytes/hash and validator result; Review reached from Files with the app terminated and already running | Not run |
| A2 | Apple third-party document provider | Provider identity, successful bounded read, Review, Apply, and provider-scope release without a retained grant | Not run |
| A3 | Apple Messages send and receive | Sender share completion, recipient attachment identity/size, recipient Review, and validated received bytes | Not run |
| A4 | Apple AirDrop send and receive | Both device identities, accepted transfer, recipient Review, and validated received bytes | Not run |
| A5 | Apple transactional UX | Review performs no writes; Apply remains disabled for invalid input; valid Apply, endpoint credential replacement/failure, rollback, one Undo, and post-Undo persisted-state verification | Not run |
| A6 | Apple VoiceOver | Ordered traversal of onboarding/Settings entry, review statuses, Apply, success counts, endpoint attention, Undo, and Finish; announcements heard once | Not run |
| A7 | Apple Dynamic Type and RTL | Full review/success traversal at maximum supported text size and RTL, including reachable Apply/Undo/Finish without clipping or overlap | Not run |
| D1 | Android real OpenDocument/CreateDocument provider | Provider identity, immediate content copy, validated saved bytes, cold and warm Review, and no assumed persistent grant | Blocked: no physical Android device |
| D2 | Android Sharesheet to a real recipient app | Recipient identity, successful first read during grant window, validated received bytes, and exact artifact cleanup after retention | Blocked: no physical Android device |
| D3 | Android transactional UX | Zero-write Review, valid Apply, endpoint credential replacement/failure, verified rollback, one Undo, and persisted-state verification | Blocked: no physical Android device |
| D4 | Android TalkBack | Ordered traversal of entry, merged compatibility statuses, Apply, polite success announcement, endpoint attention, Undo, and Finish | Blocked: no physical Android device |
| D5 | Android large text and RTL | Full review/success traversal at 2.0× text and RTL with reachable actions and no overlap | Blocked: no physical Android device |
| X1 | Apple-origin file transferred through a real channel and opened on Android | Original and received hashes, 217 requested / 88 available / 129 unavailable compatibility result, Apply, and exact typed Apple-extension preservation on re-export | Blocked: no physical Android device |
| X2 | Android-origin file transferred through a real channel and opened on Apple | Original and received hashes, exact supported selection result, distinct Android metrics unavailable rather than aliased, and exact typed Android-extension preservation on re-export | Blocked: no physical Android device |

## Physical-hardware launch smoke (not a matrix row)

During one unlocked, backlight-on window on the paired iPhone 17 Pro (iOS 26.6), the final signed build was launched twice through CoreDevice:

- Plain cold launch: the app launched and its process stayed alive after 12 seconds (no crash loop).
- Relaunch with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`, `-AppleTextDirection YES`, and `-NSForceRightToLeftWritingDirection YES`: the app again launched and stayed alive, exercising the maximum-Dynamic-Type and forced-RTL rendering paths on physical hardware.

The app was then terminated, leaving the device as found. Remote screenshots were unavailable (the device is reachable only through the CoreDevice network tunnel; `idevicescreenshot` requires a USB/usbmuxd connection). Per this record's own rule, a launch attempt alone does not satisfy any row above — no UI outcome, artifact, or accessibility result was observed — so **no row in the physical-device execution matrix is marked passed by this smoke test**. The staged fixtures remain in the app container (`Documents/Physical-Family-Setup.healthmdconfig` and `Documents/Family.healthmdconfig`).

## Remaining release gate

A paired physical iPhone briefly became reachable and accepted a signed development build plus a synthetic fixture copied into the app container. It was actively running another foreground app, however, and Health.md was not foreground-activated. It is currently paired again, and the final source builds and signs successfully for its physical destination. While CoreDevice reported that a passcode was required and the display backlight was off, the final signed app was installed and the current canonical fixture was staged as `Documents/Physical-Family-Setup.healthmdconfig`; both operations left the backlight off. The device was not awakened, unlocked, or foreground-activated, so no physical UI result is counted. No physical Android device is connected.

The following physical-device checks remain unavailable and are required before changing the contract from `deferred` or the capability from `planned`:

- Apple send and receive through Messages;
- Apple send and receive through AirDrop;
- Apple save/open through the Files UI and a third-party document provider;
- Android send/receive through real recipient apps and third-party document providers;
- VoiceOver and TalkBack traversal, announcements, and action discoverability;
- full Dynamic Type/large-font and RTL traversal on both platforms;
- Apply, endpoint confirmation, Undo, and artifact cleanup on physical Apple and Android devices.

Do not mark the capability available, canonicalize the contract, or call the thread goal complete until these checks pass and the post-fix automated gates above are rerun.

## Prompt-to-artifact completion audit

| Objective requirement | Concrete evidence | Status |
|---|---|---|
| Dedicated local worktree | `/Users/codybontecou/dev/health-md-shared-setup`, branch `feature/shared-setup-v1` | Done |
| Versioned contract directory with `contract.md`, schema, and fixtures | `packages/contracts/shared-setup/v1/`; synthetic Apple- and Android-origin fixtures | Done |
| Envelope, canonical enums, semantic metric IDs, aliases, and no category authority | Schema plus contract sections; `test_metric_alias_tampering_and_categories_are_rejected`; Swift/Kotlin alias and registry-drift tests | Done |
| Manifest, capability ledger, and validator | `manifest.json` entry `healthmd.shared_setup`; capability `setup.share-portable-configuration`; `validate.py`; 11 contract tests | Done, intentionally `deferred` / `planned` |
| Independent version; no Apple export-schema or direct-protocol bump | Diff does not alter `HealthMdExportSchema.version` or a direct protocol version | Done |
| Dedicated Swift adapter rather than native serialization | `SharedSetupV1.swift` mapper/codec and `SharedSetupCanonicalAliases`; canonical and Android-origin mapping tests | Done |
| Dedicated Kotlin adapter rather than DataStore serialization | `SharedSetupModels.kt`, `SharedSetupCodec.kt`, `SharedSetupMapper.kt`, and registry/alias adapters | Done |
| Compatibility states `applied`, `requires_action`, `unsupported`, `invalid` | Swift and Kotlin compatibility models, review cards, and fixtures/tests | Done |
| Explicit cross-platform defaults | Required daily-note, individual-entry filename, and schedule fields in the contract; both-origin mapping assertions | Done |
| Apple batch apply, coordinated schedule/endpoint transaction, verification, rollback, one Undo | `AdvancedExportSettings.applyPortableSnapshot`, `SharedSetupTransaction.swift`; transactional apply/Undo, failed-apply, persistence, and credential tests | Done |
| Android one-update candidate commit, coordinated schedule/endpoint handling, verification, rollback, one Undo | `SettingsRepositoryImpl.kt`, `SharedSetupService.kt`; compare-and-set, rollback, credential, and Undo tests | Done |
| Rollback snapshot is bounded, portable, and non-secret | Native transaction snapshot types plus codec/security tests; credentials remain in dedicated local stores | Done |
| `.healthmdconfig`, vendor MIME, Apple UTType | Contract plus Apple `Info.plist` and Android constants/manifest | Done |
| Apple Settings card, importer/exporter/share, app-scoped coordinator, cold/warm open, security-scoped read | iPhone/iPad settings and onboarding XCUITests; Debug/iOS 26 native picker fallback plus iOS 17–25 Release `fileImporter`; `SharedSetupCoordinator.swift`; cancellation and share-cleanup tests; iPhone/iPad simulator external opens | Implemented; physical Files/share channels pending |
| Android Settings card, Sharesheet, narrow provider, Open/CreateDocument, ACTION_VIEW on create/new intent, immediate bounded copy | Settings/navigation/activity/document-store files; unit/instrumentation tests; API 35 AVD cold/warm and native picker/sharesheet checks | Done on phone AVD; physical providers/recipients pending |
| Concise review content and Apply action | Android `SharedSetupScreen.kt`; Apple `SharedSetupCoordinator.swift` (`SharedSetupFlowView`); the manual simulator/emulator tables above enumerate the observed summary, disclosure, and status content | Done |
| Success counts, attention, Undo, Finish Setup | Both native screens; manual Android Apply/Undo and automated transaction tests | Done; physical traversal pending |
| Minimal `Use a Shared Setup` welcome action with no new milestone or duplicate flow | Apple and Android onboarding integrations route to the same coordinator/screen; Apple Debug/Release iPhone/iPad picker UI tests and Android onboarding checks pass; onboarding migration tests remain green | Done |
| Swift and Kotlin decode canonical fixture | `testCanonicalCrossLanguageFixtureDecodesAndMapsExactSettings`; `canonicalCrossLanguageFixtureDecodesAndMapsExactSupportedSettings` | Done |
| Apple→Android and Android→Apple expectations, including valid re-export | Both-origin fixtures now include common, Apple-only unavailable, and Android-distinct metrics; Apple and Android round-trip tests; full native Apple 217-metric artifact opened/applied on Android, Android re-export preserved the exact typed Apple extension, and Apple opened the 88-metric Android result | Done in automated/simulator coverage; physical transfer pending |
| Future version rejection and bounded unknown optional tolerance | Contract, Swift, and Kotlin future/unknown-field tests | Done |
| Unsupported metric and legacy alias behavior | Registry-drift, distinct-metric, duplicate/tampered alias, and unknown-future-metric tests | Done |
| Template placeholder compatibility | Swift/Kotlin malformed-template tests plus Android ICU device test | Done |
| Exact schedules with no approximation | Contract contradiction/operational-field tests; Swift unsupported and Kotlin unsupported/sub-15-minute schedule tests | Done |
| Endpoint query stripping and credential non-inheritance | Swift/Kotlin writer and transactional credential tests | Done |
| No secret, bookmark, SAF URI, device ID, history, or health data | Contract prohibited-state scanner and writer security scans; bounded synthetic fixtures | Done |
| Oversized, malformed, deep/path-traversal input rejection | Contract generic-bound tests; native bounded preflight/stream reads and malformed/unsafe-path tests | Done |
| Preview performs zero writes | Swift and Kotlin zero-write preview tests | Done |
| Failed apply leaves configuration unchanged | Swift failed-apply test; Android post-commit verification and rollback tests | Done |
| Undo restores previous portable profile | Swift transaction test; Android exact previous-state test; Android manual Undo | Done in automated/emulator coverage; physical check pending |
| Cold/warm external opening | Native coordinator tests plus iOS simulator and Android phone-AVD cold/warm checks | Done in automated/emulator coverage; physical lifecycle check pending |
| Large text, RTL, and screen-reader semantics | iOS simulator max Dynamic Type/forced RTL; Android 2.0× full review/apply/success traversal, Arabic-locale RTL traversal, and six device tests | Semantics/layout covered; physical VoiceOver/TalkBack traversal pending |
| Manual Messages, AirDrop, Files, and Android Sharesheet | Android Files/Sharesheet and iOS simulator document opening completed | **Incomplete:** physical Messages, AirDrop, Files/providers, and real Android recipients remain unavailable |

**Audit verdict:** not achieved. The implementation and automated/simulator coverage are complete enough for continued device QA, but the explicitly required physical interoperability and accessibility evidence is still missing. The contract therefore remains `deferred`, the capability remains `planned`, and the branch remains uncommitted/unpushed.
