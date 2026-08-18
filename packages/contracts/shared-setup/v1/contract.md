# Health.md Shared Setup v1

## Status and purpose

`healthmd.shared_setup` version 1 is the implemented, pre-canonical public language-neutral contract candidate for sharing a bounded **portable setup profile** between Health.md on Apple and Android. Canonical status is deferred until the required physical-device interoperability and accessibility QA is complete. The user-facing outcome is “Share My Setup”: a recipient can review and apply export preferences without receiving health records or device-bound state.

This contract versions independently. Version 1 does **not** change Apple `healthmd.health_data` v8, Android frozen v4 or analytical v5, the semantic/render input contracts, or any direct-device protocol.

Readers MUST reject any `schema_version` other than `1`. Within version 1, readers MUST ignore unknown optional fields after bounded recursive preflight and the security checks below; ignored fields are never applied, persisted, copied into Undo state, or re-exported. Writers use an explicit allowlist and MUST emit only the fields defined by the [JSON Schema](shared-setup.schema.json), with the required fields and canonical enum spellings. The schema intentionally permits unknown reader input for forward-compatible decoding; this is not permission for writers to add opaque payloads.

The registered file representation is UTF-8 JSON with:

- extension `.healthmdconfig`;
- media type `application/vnd.healthmd.configuration+json`;
- Apple uniform type identifier `com.healthmd.configuration`;
- maximum encoded size **262,144 bytes**.

## Safety model

A shared setup file is untrusted input. Import is:

1. bounded read;
2. strict discriminator and structural validation;
3. security validation and compatibility analysis;
4. human-readable preview;
5. explicit confirmation;
6. one transactional native apply;
7. persistence verification with a bounded local Undo snapshot.

Preview MUST perform no writes. A failed apply MUST leave the prior configuration intact. Unknown required meanings, unsupported enum values, unsafe paths, or future schema versions fail closed.

A Health.md writer MUST NOT place health records, source data, user/account identity, credentials, tokens, authorization values, request headers, cookies, bookmarks, Android SAF URIs, folder grants, device or installation identifiers, permissions, purchases, onboarding state, analytics, export history, pending work, retries, operation identifiers, destination fingerprints, engine pins, or schedule runtime timestamps anywhere in the artifact. Readers treat a file as attacker-controlled: they ignore unknown fields and apply only the documented allowlist, even if an attacker places prohibited material under an unrecognized key. Custom template, fixed-frontmatter text, and endpoint host/path are intentionally portable user-authored content; export UI MUST disclose them and users MUST review them for personal, tenant, routing, or secret text.

## Envelope

Every document has:

- `schema`: exactly `healthmd.shared_setup`;
- `schema_version`: exactly `1`;
- `created_by`: non-authoritative app version and `apple` or `android` origin;
- `profile`: the portable setup;
- `metric_registry`: the exact source registry schema, version, and SHA-256 used by the writer;
- `metric_aliases`: a stable translation ledger derived from that source registry;
- `platform_extensions`: explicitly versioned native-only portable preferences.

`created_by` is provenance only. It MUST NOT contain device, installation, user, or account identifiers.

## Portable profile

### Export

`profile.export` always serializes effective values rather than relying on native defaults:

- `formats`: unique canonical values `markdown`, `obsidian_bases`, `json`, `csv`;
- `include_metadata` and `group_by_category`;
- `filename_template` and relative `folder_template`;
- `write_mode`: `overwrite`, `append`, or `update`;
- `include_granular_data`.

An empty format list is valid configuration but native export actions remain unavailable until a usable output is selected.

### Metrics and alias ledger

`profile.metrics.enabled_ids` is the sole selection authority. Each value is an exact `semantic_id` from the pinned `healthmd.metric_registry` v1. Native category IDs and category selections are never serialized and never enable metrics.

`metric_aliases` contains one row per selected semantic ID, sorted by `semantic_id`. Each row records:

- the canonical `semantic_id`;
- the registry evidence classification (`platform_exact_or_unavailable`, `mapped_alias`, or `platform_distinct`);
- the exact Apple and Android native `selection_id`, or `null` when unavailable.

When `metric_registry.registry_sha256` matches the receiver's registry bytes, readers verify every ledger row exactly. When it differs, readers use their local registry only for known semantic IDs and preserve syntactically valid unknown semantic IDs in the in-memory compatibility report as `requires_action`; unknown IDs are not applied or persisted into native metric selection. They do not infer aliases from labels or trust source-native selection IDs as application authority. A related native metric MUST NOT be substituted. Native selection categories never appear in this contract.

### Presentation and custom content

`profile.presentation` includes explicit canonical date, time, and unit enums plus:

- frontmatter field enablement/renames;
- bounded custom fixed values and placeholder names;
- date/type keys and fixed type value;
- `snake_case` or `camel_case` key style;
- Markdown style, verbatim bounded custom text, header level, emoji, summary, bullet style, and origin dialect.

The date enum is `iso8601`, `us_short`, `us_long`, `eu_short`, `eu_long`, `compact`, or `friendly`. The time enum is `hour_24`, `hour_24_seconds`, `hour_12`, or `hour_12_seconds`. Units are `metric` or `imperial`.

Custom Markdown is copied verbatim; importers MUST NOT sanitize, rewrite, or execute it. `origin_dialect` is `portable`, `apple`, or `android`. Tokens use `{{name}}`; conditional blocks use non-nested `{{#section}}...{{/section}}` with the same section name. The portable replacement catalog is `date`, `metrics`, `sleep_metrics`, `activity_metrics`, `heart_metrics`, `vitals_metrics`, `body_metrics`, `nutrition_metrics`, `mobility_metrics`, `mindfulness_metrics`, and `workout_list`; the portable conditional catalog is `sleep`, `activity`, `heart`, `vitals`, `body`, `nutrition`, `mobility`, `mindfulness`, and `workouts`. Other tokens/sections are platform dialect extensions. A receiver scans balanced tokens and blocks before apply. Unsupported or malformed placeholders produce `requires_action`; the importer leaves the existing local template unchanged rather than silently reinterpreting or installing unresolved tokens.

### Individual entries

`profile.individual_entries` contains the effective master toggle, a canonical-semantic-ID keyed metric map, relative entries folder, category-folder preference, and explicit filename template. This explicit value preserves the native default difference (`{date}_{time}_{metric}` on Apple and `{metric}-{date}-{time}` on Android).

Per-metric custom folders are relative. Metric keys use canonical semantic IDs and follow the same registry-backed translation rules as `enabled_ids`.

### Daily Notes

`profile.daily_notes` contains `enabled`, relative `folder`, `filename_template`, `create_if_missing`, and `inject_sections`. Writers always include `create_if_missing`, preserving Apple’s effective default `false` and Android’s historical decode default `true`.

Apple Daily Notes Only is not equivalent to Android behavior and lives in `platform_extensions.apple.daily_notes.only`.

### Declarative schedule intent

`profile.schedule` is non-operative intent only:

- `activation_requested` records whether the sender would like the recipient to enable it;
- cadence has explicit positive `value` and `minutes`, `hours`, `days`, `weeks`, or `months` unit;
- wall-clock `hour` and `minute` are explicit, preserving Apple’s 08:00 and Android’s 06:00 defaults;
- `lookback_days`, `date_window`, and desired `device_folder` or `api_endpoint` target are explicit.

Import always stores scheduling **disabled**. Activation requires a separate local action after exact cadence/target support, destination access, permissions, endpoint authentication, background capability, and current entitlement are confirmed. Unsupported cadence or target semantics return `requires_action`; they are never approximated.

No schedule operational state is portable: no enabled flag, enabled-at timestamp, anchor execution timestamp, last run/success, retry queue, pending request, operation ID, fingerprint, worker/alarm identity, or renderer/engine pin.

### API endpoint hint

`profile.api_endpoint` is either `null` or a non-operative endpoint hint with separate `scheme`, DNS host, port, and path components. The scheme is HTTPS only. Userinfo, percent escapes, network-path `//`, query, and fragment are forbidden. `query_omitted` explicitly records whether a sender removed a query; `credentials_required` is always `true`. A host/path can still contain tenant or routing identity, so sharing UI requires explicit sender disclosure and recipient preview. Loopback, private, and public DNS names are syntactically portable; no connection occurs during import.

Import never inherits or binds existing credentials to the hint. Native code constructs a URL from validated components rather than string concatenation. The receiver presents host/path, requires explicit confirmation and local credential entry, and keeps API scheduling disabled. Credentials and custom headers remain in each device’s secure store and never enter this contract.

## Versioned platform extensions

Extensions are reviewed typed fields, not opaque native settings snapshots. Each platform key is required but its value is either a typed `extension_version: 1` object or `null`. A writer MUST emit its own platform extension. It emits the other platform extension only when preserving a previously imported typed extension; otherwise it emits `null`. Receivers never fabricate foreign-platform defaults and apply their native extension only when an object is present.

The Apple extension may carry:

- format-folder organization, ZIP archive, data dictionary, summary-only output, and weekly/monthly/yearly rollups;
- Daily Notes Only;
- Apple schedule frequency/custom unit, weekday, Today Refresh intent, refresh interval, and desired local-iPhone/connected-Mac/API target.

The Android extension may carry:

- frozen-v4 versus analytical-v5 local compatibility profile;
- legacy alias and Android-native-field output switches;
- relative local subfolder and folder organization.

These sections never carry folder bookmarks/grants, SAF content URIs, endpoint credentials, purchases, onboarding state, runtime work, raw persistence snapshots, or histories. A different platform preserves a present unsupported extension for round trip and reports it; it does not apply an approximation. A `null` foreign extension remains absent rather than being replaced by guessed defaults.

## Bounds and path rules

In addition to the encoded-file limit, known fields are schema-bounded: 256 metric selections/aliases, 256 frontmatter fields, 128 custom/placeholder entries, 256 per-metric individual-entry entries, 4,096 characters per path/template string, and 65,536 characters of custom Markdown. Before schema decoding, readers enforce a maximum nesting depth of 16, at most 256 members/items in any object/array, at most 65,536 Unicode scalar values in any string, and at most 16,384 total JSON nodes across known and unknown input. This bounds forward-compatible unknown fields before they are ignored.

Every folder/path value is destination-relative. The empty folder string means the recipient-selected destination root. A non-empty value MUST NOT be absolute, contain a drive prefix, percent sign, backslash, URI scheme, control character, repeated separator, or `.`/`..` component, and must resolve inside the selected root. Filename templates are non-empty single path segments and follow the same exclusions. Folder grants are selected locally after import.

## Compatibility result

Native readers report each reviewed item as one of:

- `applied`: exact supported portable meaning can be applied after confirmation;
- `requires_action`: valid intent needs a local choice, credentials, permission, entitlement, or unsupported-placeholder/cadence resolution;
- `unsupported`: valid platform-specific meaning is preserved but not applied;
- `invalid`: unsafe, malformed, future-version, or contradictory input; no changes are allowed.

The reference [synthetic fixture](fixtures/shared-setup-v1.json) contains no production health data, account identity, credential, endpoint secret, or device identifier.
