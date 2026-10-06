# Successor render input and artifact plan v2

Status: owner-authorized implementation, not production-qualified.

This independently versioned boundary accepts only `apple_health_data_v10` and `android_sleep_v6`, canonical model/semantic input v2 and registry v2. Historical render input/artifact plan v1, schemas, closed profiles, frozen bytes and merge behavior remain unchanged. The default build-info versions remain the legacy defaults; callers must select successor versions explicitly, never infer them from latest app/build metadata.

## Authority

Configuration and completed semantic result must agree on profile, registry, revision, session and the complete `sleep_capture_context`, including the captured owner-date timezone. Render/profile revision 2 and all existing bounds/selection attestation remain required. Public outputs obey the [sleep attribution contract](../../sleep-attribution/v1/contract.md).

JSON, CSV and frontmatter/Bases declare the actual native daily version/profile and atomic calendar/timestamp/attribution/owner/clipping authority. Metadata-off Markdown visibly declares the profile, clock and whole-session wake-date ownership without silently re-enabling frontmatter. Custom fields, placeholder/disabled keys, date/type aliases and metric placement cannot override required authority.

Supplied bounded ordered native JSON and CSV are presentation facts, not permission to relabel legacy data. Their version/profile/timezone/attribution must match the completed semantic authority, transactionally. The renderer retains native payloads and row order and owns escaping/format assembly/checksums. Android v6 retains Light rather than emitting a Core alias.

## API and plans

API envelope version remains independent from daily-record identity. Shared successor controls exercise explicitly configured envelopes; native historical Android API-v1 stays frozen-v4, while the separately prepared native Morning ends entrypoint selects envelope2/daily6. Each successor envelope declares `daily_record_schema_version`, `daily_record_schema_profile` and `daily_record_time_context`, including failure-only batches. Its successful records carry matching daily authority. Generated Android API records use canonical metric units and UTC timestamps; local-format clocks must not be relabeled as UTC.

Generated API numeric values are bound to the completed semantic result, not converted from formatted text. Their unit dictionary comes from the pinned profile registry (output unit, or one unambiguous selection unit), with equivalence checked against the reduced semantic unit. Presentation-only unit labels cannot become API authority. Proven spellings such as `steps`/`count` and `%`/`percent` are unit aliases, not conversions of the numeric value.

Supplied ordered native JSON can feed API records only when it is already a prepared canonical document: explicit UTC timestamp authority, metric unit system, matching owner date and every projected value matching its bound semantic value. Existing unit entries must be equivalent to the attested projection units. Native-only payload values, source identifiers and unrelated unit entries are retained; the API unit dictionary and envelope formatting are assembled by the renderer. Local-calendar or imperial documents fail with a bounded presentation error, not a metadata swap. This is **not** native local-clock/imperial normalization or proof of exact SDK timestamps. Native producers still need independently qualified canonical API writers before those local presentation paths can be enabled.

Successor decimal public values are parsed with correctly rounded binary64 conversion before exact semantic binding. Neighboring values, decimal strings/nulls and duplicate value keys still reject; no tolerance or semantic-value substitution is allowed. Historical render-input-v1 parsing is unchanged.

Artifact plan v2 has the same bounded destination-neutral item grammar and write operations as v1, with the successor-only profile set. Native code must verify the plan/item before any side effect. Existing fingerprint/transcript, raw source ownership and opaque committed spool bytes are unaffected.

## Managed Markdown merge

Successor merge is separate from the frozen historical policies. Both incoming and nonempty existing documents must declare the same complete source/profile/version/clock/attribution/owner/clipping authority and use the same metadata surface. An empty target accepts a valid new successor document. Unversioned or historical content, conflicting or ambiguous authority, Android Core aliases and changing metadata-on/off surfaces fail closed. An explicit user-selected overwrite is a different operation; merge never grants migration approval or silently restores disabled frontmatter.

The merge retains physically spliced user YAML blocks/lists, filled placeholders and unmanaged prose while replacing generated properties/sections. Fenced and indented code headings are literal user content, not managed section boundaries. Metadata-off documents retain their visible authority without introducing frontmatter. Native adoption, custom-template/Daily Note injection and independent native merge goldens remain qualification work; these shared-core tests are not evidence that the app can enable the setting.

## Native post-capture interoperability controls

[`native-android-v6-handoff.json`](fixtures/native-android-v6-handoff.json) is emitted by the Kotlin semantic/render adapters from synthetic SDK aggregate facts and explicit capture authority. Rust replays it through real sessions against literal expected reductions. [`core-android-v6-artifact-plan.json`](fixtures/core-android-v6-artifact-plan.json) is emitted separately by the core; Kotlin verifies the populated plan's identities, hashes, lengths, profile/version and defensive copies. Neither fixture invokes a health SDK or destination, and neither is an independently frozen native public-writer golden. These additions are not yet manifest-inventoried; positive schema checks do not qualify the entire v2 grammar.

A separate synthetic SDK-boundary control now executes Android sleep-only `HealthConnectManager` capture (mocked IPC only), native successor JSON preparation and the real host UniFFI planner. It verifies literal epoch/nanosecond clocks on a DST end-date owner. The concrete Android planner now supplies prepared native JSON for every admitted JSON request, independently of sleep presence or co-requested canonical formats; all completed owners require matching captured data. Source clocks retain nanoseconds and sleep quantities retain the existing native millisecond reducer without integer-second serialization loss. Native API, other native formats, comprehensive public grammar/consumer qualification, production acceptance and device/provider behavior remain unqualified. The earlier bare canonical-summary controls are not a native public-writer grammar qualification.

## Incomplete gates

Successor calendar/range output, native merge/Daily Note adoption, native local document/API normalization, native producer/execution integration, independent native public-writer fixtures, consumer adoption and device/accessibility qualification remain tracked by the feature contract. Current post-capture/native-plan, managed-merge and prepared-canonical-record controls are not a declaration that those gates are complete.
