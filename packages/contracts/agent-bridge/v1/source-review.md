# B01/B05 source and API review

Reviewed starting source `23ef94e19a64c770596c82b06a0faa4c3a9c270f`. This revalidates the
[coordinator audit](../../../../docs/architecture/agent-bridge-parity-roadmap.md); no device, health
values, native credentials, provider session, release or notification was accessed.

## Audit revalidation

- [Apple file producer](../../../../apps/apple/HealthMd/iOS/IPhoneDirectFileExportProducer.swift)
  `resolveSelection` validates Apple source/metrics; `resolveSettingsBase` inherits live/profile output
  preferences. `makeInternalRequest` accepts request-local capture but not complete request-owned output.
- [Android coordinator](../../../../apps/android/app/src/main/java/com/healthmd/direct/DirectCliCoordinator.kt)
  accepts only saved-device/profile generated settings; requested scope rejects. Its reserved daily
  product still errors and is not advertised. [Producer](../../../../apps/android/app/src/main/java/com/healthmd/direct/DirectGeneratedFilesProducer.kt)
  uses production exporters and native range reads, not a query evaluator. Existing fallback/empty/error
  behavior must not be copied into a new truthful query capture path.
- [Apple query contracts](../../../../apps/apple/HealthMd/Shared/Query/QueryContracts.swift),
  [Swift evaluator](../../../../apps/apple/HealthMd/Shared/Query/QueryEvaluator.swift), and
  [iPhone coordinator](../../../../apps/apple/HealthMd/iOS/IPhoneDirectQueryCoordinator.swift) own current
  evaluation and paging. This is not an implemented Rust shared query engine. Existing source constants/
  registry [CLI schemas](../../../../apps/cli/crates/healthmd-operations/src/registry.rs) are Apple-oriented.
- [Rust wire hello](../../../healthmd-core-rust/crates/healthmd-protocol/src/wire.rs) preserves the
  existing version array. [Kotlin decoder](../../../../apps/android/direct-protocol/src/main/kotlin/com/healthmd/direct/protocol/DirectCodecs.kt)
  rejects unknown hello properties. V4 uses only the existing version array, then separately negotiated
  closed envelopes; it does not insert unknown optional hello objects.
- [Android native boundaries](../../../../apps/android/docs/export-contract/platform-native-export-boundaries.md),
  [migration policy](../../../../apps/android/docs/export-contract/migration-plan.md),
  [Apple export contract](../../../../apps/apple/docs/features/export-schema.md),
  [Shared Setup v2](../../shared-setup/v2/contract.md) and
  [CLI frozen scope](../../../../apps/cli/docs/production-readiness.md) retain authority.

## Evidence quality and SDK pin

Android Gradle pins `androidx.health.connect:connect-client:1.2.0-alpha02` in
[version catalog](../../../../apps/android/gradle/libs.versions.toml). The locally cached AAR was inspected
with `javap`; its SHA-256 is
`145ec68993ac26f16ebcb408b176bda2f1170e73d46686634270e55d5925e1fa`.
Observed public members include `HeartRateVariabilityRmssdRecord.heartRateVariabilityMillis`,
`SkinTemperatureRecord` nullable baseline/deltas/location and `TEMPERATURE_DELTA_AVG/MIN/MAX`, sleep stage
constants (including UNKNOWN/SLEEPING/OUT_OF_BED/LIGHT/AWAKE_IN_BED), `Metadata` native ID/dataOrigin/
client ID/version/lastModified, and availability/history/background feature constants. No invented
RMSSD aggregate or medication-dose API is used.

Current official Android public pages were successfully retrieved read-only during this lane:

- [Read raw data](https://developer.android.com/health-and-fitness/health-connect/read-data): native page
  tokens may be null **or empty** at terminal; do not leak/reuse SDK tokens as bridge cursors. Cumulative
  steps use `aggregate`, not raw sum. History generally starts 30 days before first permission grant
  unless history permission is available+granted; reinstall resets that boundary. Own-data exceptions
  differ by OS and are not proof of other-provider full history. Foreground services can continue reads;
  background read permission is separate, not granted by pairing.
- [Read aggregated data](https://developer.android.com/health-and-fitness/health-connect/aggregate-data):
  sparse aggregate buckets may be absent, not zero. User priority affects deduplication of Sleep and
  Activity; other types combine source data. Period buckets require LocalDateTime, not Instant. Preserve
  aggregate attribution and exact canonical units, and disclose native priority semantics.
- [Feature availability](https://developer.android.com/health-and-fitness/health-connect/features/availability):
  SDK presence does not mean provider support. Use `getSdkStatus` and per-feature `getFeatureStatus`, then
  permission checks. Android 13 APK providers cannot expose Android 14 module-only features.

The raw pages/SDK member dump and hashes are retained in coordinator lane evidence, not product source.
The latest page mentions framework `getCurrentDeviceDataSource` and `FEATURE_MATCHMAKING`, which are
**not** claimed available in this pinned Jetpack library. On-device step synthetic package names must
not be hardcoded or conflated with user identity. Fresh installed OS/module/provider/version evidence
is still required by B06/B22. No live provider availability was observed.

Apple production selectors/contracts/authorization/evaluator were reviewed; the identity refinement also
inspected the **installed iOS Simulator SDK 26.5 public headers** (Xcode 26.6, build 17F113), including
`HKObject.h`, `HKSample.h`, `HKObjectType.h`, `HKTypeIdentifiers.h`, `HKMetadata.h` and Foundation `NSDate.h`.
Header copies/digests and a fresh pinned Android `javap` identity dump are retained in lane evidence.
This is current local SDK/API evidence, not a device observation or Rust/Swift/Kotlin DTO pass. No live
HealthKit call ran, and current Apple web pages were not retrieved; broader vendor/runtime review is
still a native-adapter gate.

## Native identity, metadata and time evidence (B05 refinement)

- [`HKObject`](https://developer.apple.com/documentation/healthkit/hkobject) public SDK header exposes
  original UUID, source/sourceRevision, nullable device and metadata. [`HKSample`](https://developer.apple.com/documentation/healthkit/hksample)
  adds sampleType, startDate/endDate and duration state. Neither exposes an Android-style system
  last-modified timestamp or client-record ID/version. The existing
  [Swift evidence projector](../../../../apps/apple/HealthMd/Shared/Query/HealthMdQueryContextProjector.swift)
  reads original UUID, exact objectTypeIdentifier and sample start/end; it does not provide those Android
  fields. `HKSourceRevision.version` is source-application version, **not** record version.
- `HKMetadata.h` defines optional `HKMetadataKeySyncIdentifier`/`HKMetadataKeySyncVersion` as client-supplied
  sync/replacement metadata. They are not a system last-modified timestamp or automatically equivalent
  Health Connect client metadata. This view does not map them into `client_record_*`; if later needed,
  retain them as independently named source metadata after review. No zero version, capture-time
  timestamp or sample-end timestamp fills an unsupported field.
- [`HKObjectType.identifier`](https://developer.apple.com/documentation/healthkit/hkobjecttype/identifier)
  is the exact HealthKit type string. SDK declarations include `HKQuantityTypeIdentifierStepCount` and
  `HKQuantityTypeIdentifierHeartRate`. Canonical production capture preserves `sample.sampleType.identifier`;
  the new `record_type`/catalog `native_record_type` grammar preserves case, unlike semantic selection IDs.
- Pinned `connect-client:1.2.0-alpha02` `Metadata` has `getId`, `getDataOrigin`, `getLastModifiedTime: Instant`,
  nullable client ID and signed-long client version. The
  [production mapper](../../../../apps/android/app/src/main/java/com/healthmd/rawexport/RawHealthConnectMapper.kt)
  preserves those actual values, Instant seconds/nanos and nullable ZoneOffset. `Record.getMetadata`
  establishes ownership by the actual SDK record; class names such as
  `androidx.health.connect.client.records.HeartRateRecord` are exact SDK identifiers, not `heart_rate_avg`.
- `HeartRateRecord.Sample` is a nested SDK child with time/beats-per-minute but **no Record Metadata or
  native record ID**; it is a derived child with parent identity, never a new native UUID. `MedicalResource`
  is a separate class, not a `Record` exposing ordinary `Metadata`; its first typed-query row stays
  unavailable. Provider-native records likewise carry only their own reviewed API metadata, not copied
  Health Connect/HealthKit fields.
- Foundation `NSDate.h` defines `NSTimeInterval` as `double` and `timeIntervalSince1970` with that type.
  HealthKit timestamps therefore do **not** prove integer nanosecond storage/accuracy. The new view keeps
  exact returned IEEE-754 binary64 epoch-seconds bits and labels a checked nanosecond-normalized view;
  it does not assert nanosecond sensor precision. Android Instant seconds/nanos retain source nanosecond
  representation; provider milliseconds/seconds are explicitly labeled and cannot carry extra precision.
  A missing original zone offset stays null; the export calendar or current device zone is not invented
  as a source offset.

Source-specific closed identity branches now omit unsupported fields and require `metadata_status`:
`available` means the actual source value is present, `absent` is only a supported-but-unset client ID,
`not_captured` reports missing capture without substituting a value, and `not_exposed_by_source` forbids
one. HealthKit sets all three Android metadata statuses to not-exposed and admits no corresponding
value members. Derived children admit no copied parent system metadata. Ordinary captured Health
Connect records can retain actual version zero; zero is not an unavailable sentinel. Unavailable HC
catalog rows with no equivalent native type omit `native_record_type` rather than inventing an HK type.
All of these fixture cases are synthetic; installed-provider/native availability is still unverified.

## Bounded reviewed metric catalog

[Machine catalog](reviewed-query-catalog.json) is a **planning inventory**, not a runtime advertisement.
It reuses exact existing registry semantic IDs and classifications. Fake-peer fixtures mark supported
hypothetical rows only for testing a future installed catalog; they are not production availability.
All additional metrics outside this reviewed edition must be unsupported until individually reviewed.
No metric-registry row is added or reclassified here.

| Meaning | Native evidence and canonical query unit | Query rule / distinction |
|---|---|---|
| `steps` | HK StepCount / HC StepsRecord, `steps` | Native daily aggregate (HC COUNT_TOTAL); priority-aware, not raw-record sum. Period sum checked; `count` counts available daily facts, not steps |
| `heart_rate_avg` | HK HeartRate / HC HeartRateRecord BPM_AVG, `bpm` | Existing `mapped_alias`; SDK daily average is a native fact, not pooled average of raw samples or cross-day weighted mean |
| `android.hrv_rmssd` | HC HeartRateVariabilityRmssdRecord, `ms` | Source-start civil day; daily latest exact same-day record. Explicit period average/min/max/latest over these facts only; no invented HC aggregate |
| `hrv` | HK HRV SDNN, `ms` | Existing Apple semantic ID; unavailable for HC; never substituted by RMSSD despite legacy Android `hrv` selector |
| `wrist_temperature` | HK AppleSleepingWristTemperature, `degC` | Apple wrist measurement, unavailable for HC; never renamed skin delta |
| `android.skin_temperature` | HC baseline/deltas/location + TEMPERATURE_DELTA_AVG/MIN/MAX, `degC_delta` | Feature-gated interval deltas; nullable absolute baseline retained only native evidence, no fabricated absolute wrist value |
| `sleep_total` | HC SleepSession native intervals, `hours` | New view explicitly retains native noon-journal additive clipped interval rule, not SDK priority-dedup total or Apple asleep duration equivalence |
| `sleep_core` | HK Core / historical HC Light alias, `hours` | Existing `mapped_alias`; historical projection remains frozen, query row unavailable pending stage/overlap review; native LIGHT retains its own raw stage identity |
| `workouts` | HK Workout / HC ExerciseSession, `count` | Native source-start day, exact interval listing, identity-qualified; count of completed sessions. Duration facts use a separate metric/unit before comparison, never `count`+hours |
| `blood_oxygen` | HC OxygenSaturationRecord Percentage, canonical `ratio` | Divide 0..100 by 100 exactly; never chart percent and ratio under one unit; no missing→zero |
| `android.medical_resources` | HC feature-gated PHR/FHIR medical resources | Separate product; unavailable in the first fixed typed query edition. Not medication-dose events, requires separate permissions and adapter |
| `clinical_medication_records` | HK ClinicalRecord | Current App Store capture is disabled; historical decoding does not authorize new reads; unavailable on HC and current Apple bridge builds |

The catalog is not a daily writer/dictionary authority: e.g. query `ratio`, `degC_delta` and aggregate
meaning do not rewrite frozen exporter keys/units. Registry `platform_exact_or_unavailable` for sleep
is evidence about that registry row, not a claim that the current Android additive compatibility summary
and Apple asleep calculations are identical. Source statistic/owner rule remains explicitly different.
Source records retain metadata/native identity; aggregate facts have no fabricated source-record UUID.

## Operation-by-operation semantics

| Fixed operation | Native boundary / deterministic rule | Dates, missingness and evidence |
|---|---|---|
| `metric_catalog` (`healthmd_metrics`) | Read registry + SDK/provider feature/permission/history configuration; no health query | No values. Installed support/permission/feature/unverified history reported independently; offline catalog is planning only |
| `metric_series` / charts | Native SDK facts in reviewed units/statistics; deterministic sorting/page projection | **Daily aggregate facts**, not intraday source observations; no hidden carry-forward. Gaps/partial history remain gaps. PNG consumers must reject mixed/unknown units |
| B08 selected projection | Explicit projection intent/selectors, source-observation identities/timestamps and pre-read durable v4 acceptance | `steps.count` retains StepsRecord start/end/count; `heart_rate.samples.bpm` retains Sample time/BPM and parent identity, never daily average or copied Metadata. Exact v4 fingerprint/manifest/spool governs transfer/resume; not a transient selector RPC |
| `sleep_session_listing` | HC native sessions/stages; source-start noon journal identity; all valid sessions additive only in explicitly labeled native summary | Exact session timestamps uncut; summary interval clipped to journal. UNKNOWN/SLEEPING/LIGHT/Core remain distinct; no guessed nap/main-sleep classification from duration. Unsupported nap classification explicitly unclassified; include-naps=false cannot silently drop unknowns |
| `workout_listing` | HC ExerciseSession records including native activity; no fuzzy cross-provider dedup | Source-start owner day, exact unclipped interval. Route is not implied by session listing or normal READ_EXERCISE; explicit native route grant only, absent route/PHR not empty success |
| `coverage` | Receipt of every planned read branch and authorized window, not query value presence alone | Complete-empty only when supported branch succeeded with no records. Unknown first grant/history/revoked permission produces unavailable/partial with exact reason; SDK error strings never exposed |
| `period_comparison` | Unique explicit per-metric descriptors; period reduction of labeled daily facts only | Both periods inside selection, expected unit exact; missing siblings prevent delta, no saturation/causation. Count uses checked exact integer arithmetic |
| `workout_sleep_alignment` | Each workout paired with first following eligible sleep start, tie-break native qualified identity; noncausal factual temporal relation | No overlapping/pre-workout sleep guessed as recovery. Include eligible adjacent-day capture only after explicit approved scope expansion; otherwise partial/unavailable. Window physiology must stay selected/authorized; no hidden metric reads |
| `source_record_listing` | Exact native IDs/types and source-specific observed metadata/precision; unavailable metadata omitted, child identity explicitly derived | Explicit native-evidence authority/detail. SDK raw snapshot/provider schema remains native, no fabricated HKObject, UUID, device or permission conclusion |
| `derive_packet` | Bounded typed factual packet: wellness/training/doctor-visit facts, no free text medical interpretation | Only selected metrics/dates/sources/detail. Coverage and evidence references from captured dataset; kind does not widen scope or authorize PHR/clinical access |

All operations use Health Connect history and provider feature checks, one bounded cancellation-aware
native capture and immutable dataset cursor lifecycle. The existing native exporter fallback to fetching
an entire day is not acceptable scope behavior for B06. Partial results cannot silently widen scopes.

## Producer/consumer inventory and residual gates

Affected future producers/consumers: Rust `healthmd-protocol` models/digests (not capture), Swift
Connectivity/native settings resolver/exporter/query adapter, Kotlin direct-protocol/native repositories,
portable CLI/client/operations/MCP/catalog/Apps/PNG, website capability docs, external Obsidian readers of
shipped profile bytes plus new dictionary/projection if adopted. No product implementation changed here.

The refinement additionally rechecked Rust v2 `ExportAccepted`/`ProductId` and generic transfer DTOs:
`android_daily_records_v1` stays reserved; `generated_files_v1` is not a projection acceptance disguise.
Only v4 accepts/journals this product. V2 `TransferSession` can carry the v4 request fingerprint, and its
unchanged `ArtifactManifest` permits generic `kind: generated_file`, string schema ID/major and existing
media/path/mode/byte/digest fields. Frames/partition/final-ack structures remain unchanged. The new v4
adapter, selector capture, native v2 decode and physical transfer/resume have **not** been run.
[Projection catalog](reviewed-projection-catalog.json) is five bounded planned mappings from pinned SDK
StepsRecord count/start/end, COUNT_TOTAL, HeartRateRecord BPM_AVG and Sample time/beatsPerMinute APIs;
parent Sample identity has no own native metadata. This is not implementation/provider qualification.

Coordinator reported baseline Rust vectors/tests and Swift Connectivity 55 passing independently;
this lane does not attribute that to new v4 conformance. Baseline `make check-core-registry` already failed
only `known_capability_ids` and `available_capability_ids_by_platform` importer drift (metric/profile rows
identical), while registry-adapters check passed. New capability rows require coordinator central
health-free capability-index regeneration after wave integration. The registry and frozen setup/semantic
fixtures are read-only in this lane. Native vendor/runtime review, new Rust/Swift/Kotlin generation,
physical qualification and broader metric support remain not run/planned.
