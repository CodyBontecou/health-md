# Google Play and F-Droid distribution plan

## Status

- **Plan status:** implemented upstream; physical-device, tagged reproducibility, and fdroiddata publication gates remain pending
- **Implementation target:** Android 1.8.1 (`versionCode 30`)
- **Scope:** Android phone application distribution
- **Primary goal:** maintain one Android source tree that produces a Google Play build and an official F-Droid-compatible build without changing Health.md export or direct-protocol contracts
- **Out of scope for the first F-Droid release:** F-Droid distribution of the Wear OS companion

The flavor architecture, compile-time exclusions, unsigned artifact verification, metadata, scanner CI, licensing, channel documentation, website disclosures, unit/lint suites, and Play/F-Droid connected emulator suites are implemented. Do not call the release reproducible or published until `android/v1.8.1` exists and the physical-device, two-clean-clone, and two-buildserver gates below pass.

## Outcome

Health.md will have one `distribution` product-flavor dimension with two supported variants:

| Capability | `play` | `fdroid` |
| --- | --- | --- |
| Application ID | `com.healthmd.android` | `com.healthmd.android` |
| Health Connect reads | Yes | Yes |
| Local/SAF exports | Yes | Yes |
| API endpoint exports | Yes | Yes |
| Direct CLI | Yes | Yes |
| Widgets and scheduled exports | Yes | Yes |
| Entitlement | Ten manual exports, then Play lifetime unlock | Full access included |
| Google Play Billing | Yes | No |
| Play In-App Review | Yes | No |
| Play Install Referrer | Yes | No |
| First-party campaign attribution | Yes, when configured | No |
| First-party onboarding/pricing analytics | Yes | No |
| Phone-to-Wear Data Layer | Yes | No in the first release |
| Direct vendor cloud imports | Yes when configured | Hidden in the first release |
| Release signer | Play release/upload signing flow | F-Droid repository signer |

Both variants must use the same version name, phone version code, export engines, schemas, reducers, direct protocol, and shared Rust core for a given source tag.

## Approved implementation decisions

The implementation applies the following product decisions, approved by the explicit implementation request.

1. **The F-Droid build includes full access at no charge.** It does not retain a ten-export limit with no available purchase path.
2. **Both variants keep `com.healthmd.android`.** They cannot normally be installed side by side, and users cannot switch between Play- and F-Droid-signed releases without uninstalling.
3. **The official F-Droid build performs no Health.md telemetry.** It does not create attribution/onboarding install IDs, queue telemetry events, or contact Health.md analytics endpoints.
4. **The first F-Droid release omits Wear Data Layer integration.** The `:wear` module remains a Play-distributed companion.
5. **The first F-Droid release hides direct Fitbit, Oura, Polar, WHOOP, and Withings cloud imports.** These can be reconsidered later with a deliberate `NonFreeNet` disclosure and a workable public OAuth configuration.
6. **The F-Droid listing discloses `NonFreeDep`.** Health Connect is available as an Android framework capability on newer systems, but supported older devices commonly require the Google-distributed Health Connect provider.
7. **F-Droid builds and signs its APK.** The initial submission will not attempt Play-signature-compatible reproducible binary publication.

If product chooses different assumptions, update this plan and its acceptance criteria before changing Gradle or source sets.

## Guardrails

- Do not create a long-lived F-Droid branch or copy the app into a second module.
- Do not let F-Droid's external build recipe patch proprietary code out with `sed`; the upstream source tag must contain and test the supported flavor.
- Do not expose Google types from common domain interfaces.
- Do not change frozen Android v4, analytical v5, API, raw export, direct protocol, or shared setup bytes for distribution work.
- Do not fabricate Wear or direct-provider support in F-Droid. Unsupported features must be absent or visibly unavailable.
- Do not make Play release validation infer success from F-Droid builds, or vice versa.
- Keep all release versions sourced from the existing Android version fields and `android/v<version>` tags.

## Target Gradle model

Add a flavor dimension to `apps/android/app/build.gradle.kts`:

```kotlin
android {
    flavorDimensions += "distribution"
    productFlavors {
        create("play") {
            dimension = "distribution"
            buildConfigField("String", "DISTRIBUTION_CHANNEL", "\"play\"")
        }
        create("fdroid") {
            dimension = "distribution"
            buildConfigField("String", "DISTRIBUTION_CHANNEL", "\"fdroid\"")
        }
    }
}
```

Expected app variants are:

- `playDebug`
- `playE2e`
- `playRelease`
- `fdroidDebug`
- `fdroidE2e` when needed for channel-specific instrumented coverage
- `fdroidRelease`

Use explicit variant names in CI, documentation, scripts, and release automation. Do not rely on aggregate tasks such as `assembleDebug` after flavors are introduced.

Move these dependencies from `implementation` to `playImplementation`:

```text
com.android.billingclient:billing-ktx
com.android.installreferrer:installreferrer
com.google.android.play:review
com.google.android.play:review-ktx
com.google.android.gms:play-services-wearable
project(:wearable-contract) when only the Play phone transport consumes it
```

Keep the FOSS AndroidX Health Connect client in common `implementation`.

### Signing

- Remove unconditional release signing from the common `release` build type.
- Assign the existing release signing configuration only to the `play` flavor's release variant.
- Leave `fdroidRelease` unsigned so fdroidserver can sign it.
- Preserve debug-key signing for both debug flavors.
- Add a clean-clone test proving `:app:assembleFdroidRelease` does not read or require `health-md-release.jks` or release passwords.

Expected outputs should be treated as contracts by scripts:

```text
app/build/outputs/bundle/playRelease/app-play-release.aab
app/build/outputs/apk/fdroid/release/app-fdroid-release-unsigned.apk
```

Confirm the exact AGP-generated names during implementation rather than silently teaching scripts guessed paths.

## Source-set architecture

Use source sets for implementation differences and common interfaces for product behavior:

```text
app/src/main/       shared domain, UI contracts, exporters, Health Connect, storage
app/src/play/       Billing, Review, Install Referrer, analytics enablement, Wear transport
app/src/fdroid/     full-access entitlement, no-op integrations, F-Droid resources/manifests
app/src/playTest/   Play Billing/referrer/review/Wear tests
app/src/fdroidTest/ F-Droid entitlement/privacy/dependency tests
```

### Distribution policy

Introduce one injected, immutable common model instead of scattering flavor checks:

```kotlin
data class DistributionPolicy(
    val channel: DistributionChannel,
    val purchasesAvailable: Boolean,
    val fullAccessIncluded: Boolean,
    val reviewPromptAvailable: Boolean,
    val campaignAttributionEnabled: Boolean,
    val onboardingAnalyticsEnabled: Boolean,
    val wearSyncAvailable: Boolean,
    val directCloudProvidersAvailable: Boolean,
)
```

Flavor-specific Hilt modules provide the policy. Common screens and coordinators consume the policy or a capability-specific interface; they should not inspect package signatures, installer package names, or `BuildConfig` directly.

Add an About/Support row showing `Google Play build` or `F-Droid build`, the source-code URL, and the AGPL-3.0 license.

## Work packages

### 1. Establish common entitlement and purchase contracts

The existing `BillingRepository` leaks Google Billing's `ProductDetails` into common code. Refactor before moving dependencies:

- Add a common `EntitlementRepository` exposing `StateFlow<Boolean>` for full access.
- Add a common purchase-facing model containing only Health.md values such as localized price text, progress state, and typed purchase errors.
- Keep Google `BillingClient`, `ProductDetails`, `Purchase`, response codes, and retry rules entirely under `src/play`.
- Bind the Play implementation to the current Billing behavior.
- Bind the F-Droid implementation to a stable `isUnlocked = true` state.
- Make F-Droid purchase and restore actions unavailable rather than simulated.
- Ensure F-Droid exports do not consume or display the free-export counter.
- Preserve `FreemiumPolicy` and purchase restoration behavior for Play.

Update consumers including:

- onboarding and paywall view models;
- export admission/accounting;
- scheduled exports;
- automation intents;
- Direct CLI export admission;
- settings purchase state.

Acceptance:

- The Play flavor still enforces ten free manual actions and restores the lifetime product.
- The F-Droid flavor can perform more than ten manual exports and schedule exports without a purchase state or Play service.
- No common production source imports `com.android.billingclient.*`.

### 2. Make onboarding and paywall channel-aware

Keep one onboarding flow while changing only the access step:

- Play continues to show the current lifetime-unlock paywall.
- F-Droid shows concise copy that full access is included with the F-Droid build.
- F-Droid exposes no buy, restore, price, or Play account controls.
- Settings replaces the paywall entry with build-channel/source/license information, or hides it if the About section already provides that information.
- Add flavor-specific strings for Play-only release notes and purchase terminology.
- Keep accessibility semantics and localization complete in both flavors.

Prefer preserving a stable onboarding page model over hard-coded page indices. Replace assumptions such as "page 3 is paywall" with a typed onboarding-step list generated from `DistributionPolicy`.

### 3. Isolate Play In-App Review

`ExportScreen.kt` currently imports `ReviewManagerFactory` directly. Replace this with a common `ReviewPrompter` interface:

- Play implementation invokes the existing user-initiated Play review flow.
- F-Droid implementation reports `Unavailable` and performs no action.
- Hide the review action/call site when unavailable; do not redirect F-Droid users to Google Play.

Acceptance:

- No F-Droid class or resource references Play Review.
- Successful exports behave identically when no review prompt is available.

### 4. Isolate attribution and disable F-Droid telemetry

Split campaign attribution at the install-referrer boundary:

- Keep the common sanitized attribution models only if another common test or persistence contract needs them.
- Move `PlayInstallReferrerSource` and its Hilt binding to `src/play`.
- Provide no attribution initializer in F-Droid, rather than returning an organic referrer after creating state.
- Do not create the `campaign_attribution` DataStore or WorkManager jobs in F-Droid.
- Keep Play endpoint/token injection unchanged.

Refactor onboarding analytics behind a common interface:

- Play binds the existing durable reporter.
- F-Droid binds an in-memory no-op that creates no UUIDs, persistence, workers, or requests.
- Remove the default onboarding analytics endpoint from the F-Droid generated `BuildConfig`.
- Ensure `HealthMdApplication` starts only integrations enabled by the distribution policy.

Acceptance:

- A fresh F-Droid launch and completed onboarding make no Health.md-operated network request.
- F-Droid app data contains no attribution or onboarding analytics store.
- Play telemetry payload and retention tests remain unchanged.
- The F-Droid metadata does not require a `Tracking` anti-feature.

### 5. Isolate phone-to-Wear transport

The phone app currently imports Google Play Services wearable APIs and starts Wear reconciliation at application startup. Separate transport from common UI/state:

- Keep channel-neutral Wear availability/status types in common code only if needed by common Settings composition.
- Move Google `DataClient`, `MessageClient`, `CapabilityClient`, task adapters, Data Layer services, and their Hilt bindings into `src/play`.
- Move the phone Data Layer service declaration from the main manifest to `src/play/AndroidManifest.xml`.
- F-Droid provides a no-op/unavailable implementation and does not schedule Wear WorkManager jobs.
- Hide the Wear settings card in F-Droid.
- Remove `play-services-wearable` and, if unused elsewhere, `:wearable-contract` from the F-Droid runtime graph.
- Keep the standalone `:wear` module and its existing Play release/evidence flow unchanged.

Acceptance:

- The F-Droid merged manifest contains no Google wearable actions or Data Layer service.
- The F-Droid APK contains no `com.google.android.gms.wearable` classes.
- Play phone/Wear sync, clear, redaction, skew, and evidence tests continue to pass.

### 6. Scope direct cloud providers for the first release

For the first official F-Droid build:

- remove direct vendor providers from the F-Droid provider catalog;
- hide OAuth setup and callback entry points that have no enabled provider;
- retain Health Connect as the authoritative provider;
- retain user-configured API endpoint exports and Direct CLI because those destinations are chosen by the user;
- add a distribution support matrix to Android and website documentation.

Do not delete common provider code solely for F-Droid. Make catalog registration channel-aware so Play retains current behavior. Verify R8/resource shrinking removes unreachable F-Droid provider implementation and copy where practical.

A later proposal may enable these providers in F-Droid if public OAuth client configuration is available in source and the listing adds an accurate `NonFreeNet` anti-feature.

### 7. Split manifests and resources

Keep the main manifest limited to shared capabilities. Use flavor overlays for channel-specific components.

Play manifest owns:

- Wear Data Layer service and wearable intent actions;
- channel-specific package queries or metadata;
- any explicit Play-only component declarations.

F-Droid manifest must not acquire transitive or explicit declarations for:

- `com.android.vending.BILLING`;
- Play Install Referrer;
- Play Review;
- Google wearable Data Layer services/actions.

Add F-Droid resources for:

- full-access onboarding copy;
- build-channel About copy;
- no-Play troubleshooting text;
- F-Droid-specific release notes where a Play release note mentions Billing, Review, attribution, or Wear.

### 8. Reorganize tests by flavor

Inventory shared tests that import Google APIs. Move Play-only tests from `src/test` to `src/playTest`, including Billing response-code, `ProductDetails`, purchase lifecycle, install-referrer, review, and Play/Wear release-readiness tests.

Add F-Droid tests proving:

- entitlement is always unlocked;
- purchase and restore controls are absent;
- more than ten exports remain admitted;
- scheduled, automation, and Direct CLI exports are admitted without billing;
- telemetry initialization is a no-op and creates no persistent IDs/jobs;
- Wear settings and services are absent;
- direct vendor providers are absent from the catalog;
- common export fixtures render byte-identically in Play and F-Droid;
- unsupported channel features report unavailable rather than fabricated success.

Add a built-artifact policy test that inspects `fdroidReleaseRuntimeClasspath`, the merged manifest, and the APK. It must fail on these groups/packages:

```text
com.android.billingclient
com.android.installreferrer
com.google.android.play
com.google.android.gms:play-services-wearable
```

Do not use a broad `com.google.*` ban: FOSS libraries such as Guava, Dagger/Hilt, and AndroidX tooling may use Google namespaces while remaining acceptable. Maintain an exact forbidden-component list with license evidence.

### 9. Migrate existing Play CI and release automation

Adding product flavors changes task names and artifact paths. Update every current Play assumption in one reviewed change:

- `.github/workflows/android-ci.yml`
- `.github/workflows/android-release.yml`
- `.github/workflows/android-wear-evidence.yml`
- `.github/workflows/practice-ci.yml`
- Android Fastlane files
- root `Makefile`
- Play upload, validation, evidence, and promotion scripts
- release-readiness tests
- `AGENTS.md`, README, Play setup/runbooks, OAuth setup, Billing setup, and Wear docs

Examples:

```text
:app:testDebugUnitTest       -> :app:testPlayDebugUnitTest
:app:lintDebug               -> :app:lintPlayDebug
:app:assembleDebug           -> :app:assemblePlayDebug
:app:connectedDebugAndroidTest -> :app:connectedPlayDebugAndroidTest
:app:bundleRelease           -> :app:bundlePlayRelease
```

Keep `:wear` task names unchanged. Update phone AAB paths in all paired-Wear validators and protected workflows. Treat this migration as release-infrastructure work: no Play mutation path may silently consume an F-Droid artifact.

Add explicit convenience commands:

```text
make android-play-debug
make android-fdroid-debug
make android-fdroid-release
```

The default developer/device command should remain Play-oriented and target the documented Pixel 7.

### 10. Add an F-Droid CI gate

Add a dedicated job or workflow that runs from a clean checkout with no release secrets:

```bash
./gradlew --no-daemon \
  :app:testFdroidDebugUnitTest \
  :app:lintFdroidDebug \
  :app:assembleFdroidDebug \
  :app:assembleFdroidRelease
```

The gate must also:

1. install Rust 1.88.0 and `cargo-ndk` 4.1.2;
2. install all four pinned Android Rust targets;
3. use NDK `27.1.12297006` (`r27b` in fdroiddata naming);
4. build every native library from the tagged source and `Cargo.lock`;
5. run the forbidden-dependency and merged-manifest checks;
6. inspect the release APK package/version/minSdk/targetSdk;
7. run `fdroid scanner` using a pinned fdroidserver environment;
8. retain the unsigned APK, dependency report, scanner result, and checksums as CI artifacts.

The Play aggregate CI gate should require both the existing Play jobs and this F-Droid job before an Android tag can be released.

### 11. Create and validate fdroiddata metadata

Maintain an upstream copy of the proposed recipe under `apps/android/fdroid/` for review and reproducibility. The canonical published copy remains the F-Droid `fdroiddata` repository.

The recipe should use:

- repository root as the Git checkout;
- `subdir: apps/android`;
- `gradle: fdroid` or the exact syntax verified by fdroidserver;
- NDK r27b / `27.1.12297006`;
- Rust 1.88.0;
- Android targets `aarch64-linux-android`, `armv7-linux-androideabi`, `x86_64-linux-android`, and `i686-linux-android`;
- `cargo-ndk` 4.1.2 installed with `--locked`;
- output `app-fdroid-release-unsigned.apk`;
- `android/v<version>` source tags and automatic update matching limited to Android tags.

Metadata must include:

- `License: AGPL-3.0-only`;
- source, issue tracker, website, and changelog URLs;
- Health Manager and appropriate secondary categories;
- an accurate `NonFreeDep` explanation for Health Connect;
- no `Tracking` designation after telemetry removal;
- no `NonFreeNet` designation while direct vendor providers are absent;
- localized summary/description and screenshots that show only F-Droid-available capabilities.

F-Droid will not provide OAuth/API credentials. The recipe must build successfully with no private Gradle properties, environment variables, signing files, Play credentials, or Cloudflare tokens.

### 12. Documentation and licensing review

Update documentation from a shared-outcome perspective:

- Android README build matrix and commands;
- lifetime unlock page with a distribution-channel section;
- onboarding, privacy, provider, Wear, and release documentation;
- website install/download page and channel-switch warning;
- privacy policy stating the F-Droid build has no Health.md telemetry;
- support guidance for Health Connect availability on Android 9–13 and Android 14+;
- an in-app source/license entry.

Audit all bundled assets and production dependencies. Preserve Geist OFL and PDFBox notices. Resolve or clearly document the currently unspecified license for `packages/contracts` before submission if any contract material is included in the F-Droid source/build boundary.

This distribution change should not bump an export schema or direct protocol version. If implementation changes observable export bytes, stop and handle that as a separate contract change under the cross-platform policy.

## Validation matrix

### Automated

| Gate | Play | F-Droid |
| --- | --- | --- |
| Common unit/export-contract tests | Required | Required |
| Flavor-specific unit tests | Billing/referrer/review/Wear | Entitlement/privacy/absence |
| Lint | `lintPlayDebug` | `lintFdroidDebug` |
| Debug APK | Required | Required |
| Release artifact | Signed/credentialed AAB in release workflow | Unsigned APK with no credentials |
| Rust four-ABI source build | Required | Required |
| Manifest/package inspection | Play components expected | Play components forbidden |
| F-Droid scanner | Not applicable | Required |
| Connected Pixel 7 smoke | Required | Required before first submission |
| Wear module and paired evidence | Required for Play release | Not applicable |

### Manual F-Droid QA

On the documented Pixel 7 and at least one Android 13-or-lower Health Connect configuration:

1. Fresh install with no Play Store dependency except the disclosed Health Connect provider where required.
2. Complete onboarding and verify full access copy, no paywall, and no purchase/restore controls.
3. Deny and grant Health Connect categories; verify rationale and unavailable states.
4. Perform at least eleven manual exports.
5. Configure and execute a scheduled export.
6. Exercise widgets, folder destinations, preview, history/retry, raw snapshot, PDF report, API endpoint, automation intent, and Direct CLI.
7. Verify direct cloud provider and Wear controls are absent.
8. Capture startup/onboarding network traffic and verify no Health.md telemetry request.
9. Clear data, reinstall, and repeat the no-identifier/no-telemetry check.
10. Verify TalkBack, large text, dark mode, and at least one RTL locale on flavor-specific screens.

### Manual Play regression QA

1. Free counter and paywall still gate at the intended threshold.
2. Purchase, pending purchase, acknowledgment, restore, reconnect, and cached entitlement behavior still work.
3. Campaign attribution remains configuration-gated and privacy-bounded.
4. Onboarding analytics retains its allowlist and delivery behavior.
5. User-initiated Play review still works.
6. Phone/Wear sync and all protected paired-release evidence remain valid.
7. Play AAB package/version/signing and upload paths are unchanged semantically despite new artifact names.

## Release and update policy

- Continue using one Android version and `android/v<version>` tag per release.
- Build both phone variants from the exact same tag.
- Do not maintain independent F-Droid source commits or cherry-pick queues.
- A Play-only integration change must still pass the F-Droid dependency/scanner gate.
- A common feature change must test both flavors.
- F-Droid may publish later than Play because its review/build queue is external, but it should not receive a different source version under the same version code.
- Keep customer-facing release notes channel-aware. Do not mention Play Billing, Play review, attribution, direct cloud providers, or Wear as available in F-Droid.
- Document that channel switching requires uninstall/reinstall because F-Droid and Play signatures differ; do not promise purchase or app-state migration across signatures.
- Review F-Droid inclusion policy, scanner rules, anti-features, Android SDK/NDK availability, and Rust recipe support before each major Android toolchain upgrade.

## Suggested implementation sequence

1. Approve the seven product decisions.
2. Refactor entitlement/purchase and review boundaries while still producing only the current Play app.
3. Refactor attribution, onboarding analytics, Wear transport, and provider catalog behind common interfaces.
4. Add `play` and `fdroid` flavors and move dependencies/source/manifest entries.
5. Split shared, Play, and F-Droid tests.
6. Migrate all existing Play CI, release scripts, artifact paths, and documentation to explicit Play variants.
7. Add F-Droid artifact/scanner CI and clean-clone native build validation.
8. Run automated and physical-device validation for both variants.
9. Cut a new Android release tag containing the flavor implementation.
10. Submit the tested metadata/build recipe to `fdroiddata` and respond to reviewer findings upstream rather than with permanent recipe patches.

## Definition of done

The work is complete when:

- `playRelease` preserves current Play billing, telemetry, review, cloud-provider, and Wear behavior;
- `fdroidRelease` builds unsigned from a clean public clone with no credentials;
- the F-Droid runtime graph and APK contain none of the forbidden Play components;
- the F-Droid build is fully usable for Health Connect, exports, scheduling, widgets, API destinations, and Direct CLI;
- the F-Droid build performs no Health.md telemetry and creates no telemetry identity/state;
- unavailable Wear/direct-provider capabilities are absent and never represented as successful;
- common export and protocol fixtures are unchanged across flavors;
- every existing Play release/evidence workflow uses explicit Play tasks and exact new artifact paths;
- both CI matrices pass from the same source revision;
- source, asset, and dependency licensing is documented;
- the F-Droid metadata accurately discloses Health Connect's non-free dependency boundary; and
- a working `fdroiddata` merge request builds the tagged unsigned APK without downstream source patches.
