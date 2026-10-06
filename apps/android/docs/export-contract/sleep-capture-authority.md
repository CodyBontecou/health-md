# Immutable sleep capture authority

Status: compatibility implementation in progress; Morning ends remains production-gated.

One accepted operation owns one calendar timezone, attribution and explicit successor discriminator. A preference or ambient timezone change cannot change that operation. Committed journal/spool bytes remain authoritative and recover before any fresh-capture availability check.

## Android durable settings snapshots

- Snapshot v1 remains readable with its original canonical encoding. Missing capture authority stays missing; decoding never consults current settings or manufactures a successor profile. Existing immutable journals may still commit their saved bytes without recapture.
- Snapshot v2 requires a `sleepCaptureContext` with `calendarTimeZoneIdentifier`, `sleepDayAttribution` and optional `exportProfileID`. The timezone must match the snapshot and engine pin. The mode/profile must agree with the native output profile.
- Fresh Night begins acceptance freezes explicit capture authority in snapshot v2. The current v4/v5 profiles cannot carry Morning ends, including when tagged with a proposed successor discriminator.
- Fresh Morning contexts identify `android-sleep-v6`; draft contexts without this marker remain unversioned on decode and are refused independently of the availability gate. Native v6 execution/writer/snapshot routing is still required before enablement.
- Missing, contradictory, unknown or oversized durable authority fails closed with bounded diagnostics. A pending operation cannot fall back to current preferences. No committed artifact is rewritten to recover it.

Restoration injects transient execution authority into `ExportSettings`; this is never encoded as a mutable preference or portable Shared Setup. Both the field-coverage ledger and native descriptor tests classify this authority as prohibited from setup sharing.

## Explicit successor handoff boundary

The internal `android_sleep_v6` profile selects semantic input/model, render input/plan and registry v2 explicitly. Packaged build-info and all historical profiles remain pinned to their original v1 handoffs. Durable v6 engine pins require Rust authority, the separate registry-v2 hash, and every explicit v2 version; missing/defaulted legacy versions cannot upgrade a draft pin. Current production policy and the historical native exporters reject this candidate rather than falling back to v4/v5.

The post-capture semantic adapter requires the matching immutable Morning context and captured timezone for configuration and every bounded batch. Its separate field projection emits native `sleep_light_hours`, excludes `sleep_core_hours`, and rejects legacy alias requests. The historical extractor's defaults and byte fixtures remain unchanged.

The render adapter checks completed v2 profile/clock/attribution/owner/clipping authority. Explicit captured v6 JSON requests now supply prepared native JSON for every completed owner, with an exact owner-to-captured-day match; missing, extra or mismatched days reject rather than mixing native documents and generated prototypes. Other native presentation and API surfaces remain gated. The plan consumer accepts v2 only with the explicit v6 profile and verifies content, lengths, hashes and profile-scoped identities. V4/v5 still require plan v1; Apple plans remain outside this Android consumer.

Synthetic Kotlin-generated handoffs and a separately core-generated plan live under `packages/contracts/render-input/v2/fixtures/`. Real Rust sessions replay the native requests against literal expected reductions, and Kotlin verifies the core plan. These are post-capture interoperability controls, not independently frozen native public-writer bytes, JNI/device packaging, Health Connect capture, durable v6 acceptance, API/direct adoption or production qualification. The new fixtures/schemas still need manifest inventory and broader negative/roll-up coverage.

## Concrete post-capture planner qualification

`FrozenDailyAggregateExportRequest` copies the captured authority, rejects missing frozen/draft authority and conflicting pin clocks, and passes the same context into the concrete semantic configuration and every batch. The Rust planner prefers that captured clock, not ambient time. Fresh export/preview orchestration now passes operation-only frozen settings to every destination planner; saved preferences remain unchanged.

The local router selects v6 only from the explicit matching Morning discriminator and requires Rust. A pinned v6 request bypasses current policy without borrowing a historical target. Invalid policies, unsupported operations and frozen nil engine authority fail rather than returning a historical legacy plan. Fresh production policy still rejects the separately identified `ANDROID_SLEEP_V6` target, before reading debug overrides; API-v1 stays frozen-v4.

The concrete v6 controls remain overwrite/metric only, without granular/legacy aliases, compatibility provenance, workouts, planned workouts or medical resources. Every admitted request containing JSON now prepares the same native JSON grammar, including empty sleep, populated sleep and non-sleep days. A JSON-only request may include captured sleep sessions with exact source clocks; multi-format requests with those local session fields still reject until native Markdown/CSV/Bases adoption qualifies. In an admitted multi-format request, only JSON receives a native document: other formats keep completed canonical projections, never historical native bodies. Missing exact clocks, draft/mismatched authority and native API use remain rejected. Bare core post-capture prototype controls are not qualification of the native public grammar or production consumer support.

`HostCoreDailyAggregatePlannerTest` explicitly opts into a freshly built host library through `HEALTHMD_HOST_CORE_LIBRARY`. Real UniFFI/JNA calls exercise semantic/render sessions, all four output formats, literal total/Light/step reductions, metadata-off output, empty sleep and pinned router clock authority. Host JNA bootstrap is test-runtime-only at the same pinned version as the Android AAR. Gradle tracks both the opt-in path and library bytes so an old receipt cannot qualify a different binary. Run the host test filter on **each** flavor task:

```bash
# In packages/healthmd-core-rust, then apps/android, respectively:
CARGO_BUILD_JOBS=2 cargo build -p healthmd-core-uniffi --all-features --locked --offline
HEALTHMD_HOST_CORE_LIBRARY=/absolute/path/to/target/debug/libhealthmd_core_uniffi.dylib \
  ./gradlew :app:testPlayDebugUnitTest --tests '*HostCoreDailyAggregatePlannerTest' \
    :app:testFdroidDebugUnitTest --tests '*HostCoreDailyAggregatePlannerTest' \
    -x :healthmd-core:prepareRustDebug --offline --max-workers=2 \
    -Pkotlin.compiler.execution.strategy=in-process
```

Without explicit host opt-in the host planner tests skip. Host execution does not qualify packaged Android JNI/device libraries, Health Connect ownership/clipping, native timestamp/unit normalization, durable v6 acceptance or UI enablement. Morning ends remains unavailable until those and the cross-platform/consumer gates pass.

## Native JSON and API source preparation

`JsonExporter.export(..., captureContext = ...)` has an explicit successor-only entrypoint for a matching Morning/`android-sleep-v6` context. It shares source construction with historical writers, not their public headers or Core aliases. Without this argument the historical branches and frozen byte fixtures remain unchanged. Native Light stays Light. The successor JSON identifies version6, full captured ownership, UTC machine timestamps and metric quantities; requested display units cannot relabel raw SDK quantities.

Machine timestamps come from source epoch seconds/nanoseconds, never `LocalDateTime.atZone`. Both occurrences of a repeated DST wall time retain different UTC instants and original offsets. Source identity, opaque provider metadata/context and native-only payloads survive. Missing/invalid source clocks, draft discrimination and conflicting owner dates fail closed; encoder errors do not expose source values or causes. Only writer-derived stage/lap/segment durations use exact elapsed instants; supplied workout/split aggregates keep their native meaning.

`APIExportEnvelopeBuilder.buildWakeDate` explicitly prepares envelope2/daily6 with the same captured context. Opt-in `buildBatches(..., captureContext = ...)` carries that authority across exact byte/day partitions, including failure-only batches. The historical API-v1 entrypoint still writes frozen-v4 and rejects successor capture/pin authority rather than discarding it. No production runner was switched to this entrypoint.

`WakeDateJsonProducerTest` exercises these real native producers with independently literal DST-fold timestamps/nanoseconds, native quantities, source identity/metadata, interval durations, empty-day bytes and failure-only partition clocks. This is synthetic post-capture JVM evidence, **not Health Connect capture, SDK ownership/clipping or packaged-device evidence**. The prepared document's summary `units` dictionary is currently empty: complete canonical unit dictionaries, native requested presentation, uniform render/plan adoption, API runner/consumer acceptance and comprehensive schema/fixture qualification remain pending. Native JSON now enters every admitted concrete v6 JSON request, not only days with sleep clocks; native API and the other native writers remain unadopted. The production feature gate stays closed.

## Native capture boundary controls

`HealthConnectMorningEndsCaptureTest` exercises the real `HealthConnectManager.fetchHealthDataRange` adapter and `JsonExporter` using actual SDK record types; only the Health Connect IPC client is substituted. Literal New York DST-fold, noon-spanning nap and midnight-ending cases retain original epoch instants/nanoseconds, nullable offsets and source identity, and land on exactly one end-date owner. The captured query remains sleep-only with its pinned clock. Unclassified `sleeping` contributes to the session total but is not reported as Light in Morning ends; the historical Night begins Light alias calculation remains unchanged.

Opt-in host tests take empty and populated native sleep days through the concrete Rust planner and validate one JSON grammar, original UTC bedtime/wake instants and successor identity. Fractional sleep summary seconds retain the existing capture reducer's millisecond quantity; independent source timestamps retain nanoseconds. Native reducers are not changed to invent higher-precision summaries. Canonical quantity/BMI binding remains independently tested through Bases machine frontmatter, not inferred from a native payload that can bypass the summary projection. This proves synthetic SDK-boundary-to-host-plan execution, not actual Health Connect provider/device behavior, packaged JNI, production policy/durable acceptance or consumer readiness. Morning ends remains gated.

SDK aggregate quantities in the successor semantic adapter come from native typed facts rather than rounded display strings. Synthetic matrix controls cover raw binary64 values, integer counts and presentation-unit independence. Historical adapters and frozen native bytes remain unchanged. This internal fidelity correction is not a change to which unrelated measurements the sleep setting captures.

## New actions versus recovery

Scheduled acceptance reads the device setting once. Scheduled runs restore the accepted snapshot. Interactive activation/editing restores output configuration, not a pending capture: a separately requested new export resolves fresh device authority. Those paths must remain distinct so old-profile activation does not grant an old job new capture authority.

Folder export/preview and API capture prefer restored operation authority over live preference reads. API planning uses the captured timezone rather than a reader-local fallback. SDK range capture receives an explicit attribution override for every chunk. Existing journal-first recovery remains unchanged.

See the [shared qualification contract](../../../../packages/contracts/sleep-attribution/v1/contract.md) and Apple's capture-context implementation. Shared-core daily successors, enum registration and JVM capture-authority tests do not establish complete native writer, roll-up, consumer, accessibility, instrumentation or device qualification.
