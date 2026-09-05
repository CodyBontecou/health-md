# Health.md Shared Setup v2

## Status and scope

`healthmd.shared_setup` version 2 is the deferred, language-neutral contract for sharing a bounded bundle of named Health.md setup profiles between Apple and Android. The observable outcome remains **Share My Setup**: a recipient can review and choose how to apply portable export preferences without receiving health records, credentials, native destination bindings, or operational state.

Version 2 is a separate grammar from the immutable [version 1 contract](../v1/contract.md). It adds named multi-profile bundles, exact split data-detail policies, per-profile destination and schedule intent, and typed Apple and Android v2 extensions. It does not change Apple `healthmd.health_data` v8, Android v4/v5 output, any raw-snapshot or HealthKit archive schema, or a direct-device protocol. Canonical status remains deferred until native import transactions, physical-device interoperability, and accessibility gates are complete.

The registered representation remains UTF-8 JSON with:

- extension `.healthmdconfig`;
- media type `application/vnd.healthmd.configuration+json`;
- Apple uniform type identifier `com.healthmd.configuration`;
- maximum encoded input size **4,194,304 bytes**.

## Reader and writer rules

A file is attacker-controlled. A reader MUST use this order:

1. read at most 4,194,304 bytes (plus a one-byte overflow probe);
2. parse generic JSON without constructing a versioned setup DTO;
3. require root `schema` to equal `healthmd.shared_setup` and require `schema_version` to be a JSON integer, never a Boolean, floating-point number, string, or `null`;
4. dispatch only integer version `1` or `2`, using the version-specific byte limit and grammar;
5. before versioned decoding, recursively reject depth greater than 20, any object or array with more than 512 members/items, any string or key with more than 65,536 Unicode scalar values, invalid Unicode scalar content, non-finite numbers, or more than 262,144 total JSON nodes;
6. run schema, prohibited-content, path, endpoint, ordering, reference, registry, and cross-field checks;
7. produce a human-readable compatibility preview without writes;
8. apply only after explicit confirmation and native transactional checks.

Version 1 keeps its own 262,144-byte, depth-16, container-256, key-256, and 16,384-node limits and continues to use its frozen schema and semantics.

Readers MAY ignore bounded unknown optional fields after the complete generic preflight and recursive security scan. Ignored input is never applied, persisted, put into Undo state, or re-exported. Writers are closed DTO allowlists: they MUST emit only fields defined by the [v2 JSON Schema](shared-setup.schema.json), including every required field. Writers do not retain unknown reader input.

Canonical fixtures and deterministic writers encode sorted compact JSON in UTF-8 with one trailing LF. JSON object keys are lexicographically sorted by the canonical encoder. Array order follows the rules below; array order is never repaired by a reader.

## Prohibited content

A v2 artifact MUST NOT contain:

- health records, samples, measurements, source payloads, raw-snapshot contents, or export output;
- account, user, person, device, installation, native profile, destination, endpoint, schedule-entry, pairing, worker, alarm, or operation identifiers;
- native profile UUIDs, folder bookmarks, security-scoped bookmarks, native root paths, Android SAF/content URIs, folder grants, or Mac pairing state;
- credentials, passwords, tokens, cookies, request/authorization headers, OAuth state, or inherited endpoint authentication;
- permissions, purchases, entitlements, onboarding, analytics, or export history;
- runtime timestamps, timezone, progress, last-run/success state, retries, pending work, destination fingerprints, or renderer/engine authority pins;
- a schedule enabled flag or native worker/alarm identity;
- v1 `include_granular_data` or weekly/monthly/yearly roll-up preferences.

`cadence.anchor_date` is date-only phase intent and is not runtime history. Bundle-local `bundle_id`, registry semantic IDs, and reviewed registry selection IDs are the only IDs in the grammar. Android `raw_snapshot` contains typed **preference options only**, never source records; it is not an Apple HealthKit archive.

Custom Markdown, custom frontmatter values, profile names, and endpoint host/path are intentionally portable user-authored text. Share UI MUST disclose that these may reveal personal, tenant, or routing information and MUST show them in recipient preview. They are copied as data, never executed. Authorization-looking strings and device-bound URI forms still fail closed.

## Root bundle

Every v2 document contains exactly one language-neutral bundle envelope:

- `schema`: exactly `healthmd.shared_setup`;
- `schema_version`: integer `2`;
- `created_by`: non-authoritative `platform` (`apple` or `android`) and bounded `app_version` only;
- `metric_registry`: exactly `healthmd.metric_registry` version `1` and the lowercase SHA-256 of the source registry bytes;
- `profiles`: one through 100 profile objects in native profile-store order;
- `active_profile`: one bundle-local profile reference;
- `metric_aliases`: the exact registry-ledger union described below.

`created_by` carries provenance, not user/device identity. It never grants the sender platform authority over a preserved foreign extension.

### Profile identity and order

The profile at zero-based array index `i` has exactly the bundle-local ID `profile-NNN`, where `NNN` is the one-based index padded to three digits. Thus the only valid sequence is `profile-001`, `profile-002`, … through at most `profile-100`. These IDs are synthesized for this artifact, have no stability outside it, and MUST NOT be copied from or reused as native identity. A local transaction sidecar may associate a source bundle ID with a separately generated native ID only to preserve the source DTO and compatibility meaning described below.

`active_profile` MUST exactly equal one emitted `bundle_id`. Profile names are non-empty, have no control characters, equal their whitespace-trimmed form, and are unique under Unicode case-insensitive comparison. A reader does not rename duplicates or repair order.

## Metric selection and root alias union

Each profile has `metrics.enabled_ids`, the sorted unique canonical semantic IDs selected for common output, and `individual_entries.metrics`, a semantic-ID-keyed map. Native category IDs, category selections, or native profile selection state never appear and never enable a metric.

Root `metric_aliases` contains exactly one row for the union of:

1. every semantic ID in every profile's `metrics.enabled_ids`; and
2. every key in every profile's `individual_entries.metrics`, including rows whose `enabled` value is `false`.

Rows are unique and sorted by `semantic_id`. The generic 512-item container bound is also the maximum union size. Each row carries `semantic_id`, registry `equivalence` (`platform_exact_or_unavailable`, `mapped_alias`, or `platform_distinct`), and exact Apple/Android `selection_id` or `null` when unavailable.

If `metric_registry.registry_sha256` identifies the receiver's exact registry bytes, the receiver verifies every known row against that registry and rejects unknown or changed evidence. If it differs, syntactically valid unknown semantic IDs are retained only in the in-memory compatibility report as `requires_action`; they are not applied or persisted into native selection. A reader never trusts a source-native selection ID as apply authority, infers an alias from a label, or substitutes a related metric.

## Common profile fields

Every profile contains `bundle_id`, `name`, and the following common sections.

### Export

`export` serializes effective portable values:

- `formats`: unique values in lexicographic canonical order `csv`, `json`, `markdown`, `obsidian_bases` (a subsequence, and possibly empty);
- `include_metadata` and `group_by_category`;
- one-segment `filename_template` and destination-relative `folder_template`;
- `write_mode`: `overwrite`, `append`, or `update`;
- `compatibility_detail`: `summary` or `selected_time_series`.

`compatibility_detail` means portable summary output versus reviewed selected sample-series output. It says nothing about Android raw snapshots or Apple canonical source archives.

### Presentation, individual entries, and Daily Notes

`presentation`, including its `frontmatter` and `markdown` objects, has the same typed values and bounds as v1. Ordered frontmatter field and placeholder arrays retain their sender setting order; writers must emit that order deterministically. Custom Markdown is preserved verbatim. Portable tokens and non-nested conditional blocks retain their v1 meanings; malformed or unsupported dialect tokens produce `requires_action` and leave the recipient's local template unchanged.

`individual_entries` retains the v1 common shape: effective master toggle, semantic-ID keyed metric rows, relative entries folder, category-folder preference, and explicit filename template. Per-metric folders are relative. Metric-map keys participate in the root alias union even when their row is disabled.

`daily_notes` retains the v1 common shape: `enabled`, relative `folder`, one-segment `filename_template`, `create_if_missing`, and `inject_sections`. Apple Daily Notes Only remains the typed Apple extension field.

## Destination intent

Each profile requires:

```json
{"kind":"device_folder|connected_mac|api_endpoint|cloud","api_endpoint":null}
```

`api_endpoint` may be non-null only when `kind` is `api_endpoint`; a null endpoint is valid unconfigured API intent. Apple writers currently originate `device_folder`, `connected_mac`, or `api_endpoint`. Android writers currently originate `device_folder` or `api_endpoint`. `cloud` is a typed preservation/future intent only and MUST NOT be inferred from iCloud/File Provider state, a filesystem path, or an Android SAF URI.

All imported destination kinds are inert and pending. Import does not resolve, inspect, open, create, pair, authenticate, or bind a destination. A recipient must separately choose a local folder, enter endpoint credentials, select a cloud account, or pair a Mac. Existing local credentials and bindings are never inherited.

A non-null endpoint uses the exact safe v1 hint: HTTPS `scheme`, DNS `host`, nullable numeric `port`, absolute URL `path`, `query_omitted`, and `credentials_required: true`. Userinfo, percent escapes, `//` network paths, queries, fragments, control characters, credentials, and headers are forbidden. Native code constructs the reviewed URL from components rather than concatenating an untrusted URL string. No network request occurs during import or preview.

## Schedule intent

`schedule` is either `null` or a declarative object containing:

- `activation_requested` sender intent;
- `cadence.value` from 1 through 365, `cadence.unit` (`days`, `weeks`, or `months`), and date-only `cadence.anchor_date` (`YYYY-MM-DD`);
- `local_time.hour` and `local_time.minute`;
- ISO weekday 1 through 7;
- `lookback_days` from 1 through 365;
- `date_window`: exactly `past_complete_days`.

The phase date, local wall time, and weekday do not include a timezone. Import ALWAYS creates or stores native schedule state disabled. `activation_requested` is not an enabled flag. Activation is a separate local action after exact cadence support, destination rebinding, permissions, authentication, background capability, and entitlement checks. Unsupported cadence or target meaning is preserved/reported and never approximated.

When an Apple extension is present, its schedule is null exactly when the common schedule is null. A `daily` Apple schedule corresponds to common cadence `{value: 1, unit: days}`; `weekly` corresponds to `{value: 1, unit: weeks}`; `custom` uses the extension's exact `custom_unit`. Contradictions are invalid.

## Typed per-profile extensions

Every profile contains `platform_extensions` with required `apple` and `android` keys. Each value is either `null` or a closed, typed `extension_version: 2` object. Every profile emitted by a writer MUST have a non-null extension for `created_by.platform`. A foreign extension is emitted only when preserving a previously imported typed extension; otherwise it remains `null`. Receivers preserve unsupported foreign typed meaning per profile for an explicit compatibility report, never apply it as an approximation, and never fabricate foreign defaults.

### Apple v2

The Apple extension contains:

- export organization, ZIP/archive-files, data-dictionary, and summary-only preferences;
- `healthkit_source_archive`: `none` or `canonical_v1`;
- the single current `generate_range_summary` preference;
- Daily Notes `only`;
- nullable typed schedule detail: `frequency`, `custom_unit`, Today Refresh request, and interval 3, 6, or 12 hours.

Common `compatibility_detail` and Apple `healthkit_source_archive` are orthogonal and preserve all four exact policies:

| Policy | `compatibility_detail` | `healthkit_source_archive` |
| --- | --- | --- |
| Summary | `summary` | `none` |
| Detailed Time-Series | `selected_time_series` | `none` |
| Archive-only | `summary` | `canonical_v1` |
| Lossless | `selected_time_series` | `canonical_v1` |

No reader derives one axis from the other. The old combined granular Boolean and old weekly/monthly/yearly roll-up list are not v2 fields. `generate_range_summary` is the only current Apple range-summary preference.

### Android v2

The Android extension's `export` object contains every current typed option:

- `mode`: `compatibility` or `raw_snapshot`;
- `legacy_primary_format`;
- `compatibility_profile`: `frozen_v4` or `analytical_v5`;
- legacy-alias and Android-native-field switches;
- all 12 `legacy_data_types` filters (`sleep`, `activity`, `heart`, `vitals`, `body`, `nutrition`, `mobility`, `reproductive_health`, `mindfulness`, `workouts`, `planned_workouts`, and `medical_resources`);
- destination-relative `subfolder` and folder organization;
- `raw_snapshot` preferences: `json`/`ndjson`, selected/all-authorized scope, exercise-route inclusion, and page size 1 through 5,000.

All fields are serialized even when `mode` is `compatibility`, so switching modes does not require guessed defaults. Android raw-snapshot settings are platform-distinct Health Connect source-read preferences. They MUST NOT be mapped to, labeled as, or used to enable Apple `healthkit_source_archive`; preserving both typed extensions in one profile does not claim equivalence.

## Deterministic ordering and bounds

In addition to the generic preflight limits:

- profile count is 1 through 100;
- bundle IDs are sequential and profile order is native store order;
- formats, enabled semantic IDs, and aliases are lexicographically sorted;
- ordered presentation arrays retain deterministic sender setting order;
- metric selections, frontmatter fields, and individual metric maps are capped at 256 per profile;
- custom values and placeholders are capped at 128;
- path/template strings are capped at 4,096 characters;
- custom Markdown is capped at 65,536 characters;
- the alias union is capped at 512 by generic container policy.

Every folder is destination-relative. Empty folder text means the future recipient-selected root. A non-empty path cannot be absolute, have a drive prefix, percent sign, backslash, URI scheme, control character, repeated separator, or `.`/`..` component and must resolve inside the locally selected root. Filename templates are non-empty single segments with the same exclusions.

## Compatibility results and apply boundary

Preview reports reviewed items as `applied`, `requires_action`, `unsupported`, or `invalid`, retaining the v1 meanings. Preview and profile-selection changes perform no writes. They do not allocate persisted native identity, change the active profile, bind or inspect a destination, create a schedule row, or write sidecar/Undo state. The immutable validated import plan, not mutable UI state or a second decode, is the sole input to apply.

Unsupported platform extensions, custom-template meaning, destination/schedule meaning, and registry IDs are reported rather than approximated. `applied` means that the portable setting is exactly representable in a fresh local snapshot; it does not mean that a destination is bound, a schedule is active, or the deferred v2 writer is canonical.

## Add, Replace, and native materialization

The transaction input is one fully validated v2 import plan, mode `add` or `replace`, and an explicit non-empty collection of selected `bundle_id` values. Before any mutation, the implementation MUST reject a non-string or empty value, a duplicate, an ID absent from the plan, an empty selection, a stale/changed plan, an unrepresentable resulting profile count/name, or any sidecar/Undo bound failure. It then normalizes the selection to `profiles` document order. Caller order, set iteration order, and UI tap order never determine persistence order.

Every selected source profile receives a fresh injected native profile identity that is unique against both the existing store and the other imports. `bundle_id` is retained only as source-document identity in compatibility sidecar state; it is never used or persisted as native profile identity. Native creation/update timestamps, when required internally, are newly generated local state and never come from the artifact.

### Add

Add preserves every existing native profile and schedule row byte-for-byte and in its existing order, retains aligned existing sidecar/blocked rows, then appends selected profiles and any exactly representable schedule rows in normalized source order. Imported names use the existing deterministic profile-store collision rule:

1. use the already-trimmed source name as the base;
2. compare names with locale-independent Unicode full case folding after trim, with no locale tailoring or additional Unicode normalization;
3. if the base comparison key is free, retain the source spelling;
4. otherwise try `Base 2`, `Base 3`, and so on, choosing the first free comparison key and considering earlier imports in the same transaction;
5. fail before mutation if the resulting name cannot be represented within the native/profile bound.

Thus a local `Café` collides with imported `CAFÉ`, while canonically different Unicode sequences are not silently normalized into one name. The imported source document itself already proves that its own names are unique under the same case-fold comparison.

If the pre-transaction active native ID still references an existing profile in the Add candidate, it remains active. If it is absent, null, or dangling, the selected source `active_profile` becomes active when selected; otherwise the first selected profile in normalized document order becomes active.

### Replace

Replace discards the existing profile list from the candidate and creates only the selected imported profiles in normalized source order. It also removes every pre-transaction scheduled-profile, sidecar, and blocked-ID row from the candidate; the resulting sidecar/blocked state contains only the selected generated profiles. Replace retains source names exactly because a validated v2 document already proves trimmed case-insensitive uniqueness. The selected source `active_profile` becomes active when selected; otherwise the first selected profile in normalized document order becomes active.

Replace changes only the profile/schedule/sidecar/blocked state covered by this transaction. It does not delete destination records or secure-store values formerly referenced by removed profiles.

### Unbound and blocked imported profiles

A selected profile receives a fresh native output-settings snapshot only for exact common settings and an exact supported native extension. The receiver owns its local engine, timezone, destination identities, credentials, authorization, purchases, and runtime state. Unsupported custom-template or other semantic meaning is retained for review and is not installed through a guessed fallback.

A destination kind may be projected to the closest native display/configuration intent, but every imported folder/API binding field is `nil`. Connected-Mac and cloud meanings remain pending rather than being mapped to a local folder or endpoint. Import never resolves, lists, reads, opens, creates, pairs, authenticates, or probes a destination, and never inherits an existing binding merely because its kind or endpoint hint resembles the source intent.

Every generated native profile ID is added to the local blocked/pending-destination set. Activation, manual/profile-scoped export, scheduled execution, App Intent/automation, and direct profile resolution MUST fail closed with a bounded non-secret reason while that ID remains blocked; none may fall back to live/global settings or a global destination. Only a later explicit local rebind gate may clear it. Folder intent requires a concrete locally selected binding, API intent requires a locally confirmed endpoint/credential flow, connected-Mac intent requires explicit local pairing/rebind confirmation, and cloud remains blocked until supported. Opening, editing, renaming, or duplicating the profile is insufficient.

For each selected non-null schedule that is exactly representable, the candidate may contain one fresh native schedule row. It is always disabled: `isEnabled` is false and enabled-at, progress, history, retry/pending-work, last-run/success, operation, and worker/alarm identity are absent or empty. `activation_requested` remains inert sender review intent and MUST NOT be interpreted as runtime enablement. A null schedule creates no row. Unsupported schedule meaning remains sidecar-only and is never rounded or substituted.

## Per-profile compatibility sidecar

The local sidecar has version `1` and one ordered `profiles` array in resulting native profile-store order. Native encoders may use their ordinary same-platform JSON field casing only when the corresponding local reader is proven semantically compatible. Each imported row contains exactly:

- generated native `profile_id`;
- original `source_bundle_id`;
- the complete closed `source_profile` v2 DTO;
- unique `unsupported_semantic_ids` in lexicographic order.

The complete source profile is the single retained meaning for pending destination/schedule intent, foreign typed extension, unsupported custom template, and other reviewed portable fields; an implementation MUST NOT split off a lossy second interpretation. Add retains sidecar rows for preserved existing profiles and appends selected rows in profile-store order. Replace retains only rows for the selected replacement profiles. A foreign typed extension and unsupported semantic ID remain attached to the generated profile identity that came from their source row, including after source-selection normalization.

The encoded aggregate sidecar is bounded to 4,194,304 bytes. It contains no credentials, grants, bookmarks/URIs, pairing state, local destination data, runtime state, or health data. Bound and complete-encoding checks happen before mutation.

The frozen local persistence keys are implementation interoperability constraints, not public artifact fields:

| Platform | Profiles | Active profile | Schedules | v2 sidecar | Blocked IDs | One-shot Undo |
| --- | --- | --- | --- | --- | --- | --- |
| Apple | `exportProfiles.list` | `exportProfiles.activeProfileID` | `scheduledExportEntries.list` | `sharedSetup.apple.v2.profileState` | `sharedSetup.apple.v2.blockedProfileIDs` | `sharedSetup.apple.v2.undo` |
| Android | `export_profiles` | `export_profiles_active_id` | `scheduled_profile_entries` | `shared_setup_v2_profile_state` | `shared_setup_v2_blocked_profile_ids` | `shared_setup_v2_undo` |

## Atomic apply, rollback, and one-shot Undo

Apply and Undo operations are serialized. The candidate covers profiles, active identity, scheduled-profile rows, sidecar rows, the blocked-ID set, and exactly one local Undo value. Before the first write, the implementation completely encodes the candidate and an Undo snapshot of the exact prior values/absence for those stores. The sidecar is bounded to 4 MiB and the complete Undo payload to 8 MiB.

A successful Add or Replace persists one previous-state Undo snapshot, verifies the complete candidate by readback, and reports success only after verification. Cancellation before commit leaves state untouched. Once commit begins, cancellation cannot expose a partial candidate: the implementation finishes verified commit or performs verified rollback.

On any encoding, write, synchronization, or verification failure, rollback restores and verifies the exact prior profile bytes/order, active identity or absence, schedule bytes/order, sidecar or absence, blocked set or absence, and the prior Undo value or absence. Apple may implement this as a bounded verified multi-key commit/restore. Android uses one DataStore edit for the candidate and, if post-commit semantic verification fails, compare-and-set rollback. An implementation that cannot attest rollback MUST report an unverified rollback and fail closed; it must not claim that prior state is intact.

Undo restores and verifies the profiles, active identity, schedules, sidecar, and blocked set from the single snapshot, then removes and verifies removal of that snapshot. A second Undo returns `no_undo_snapshot` and performs no writes. If Undo fails before verified completion, it restores the post-apply state and keeps the same Undo snapshot available; inability to verify that recovery is an unverified rollback failure.

Add, Replace, failed-apply rollback, and Undo never mutate the destination store or secure credential store. They never delete, rewrite, relink, or copy a folder grant/bookmark/SAF URI, endpoint credential/header, cloud account, or Mac pairing. Explicit rebinding is a separate local transaction outside this contract.

## Transaction scenario and public-artifact isolation

The [transaction scenario fixture](fixtures/transaction-scenarios-v1.json) is deterministic local test infrastructure, not a `healthmd.shared_setup` document, public wire field, native persistence grammar, or claim of production availability. Its explicit local-only envelope may name synthetic native profiles, schedules, bindings, blocked rows, and runtime sentinels so Add/Replace/rollback/Undo results can be compared exactly. Those values MUST NOT be copied into its embedded public source DTO or either canonical public v2 artifact fixture.

Validation recursively proves selection normalization, active-profile fallbacks, collision suffixing, nil imported bindings, disabled imported schedules, per-generated-profile foreign/unsupported preservation, exact rollback, Undo consumption, and unchanged destination/secure-store markers. It also recursively rejects native IDs, credentials, grants, native paths/URIs, runtime timestamps/history, health data, and operation identity in the embedded or canonical public artifacts.

The canonical [Apple-origin](fixtures/apple-shared-setup-v2.json) and [Android-origin](fixtures/android-shared-setup-v2.json) fixtures remain one-line UTF-8 synthetic public documents. They contain no production health data, user/account/device identity, credential, grant, pairing, native ID, or runtime state. The Apple fixture covers all four data-detail/archive combinations; the Android fixture covers compatibility and raw-snapshot modes. V2 status remains `deferred`, its schema/version remain frozen, and every tracked v1 authority/fixture byte remains immutable.
